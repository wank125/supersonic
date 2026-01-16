# SuperSonic 最新报错详细分析

**报告生成时间**: 2026-01-15
**分析对象**: Docker 部署的 SuperSonic 应用

---

## 一、错误概述

### 1.1 用户查询
```
对比alice和lucy的停留时长
```

### 1.2 错误时间
2026-01-15 16:22:23

### 1.3 错误类型
- **NullPointerException**: LLM 返回空 SQL
- **字段不匹配**: 查询字段与语义字段不匹配

---

## 二、错误详情

### 2.1 主要错误 - NullPointerException

**错误堆栈**:
```
java.lang.NullPointerException: Cannot invoke "OnePassSCSqlGenStrategy$SemanticSql.getSql()" because "s2Sql" is null
at com.tencent.supersonic.headless.chat.parser.llm.OnePassSCSqlGenStrategy.lambda$generate$0(OnePassSCSqlGenStrategy.java:92)
at java.base/java.util.stream.ForEachOps$ForEachOp$OfRef.accept(ForEachOps.java:184)
at java.base/java.util.HashMap$KeySpliterator.forEachRemaining(HashMap.java:1715)
...
at com.tencent.supersonic.headless.server.facade.service.impl.S2ChatLayerService.parse(S2ChatLayerService.java:74)
```

**发生位置**: `OnePassSCSqlGenStrategy.java:92`

### 2.2 次要错误 - 字段不匹配

**错误信息**:
```
Querying columns[[用户, 数据日期, 停留时长]] not matched with semantic fields[[停留时长, 数据日期]]
```

**原因**: LLM 生成的 SQL 使用了中文字段名，与数据库字段不匹配

---

## 三、LLM 生成的问题 SQL

### 3.1 LLM 生成的 SQL（错误）
```sql
SELECT 用户, SUM(停留时长) AS _停留时长_
FROM 超音数数据集
WHERE 用户 IN ('alice', 'lucy')
AND 数据日期 >= '2026-01-01' AND 数据日期 <= '2026-01-15'
GROUP BY 用户
```

**问题**:
1. 字段 `用户` - 实际表中不存在
2. 字段 `停留时长` - 实际表中不存在
3. 表 `超音数数据集` - 实际表名为 `s2_stay_time_statis`

### 3.2 期望的正确 SQL
```sql
SELECT user_name, SUM(stay_hours)
FROM s2_stay_time_statis
WHERE user_name IN ('alice', 'lucy')
AND imp_date >= '2026-01-01' AND imp_date <= '2026-01-15'
GROUP BY user_name
```

---

## 四、根因分析

### 4.1 根因 1: LLM 返回空 SQL

**问题代码**: `OnePassSCSqlGenStrategy.java:90-95`
```java
prompt2Exemplar.keySet().parallelStream().forEach(prompt -> {
    SemanticSql s2Sql = extractor.generateSemanticSql(prompt.toUserMessage().singleText());
    output2Prompt.put(s2Sql.getSql(), prompt);  // 第92行 - NPE发生位置
    keyPipelineLog.info("OnePassSCSqlGenStrategy modelReq:\n{} \nmodelResp:\n{}",
            prompt.text(), s2Sql);
});
```

**原因**:
- LLM 无法解析 prompt 或返回格式不符合预期
- `SemanticSql.sql` 字段为 `null`
- 代码没有 null 检查保护

### 4.2 根因 2: Schema 传递使用中文字段名

**问题代码**: `PromptHelper.java:84-170`
```java
// 构建度量字段 - 使用 getName() 而非 getBizName()
llmReq.getSchema().getMetrics().stream().forEach(metric -> {
    metricStr.append(metric.getName());  // 中文名称，如 "停留时长"
    // ...
});

// 构建维度字段 - 使用 getName() 而非 getBizName()
llmReq.getSchema().getDimensions().stream().forEach(dimension -> {
    dimensionStr.append(dimension.getName());  // 中文名称，如 "用户"
    // ...
});
```

**后果**:
- LLM 接收到的 Schema 信息是中文字段名
- LLM 基于这些中文名称生成 SQL
- 生成的 SQL 与实际数据库字段不匹配

### 4.3 根因 3: 字段匹配逻辑依赖精确匹配

**问题代码**: `SqlQueryParser.java:183-260`
```java
// 只匹配 name 或 bizName
if (fields.contains(m.getName()) || fields.contains(m.getBizName())) {
    ontologyQuery.getMetricMap()...add(m);
    // ...
}
```

**问题**:
- LLM 生成的中文字段名可能与 `name` 或 `bizName` 都不匹配
- 缺少模糊匹配或别名匹配机制
- 导致字段验证失败

---

## 五、修复方案

