# SuperSonic SQL 方言处理分析报告

## 一、多层架构概述

SuperSonic 使用**多层架构**处理不同数据库的 SQL 方言差异：

```
用户查询 (自然语言)
    ↓
语义解析 (Schema Mapper → Semantic Parser)
    ↓
Calcite SQL 生成 (数据库无关)
    ↓
方言转换 (DbDialectOptimizer + DbAdaptor)
    ↓
JSQLParser 精细转换 (函数/字段替换)
    ↓
数据库执行
```

## 二、核心组件

### 1. Calcite SQL 生成层

**[DefaultSemanticTranslator.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/translator/DefaultSemanticTranslator.java)**

```java
public void translate(QueryStatement queryStatement) throws Exception {
    // 1. 解析阶段 - QueryParsers 生成初始 SQL
    for (QueryParser parser : ComponentFactory.getQueryParsers()) {
        if (parser.accept(queryStatement)) {
            parser.parse(queryStatement);
        }
    }

    // 2. 合并本体查询
    mergeOntologyQuery(queryStatement);

    // 3. 优化阶段 - QueryOptimizers 转换 SQL
    for (QueryOptimizer optimizer : ComponentFactory.getQueryOptimizers()) {
        if (optimizer.accept(queryStatement)) {
            optimizer.rewrite(queryStatement);
        }
    }
}
```

**[SqlBuilder.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/translator/parser/calcite/SqlBuilder.java)**

```java
public String buildOntologySql(QueryStatement queryStatement) throws Exception {
    // 1. 从模型渲染 TableView
    TableView tableView = render(ontologyQuery, dataModels, scope, schema);

    // 2. 构建 Calcite SQL 节点
    SqlNode parserNode = tableView.build();

    // 3. 可选优化
    parserNode = optimizeParseNode(parserNode, engineType);

    // 4. 使用 SemanticNode.getSql() 转换为 SQL 字符串
    return SemanticNode.getSql(parserNode, engineType);
}
```

### 2. Calcite 方言配置

**[SqlDialectFactory.java](common/src/main/java/com/tencent/supersonic/common/calcite/SqlDialectFactory.java)**

```java
static {
    sqlDialectMap = new HashMap<>();
    sqlDialectMap.put(EngineType.CLICKHOUSE, new SemanticSqlDialect(DEFAULT_CONTEXT));
    sqlDialectMap.put(EngineType.MYSQL, new SemanticSqlDialect(DEFAULT_CONTEXT));
    sqlDialectMap.put(EngineType.H2, new SemanticSqlDialect(DEFAULT_CONTEXT));
    sqlDialectMap.put(EngineType.POSTGRESQL, new SemanticSqlDialect(POSTGRESQL_CONTEXT));
    sqlDialectMap.put(EngineType.HANADB, new SemanticSqlDialect(HANADB_CONTEXT));
}

public static SemanticSqlDialect getSqlDialect(EngineType engineType) {
    return sqlDialectMap.getOrDefault(engineType, new SemanticSqlDialect(DEFAULT_CONTEXT));
}
```

**[SemanticSqlDialect.java](common/src/main/java/com/tencent/supersonic/common/calcite/SemanticSqlDialect.java)**

核心自定义：

1. **MySQL 风格的 LIMIT/OFFSET**
   - 不使用 `OFFSET x FETCH y` 语法
   - 使用 `LIMIT offset, count` 语法

2. **时间间隔处理**
   - 修改 `INTERVAL` 表达式的生成方式

3. **FROM 别名要求**
   - `requiresAliasForFromItems() = true`
   - 强制所有 FROM 项必须有别名

### 3. 方言转换层

**[DbDialectOptimizer.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/translator/optimizer/DbDialectOptimizer.java)**

