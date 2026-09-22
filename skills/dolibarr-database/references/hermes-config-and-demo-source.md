# Hermes 配置与 Demo 源数据流程

本文件说明一个完整的演示闭环：先向 Dolibarr 核心业务表写入带有正常样本和少量异常的源数据，再由 Hermes 读取、分析并写入 AI 看板事实表。它不允许把预设的 AI 结论直接写进看板表。

## 1. 目标数据流

```text
Dolibarr 核心业务表
  ├─ llx_commande / llx_commandedet
  ├─ llx_commande_fournisseur / llx_commande_fournisseurdet
  ├─ llx_product / llx_product_stock / llx_stock_mouvement
  ├─ llx_entrepot / llx_societe
  └─ 可选：llx_reception / llx_receptiondet_batch / llx_facture / llx_facturedet
              │
              ▼ 只读读取、聚合、推断
           Hermes
              │
              ▼ 事务写入
  llx_ai_dashboard_run
  llx_ai_dashboard_order_risk_daily
  llx_ai_dashboard_inventory_risk_daily
              │
              ▼
        Dolibarr AI 看板
```

关键边界：

- Demo 源数据脚本可以 INSERT Dolibarr 核心业务表，但不可以 INSERT、UPDATE 或 DELETE `llx_ai_dashboard_*`。
- Hermes 的分析阶段只能读取核心业务表；Hermes 的结果阶段只能写 AI 专用三张表，除非用户另行授权。
- AI 看板显示的是 Hermes 的推断结果，不是 Demo 脚本预先写好的答案。
- 如果源数据脚本和 Hermes 连接的是不同的实体、数据库或表前缀，流程会出现“源表有数据、看板没有数据”的假象，必须先核对连接参数。

## 2. 项目内 Demo 源数据

推荐使用 `outputs/dolibarr-ai-demo-seed-large.sql`。该文件是源业务数据脚本，不写 AI 看板表，包含：

- 约 12 个月的历史数据；
- 240 条销售订单、约 720 条销售订单行；
- 96 条采购订单、约 184 条采购订单行；
- 约 75 条收货、约 150 条收货行、发票和库存流水；
- 正常数据占多数，少量订单延期、采购交期异常、低库存和呆滞库存样本；
- 日期使用 `NOW()`、`CURDATE()` 的相对表达式，重新执行前需要按脚本头部的预检确认保留 ID 范围没有冲突。

该脚本的业务主键使用 `AIH-` 前缀，ID 使用独立范围。不要在已有冲突时强行执行，也不要为了重跑而删除整个业务表。先备份，再将脚本头部的预检结果保存下来；如果范围冲突，应整体更换保留 ID 区间和业务引用前缀。

执行顺序：

1. 执行 `outputs/dolibarr-ai-dashboard.sql`，只创建 AI 专用表。
2. 审核并执行 `outputs/dolibarr-ai-demo-seed-large.sql`，只生成 Dolibarr 核心源数据。
3. 用下面的只读查询确认源数据已经落入目标实体。
4. Hermes 读取源数据、输出结构化风险结果并写入 AI 专用表。
5. 打开 AI 看板，确认其使用最新 `success` 快照。

源数据预检和执行后的只读检查：

```sql
SELECT DATABASE() AS database_name, CURRENT_USER() AS current_user,
       @@session.time_zone AS session_time_zone, @@global.time_zone AS global_time_zone;

SELECT 'products' AS metric, COUNT(*) AS row_count
FROM llx_product WHERE entity = 1 AND ref LIKE 'AIH-%'
UNION ALL SELECT 'sales_orders', COUNT(*)
FROM llx_commande WHERE entity = 1 AND ref LIKE 'AIH-SO-%'
UNION ALL SELECT 'purchase_orders', COUNT(*)
FROM llx_commande_fournisseur WHERE entity = 1 AND ref LIKE 'AIH-PO-%'
UNION ALL SELECT 'stock_movements', COUNT(*)
FROM llx_stock_mouvement sm
JOIN llx_product p ON p.rowid = sm.fk_product
WHERE p.entity = 1 AND p.ref LIKE 'AIH-%';

SELECT c.ref, c.fk_statut, c.date_livraison,
       p.ref AS product_ref, cd.qty,
       cf.ref AS purchase_ref, cf.fk_statut AS purchase_status,
       cf.date_livraison AS purchase_due_date
FROM llx_commande c
JOIN llx_commandedet cd ON cd.fk_commande = c.rowid
JOIN llx_product p ON p.rowid = cd.fk_product
LEFT JOIN llx_commande_fournisseurdet cfd ON cfd.rowid = cd.fk_commandefourndet
LEFT JOIN llx_commande_fournisseur cf ON cf.rowid = cfd.fk_commande
WHERE c.entity = 1 AND c.ref LIKE 'AIH-SO-%'
ORDER BY c.date_livraison, c.ref
LIMIT 50;
```