### 5.1 方案 1: 空指针保护（高优先级）

**文件**: `headless/chat/src/main/java/com/tencent/supersonic/headless/chat/parser/llm/OnePassSCSqlGenStrategy.java`

**修改位置**: 第90-95行

```java
prompt2Exemplar.keySet().parallelStream().forEach(prompt -> {
    SemanticSql s2Sql = extractor.generateSemanticSql(prompt.toUserMessage().singleText());
    // 添加 null 检查
    if (s2Sql != null && StringUtils.isNotBlank(s2Sql.getSql())) {
        output2Prompt.put(s2Sql.getSql(), prompt);
        keyPipelineLog.info("OnePassSCSqlGenStrategy modelReq:\n{} \nmodelResp:\n{}",
                prompt.text(), s2Sql);
    } else {
        log.warn("LLM returned null or empty SQL for prompt: {}", prompt.text());
    }
});
```

### 5.2 方案 2: 修改 Prompt 指令（中优先级）

**文件**: `headless/chat/src/main/java/com/tencent/supersonic/headless/chat/parser/llm/OnePassSCSqlGenStrategy.java`

**修改位置**: `INSTRUCTION` 常量

添加以下规则：
```java
"\n8.CRITICAL: In Schema, field names are shown as <FieldName>. Use EXACTLY these field names in your SQL."
```

### 5.3 方案 3: 使用 bizName 构建 Schema（长期方案）

**文件**: `headless/chat/src/main/java/com/tencent/supersonic/headless/chat/parser/llm/PromptHelper.java`

**修改位置**: `buildSchemaStr()` 方法

```java
// 使用 bizName 作为主要字段名
metricStr.append(metric.getBizName());  // 数据库字段名
metricStr.append("|");
metricStr.append(metric.getName());     // 中文名称作为参考
```

---

## 六、关键文件清单

| 文件 | 路径 | 问题描述 |
|------|------|----------|
| OnePassSCSqlGenStrategy.java | headless/chat/src/main/java/com/tencent/supersonic/headless/chat/parser/llm/OnePassSCSqlGenStrategy.java | 第92行空指针异常 |
| PromptHelper.java | headless/chat/src/main/java/com/tencent/supersonic/headless/chat/parser/llm/PromptHelper.java | 使用 getName() 构建 Schema |
| SqlQueryParser.java | headless/core/src/main/java/com/tencent/supersonic/headless/core/translator/parser/SqlQueryParser.java | 字段匹配逻辑 |
| DefaultSemanticTranslator.java | headless/core/src/main/java/com/tencent/supersonic/headless/core/translator/DefaultSemanticTranslator.java | mergeOntologyQuery 验证 |

---

## 七、SchemaElement 字段定义

```java
@Data
public class SchemaElement implements Serializable {
    private String name;      // 中文名称，如 "停留时长"
    private String bizName;   // 业务名称/数据库字段名，如 "stay_hours"
    // ...其他字段...
}
```

---

## 八、数据库字段映射

### s2_stay_time_statis 表结构

| 中文名称 | 数据库字段 | 类型 |
|----------|-----------|------|
| 用户 | user_name | VARCHAR |
| 数据日期 | imp_date | DATE |
| 停留时长 | stay_hours | NUMERIC |
| 页面 | page | VARCHAR |

---

## 九、总结

### 9.1 问题链路

```
用户查询 "对比alice和lucy的停留时长"
    ↓
Schema 构建使用中文字段名 (PromptHelper.java)
    ↓
LLM 接收中文字段名
    ↓
LLM 生成使用中文字段名的 SQL
    ↓
字段验证失败 (SqlQueryParser.java)
    ↓
NullPointerException (OnePassSCSqlGenStrategy.java:92)
```

### 9.2 根本原因

1. **设计问题**: Schema 使用 `getName()` 而非 `getBizName()` 传递给 LLM
2. **保护缺失**: 缺少空指针检查
3. **匹配逻辑**: 字段匹配依赖精确匹配，容错性差

### 9.3 建议修复顺序

1. **高优先级**: 添加空指针保护（方案 1）- 防止应用崩溃
2. **中优先级**: 改进 Prompt 指令（方案 2）- 提高 LLM 准确性
3. **长期方案**: 重构 Schema 构建逻辑（方案 3）

---

## 十、参考资料

- 错误日志: `/usr/src/app/supersonic-standalone-1.0.0-SNAPSHOT/logs/s2-error.log`
- LLM 日志: `/usr/src/app/supersonic-standalone-1.0.0-SNAPSHOT/logs/s2-llm.log`
- 聊天服务日志: `/usr/src/app/supersonic-standalone-1.0.0-SNAPSHOT/logs/serviceinfo.chat.log`