```java
@Component("DbDialectOptimizer")
public class DbDialectOptimizer implements QueryOptimizer {
    @Override
    public void rewrite(QueryStatement queryStatement) {
        SemanticSchemaResp semanticSchemaResp = queryStatement.getSemanticSchema();
        DatabaseResp database = semanticSchemaResp.getDatabaseResp();
        String sql = queryStatement.getSql();

        // 获取数据库特定的适配器
        DbAdaptor engineAdaptor = DbAdaptorFactory.getEngineAdaptor(database.getType());
        if (Objects.nonNull(engineAdaptor)) {
            String adaptedSql = engineAdaptor.rewriteSql(sql);
            queryStatement.setSql(adaptedSql);
        }
    }
}
```

**[DbAdaptorFactory.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/DbAdaptorFactory.java)**

```java
static {
    dbAdaptorMap = new HashMap<>();
    dbAdaptorMap.put(EngineType.CLICKHOUSE.getName(), new ClickHouseAdaptor());
    dbAdaptorMap.put(EngineType.MYSQL.getName(), new MysqlAdaptor());
    dbAdaptorMap.put(EngineType.POSTGRESQL.getName(), new PostgresqlAdaptor());
    dbAdaptorMap.put(EngineType.DUCKDB.getName(), new DuckdbAdaptor());
    dbAdaptorMap.put(EngineType.PRESTO.getName(), new PrestoAdaptor());
    dbAdaptorMap.put(EngineType.TRINO.getName(), new TrinoAdaptor());
    dbAdaptorMap.put(EngineType.KYUUBI.getName(), new KyuubiAdaptor());
    dbAdaptorMap.put(EngineType.H2.getName(), new H2Adaptor());
    dbAdaptorMap.put(EngineType.HANADB.getName(), new HanadbAdaptor());
    dbAdaptorMap.put(EngineType.STARROCKS.getName(), new StarrocksAdaptor());
}
```

## 三、数据库适配器实现

### 1. MySQL 适配器

**[MysqlAdaptor.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/MysqlAdaptor.java)**

```java
// 日期格式转换示例
getDateFormat("MONTH", "yyyyMMdd", column)
    → "DATE_FORMAT(str_to_date(column, '%Y%m%d'),'%Y-%m')"

getDateFormat("WEEK", "yyyy-MM-dd", column)
    → "DATE_FORMAT(DATE_SUB(column, INTERVAL (DAYOFWEEK(column) - 2) DAY), '%Y-%m-%d')"
```

### 2. PostgreSQL 适配器

**[PostgresqlAdaptor.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/PostgresqlAdaptor.java)**

```java
@Override
public String rewriteSql(String sql) {
    Map<String, String> functionMap = new HashMap<>();
    functionMap.put("MONTH".toLowerCase(), "TO_CHAR");
    functionMap.put("DAY".toLowerCase(), "TO_CHAR");
    functionMap.put("YEAR".toLowerCase(), "TO_CHAR");

    // 添加格式参数
    functionCall.put("MONTH".toLowerCase(), o -> {
        if (o instanceof ExpressionList) {
            ExpressionList expressionList = (ExpressionList) o;
            expressionList.add(new StringValue("MM"));
            return expressionList;
        }
        return o;
    });

    sql = SqlReplaceHelper.replaceFunction(sql, functionMap, functionCall);
    sql = sql.replaceAll("`", "\""); // 反引号替换为双引号
    return sql;
}
```

### 3. ClickHouse 适配器

**[ClickHouseAdaptor.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/ClickHouseAdaptor.java)**

```java
@Override
public String rewriteSql(String sql) {
    Map<String, String> functionMap = new HashMap<>();
    functionMap.put("MONTH".toLowerCase(), "toMonth");
    functionMap.put("DAY".toLowerCase(), "toDayOfMonth");
    functionMap.put("YEAR".toLowerCase(), "toYear");
    return SqlReplaceHelper.replaceFunction(sql, functionMap);
}