## 3. Hermes 需要的配置

Hermes 实际配置名称以 Hermes 的安装方式为准，不要凭空把下面的名字当成固定产品 API。下面是必须收集的配置契约。

### 3.1 数据库连接配置

至少需要：

| 配置 | 作用 | 示例/说明 |
|---|---|---|
| `DB_HOST` | MySQL 主机 | 目标 Dolibarr 数据库地址 |
| `DB_PORT` | MySQL 端口 | 通常为 `3306`，以实际连接工具为准 |
| `DB_NAME` | 数据库名 | Dolibarr 实际数据库名 |
| `DB_USER` | Hermes 数据库账号 | 推荐专用最小权限账号 |
| `DB_PASSWORD` | Hermes 数据库密码 | 放 secret manager、环境变量或本机安全配置，不放 skill、SQL 文件或聊天记录 |
| `DB_PREFIX` | 物理表前缀 | 通常为 `llx_`，从 `MAIN_DB_PREFIX` 核对 |
| `DB_CHARSET` | 字符集 | 推荐 `utf8mb4` |
| `DB_TIMEZONE` | 任务时区 | 例如 `Asia/Shanghai`，不能依赖服务器默认时区 |
| `DOLIBARR_ENTITY` | 业务实体 | 通常是 `1`，必须和源表及 AI 表一致 |

生产建议给 Hermes 单独账号：源表只授予 `SELECT`；AI 专用表按需要授予 `SELECT, INSERT, UPDATE`，只有采用“按日期完整替换”的实现时才授予限定范围内的 `DELETE`。不要直接把 Dolibarr 管理员账号交给定时任务。

权限由 DBA 依据实际数据库名、前缀和账号执行，下面只是模板，不能直接带入生产：

```sql
GRANT SELECT ON `<dolibarr_db>`.`<prefix>commande` TO '<hermes_user>'@'<hermes_host>';
GRANT SELECT ON `<dolibarr_db>`.`<prefix>commandedet` TO '<hermes_user>'@'<hermes_host>';
GRANT SELECT ON `<dolibarr_db>`.`<prefix>commande_fournisseur` TO '<hermes_user>'@'<hermes_host>';
GRANT SELECT ON `<dolibarr_db>`.`<prefix>commande_fournisseurdet` TO '<hermes_user>'@'<hermes_host>';
GRANT SELECT ON `<dolibarr_db>`.`<prefix>product` TO '<hermes_user>'@'<hermes_host>';
GRANT SELECT ON `<dolibarr_db>`.`<prefix>product_stock` TO '<hermes_user>'@'<hermes_host>';
GRANT SELECT ON `<dolibarr_db>`.`<prefix>stock_mouvement` TO '<hermes_user>'@'<hermes_host>';
GRANT SELECT ON `<dolibarr_db>`.`<prefix>entrepot` TO '<hermes_user>'@'<hermes_host>';
GRANT SELECT, INSERT, UPDATE ON `<dolibarr_db>`.`<prefix>ai_dashboard_run` TO '<hermes_user>'@'<hermes_host>';
GRANT SELECT, INSERT, UPDATE ON `<dolibarr_db>`.`<prefix>ai_dashboard_order_risk_daily` TO '<hermes_user>'@'<hermes_host>';
GRANT SELECT, INSERT, UPDATE ON `<dolibarr_db>`.`<prefix>ai_dashboard_inventory_risk_daily` TO '<hermes_user>'@'<hermes_host>';
```

### 3.2 任务和模型配置

Hermes 还需要知道：

