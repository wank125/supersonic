# SuperSonic 成功查询的 SQL 生成分析

**分析时间**: 2026-01-15
**查询**: "对比alice和lucy的停留时长"

---

## 一、成功案例概览

### 1.1 查询 "对比alice和lucy的停留时长" - 最终成功

**执行时间**: 2026-01-15 15:19:42
**状态**: ✅ 成功

**完整日志**:
```
15:19:42,542 [INFO] parse with ontologyQuery fields: [[user_name, stay_hours, imp_date]]

15:19:42,545 [INFO] SqlInfoProcessor results:
Parsed S2SQL: SELECT 数据日期, SUM(停留时长) FROM `超音数数据集` WHERE 用户名 IN ('alice', 'lucy') AND 数据日期 >= '2026-01-08' AND 数据日期 <= '2026-01-15' GROUP BY 数据日期 LIMIT 200 OFFSET 0
Corrected S2SQL: SELECT 数据日期, SUM(停留时长) FROM `超音数数据集` WHERE 用户名 IN ('alice', 'lucy') AND 数据日期 >= '2026-01-08' AND 数据日期 <= '2026-01-15' GROUP BY 数据日期 LIMIT 200 OFFSET 0
Query SQL: WITH t_1 AS (SELECT user_name, stay_hours, imp_date FROM s2_stay_time_statis) SELECT imp_date, SUM(stay_hours) AS stay_hours FROM t_1 WHERE user_name IN ('alice', 'lucy') AND imp_date >= '2026-01-08' AND imp_date <= '2026-01-15' GROUP BY imp_date LIMIT 200 OFFSET 0

15:19:42,794 [INFO] executing SQL: WITH t_1 AS (SELECT user_name, stay_hours, imp_date FROM s2_stay_time_statis) SELECT imp_date, SUM(stay_hours) AS stay_hours FROM t_1 WHERE user_name IN ('alice', 'lucy') AND imp_date >= '2026-01-08' AND imp_date <= '2026-01-15' GROUP BY imp_date LIMIT 200 OFFSET 0
```

---

## 二、SQL 转换流程分析

### 2.1 三层 SQL 结构

| 层级 | SQL | 说明 |
|------|-----|------|
| **Parsed S2SQL** | `SELECT 数据日期, SUM(停留时长) FROM 超音数数据集 WHERE 用户名 IN ('alice', 'lucy')...` | 语义层SQL，使用中文字段名 |
| **Corrected S2SQL** | `SELECT 数据日期, SUM(停留时长) FROM 超音数数据集 WHERE 用户名 IN ('alice', 'lucy')...` | 修正后的语义SQL |
| **Query SQL** | `WITH t_1 AS (SELECT user_name, stay_hours, imp_date FROM s2_stay_time_statis) SELECT imp_date, SUM(stay_hours) AS stay_hours FROM t_1...` | 实际执行的SQL，使用数据库字段名 |

### 2.2 SQL 对比详解

#### Parsed S2SQL（语义层）
```sql
SELECT 数据日期, SUM(停留时长)
FROM `超音数数据集`
WHERE 用户名 IN ('alice', 'lucy')
AND 数据日期 >= '2026-01-08' AND 数据日期 <= '2026-01-15'
GROUP BY 数据日期
LIMIT 200 OFFSET 0
```

**特点**:
- 使用中文字段名：`数据日期`、`停留时长`、`用户名`
- 使用中文表名：`超音数数据集`
- 这是用户友好的表示方式

#### Query SQL（实际执行）
```sql
WITH t_1 AS (
    SELECT user_name, stay_hours, imp_date
    FROM s2_stay_time_statis
)
SELECT imp_date, SUM(stay_hours) AS stay_hours
FROM t_1
WHERE user_name IN ('alice', 'lucy')
AND imp_date >= '2026-01-08' AND imp_date <= '2026-01-15'
GROUP BY imp_date
LIMIT 200 OFFSET 0
```

**特点**:
- 使用实际数据库字段名：`user_name`、`stay_hours`、`imp_date`
- 使用实际表名：`s2_stay_time_statis`
- 使用 CTE (WITH 子句) 进行数据提取
- 这是真正可以执行的 SQL

---

## 三、字段映射关系

### 3.1 语义字段到数据库字段的映射

| 语义字段（中文） | 数据库字段（英文） | 数据类型 | 说明 |
|-----------------|-------------------|----------|------|
| 数据日期 | imp_date | DATE | 分区时间字段 |
| 停留时长 | stay_hours | NUMERIC | 指标字段 |
| 用户名 | user_name | VARCHAR | 维度字段 |

### 3.2 表映射

| 语义表名 | 数据库表名 | 说明 |
|----------|-----------|------|
| 超音数数据集 | s2_stay_time_statis | 停留时长统计表 |

---

## 四、其他成功案例

### 4.1 查询 "alice的停留时长"（单用户）

**执行时间**: 2026-01-15 15:18:10

**Query SQL**:
```sql
WITH t_1 AS (
    SELECT user_name, stay_hours, imp_date
    FROM s2_stay_time_statis
)
SELECT imp_date, SUM(stay_hours) AS stay_hours
FROM t_1
WHERE user_name = 'alice'
AND imp_date >= '2026-01-08' AND imp_date <= '2026-01-15'
GROUP BY imp_date
LIMIT 200 OFFSET 0
```

### 4.2 查询 "各公司员工都有多少人"

**执行时间**: 2026-01-15 14:34:32

