# SuperSonic Docker 部署分析报告

生成时间: 2026-01-15

---

## 一、Docker 部署配置

### 1.1 Docker Compose 配置

**文件**: `docker/docker-compose.yml`

**核心配置**:
```yaml
services:
  # PostgreSQL 数据库（带 pgvector 扩展）
  supersonic_postgres:
    image: pgvector/pgvector:pg17
    ports: ["15432:5432"]
    environment:
      POSTGRES_DB: postgres
      POSTGRES_USER: supersonic_user
      POSTGRES_PASSWORD: supersonic_password

  # SuperSonic 应用服务
  supersonic_standalone:
    image: supersonicbi/supersonic:latest
    ports: ["9080:9080"]
    environment:
      S2_DB_TYPE: postgres  # 注意：必须是 postgres，不是 postgresql
```

### 1.2 容器运行状态

| 容器名 | 状态 | 端口映射 |
|--------|------|----------|
| supersonic_postgres | Up 2 hours (healthy) | 0.0.0.0:15432->5432/tcp |
| supersonic_standalone | Up 2 hours | 0.0.0.0:9080->9080/tcp |

---

## 二、数据库初始化流程

### 2.1 初始化顺序

根据 `application-postgres.yaml` 配置，启动时按以下顺序执行：

| 阶段 | 文件 | 内容 |
|------|------|------|
| **Schema** | `schema-postgres.sql` | 37张系统表（Domain、Model、Metric、Dimension等） |
| **Schema** | `schema-postgres-demo.sql` | 8张示例业务表 |
| **Data** | `data-postgres.sql` | 系统基础数据（用户、权限配置） |
| **Data** | `data-postgres-demo.sql` | 示例业务数据 |

### 2.2 数据库连接信息

**配置**: `S2数据库DEMO`

| 配置项 | 值 |
|--------|-----|
| 类型 | PostgreSQL |
| Host | supersonic_postgres:5432 |
| Database | postgres |
| User | supersonic_user |
| 宿主机访问 | localhost:15432 |

---

## 三、业务域配置

| ID | 名称 | 英文名 |
|----|------|--------|
| 1 | 产品数据域 | supersonic |
| 2 | 企业数据域 | corporate |
| 3 | 歌手数据域 | singer |

---

## 四、示例数据集详情

### 4.1 S2VisitsDemo - 访问统计 (产品数据域)

#### 用户部门关系
| 用户 | 部门 |
|------|------|
| jack, alice | sales |
| tom, dean | marketing |
| lucy | marketing |
| john | strategy |

#### 每日访问统计 (最近15天)
| 日期 | PV | UV |
|------|----|----|
| 2026-01-15 | 6 | 5 |
| 2026-01-14 | 23 | 6 |
| 2026-01-13 | 24 | 6 |
| 2026-01-12 | 18 | 6 |
| 2026-01-11 | 19 | 6 |
| ... | ... | ... |

#### 关联模型
- `s2_user_department` - 用户部门表
- `s2_pv_uv_statis` - PV/UV统计表 (300条记录)
- `s2_stay_time_statis` - 停留时长表 (300条记录)

---

### 4.2 S2ArtistDemo - 歌手数据 (歌手数据域)

#### 歌手列表
| 歌手 | 区域 | 代表歌曲 | 流派 |
|------|------|----------|------|
| 周杰伦 | 港台 | 青花瓷 | 国风 |
| 陈奕迅 | 港台 | 爱情转移 | 流行 |
| 林俊杰 | 港台 | 美人鱼 | 流行 |
| 张碧晨 | 内地 | 光的方向 | 流行 |
| 程响 | 内地 | 人间烟火 | 国风 |
| Taylor Swift | 欧美 | Love Story | 流行 |

---

### 4.3 S2CompanyDemo - 企业数据 (企业数据域)

#### 公司信息
| 公司 | 总部 | 成立时间 | CEO | 年营收 |
|------|------|----------|-----|--------|
| 微软 | 西雅图 | 1975 | 纳德拉 | 1023亿 |
| 特斯拉 | 加州 | 2003 | 马斯克 | 3768亿 |
| 谷歌 | 加州 | 1998 | 劈柴 | 3216亿 |
| 亚马逊 | 加州 | 1994 | 贝索斯 | 288亿 |
| 英伟达 | 杭州 | 1993 | 黄仁勋 | 675亿 |

#### 品牌信息
Office, Windows, Model 3, Model Y, Google, Android, AWS, Kindle, H100, A100

---

## 五、指标配置

