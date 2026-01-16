# MysqlAdaptor 分析及 Oracle 适配器可行性评估

## 一、MysqlAdaptor 代码分析

**文件路径:** [MysqlAdaptor.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/MysqlAdaptor.java)

```java
public class MysqlAdaptor extends BaseDbAdaptor {

    @Override
    public String getDateFormat(String dateType, String dateFormat, String column) {
        // 处理三种日期类型：MONTH、WEEK、DAY
        // 支持两种输入格式：DAY_FORMAT_INT (yyyyMMdd) 和 DAY_FORMAT (yyyy-MM-dd)
        if (dateFormat.equalsIgnoreCase(Constants.DAY_FORMAT_INT)) {
            if (TimeDimensionEnum.MONTH.name().equalsIgnoreCase(dateType)) {
                return "DATE_FORMAT(%s, '%Y-%m')".replace("%s", column);
            } else if (TimeDimensionEnum.WEEK.name().equalsIgnoreCase(dateType)) {
                return "DATE_FORMAT(DATE_SUB(%s, INTERVAL (DAYOFWEEK(%s) - 2) DAY), '%Y-%m-%d')"
                        .replace("%s", column);
            } else {
                return "date_format(str_to_date(%s, '%Y%m%d'),'%Y-%m-%d')".replace("%s", column);
            }
        } else if (dateFormat.equalsIgnoreCase(Constants.DAY_FORMAT)) {
            // 类似逻辑，但输入已是 yyyy-MM-dd 格式
        }
        return column;
    }

    @Override
    public String rewriteSql(String sql) {
        return sql; // MySQL 不需要额外重写
    }
}
```

### 继承的功能（来自 BaseDbAdaptor）

| 方法 | 功能 | 实现 |
|------|------|------|
| `getCatalogs()` | 获取目录列表 | 使用 `SHOW CATALOGS` |
| `getDBs()` | 获取数据库列表 | 使用 JDBC metadata `getSchemas()` / `getCatalogs()` |
| `getTables()` | 获取表列表 | 使用 JDBC metadata `getTables()` |
| `getColumns()` | 获取列信息 | 使用 JDBC metadata `getColumns()` |
| `classifyColumnType()` | 类型分类 | INT/DOUBLE/DECIMAL → measure, DATE/TIMESTAMP → time, 其他 → categorical |
| `getConnection()` | 获取 JDBC 连接 | 通用连接池 |

### DbAdaptor 接口契约

```java
public interface DbAdaptor {
    String getDateFormat(String dateType, String dateFormat, String column);
    String rewriteSql(String sql);
    List<String> getCatalogs(ConnectInfo connectInfo) throws SQLException;
    List<String> getDBs(ConnectInfo connectInfo, String catalog) throws SQLException;
    List<String> getTables(ConnectInfo connectInfo, String catalog, String schemaName) throws SQLException;
    List<DBColumn> getColumns(ConnectInfo connectInfo, String catalog, String schemaName,
            String tableName) throws SQLException;
    FieldType classifyColumnType(String typeName);
}
```

## 二、Oracle 适配器可行性分析

### ✅ 可行性评估：**高可行性 (★★★★☆ 4/5)**

**理由：**
1. **架构成熟** - 已有 10+ 数据库适配器实现，模式清晰
2. **接口简洁** - 只需实现 7 个方法，其中 5 个可继承
3. **继承基础** - BaseDbAdaptor 提供大部分 JDBC 操作
4. **参考案例** - PostgreSQL/H2/HANA 等关系型数据库实现可参考

### Oracle SQL 方言特点

| 特性 | Oracle 语法 | 需要适配 |
|------|-------------|----------|
| **日期格式化** | `TO_CHAR(date, 'YYYY-MM')` | ✅ 是 |
| **日期解析** | `TO_DATE('20240101', 'YYYYMMDD')` | ✅ 是 |
| **周计算** | `TRUNC(date, 'IW')` (ISO 周) | ✅ 是 |
| **标识符引号** | 使用双引号 `"identifier"` | ✅ 是 |
| **分页** | `OFFSET x ROWS FETCH NEXT y ROWS ONLY` (12c+) | ✅ 是 |
| **连接语法** | 标准 INNER/LEFT JOIN | ✅ 兼容 |
| **类型系统** | NUMBER, VARCHAR2, DATE, CLOB, BLOB | ✅ 需分类 |