// 日期格式转换
getDateFormat("MONTH", "yyyyMMdd", column)
    → "toYYYYMM(toDate(parseDateTimeBestEffort(toString(column))))"
```

### 4. DuckDB 适配器

**[DuckdbAdaptor.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/DuckdbAdaptor.java)**

```java
@Override
public String rewriteSql(String sql) {
    // DuckDB 不使用反引号
    return sql.replaceAll("`", "");
}
```

### 5. Presto/Trino 适配器

**[PrestoAdaptor.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/PrestoAdaptor.java)**

```java
// Presto 日期函数
getDateFormat("DAY", "yyyyMMdd", column)
    → "date_format(date_parse(column, '%Y%m%d'), '%Y-%m-%d')"

getDateFormat("WEEK", "yyyy-MM-dd", column)
    → "date_format(date_add('day', - (day_of_week(column) - 2), column), '%Y-%m-%d')"
```

**TrinoAdaptor** 继承 PrestoAdaptor（共享实现）

### 6. Kyuubi 适配器

**[KyuubiAdaptor.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/KyuubiAdaptor.java)**

```java
// Hive Spark SQL 语法
getDateFormat("DAY", "yyyyMMdd", column)
    → "date_format(to_date(cast(column as string), 'yyyyMMdd'), 'yyyy-MM-dd')"

getDateFormat("WEEK", "yyyy-MM-dd", column)
    → "date_format(date_sub(column, (dayofweek(column) - 2)), 'yyyy-MM-dd')"

// 使用 SHOW DATABASES 而非 JDBC 元数据
```

### 7. H2 适配器

**[H2Adaptor.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/H2Adaptor.java)**

```java
// H2 特定日期函数
getDateFormat("MONTH", "yyyyMMdd", column)
    → "FORMATDATETIME(PARSEDATETIME(column, 'yyyyMMdd'),'yyyy-MM')"

getDateFormat("WEEK", "yyyy-MM-dd", column)
    → "DATE_TRUNC('week', column)"
```

### 8. HANA DB 适配器

**[HanadbAdaptor.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/HanadbAdaptor.java)**

```java
@Override
public String rewriteSql(String sql) {
    // 反引号转双引号
    sql = sql.replaceAll("`(.*?)`", "\"$1\"");
    // 移除大写标识符的引号
    sql = sql.replaceAll("\"([A-Z0-9_]+?)\"", "$1");
    return sql;
}
```

### 9. StarRocks 适配器

**[StarrocksAdaptor.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/StarrocksAdaptor.java)**

- 继承 MysqlAdaptor
- 使用 SHOW DATABASES/TABLES
- 特殊的目录处理（SET CATALOG 命令）

## 四、日期函数映射表

| 数据库 | DAY (yyyyMMdd) | MONTH | WEEK |
|--------|----------------|-------|------|
| **MySQL** | `date_format(str_to_date(col, '%Y%m%d'),'%Y-%m-%d')` | `DATE_FORMAT(col, '%Y-%m')` | `DATE_FORMAT(DATE_SUB(col, INTERVAL (DAYOFWEEK(col) - 2) DAY), '%Y-%m-%d')` |
| **PostgreSQL** | `to_char(to_date(col,'yyyymmdd'), 'yyyy-mm-dd')` | `to_char(col, 'yyyy-mm')` | `to_char(date_trunc('week',to_date(col, 'yyyymmdd')),'yyyy-mm-dd')` |
| **ClickHouse** | `toDate(parseDateTimeBestEffort(toString(col)))` | `toYYYYMM(toDate(...))` | `toMonday(toDate(...))` |
| **Presto/Trino** | `date_format(date_parse(col, '%Y%m%d'), '%Y-%m-%d')` | `date_format(col, '%Y-%m')` | `date_format(date_add('day', - (day_of_week(col) - 2), col), '%Y-%m-%d')` |
| **Kyuubi** | `date_format(to_date(cast(col as string), 'yyyyMMdd'), 'yyyy-MM-dd')` | `date_format(col, 'yyyy-MM')` | `date_format(date_sub(col, (dayofweek(col) - 2)), 'yyyy-MM-dd')` |
| **H2** | `PARSE_DATETIME(col, 'yyyyMMdd')` | `FORMATDATETIME(..., 'yyyy-MM')` | `DATE_TRUNC('week', col)` |

## 五、JSQLParser 精细转换

**[SqlReplaceHelper.java](common/src/main/java/com/tencent/supersonic/common/jsqlparser/SqlReplaceHelper.java)**

```java
// 函数名替换
public static String replaceFunction(String sql, Map<String, String> functionMap)