| ID | 指标名称 | 英文名 | 模型 | 类型 |
|----|----------|--------|------|------|
| 1 | 停留时长 | stay_hours | s2_stay_time_statis | ATOMIC |
| 2 | 访问用户数 | uv | s2_pv_uv_statis | DERIVED |
| 3 | 访问次数 | pv | s2_pv_uv_statis | DERIVED |
| 4 | 人均访问次数 | pv_avg | s2_pv_uv_statis | DERIVED |
| 5 | 年营业额 | annual_turnover | company | ATOMIC |
| 6 | 员工数 | employee_count | company | ATOMIC |
| 7 | 注册资本 | registered_capital | brand | ATOMIC |
| 8 | 营收 | revenue | brand_revenue | ATOMIC |
| 9 | 利润 | profit | brand_revenue | ATOMIC |
| 10 | 营收同比增长 | revenue_growth_year_on_year | brand_revenue | ATOMIC |
| 11 | 利润同比增长 | profit_growth_year_on_year | brand_revenue | ATOMIC |
| 12 | 播放量 | js_play_cnt | singer | ATOMIC |
| 13 | 下载量 | down_cnt | singer | ATOMIC |
| 14 | 收藏量 | favor_cnt | singer | ATOMIC |

---

## 六、维度配置

| ID | 名称 | 英文名 | 模型ID | 类型 |
|----|------|--------|--------|------|
| 1 | 部门 | department | 1 | categorical |
| 2 | 用户名 | user_name | 1 | primary_key |
| 4 | 用户名 | user_name | 2 | foreign_key |
| 5 | 数据日期 | imp_date | 3 | partition_time |
| 6 | 页面 | page | 3 | categorical |
| 7 | 用户名 | user_name | 3 | foreign_key |
| 8 | 公司名称 | company_name | 4 | categorical |
| 13 | 公司id | company_id | 4 | primary_key |
| 14 | 品牌名称 | brand_name | 5 | categorical |
| 17 | 品牌id | brand_id | 5 | primary_key |
| 18 | 公司id | company_id | 5 | foreign_key |
| 19 | 财年 | year_time | 6 | time |
| 20 | 品牌id | brand_id | 6 | foreign_key |
| 21 | 活跃区域 | act_area | 7 | categorical |

---

## 七、业务术语

| 名称 | 描述 | 别名 |
|------|------|------|
| 近期 | 指近10天 | 近一段时间 |
| 核心用户 | 用户为tom和lucy | VIP用户 |

---

## 八、数据集配置

| ID | 名称 | 英文名 | 描述 | 包含模型 |
|----|------|--------|------|----------|
| 1 | 超音数数据集 | s2 | 包含超音数访问统计相关的指标和维度等 | 用户部门, PVUV统计, 停留时长统计 |
| 2 | 企业数据集 | CorporateData | 巨头公司核心经营数据 | 公司维度, 品牌维度, 品牌历年收入 |
| 3 | 歌手数据集 | singer | 包含歌手相关标签和指标信息 | 歌手库 |

---

## 九、日志分析报告

### 9.1 日志文件位置

| 日志文件 | 路径 | 内容 |
|----------|------|------|
| **错误日志** | `/usr/src/app/supersonic-standalone-1.0.0-SNAPSHOT/logs/s2-error.log` | 错误堆栈 |
| **通用错误** | `/usr/src/app/supersonic-standalone-1.0.0-SNAPSHOT/logs/error.log` | 错误堆栈 |
| **LLM日志** | `/usr/src/app/supersonic-standalone-1.0.0-SNAPSHOT/logs/s2-llm.log` | LLM调用详情 |
| **聊天服务** | `/usr/src/app/supersonic-standalone-1.0.0-SNAPSHOT/logs/serviceinfo.chat.log` | 聊天服务日志 |
| **信息日志** | `/usr/src/app/supersonic-standalone-1.0.0-SNAPSHOT/logs/s2-info.log` | 运行信息 |

### 9.2 查看日志命令

```bash
# 查看错误日志
docker exec supersonic_standalone tail -200 /usr/src/app/supersonic-standalone-1.0.0-SNAPSHOT/logs/s2-error.log

# 查看LLM日志
docker exec supersonic_standalone tail -300 /usr/src/app/supersonic-standalone-1.0.0-SNAPSHOT/logs/s2-llm.log

# 查看聊天服务日志
docker exec supersonic_standalone tail -200 /usr/src/app/supersonic-standalone-1.0.0-SNAPSHOT/logs/serviceinfo.chat.log
```

---

## 十、主要错误问题分析

### 10.1 SQL解析失败 - 语义字段不匹配

#### 错误信息
```
Querying columns[[用户, 数据日期, 停留时长]] not matched with semantic fields[[停留时长, 数据日期]]
```

#### 问题分析
- LLM生成的SQL使用了"用户"字段，但数据集中没有对应的语义字段
- 数据集 `s2_stay_time_statis` 模型只有 `[user_name, stay_hours, imp_date]`
- LLM生成SQL时: `SELECT 用户, SUM(停留时长)...` 但表中应该是 `user_name`

#### 影响范围
查询"对比alice和lucy的停留时长"多次失败

#### 错误查询示例

**用户问题**: "对比alice和lucy的停留时长"

**LLM生成SQL**:
```sql
SELECT 用户, SUM(停留时长) AS _停留时长_
FROM 超音数数据集
WHERE 用户 IN ('alice', 'lucy')
AND 数据日期 >= '2026-01-01' AND 数据日期 <= '2026-01-15'
GROUP BY 用户
```