## 三、Oracle 适配器实现草案

```java
package com.tencent.supersonic.headless.core.adaptor.db;

import com.tencent.supersonic.common.pojo.Constants;
import com.tencent.supersonic.common.pojo.enums.TimeDimensionEnum;
import com.tencent.supersonic.headless.api.pojo.enums.FieldType;
import lombok.extern.slf4j.Slf4j;

@Slf4j
public class OracleAdaptor extends BaseDbAdaptor {

    @Override
    public String getDateFormat(String dateType, String dateFormat, String column) {
        if (dateFormat.equalsIgnoreCase(Constants.DAY_FORMAT_INT)) {
            // 输入格式: yyyyMMdd (整数或字符串)
            if (TimeDimensionEnum.MONTH.name().equalsIgnoreCase(dateType)) {
                // TO_DATE(TO_CHAR(column), 'YYYYMMDD'), 'YYYY-MM')
                return "TO_CHAR(TO_DATE(%s, 'YYYYMMDD'), 'YYYY-MM')".replace("%s", column);
            } else if (TimeDimensionEnum.WEEK.name().equalsIgnoreCase(dateType)) {
                // TRUNC(TO_DATE(column, 'YYYYMMDD'), 'IW') - ISO 周一
                return "TRUNC(TO_DATE(%s, 'YYYYMMDD'), 'IW')".replace("%s", column);
            } else {
                // DAY - 保持原始日期格式或转换为 YYYY-MM-DD
                return "TO_CHAR(TO_DATE(%s, 'YYYYMMDD'), 'YYYY-MM-DD')".replace("%s", column);
            }
        } else if (dateFormat.equalsIgnoreCase(Constants.DAY_FORMAT)) {
            // 输入格式: yyyy-MM-dd (字符串)
            if (TimeDimensionEnum.MONTH.name().equalsIgnoreCase(dateType)) {
                return "TO_CHAR(TO_DATE(%s, 'YYYY-MM-DD'), 'YYYY-MM')".replace("%s", column);
            } else if (TimeDimensionEnum.WEEK.name().equalsIgnoreCase(dateType)) {
                return "TRUNC(TO_DATE(%s, 'YYYY-MM-DD'), 'IW')".replace("%s", column);
            } else {
                return column; // 已经是标准格式
            }
        }
        return column;
    }

    @Override
    public String rewriteSql(String sql) {
        // 1. 替换反引号为双引号
        sql = sql.replaceAll("`", "\"");

        // 2. 可能需要处理 Calcite 生成的日期函数
        // 例如: MONTH(column) -> EXTRACT(MONTH FROM column) 或 TO_CHAR(column, 'MM')

        return sql;
    }

    @Override
    public FieldType classifyColumnType(String typeName) {
        switch (typeName.toUpperCase()) {
            // 数值类型
            case "NUMBER":
            case "BINARY_FLOAT":
            case "BINARY_DOUBLE":
            case "FLOAT":
            case "INTEGER":
            case "DECIMAL":
            case "NUMERIC":
                return FieldType.measure;

            // 日期时间类型
            case "DATE":
            case "TIMESTAMP":
            case "TIMESTAMP WITH TIME ZONE":
            case "TIMESTAMP WITH LOCAL TIME ZONE":
            case "INTERVAL YEAR TO MONTH":
            case "INTERVAL DAY TO SECOND":
                return FieldType.time;

            // 字符串和大对象 (默认 categorical)
            case "VARCHAR2":
            case "CHAR":
            case "NVARCHAR2":
            case "NCHAR":
            case "CLOB":
            case "NCLOB":
            case "BLOB":
            case "RAW":
            case "LONG":
            default:
                return FieldType.categorical;
        }
    }
}
```

## 四、风险评估

### 🔴 高风险

| 风险项 | 描述 | 缓解措施 |
|--------|------|----------|
| **Calcite LIMIT 语法** | Calcite 默认生成 `LIMIT offset, count`，Oracle 12c+ 使用 `OFFSET x ROWS FETCH NEXT y ROWS ONLY` | 需在 `SqlDialectFactory` 配置专属 Oracle 方言，或实现 `OracleSqlDialect` |
| **日期函数映射** | Calcite 可能生成 `MONTH(col)`/`DAY(col)`，Oracle 需 `EXTRACT(MONTH FROM col)` 或 `TO_CHAR(col, 'MM')` | 在 `rewriteSql()` 中使用 `SqlReplaceHelper.replaceFunction()` 处理函数替换 |

### 🟡 中风险

| 风险项 | 描述 | 缓解措施 |
|--------|------|----------|
| **类型映射精度** | Oracle `NUMBER(p,s)` 可对应多种 Java 类型，需区分整数/浮点 | 需测试验证 `classifyColumnType`，可能需要解析类型参数 |
| **JDBC 驱动兼容** | 不同版本 Oracle JDBC 行为差异（ojdbc8 vs ojdbc11） | 建议使用 `ojdbc11` (Java 11+)，明确依赖版本 |
| **大字段处理** | CLOB/BLOB 字段查询可能异常 | 在 `getColumns()` 中过滤或特殊处理 |
| **Schema 概念** | Oracle 用户=Schema，catalog 为空，`getCatalogs()` 可能返回空 | 需测试 `getDBs()`/`getTables()` 的行为 |
| **日期字面量** | Calcite 可能生成 `DATE '2024-01-01'`，需确认 Oracle 支持 | Oracle 支持标准 ANSI 日期字面量 |

### 🟢 低风险

| 风险项 | 描述 | 缓解措施 |
|--------|------|----------|
| **连接池** | 可用 HikariCP | 基础配置，已验证 |
| **元数据查询** | 标准 JDBC metadata API | 继承 `BaseDbAdaptor` 已实现 |
| **函数替换** | 使用 `SqlReplaceHelper.replaceFunction()` | 已有工具支持，PostgreSQL 已验证 |
| **JOIN 语法** | 标准 SQL JOIN | Calcite 生成标准语法 |

---

## ⚠️ 关键技术点：Calcite 方言配置详解

### 问题分析

**[SqlDialectFactory.java](common/src/main/java/com/tencent/supersonic/common/calcite/SqlDialectFactory.java)** 当前使用 `SemanticSqlDialect`，它生成 **MySQL 风格的 LIMIT 语法**：

```java
// SemanticSqlDialect.java:22-43
public static void unparseFetchUsingAnsi(SqlWriter writer, @Nullable SqlNode offset,
        @Nullable SqlNode fetch) {
    // 生成: LIMIT offset, fetch (MySQL 风格)
    writer.keyword("LIMIT");
    boolean hasOffset = false;
    if (offset != null) {
        offset.unparse(writer, -1, -1);
        hasOffset = true;
    }
    if (fetch != null) {
        if (hasOffset) {
            writer.keyword(",");
        }
        fetch.unparse(writer, -1, -1);
    }
}
```

**当前注册的方言：**

```java
static {
    sqlDialectMap = new HashMap<>();
    sqlDialectMap.put(EngineType.CLICKHOUSE, new SemanticSqlDialect(DEFAULT_CONTEXT));
    sqlDialectMap.put(EngineType.MYSQL, new SemanticSqlDialect(DEFAULT_CONTEXT));
    sqlDialectMap.put(EngineType.H2, new SemanticSqlDialect(DEFAULT_CONTEXT));
    sqlDialectMap.put(EngineType.POSTGRESQL, new SemanticSqlDialect(POSTGRESQL_CONTEXT));
    sqlDialectMap.put(EngineType.HANADB, new SemanticSqlDialect(HANADB_CONTEXT));
    // Oracle 未注册，将使用默认方言 (生成 MySQL 风格 LIMIT)
}
```

### Oracle 12c+ 需要的分页语法

```sql
-- Oracle 分页语法 (SQL:2008 标准)
OFFSET 10 ROWS FETCH NEXT 20 ROWS ONLY