**Query SQL**:
```sql
WITH t_2 AS (
    SELECT employee_count, company_id, company_name
    FROM company
)
SELECT company_id, company_name, SUM(employee_count) AS "_员工数_"
FROM t_2
GROUP BY company_id, company_name
LIMIT 1000
```

### 4.3 查询 "按部门统计访问人数"（多表关联）

**执行时间**: 2026-01-15 14:30:41

**Query SQL**:
```sql
WITH t_1 AS (
    SELECT t3.user_name, t3.imp_date, t2.department
    FROM (SELECT * FROM s2_user_department) AS t2
    LEFT JOIN (SELECT * FROM s2_pv_uv_statis) AS t3
    ON t2.user_name = t3.user_name
)
SELECT department, (count(1)), (count(DISTINCT user_name)), (count(1) / count(DISTINCT user_name))
FROM t_1
WHERE imp_date >= '2026-01-08' AND imp_date <= '2026-01-15'
GROUP BY department
LIMIT 200 OFFSET 0
```

### 4.4 简单统计查询示例

| 查询 | Query SQL |
|------|-----------|
| 按部门统计 | `WITH t_null AS (SELECT department FROM s2_user_department) SELECT department, count(1) FROM t_null GROUP BY department ORDER BY count(1) DESC LIMIT 100000` |
| 按用户统计 | `WITH t_null AS (SELECT user_name FROM s2_user_department) SELECT user_name, count(1) FROM t_null GROUP BY user_name ORDER BY count(1) DESC LIMIT 100000` |
| 按CEO统计 | `WITH t_null AS (SELECT ceo FROM company) SELECT ceo, count(1) FROM t_null GROUP BY ceo ORDER BY count(1) DESC LIMIT 100000` |
| 按歌手统计 | `WITH t_null AS (SELECT singer_name FROM singer) SELECT singer_name, count(1) FROM t_null GROUP BY singer_name ORDER BY count(1) DESC LIMIT 100000` |

---

## 五、SQL 生成模式总结

### 5.1 通用 CTE 模式

**结构**:
```sql
WITH t_{n} AS (
    SELECT {字段列表}
    FROM {实际表名}
)
SELECT {查询字段}
FROM t_{n}
WHERE {条件}
GROUP BY {分组字段}
LIMIT {限制} OFFSET {偏移}
```

**说明**:
- `{n}`: 表编号（1, 2, 3...）
- CTE 用于数据提取和预处理
- 主查询使用 CTE 结果

### 5.2 多表关联模式

**结构**:
```sql
WITH t_{n} AS (
    SELECT t{a}.{字段}, t{b}.{字段}
    FROM (SELECT * FROM {表A}) AS t{a}
    {JOIN类型} (SELECT * FROM {表B}) AS t{b}
    ON t{a}.{关联字段} = t{b}.{关联字段}
)
SELECT {查询字段}
FROM t_{n}
WHERE {条件}
GROUP BY {分组字段}
```

### 5.3 字段别名规则

| 场景 | 别名规则 |
|------|----------|
| 聚合字段 | `SUM(stay_hours) AS stay_hours` |
| 中文指标别名 | `SUM(employee_count) AS "_员工数_"` |
| 无别名 | 直接使用字段名 |

---

## 六、关键发现

### 6.1 成功执行的关键条件

1. **正确的字段映射**: 语义层正确将中文字段名映射到数据库字段名
2. **WITH 子句**: 使用 CTE 封装原始表查询
3. **时间范围**: 自动添加时间范围条件
4. **LIMIT/OFFSET**: 默认添加分页限制

### 6.2 LLM 失败后的降级机制

当 LLM 解析失败时，系统使用**基于规则的方法**生成 SQL：

```
LLM 解析失败 → 重试 → 仍失败 → 使用规则引擎 → 生成 SQL
```

这就是为什么同一个查询在 LLM 失败后仍然能成功执行。

### 6.3 字段识别

**成功日志**:
```
parse with ontologyQuery fields: [[user_name, stay_hours, imp_date]]
```

系统正确识别了：
- `user_name` (用户名)
- `stay_hours` (停留时长)
- `imp_date` (数据日期)

---

## 七、与失败案例的对比

### 7.1 LLM 生成的问题 SQL（失败）

```sql
SELECT 用户, SUM(停留时长) AS _停留时长_
FROM 超音数数据集
WHERE 用户 IN ('alice', 'lucy')
AND 数据日期 >= '2026-01-01' AND 数据日期 <= '2026-01-15'
GROUP BY 用户
```

**问题**:
- 字段 `用户` 不存在于数据库
- 无法映射到实际字段

### 7.2 规则引擎生成的 SQL（成功）

```sql
WITH t_1 AS (
    SELECT user_name, stay_hours, imp_date
    FROM s2_stay_time_statis
)
SELECT imp_date, SUM(stay_hours) AS stay_hours
FROM t_1
WHERE user_name IN ('alice', 'lucy')
AND imp_date >= '2026-01-08' AND imp_date <= '2026-01-15'
GROUP BY imp_date
LIMIT 200 OFFSET 0
```

**优势**:
- 使用实际数据库字段名
- 使用 CTE 结构
- 可直接执行

---

## 八、总结

1. **双层 SQL 结构**: 系统维护语义层 SQL（中文）和执行层 SQL（英文）
2. **自动字段映射**: 通过 `DefaultSemanticTranslator` 完成字段映射
3. **降级机制**: LLM 失败时自动切换到规则引擎
4. **CTE 模式**: 使用 WITH 子句封装表查询，提高可读性
5. **成功关键**: 正确的语义配置和字段映射关系