- 任务类型：`manufacturing_risk`；
- 调度时间：建议在 ERP 当日业务录入和库存同步完成后运行；
- 快照模式：首次 Demo 使用 `full`，同一 `entity + snapshot_date` 形成完整集合；
- 业务日期：由任务明确传入 `YYYY-MM-DD`，不要让跨时区的 `CURDATE()` 决定业务日期；
- 读取范围：订单、采购、产品、库存、仓库、库存流水，按安装情况增加收货和发票；
- 结果格式：必须能逐行提供订单风险和库存风险字段，而不是只返回自然语言；
- 模型配置：模型名、LLM endpoint、API key、请求超时、重试次数；
- 失败策略：读取失败、解析失败、校验失败都不得生成 `success` 快照；
- 幂等策略：同一个实体、任务类型和业务日期只能有一条 run，明细必须按各自唯一键 upsert 或完整替换。

模型返回的自然语言可以作为 `risk_reason` 和 `summary`，但 dashboard 需要的枚举、数值、日期和 ID 必须经过结构化解析和校验。禁止让模型自行编造 `order_id`、`product_id` 或引用不存在的业务单号；写入前必须回查源表。

## 4. 如何找到配置

### 4.1 在 Dolibarr 中找数据库连接和前缀

部署实例的 `htdocs/conf/conf.php` 是来源；该文件不要提交到仓库，也不要把密码复制到聊天中。只查看非敏感字段：

```powershell
Select-String -Path 'htdocs/conf/conf.php' `
  -Pattern 'dolibarr_main_db_(host|port|name|user|prefix)'
```

重点确认：`dolibarr_main_db_host`、`dolibarr_main_db_port`、`dolibarr_main_db_name`、`dolibarr_main_db_user`、`dolibarr_main_db_prefix`。数据库密码只在 Hermes 本机的 secret 配置中填写。

如果只能从 MySQL 客户端确认，可以执行：

```sql
SELECT DATABASE(), CURRENT_USER(), @@version, @@session.time_zone;
SHOW TABLES LIKE '%commande%';
```

### 4.2 在 Hermes 项目中找变量名

在 Hermes 的项目目录、`.env.example`、Docker Compose、systemd service、Windows 任务计划脚本或部署文档中搜索配置名。只输出变量名和文件位置，不要输出变量值：

```powershell
rg -n --hidden -g '!*.log' -g '!.git' `
  'HERMES|DATABASE_URL|DB_HOST|DB_PORT|DB_NAME|DB_USER|MYSQL|DOLIBARR|OPENAI_BASE_URL|OPENAI_API_KEY|MODEL|SCHEDULE|CRON' `
  '<Hermes目录>'