-- 当只有 FETCH 无 OFFSET
FETCH FIRST 20 ROWS ONLY
```

### 解决方案对比

#### 💡 方案 A：直接使用 Calcite 内置的 OracleSqlDialect（⭐⭐⭐⭐⭐⭐ 最佳）

**重要发现：Calcite 1.37.0 已内置 `org.apache.calcite.sql.dialect.OracleSqlDialect`**

参考 SuperSonic 中已有的 [S2MysqlSqlDialect.java](common/src/main/java/com/tencent/supersonic/common/calcite/S2MysqlSqlDialect.java)，只需创建一个简单的包装类：

**新增文件：** `common/src/main/java/com/tencent/supersonic/common/calcite/S2OracleSqlDialect.java`

```java
package com.tencent.supersonic.common.calcite;

import org.apache.calcite.sql.dialect.OracleSqlDialect;

/**
 * Oracle Database SQL Dialect wrapper
 * Extends Calcite's built-in OracleSqlDialect for SuperSonic compatibility
 */
public class S2OracleSqlDialect extends OracleSqlDialect {

    public S2OracleSqlDialect(Context context) {
        super(context);
    }

    // 可以根据需要覆盖特定方法，如字符串字面量处理
    @Override
    public void quoteStringLiteral(StringBuilder buf, String charsetName, String val) {
        buf.append(this.literalQuoteString);
        buf.append(val.replace(this.literalEndQuoteString, this.literalEscapedQuote));
        buf.append(this.literalEndQuoteString);
    }
}
```

**在 SqlDialectFactory 中注册：**

```java
// SqlDialectFactory.java