**实际字段应该是**:
```sql
SELECT user_name, SUM(stay_hours)
FROM s2_stay_time_statis
WHERE user_name IN ('alice', 'lucy') ...
```

---

### 10.2 LLM Text2SQL NullPointer异常

#### 错误信息
```
java.lang.NullPointerException: Cannot invoke "OnePassSCSqlGenStrategy$SemanticSql.getSql()" because "s2Sql" is null
```

#### 错误位置
```
com.tencent.supersonic.headless.chat.parser.llm.OnePassSCSqlGenStrategy.lambda$generate$0(OnePassSCSqlGenStrategy.java:92)
```

#### 重试机制
系统自动重试3次，均失败

---

### 10.3 字段映射不一致

#### 数据集配置 (s2_data_set)
- **模型1 (user_department)**: 维度 [部门, 用户名]
- **模型2 (s2_pv_uv_statis)**: 维度 [用户名, 数据日期], 指标 [uv, pv, pv_avg]
- **模型3 (s2_stay_time_statis)**: 维度 [数据日期, 用户名, 页面], 指标 [停留时长]

#### 问题
LLM生成的SQL使用中文别名"用户"而非实际字段名"user_name"

---

### 10.4 成功查询示例

#### 查询: "各公司员工都有多少人"

**结果**: ✅ 成功执行

**生成的SQL**:
```sql
SELECT 公司id, 公司名称, SUM(员工数) AS _员工数_
FROM 企业数据集
GROUP BY 公司id, 公司名称
```

---

## 十一、系统状态总结

| 状态项 | 状态 |
|--------|------|
| 容器运行 | ✅ 正常 |
| 数据库连接 | ✅ 正常 |
| 向量Embedding | ✅ 定期重载成功 (8189ms) |
| 部分查询 | ✅ 可以正常工作 |
| LLM字段映射 | ⚠️ 需要优化 |

---

## 十二、访问方式

- **Web界面**: http://localhost:9080
- **Swagger API**: http://localhost:9080/swagger-ui.html
- **数据库直连** (宿主机):
  - Host: localhost
  - Port: 15432
  - Database: postgres
  - User: supersonic_user
  - Password: supersonic_password

---

## 十三、数据库表结构汇总

### 13.1 系统核心表 (37张)

**业务域相关表**:
- `s2_domain` - 主题域基础信息表
- `s2_model` - 模型定义表
- `s2_model_rela` - 模型关系表
- `s2_database` - 数据库实例表

**指标和维度表**:
- `s2_metric` - 指标表
- `s2_dimension` - 维度表
- `s2_data_set` - 数据集表

**聊天和分析表**:
- `s2_agent` - AI助手配置表
- `s2_chat` - 聊天会话表
- `s2_chat_query` - 聊天查询表
- `s2_chat_model` - 对话大模型实例表
- `s2_chat_memory` - 聊天记忆表

**其他重要表**:
- `s2_user` - 用户表
- `s2_term` - 术语表
- `s2_tag_object` - 标签对象表
- `s2_query_rule` - 查询规则表
- `s2_query_stat_info` - 查询统计信息表

### 13.2 示例业务表 (8张)

**S2VisitsDemo**:
- `s2_user_department` - 用户部门关系表
- `s2_pv_uv_statis` - 页面浏览量统计表
- `s2_stay_time_statis` - 停留时长统计表

**S2ArtistDemo**:
- `singer` - 歌手信息表
- `genre` - 音乐流派表

**S2CompanyDemo**:
- `company` - 公司信息表
- `brand` - 品牌信息表
- `brand_revenue` - 品牌营收表

---

## 十四、LLM示例查询 (s2-exemplar.json)

系统内置8个示例查询用于训练LLM:

| 序号 | 场景 | 示例问题 |
|------|------|----------|
| 1 | 用户对比 | "比较jack和tom今年以来的访问次数" |
| 2 | 部门统计 | "超音数近12个月访问人数按部门" |
| 3 | 条件筛选 | "访问时长小于1小时且来自美术部的用户" |
| 4 | 排名查询 | "本月pv最高的用户有哪些" |
| 5 | 部门筛选 | "超音数过去90天美术部、技术研发部的访问时长" |
| 6 | 阈值筛选 | "超音数访问次数大于1k的部门是哪些" |
| 7 | 术语使用 | "过去半个月核心用户的访问次数" |
| 8 | 聚合筛选 | "过去半个月忠实用户有哪一些" |

---

## 十五、建议

1. **优化LLM字段映射**: 确保LLM生成的SQL使用正确的数据库字段名而非中文别名
2. **增强错误处理**: 改进 `OnePassSCSqlGenStrategy` 的空值处理
3. **完善语义层映射**: 确保语义字段与实际数据库字段的正确对应
4. **改进提示词**: 在LLM提示词中明确要求使用实际的数据库字段名