```

如果 Hermes 尚未有配置文件，先按 Hermes 自己的配置约定建立本机配置；不要把真实连接信息写进本技能。至少准备一份不含秘密的 `env.example`，明确数据库连接、任务时区、实体、模型和调度配置。

### 4.3 Hermes 与 Dolibarr 页面问答是两套配置

Dolibarr AI 看板页面的问答客户端读取 `htdocs/conf/conf.php` 中的以下变量：

```php
$dolibarr_hermes_endpoint = 'http://127.0.0.1:8000/v1/chat/completions';
$dolibarr_hermes_api_key = '';
$dolibarr_hermes_model = 'hermes';
$dolibarr_hermes_timeout = 120;
$dolibarr_hermes_system_prompt = '';
```

这些配置只负责“用户在页面输入问题后调用 Hermes”。它们不等于 Hermes 定时任务访问 MySQL 的 `DB_*` 配置。页面 endpoint 可以是 OpenAI-compatible 的 `/v1/chat/completions`；私网或本机地址还要按 Dolibarr 的 endpoint 安全策略配置 `$dolibarr_ai_allow_local_endpoints`。API key 仍然只能放在 `conf.php` 或安全配置中。

## 5. Hermes 的实际执行步骤

服务器如果没有 `mysql` 命令行客户端，使用本 skill 的
`scripts/hermes_dolibarr_db.py`。它通过 `DOLIBARR_DB_ENV_FILE` 读取连接配置，避免把密码
放入命令参数；`preflight` 和 `context` 只读核心表，`write --input` 只接受 Hermes 生成的
JSON，并在写入 AI 表前回查订单、产品和仓库 ID。建议把脚本复制到 Hermes skill 目录或
`~/.hermes/scripts/`，并先执行：

```bash
python scripts/hermes_dolibarr_db.py preflight
python scripts/hermes_dolibarr_db.py context --date YYYY-MM-DD > /tmp/dolibarr-ai-context.json
```

Hermes 分析 `/tmp/dolibarr-ai-context.json` 后，将结构化结果保存为单独 JSON，再执行：

```bash
python scripts/hermes_dolibarr_db.py write --input /tmp/dolibarr-ai-results.json
```

这个脚本不是 AI 推理器，也不生成风险结论；它只负责安全地读源数据和提交 Hermes 的结果。

### 阶段 A：源数据读取

1. 读取 `entity`、业务日期和表前缀配置。
2. 用 `information_schema` 检查源表和 AI 表存在。
3. 按 `entity` 读取未完成销售订单、销售订单行、采购订单和采购行。
4. 读取产品、仓库、产品仓库库存和库存流水。
5. 计算每个产品的当前库存、近期日均消耗、预计可用天数、最近流水日期、未完成采购数量和受影响订单。
6. 计算每个销售订单的交付日期、订单金额、缺料行数、关联采购单和最迟采购到货日期。
7. 只在源表中能回查到 ID、引用和实体时，才允许进入写入阶段。

建议的核心口径：

- 延期风险：订单未完成，且承诺交付日期临近或已过；若订单行对应产品低于安全库存，或关联采购单未完成且到货日晚于交付日，则提升风险。
- 缺料风险：当前库存低于 `seuil_stock_alerte`，或按近期消耗计算的 `days_to_stockout` 小于采购交期；要关联未完成销售订单估算影响。
- 呆滞风险：库存大于零且最近出库/库存流水超过约定阈值，例如 90 或 120 天；阈值必须作为任务配置记录。
- 日均消耗、金额、预计天数和概率的计算方式必须随 run 写入 `summary` 或任务日志，不能只写一个没有口径的结果数字。

### 阶段 B：AI 结果写入

按照 [`hermes-operations.md`](hermes-operations.md) 执行：先创建 `running` run，写入同一快照日期的完整订单风险和库存风险，校验计数和外键回查，成功后才标记 `success`。任何模型输出解析失败、源数据回查失败、枚举值非法或关键字段为空，都应回滚并写入 `failed`。

推荐每个结果对象至少包含：

```json
{
  "entity": 1,
  "snapshot_date": "2026-09-22",
  "order_id": 122007,
  "order_ref": "AIH-SO-0007",
  "risk_level": "high",
  "delay_probability": 0.92,
  "expected_delay_days": 8,
  "shortage_count": 2,
  "linked_purchase_count": 1,
  "risk_reason": "源数据证据摘要"
}
```

库存风险对象使用 `risk_type = shortage|stagnant`，并提供 `product_id`、`warehouse_id`、`current_stock`、`daily_consumption`、`days_to_stockout`、`last_movement_date` 和 `risk_reason`。数值应使用数据库字段的原始单位；金额需明确未税/含税口径。

### 阶段 C：看板验证

Hermes 成功后用只读查询验证：

```sql
SELECT r.entity, r.run_type, r.snapshot_date, r.status,
       r.row_count, r.source, r.finished_at
FROM llx_ai_dashboard_run r
WHERE r.run_type = 'manufacturing_risk'
ORDER BY r.snapshot_date DESC, r.rowid DESC
LIMIT 5;

SELECT snapshot_date, risk_level, COUNT(*) AS order_count
FROM llx_ai_dashboard_order_risk_daily
WHERE entity = 1
GROUP BY snapshot_date, risk_level
ORDER BY snapshot_date DESC, risk_level;

SELECT snapshot_date, risk_type, risk_level, COUNT(*) AS product_count
FROM llx_ai_dashboard_inventory_risk_daily
WHERE entity = 1
GROUP BY snapshot_date, risk_type, risk_level
ORDER BY snapshot_date DESC, risk_type, risk_level;
```

只有最新业务日期存在 `success` run 且明细行的 `source_run_id` 指向该 run 时，才认为 Hermes 已经真正填充看板。仅仅存在 `llx_ai_dashboard_*` 表、或者存在旧日期数据，都不能证明本次 Demo 成功。