import org.apache.calcite.sql.dialect.OracleSqlDialect;

// 1. 定义 Oracle Context (使用 Calcite 内置的 OracleSqlDialect.Context)
public static final Context ORACLE_CONTEXT =
        SqlDialect.EMPTY_CONTEXT
                .withDatabaseProduct(DatabaseProduct.ORACLE)
                .withLiteralQuoteString("'")
                .withLiteralEscapedQuoteString("''")
                .withIdentifierQuoteString("\"")      // Oracle 使用双引号
                .withUnquotedCasing(Casing.TO_UPPER)  // Oracle 未加引号标识符自动转大写
                .withQuotedCasing(Casing.UNCHANGED)
                .withCaseSensitive(false);

// 2. 注册 Oracle 方言
static {
    sqlDialectMap = new HashMap<>();
    // ... 现有注册
    sqlDialectMap.put(EngineType.ORACLE, new S2OracleSqlDialect(ORACLE_CONTEXT));
}
```

**优点：**
- ✅ **最简实现** - 直接复用 Calcite 官方实现，代码量最小
- ✅ **官方支持** - Calcite 团队维护 Oracle 方言，持续更新
- ✅ **已验证** - Calcite 的 OracleSqlDialect 已经过充分测试
- ✅ **自动支持** - OFFSET/FETCH、分页、日期函数等 Oracle 特性自动处理
- ✅ **架构一致** - 与 S2MysqlSqlDialect 模式完全一致

**Calcite 1.37.0 OracleSqlDialect 内置支持：**
- ✅ `OFFSET x ROWS FETCH NEXT y ROWS ONLY` 分页语法
- ✅ `FETCH FIRST x ROWS ONLY` 语法
- ✅ Oracle 日期函数（TO_CHAR、TO_DATE、TRUNC 等）
- ✅ Oracle 连接语法
- ✅ 双引号标识符
- ✅ 大小写处理

---

#### 方案 B：自定义 SemanticSqlDialect 扩展（⭐⭐⭐ 备选）

如果需要更精细的控制，可以继承 `SemanticSqlDialect` 而非 Calcite 的 OracleSqlDialect：

```java
package com.tencent.supersonic.common.calcite;

/**
 * Custom Oracle Dialect extending SemanticSqlDialect
 * Use this when you need SuperSonic-specific customizations
 */
public class OracleSqlDialect extends SemanticSqlDialect {

    public OracleSqlDialect(Context context) {
        super(context);
    }

