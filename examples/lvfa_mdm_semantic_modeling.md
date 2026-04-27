# lvfa_mdm 语义建模示例

本文档记录了将外部 PostgreSQL 数据库中 lvfa_mdm schema 的物业主数据表接入 SuperSonic 并完成语义建模的全过程。

## 背景

lvfa_mdm 是绿发物业的 MDM（主数据管理）schema，包含 27 张业务表，按域分类：

| 域 | 前缀 | 说明 | 核心表 |
|---|---|---|---|
| W（物业） | mdm_w* | 物业资产类 | 项目、物业单元、设备、仪表等 |
| H（住户） | mdm_h* | 客户/住户类 | 客户、账户、订阅、人员等 |
| F（费用） | mdm_f* | 财务费用类 | 合同、业务项目、账单、科目等 |
| E（企业） | mdm_e* | 运营管理类 | 工作计划、工单等 |

## 前置条件

- SuperSonic 已部署运行（本例使用 Docker 部署，端口 9080）
- 外部 PostgreSQL 数据库可从 SuperSonic 容器网络访问
- 已有管理员账号（admin）

## 步骤一：添加数据库连接

通过 SuperSonic 管理界面（数据库管理页面）或 API 添加外部数据源。

关键参数：

| 参数 | 值 |
|---|---|
| 名称 | lvfa_mdm物业主数据 |
| 类型 | POSTGRESQL |
| JDBC URL | `jdbc:postgresql://192.168.31.123:5433/postgres?currentSchema=lvfa_mdm&stringtype=unspecified` |
| 用户名 | sc-postgresql |
| 密码 | postgres |

**注意事项：**
- `currentSchema=lvfa_mdm` 参数指定默认 schema
- `stringtype=unspecified` 避免 PostgreSQL 类型转换问题
- 添加后务必点击"测试连接"验证连通性

## 步骤二：查看源表结构

使用 psql 查看表列表和字段信息：

```bash
# 查看所有表
PGPASSWORD=postgres psql -h 192.168.31.123 -p 5433 -U sc-postgresql -d postgres \
  -c "SELECT tablename FROM pg_tables WHERE schemaname = 'lvfa_mdm' ORDER BY tablename;"

# 查看指定表的字段
PGPASSWORD=postgres psql -h 192.168.31.123 -p 5433 -U sc-postgresql -d postgres \
  -c "SELECT table_name, column_name, data_type, is_nullable
      FROM information_schema.columns
      WHERE table_schema = 'lvfa_mdm'
      AND table_name IN ('mdm_w7_project','mdm_f3_bill')
      ORDER BY table_name, ordinal_position;"
```

## 步骤三：创建语义模型

使用 SuperSonic API 批量创建模型。核心 API 端点：

- 批量创建：`POST /api/semantic/model/createModelBatch`
- 更新模型：`POST /api/semantic/model/updateModel`

### 3.1 创建模型基础信息

```bash
# 获取认证 Token（从浏览器 localStorage 的 SUPERSONIC_TOKEN 获取）
TOKEN="your_jwt_token_here"

# 批量创建模型
for table_info in \
  "MDM项目|mdm_w7_project" \
  "MDM物业单元|mdm_w2_property_unit" \
  "MDM客户|mdm_h1_customer" \
  "MDM账单|mdm_f3_bill" \
  "MDM合同|mdm_f1_contract" \
  "MDM工单|mdm_e2_work_order" \
  "MDM设备|mdm_w5_equipment"
do
  IFS='|' read -r name bizName <<< "$table_info"
  curl -s -X POST "http://localhost:9080/api/semantic/model/createModelBatch" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$name\",
      \"bizName\": \"$bizName\",
      \"databaseId\": 3,
      \"domainId\": 4,
      \"tables\": [\"$bizName\"],
      \"buildByLLM\": false
    }"
done
```

参数说明：
- `databaseId`: 数据库连接 ID（在数据库管理页面可查看）
- `domainId`: 主题域 ID（在语义建模页面可查看）
- `tables`: 源表名列表
- `buildByLLM`: 是否用 LLM 自动识别字段语义（设为 false 手动配置）

### 3.2 配置模型字段映射

创建模型后需要通过 `updateModel` API 补充维度、度量和标识字段。

以下以 **MDM账单（mdm_f3_bill）** 为例，展示完整的模型配置：