// 函数名 + 参数替换
public static String replaceFunction(String sql, Map<String, String> functionMap,
                                      Map<String, Function<Object, Object>> functionCall)

// 字段名替换
public static String replaceFields(String sql, Map<String, String> fieldNameMap)

// 表名替换
public static String replaceTable(String sql, String tableName)

// 别名反引号处理（中文支持）
public static String replaceAliasWithBackticks(String sql)
```

## 六、优化器链

**Spring SPI 注册** ([spring.factories](launchers/headless/src/main/resources/META-INF/spring.factories))

```properties
com.tencent.supersonic.headless.core.translator.optimizer.QueryOptimizer=\
    com.tencent.supersonic.headless.core.translator.optimizer.DbDialectOptimizer,\
    com.tencent.supersonic.headless.core.translator.optimizer.ResultLimitOptimizer
```

**执行顺序：**
1. DbDialectOptimizer - 数据库方言转换
2. ResultLimitOptimizer - 添加 LIMIT 子句

## 七、关键设计模式

1. **适配器模式**: DbAdaptor 接口 + 数据库特定实现
2. **工厂模式**: DbAdaptorFactory、SqlDialectFactory
3. **策略模式**: QueryOptimizer 实现
4. **建造者模式**: SqlBuilder 构造 Calcite SQL 节点
5. **模板方法**: BaseDbAdaptor 提供通用功能
6. **访问者模式**: JSQLParser 的 AST 遍历

## 八、添加新数据库支持步骤

1. 在 `EngineType` 枚举中添加新类型
2. 实现 `DbAdaptor` 接口
3. 在 `DbAdaptorFactory` 中注册
4. 如需特殊参数，实现 `DbParametersBuilder`
5. 在 `SqlDialectFactory` 中添加 Calcite 方言配置（可选）

## 九、关键文件路径

| 功能 | 文件路径 |
|------|----------|
| 主翻译器 | [headless/core/.../DefaultSemanticTranslator.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/translator/DefaultSemanticTranslator.java) |
| SQL 构建器 | [headless/core/.../calcite/SqlBuilder.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/translator/parser/calcite/SqlBuilder.java) |
| 方言工厂 | [common/.../calcite/SqlDialectFactory.java](common/src/main/java/com/tencent/supersonic/common/calcite/SqlDialectFactory.java) |
| 自定义方言 | [common/.../calcite/SemanticSqlDialect.java](common/src/main/java/com/tencent/supersonic/common/calcite/SemanticSqlDialect.java) |
| 方言优化器 | [headless/core/.../DbDialectOptimizer.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/translator/optimizer/DbDialectOptimizer.java) |
| 适配器工厂 | [headless/core/.../adaptor/db/DbAdaptorFactory.java](headless/core/src/main/java/com/tencent/supersonic/headless/core/adaptor/db/DbAdaptorFactory.java) |
| SQL 替换助手 | [common/.../jsqlparser/SqlReplaceHelper.java](common/src/main/java/com/tencent/supersonic/common/jsqlparser/SqlReplaceHelper.java) |
| 配置类 | [common/.../calcite/Configuration.java](common/src/main/java/com/tencent/supersonic/common/calcite/Configuration.java) |