    @Override
    public void unparseOffsetFetch(SqlWriter writer, @Nullable SqlNode offset,
            @Nullable SqlNode fetch) {
        // 生成: OFFSET offset ROWS FETCH NEXT fetch ROWS ONLY
        if (offset != null) {
            writer.newlineAndIndent();
            writer.keyword("OFFSET");
            offset.unparse(writer, -1, -1);
            writer.keyword("ROWS");
        }

        if (fetch != null) {
            if (offset != null) {
                writer.keyword("FETCH");
                writer.keyword("NEXT");
            } else {
                writer.newlineAndIndent();
                writer.keyword("FETCH");
                writer.keyword("FIRST");
            }
            fetch.unparse(writer, -1, -1);
            writer.keyword("ROWS");
            writer.keyword("ONLY");
        }
    }
}
```

**何时使用方案 B：**
- 需要深度定制 SQL 生成行为
- 需要覆盖 SemanticSqlDialect 的特殊逻辑（如 INTERVAL 处理）
- 与 SuperSonic 现有方言体系保持完全一致

---

#### 方案 C：在 OracleAdaptor.rewriteSql() 中正则替换（⭐ 不推荐）

```java
@Override
public String rewriteSql(String sql) {
    // 1. 替换反引号为双引号
    sql = sql.replaceAll("`", "\"");

    // 2. 转换 LIMIT 语法 (正则替换 - 仅适用于简单场景)
    // LIMIT 10, 20 → OFFSET 10 ROWS FETCH NEXT 20 ROWS ONLY
    sql = sql.replaceAll("LIMIT\\s+(\\d+)\\s*,\\s*(\\d+)",
            "OFFSET $1 ROWS FETCH NEXT $2 ROWS ONLY");

    // 3. 处理单独的 LIMIT (无 OFFSET)
    // LIMIT 20 → FETCH FIRST 20 ROWS ONLY
    sql = sql.replaceAll("LIMIT\\s+(\\d+)(?!\\s*,)",
            "FETCH FIRST $1 ROWS ONLY");

    return sql;
}
```

**缺点：**
- ❌ 正则匹配不够精确，可能误处理复杂 SQL
- ❌ 无法正确处理子查询中的 LIMIT
- ❌ 无法处理 LIMIT 中包含表达式的情况（如 `LIMIT ?` 参数化查询）
- ❌ 维护成本高，容易出现边界情况 bug

#### 方案 D：rewriteSql + JSQLParser（⭐⭐ 高精度但复杂）

使用 JSQLParser 解析 SQL，精确替换 LIMIT 语法：

```java
@Override
public String rewriteSql(String sql) {
    // 1. 替换反引号
    sql = sql.replaceAll("`", "\"");

    // 2. 使用 JSQLParser 解析并转换 LIMIT
    try {
        Statement statement = CCJSqlParserUtil.parse(sql);
        if (statement instanceof Select) {
            Select select = (Select) statement;
            SelectBody selectBody = select.getSelectBody();

            if (selectBody instanceof PlainSelect) {
                PlainSelect plainSelect = (PlainSelect) selectBody;
                Limit limit = plainSelect.getLimit();

                if (limit != null) {
                    // 转换为 Oracle OFFSET/FETCH
                    OracleOffsetFetch oracleLimit = new OracleOffsetFetch(
                        limit.getOffset(), limit.getRowCount()
                    );
                    plainSelect.setLimit(oracleLimit);
                }
            }
        }
        return statement.toString();
    } catch (JSQLParserException e) {
        log.warn("Failed to parse SQL for Oracle conversion", e);
        return sql;
    }
}
```

**缺点：**
- ⚠️ 需要自定义 OracleOffsetFetch 类
- ⚠️ 实现复杂度高，性能开销较大
- ⚠️ 仍需处理边界情况

### 推荐实施方案

| 优先级 | 方案 | 适用场景 | 推荐度 |
|--------|------|----------|--------|
| **首选** | 方案 A: S2OracleSqlDialect (继承 Calcite 内置) | **生产环境，推荐方案** | ⭐⭐⭐⭐⭐⭐ |
| **备选** | 方案 B: 自定义 SemanticSqlDialect 扩展 | 需要 SuperSonic 特定定制 | ⭐⭐⭐ |
| **验证用** | 方案 C: 正则替换 | 仅用于快速原型验证 | ⭐ |
| **不推荐** | 方案 D: JSQLParser | 过于复杂，维护成本高 | ⭐⭐ |

**最终建议**：使用 **方案 A（S2OracleSqlDialect 继承 Calcite 内置 OracleSqlDialect）**

理由：
1. **最简实现** - 参考 `S2MysqlSqlDialect` 模式，仅需约 15 行代码
2. **官方支持** - Calcite 1.37.0 内置的 OracleSqlDialect 已经过充分测试
3. **自动适配** - OFFSET/FETCH、日期函数、标识符等 Oracle 特性自动处理
4. **架构一致** - 与 SuperSonic 现有方言配置模式完全一致
5. **易于维护** - Calcite 升级时自动获得 Oracle 方言改进

---

## 五、实施步骤

### 1. 添加 EngineType 枚举

**文件:** [EngineType.java](common/src/main/java/com/tencent/supersonic/common/pojo/enums/EngineType.java)

```java
public enum EngineType {
    // ... 现有类型
    TRINO(13, "TRINO"),
    ORACLE(14, "ORACLE");  // 新增
}
```

### 2. 创建 OracleAdaptor

**文件:** `headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/OracleAdaptor.java`

使用上述实现草案代码。

### 3. 注册适配器

**文件:** [DbAdaptorFactory.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/DbAdaptorFactory.java)

```java
static {
    // ... 现有注册
    dbAdaptorMap.put(EngineType.ORACLE.getName(), new OracleAdaptor());
}
```

### 4. 配置 Calcite 方言（推荐使用 Calcite 内置）

**文件:** [SqlDialectFactory.java](common/src/main/java/com/tencent/supersonic/common/calcite/SqlDialectFactory.java)

**推荐方案：** 创建 S2OracleSqlDialect 包装类（约 15 行代码）

```java
// 新增文件: common/src/main/java/com/tencent/supersonic/common/calcite/S2OracleSqlDialect.java
package com.tencent.supersonic.common.calcite;