```json
{
  "id": 30,
  "name": "MDM账单",
  "bizName": "mdm_f3_bill",
  "description": "lvfa_mdm账单明细",
  "domainId": 4,
  "databaseId": 3,
  "status": 1,
  "sensitiveLevel": 0,
  "modelDetail": {
    "queryType": "table_query",
    "sqlQuery": null,
    "tableQuery": "mdm_f3_bill",
    "filterSql": null,
    "fields": [],
    "sqlVariables": [],
    "identifiers": [
      {
        "name": "账单ID",
        "type": "primary",
        "expr": "bill_id",
        "bizName": "mdm_f3_bill_id",
        "description": "账单ID"
      }
    ],
    "dimensions": [
      {
        "name": "账单类型", "type": "categorical", "expr": "bill_type",
        "dateFormat": "yyyy-MM-dd", "typeParams": null, "isCreateDimension": 0,
        "bizName": "mdm_f3_bill_type", "description": "账单类型", "fieldName": "bill_type"
      },
      {
        "name": "账单状态", "type": "categorical", "expr": "status",
        "dateFormat": "yyyy-MM-dd", "typeParams": null, "isCreateDimension": 0,
        "bizName": "mdm_f3_status", "description": "账单状态", "fieldName": "status"
      },
      {
        "name": "费用期间开始", "type": "time", "expr": "period_start",
        "dateFormat": "yyyy-MM-dd", "typeParams": null, "isCreateDimension": 0,
        "bizName": "mdm_f3_period_start", "description": "费用期间开始", "fieldName": "period_start"
      }
    ],
    "measures": [
      {
        "name": "应收金额", "agg": "sum", "expr": "amount_due",
        "bizName": "mdm_f3_amount_due", "description": "应收金额", "fieldName": "amount_due"
      },
      {
        "name": "实收金额", "agg": "sum", "expr": "amount_paid",
        "bizName": "mdm_f3_amount_paid", "description": "实收金额", "fieldName": "amount_paid"
      },
      {
        "name": "账单数量", "agg": "count", "expr": "bill_id",
        "bizName": "mdm_f3_bill_count", "description": "账单数量", "fieldName": "bill_id"
      }
    ]
  }
}
```

#### 字段类型说明

| 字段类型 | 用途 | 示例 |
|---|---|---|
| identifier (primary) | 主键标识 | bill_id, project_id |
| dimension (categorical) | 分类维度 | 账单类型、状态、城市 |
| dimension (time) | 时间维度 | 创建时间、费用期间 |
| measure (sum) | 求和度量 | 应收金额、建筑面积 |
| measure (count) | 计数度量 | 账单数量、工单数量 |
| measure (avg) | 平均度量 | 健康评分 |

## 步骤四：模型配置汇总

7 个核心表的字段配置如下：

### MDM项目（mdm_w7_project）
| 类型 | 字段 | 说明 |
|---|---|---|
| 标识 | project_id | 项目ID |
| 维度 | project_code, project_name, biz_type, status, city | 项目基本信息 |
| 时间维度 | inception_date, exit_date | 启动/退出日期 |
| 度量 | total_gfa (sum) | 总建筑面积 |

### MDM物业单元（mdm_w2_property_unit）
| 类型 | 字段 | 说明 |
|---|---|---|
| 标识 | prop_id | 物业ID |
| 维度 | prop_no, prop_type, building_no, ownership_status | 物业属性 |
| 度量 | gfa (sum), billing_area (sum) | 建筑面积、计费面积 |

### MDM客户（mdm_h1_customer）
| 类型 | 字段 | 说明 |
|---|---|---|
| 标识 | global_id | 客户全局ID |
| 维度 | cust_type, cust_name, gender, occupancy_status, spending_tier | 客户属性 |
| 度量 | asset_count (sum), parking_count (sum) | 资产/车位数量 |

### MDM账单（mdm_f3_bill）
| 类型 | 字段 | 说明 |
|---|---|---|
| 标识 | bill_id | 账单ID |
| 维度 | bill_type, status, contract_id, project_id, reconcile_status | 账单属性 |
| 时间维度 | period_start, due_date | 费用期间、到期日 |
| 度量 | amount_due (sum), amount_paid (sum), amount_outstanding (sum), bill_id (count) | 金额与数量 |

### MDM合同（mdm_f1_contract）
| 类型 | 字段 | 说明 |
|---|---|---|
| 标识 | contract_id | 合同ID |
| 维度 | contract_type, contract_name, party_a, party_b, status | 合同属性 |
| 时间维度 | start_date, end_date | 合同期限 |
| 度量 | amount (sum) | 合同金额 |

### MDM工单（mdm_e2_work_order）
| 类型 | 字段 | 说明 |
|---|---|---|
| 标识 | wo_id | 工单ID |
| 维度 | wo_no, defect_type, source, priority, status | 工单属性 |
| 时间维度 | created_at | 创建时间 |
| 度量 | sla_hours (sum), wo_id (count) | SLA时限、工单数量 |

### MDM设备（mdm_w5_equipment）
| 类型 | 字段 | 说明 |
|---|---|---|
| 标识 | equip_gid | 设备ID |
| 维度 | equip_code, equip_name, equip_category, asset_level, brand, status | 设备属性 |
| 时间维度 | install_date | 安装日期 |
| 度量 | health_score (avg) | 健康评分 |

## 步骤五：验证查询

在"问答对话"中选择对应的智能助理（如"物业管家"），输入自然语言查询进行验证：

- "MDM账单的应收总金额是多少" → 返回 83,006,997.49
- "MDM项目有哪些城市" → 返回项目城市分布
- "MDM工单按状态统计数量" → 返回各状态工单数

## 常见问题

### 1. API 认证失败

curl 直接调用 POST 接口可能遇到 403 错误，解决方法是在浏览器上下文中通过 `page.evaluate` 调用 fetch API，自动携带认证信息：

```javascript
// 在浏览器控制台或 Playwright page.evaluate 中执行
const token = localStorage.getItem('SUPERSONIC_TOKEN');
const resp = await fetch('/api/semantic/model/updateModel', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token
  },
  body: JSON.stringify(modelConfig)
});
```

### 2. modelDetail 为 null

`createModelBatch` 只创建模型基础信息，不自动填充字段映射。需要再调用 `updateModel` 补充 modelDetail。

### 3. 查询不到新建模型的数据

新建的模型需要在对应的数据集中关联，或确保智能助理配置了包含该模型的数据集。