import org.apache.calcite.sql.dialect.OracleSqlDialect;

public class S2OracleSqlDialect extends OracleSqlDialect {
    public S2OracleSqlDialect(Context context) {
        super(context);
    }
}
```

**在 SqlDialectFactory 中注册：**

```java
// SqlDialectFactory.java

// 1. 定义 Oracle Context
public static final Context ORACLE_CONTEXT =
        SqlDialect.EMPTY_CONTEXT
                .withDatabaseProduct(DatabaseProduct.ORACLE)
                .withLiteralQuoteString("'")
                .withLiteralEscapedQuoteString("''")
                .withIdentifierQuoteString("\"")
                .withUnquotedCasing(Casing.TO_UPPER)
                .withQuotedCasing(Casing.UNCHANGED)
                .withCaseSensitive(false);

// 2. 注册 Oracle 方言
static {
    sqlDialectMap = new HashMap<>();
    // ... 现有注册
    sqlDialectMap.put(EngineType.ORACLE, new S2OracleSqlDialect(ORACLE_CONTEXT));
}
```

### 5. 添加 JDBC 依赖

**文件:** `pom.xml` (根 pom 或 headless pom)

```xml
<dependency>
    <groupId>com.oracle.database.jdbc</groupId>
    <artifactId>ojdbc11</artifactId>
    <version>21.11.0.0</version>
    <scope>provided</scope>  <!-- 或 runtime -->
</dependency>
```

### 6. 单元测试

```java
@Test
public void testGetDateFormat() {
    OracleAdaptor adaptor = new OracleAdaptor();

    // MONTH - yyyyMMdd
    String result = adaptor.getDateFormat("MONTH", "yyyyMMdd", "sys_imp_date");
    assertEquals("TO_CHAR(TO_DATE(sys_imp_date, 'YYYYMMDD'), 'YYYY-MM')", result);

    // WEEK - yyyy-MM-dd
    result = adaptor.getDateFormat("WEEK", "yyyy-MM-dd", "sys_imp_date");
    assertEquals("TRUNC(TO_DATE(sys_imp_date, 'YYYY-MM-DD'), 'IW')", result);
}

@Test
public void testClassifyColumnType() {
    OracleAdaptor adaptor = new OracleAdaptor();

    assertEquals(FieldType.measure, adaptor.classifyColumnType("NUMBER"));
    assertEquals(FieldType.measure, adaptor.classifyColumnType("BINARY_FLOAT"));
    assertEquals(FieldType.time, adaptor.classifyColumnType("DATE"));
    assertEquals(FieldType.time, adaptor.classifyColumnType("TIMESTAMP WITH TIME ZONE"));
    assertEquals(FieldType.categorical, adaptor.classifyColumnType("VARCHAR2"));
    assertEquals(FieldType.categorical, adaptor.classifyColumnType("CLOB"));
}
```

### 7. 集成测试

```java
@Test
public void testOracleConnection() throws SQLException {
    ConnectInfo connectInfo = new ConnectInfo();
    connectInfo.setUrl("jdbc:oracle:thin:@localhost:1521:ORCL");
    connectInfo.setUserName("system");
    connectInfo.setPassword("password");

    OracleAdaptor adaptor = new OracleAdaptor();

    // 测试获取数据库列表
    List<String> dbs = adaptor.getDBs(connectInfo, null);
    assertNotNull(dbs);

    // 测试获取表列表
    List<String> tables = adaptor.getTables(connectInfo, null, "SYSTEM");
    assertNotNull(tables);
}
```

## 六、需要注意的 Oracle 特性

| 特性 | 描述 | 影响 |
|------|------|------|
| **空字符串处理** | Oracle 将空字符串 `''` 视为 `NULL` | 需在查询构建时注意 |
| **大小写敏感** | 未加引号的标识符自动转大写 | `getColumns()` 返回的列名是大写 |
| **ROWNUM 分页** | 传统分页使用 `ROWNUM`（但 12c+ 支持 OFFSET/FETCH） | 建议使用新语法 |
| **日期字面量** | 使用 `DATE '2024-01-01'` 语法 | Calcite 生成标准语法，应兼容 |
| **NCHAR/NVARCHAR** | Unicode 字符集支持 | `classifyColumnType` 需处理 |
| **序列（Sequence）** | `sequence.NEXTVAL` 获取自增 ID | 如果模型使用需注意 |
| **同义词（Synonym）** | 可以引用其他 schema 的对象 | `getTables()` 可能返回同义词 |

## 七、总结

### 可行性：★★★★☆ (4/5)

参考 MysqlAdaptor 编写 Oracle 适配器是**完全可行**的。

### 主要工作

1. 实现 `getDateFormat()` - Oracle 日期函数映射（TO_CHAR, TO_DATE, TRUNC）
2. 实现 `rewriteSql()` - 引号替换（`"`）+ 可选函数替换
3. 重写 `classifyColumnType()` - Oracle 类型映射（NUMBER, VARCHAR2, DATE, CLOB 等）
4. 配置 Calcite 方言 - 处理 LIMIT 语法差异（OFFSET/FETCH）

### 风险可控，但需要

1. **充分测试日期函数转换** - Oracle 日期格式代码（YYYY-MM vs YYYYMM）
2. **验证 Calcite SQL 兼容性** - 特别是 LIMIT/OFFSET 语法
3. **处理函数名冲突** - MONTH/DAY/YEAR 可能与 Oracle 关键字冲突
4. **测试 JDBC 元数据查询** - Oracle 的 schema 概念（用户=schema）
5. **验证类型分类精度** - NUMBER(p,s) 的语义

### 建议开发顺序

1. 先实现 `classifyColumnType()` 和 `rewriteSql()`（最简单）
2. 实现 `getDateFormat()`（核心逻辑）
3. 单元测试验证
4. 配置 Calcite 方言（如果需要）
5. 连接真实 Oracle 数据库集成测试
