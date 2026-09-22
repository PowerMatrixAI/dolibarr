# Hermes AI 看板写入与读取操作规范

本文件用于 Hermes 定时任务或其他已获授权的自动化任务。它描述的是
`dolibarr-ai-dashboard.sql` 创建的 AI 专用事实表，不是对 Dolibarr 核心业务表的
直接写入方案。Hermes 必须先按
[`hermes-config-and-demo-source.md`](hermes-config-and-demo-source.md) 从核心业务表读取
并推断结果；本文件中的 INSERT、UPDATE 和 DELETE 只适用于已经完成源数据回查和结果
校验之后的 AI 专用表写入阶段。不要把预设的 demo 结论当作 Hermes 输出。

## 1. 固定范围和幂等键

| 表 | 用途 | 一条记录的业务粒度 | 幂等键 |
|---|---|---|---|
| `llx_ai_dashboard_run` | 记录一次 Hermes 快照任务 | 一个实体、一个任务类型、一个业务日期 | `entity + run_type + snapshot_date` |
| `llx_ai_dashboard_order_risk_daily` | 每日延期风险订单 | 一个实体、一个业务日期、一个销售订单 | `entity + snapshot_date + order_id` |
| `llx_ai_dashboard_inventory_risk_daily` | 每日缺料/呆滞库存 | 一个实体、一个业务日期、一个风险类型、一个产品、一个仓库 | `entity + snapshot_date + risk_type + product_id + warehouse_id` |

固定枚举值：

- `run_type` 当前使用 `manufacturing_risk`。
- `status` 使用 `running`、`success`、`failed`。
- `risk_level` 使用 `high`、`medium`、`low`。
- `risk_type` 只能使用 `shortage` 或 `stagnant`。

`snapshot_date` 是业务快照日期，格式为 `YYYY-MM-DD`。不要因为服务器时区、
任务跨午夜或数据库连接时区不同而直接用 `CURDATE()` 代替任务传入的业务日期。
同一次任务的所有行必须使用同一个 `entity` 和 `snapshot_date`。

## 2. 运行前核验

写入前先确认三张表存在、唯一键存在，并确认本次任务的实体和业务日期。下面的
`:entity`、`:snapshot_date` 是由 Hermes 连接器绑定的参数，不要拼接用户输入。

```sql
SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN (
      'llx_ai_dashboard_run',
      'llx_ai_dashboard_order_risk_daily',
      'llx_ai_dashboard_inventory_risk_daily'
  );

SELECT TABLE_NAME, INDEX_NAME, NON_UNIQUE, SEQ_IN_INDEX, COLUMN_NAME
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN (
      'llx_ai_dashboard_run',
      'llx_ai_dashboard_order_risk_daily',
      'llx_ai_dashboard_inventory_risk_daily'
  )
ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX;
```

如果实例的 `MAIN_DB_PREFIX` 不是 `llx_`，先将 SQL 中的物理前缀替换成实际前缀。
如果任意一张表缺失，先执行项目中的
`outputs/dolibarr-ai-dashboard.sql`，不要临时创建字段不一致的表。

## 3. 推荐的每日全量快照流程

每日任务应先从 Dolibarr 核心表读取并计算结果，再将一整份快照写入 AI 专用表。
推荐的事务边界如下：

1. 开始事务，创建或重置一条 `running` 任务记录。
2. 在事务内删除本实体、本业务日期的旧 AI 快照。
3. 批量插入或 upsert 本次订单风险和库存风险。
4. 在事务内执行数据质量校验，并统计实际写入行数。
5. 校验通过则将任务标记为 `success` 并提交。
6. 任意步骤失败则回滚；回滚后单独写入 `failed` 任务记录，错误信息不得包含密码、API key 或完整连接串。

如果任务只能产生增量结果，不得执行第 2 步；应明确记录为增量任务，并解决旧行
如何失效的问题。没有完整集合时，推荐先写入临时表再校验，之后用批次策略替换，
不要直接删除一个日期的生产数据。

以下模板适用于全量快照。占位符必须使用预编译参数或连接器绑定，不要用字符串拼接：

```sql
START TRANSACTION;

INSERT INTO llx_ai_dashboard_run
    (entity, run_type, snapshot_date, status, started_at, finished_at, row_count, source, summary, error_message)
VALUES
    (:entity, 'manufacturing_risk', :snapshot_date, 'running', NOW(), NULL, 0, :source, :summary, NULL)
ON DUPLICATE KEY UPDATE
    rowid = LAST_INSERT_ID(rowid),
    status = 'running',
    started_at = VALUES(started_at),
    finished_at = NULL,
    row_count = 0,
    source = VALUES(source),
    summary = VALUES(summary),
    error_message = NULL;

SET @hermes_run_id = LAST_INSERT_ID();

DELETE FROM llx_ai_dashboard_order_risk_daily
WHERE entity = :entity AND snapshot_date = :snapshot_date;

DELETE FROM llx_ai_dashboard_inventory_risk_daily
WHERE entity = :entity AND snapshot_date = :snapshot_date;

-- 在这里批量 INSERT/UPSERT 两类事实数据。
-- 写入并校验通过后再更新任务状态。
```

注意：如果数据库连接器不允许在一个请求中执行多条语句，分别执行每条语句，
但必须保持同一个事务连接；不能在不同连接之间拆分事务。

## 4. 订单风险写入规则

生产数据中的 `order_id` 应为 `llx_commande.rowid`，`order_ref` 应保存当时展示用的
订单编号，`customer_id` 应为 `llx_societe.rowid`。AI 分析可以来自订单、订单行、
采购订单、收货和库存数据，但结果只写入下面这张 AI 事实表：

```sql
INSERT INTO llx_ai_dashboard_order_risk_daily
    (entity, snapshot_date, order_id, order_ref, customer_id, customer_name,
     risk_level, delay_probability, expected_delay_days, risk_reason,
     shortage_count, linked_purchase_count, affected_amount, source_run_id, created_at)
VALUES
    (:entity, :snapshot_date, :order_id, :order_ref, :customer_id, :customer_name,
     :risk_level, :delay_probability, :expected_delay_days, :risk_reason,
     :shortage_count, :linked_purchase_count, :affected_amount, @hermes_run_id, NOW())
ON DUPLICATE KEY UPDATE
    order_ref = VALUES(order_ref),
    customer_id = VALUES(customer_id),
    customer_name = VALUES(customer_name),
    risk_level = VALUES(risk_level),
    delay_probability = VALUES(delay_probability),
    expected_delay_days = VALUES(expected_delay_days),
    risk_reason = VALUES(risk_reason),
    shortage_count = VALUES(shortage_count),
    linked_purchase_count = VALUES(linked_purchase_count),
    affected_amount = VALUES(affected_amount),
    source_run_id = VALUES(source_run_id),
    created_at = VALUES(created_at);
```

字段约束：

- `delay_probability` 范围为 0 到 100；没有足够依据时写 `NULL`，不要写伪造的概率。
- `expected_delay_days` 为预计延期天数；没有预测时写 `NULL`，不能用 0 掩盖缺失。
- `shortage_count`、`linked_purchase_count` 为非负整数。
- `affected_amount` 必须说明金额口径。推荐使用实体本位币、未税订单金额；如果项目采用其他口径，应在 `summary` 或 `risk_reason` 中说明。
- `order_id=0` 仅用于脱离真实订单的演示行；生产写入应尽量使用真实 `rowid`，并通过校验 SQL 检查订单是否存在。

延期判断至少要在任务摘要中说明：订单状态范围、承诺交付日期、实际收货/发货
事件、当前日期、取消/关闭订单是否排除，以及多订单行是按订单还是按行聚合。

## 5. 库存风险写入规则

`risk_type='shortage'` 表示库存和未来需求/供应之间存在缺口，
`risk_type='stagnant'` 表示当前库存达到呆滞规则。生产数据中的
`product_id`、`warehouse_id` 应分别对应 `llx_product.rowid` 和 `llx_entrepot.rowid`。

```sql
INSERT INTO llx_ai_dashboard_inventory_risk_daily
    (entity, snapshot_date, risk_type, risk_level, product_id, product_ref, product_label,
     warehouse_id, warehouse_ref, current_stock, daily_consumption, days_to_stockout,
     forecast_stockout_date, desired_stock, alert_stock, impact_amount,
     affected_order_count, affected_order_refs, last_movement_date, risk_reason,
     source_run_id, created_at)
VALUES
    (:entity, :snapshot_date, :risk_type, :risk_level, :product_id, :product_ref, :product_label,
     :warehouse_id, :warehouse_ref, :current_stock, :daily_consumption, :days_to_stockout,
     :forecast_stockout_date, :desired_stock, :alert_stock, :impact_amount,
     :affected_order_count, :affected_order_refs, :last_movement_date, :risk_reason,
     @hermes_run_id, NOW())
ON DUPLICATE KEY UPDATE
    risk_level = VALUES(risk_level),
    product_ref = VALUES(product_ref),
    product_label = VALUES(product_label),
    warehouse_ref = VALUES(warehouse_ref),
    current_stock = VALUES(current_stock),
    daily_consumption = VALUES(daily_consumption),
    days_to_stockout = VALUES(days_to_stockout),
    forecast_stockout_date = VALUES(forecast_stockout_date),
    desired_stock = VALUES(desired_stock),
    alert_stock = VALUES(alert_stock),
    impact_amount = VALUES(impact_amount),
    affected_order_count = VALUES(affected_order_count),
    affected_order_refs = VALUES(affected_order_refs),
    last_movement_date = VALUES(last_movement_date),
    risk_reason = VALUES(risk_reason),
    source_run_id = VALUES(source_run_id),
    created_at = VALUES(created_at);
```

字段约束：

- `risk_type` 只能是 `shortage` 或 `stagnant`。
- `current_stock`、`daily_consumption`、`desired_stock`、`alert_stock` 使用产品基础单位；单位换算必须在任务摘要中写明。
- `days_to_stockout` 和 `forecast_stockout_date` 只适用于可计算的短缺预测；呆滞行通常为 `NULL`。
- `last_movement_date` 没有库存变动记录时应写 `NULL`，并在 `risk_reason` 说明“无历史变动”，不要误写成某个日期。
- `impact_amount` 推荐使用当前库存成本金额，并在任务摘要中说明成本价来源、币种和是否含税。
- 为了保证唯一键幂等，生产行应提供真实 `warehouse_id`。不能确认仓库时不要反复使用 `NULL` 生成多条无法稳定更新的记录。

## 6. 任务完成和失败处理

插入完两类事实并完成校验后，统计行数并在同一事务内完成：

```sql
SELECT
    (SELECT COUNT(*) FROM llx_ai_dashboard_order_risk_daily
     WHERE entity = :entity AND snapshot_date = :snapshot_date)
  + (SELECT COUNT(*) FROM llx_ai_dashboard_inventory_risk_daily
     WHERE entity = :entity AND snapshot_date = :snapshot_date) AS row_count;

UPDATE llx_ai_dashboard_run
SET status = 'success',
    finished_at = NOW(),
    row_count = :row_count,
    error_message = NULL
WHERE rowid = @hermes_run_id
  AND entity = :entity
  AND run_type = 'manufacturing_risk'
  AND snapshot_date = :snapshot_date;

COMMIT;
```

失败时：

```sql
ROLLBACK;

INSERT INTO llx_ai_dashboard_run
    (entity, run_type, snapshot_date, status, started_at, finished_at, row_count, source, summary, error_message)
VALUES
    (:entity, 'manufacturing_risk', :snapshot_date, 'failed', :started_at, NOW(), 0, :source, :summary, :safe_error_message)
ON DUPLICATE KEY UPDATE
    status = 'failed',
    finished_at = VALUES(finished_at),
    error_message = VALUES(error_message),
    summary = VALUES(summary);
```

失败记录不得写入数据库密码、Hermes API key、Authorization header 或完整请求体。
如果任务中途断开，下一次运行前检查 `status='running'` 的旧记录，并由新任务覆盖
同一 `entity + run_type + snapshot_date` 的状态。

## 7. 写入后的校验 SQL

```sql
-- 不允许重复业务粒度
SELECT entity, snapshot_date, order_id, COUNT(*) AS nb
FROM llx_ai_dashboard_order_risk_daily
GROUP BY entity, snapshot_date, order_id
HAVING COUNT(*) > 1;

SELECT entity, snapshot_date, risk_type, product_id, warehouse_id, COUNT(*) AS nb
FROM llx_ai_dashboard_inventory_risk_daily
GROUP BY entity, snapshot_date, risk_type, product_id, warehouse_id
HAVING COUNT(*) > 1;

-- 检查枚举和概率
SELECT *
FROM llx_ai_dashboard_order_risk_daily
WHERE risk_level NOT IN ('high', 'medium', 'low')
   OR delay_probability < 0
   OR delay_probability > 100;

SELECT *
FROM llx_ai_dashboard_inventory_risk_daily
WHERE risk_type NOT IN ('shortage', 'stagnant')
   OR risk_level NOT IN ('high', 'medium', 'low');

-- 生产数据才执行的业务对象存在性检查
SELECT r.order_id, r.order_ref
FROM llx_ai_dashboard_order_risk_daily AS r
LEFT JOIN llx_commande AS so
       ON so.rowid = r.order_id AND so.entity = r.entity
WHERE r.entity = :entity
  AND r.snapshot_date = :snapshot_date
  AND r.order_id > 0
  AND so.rowid IS NULL;

SELECT r.product_id, r.product_ref, r.warehouse_id
FROM llx_ai_dashboard_inventory_risk_daily AS r
LEFT JOIN llx_product AS p ON p.rowid = r.product_id AND p.entity = r.entity
LEFT JOIN llx_entrepot AS w ON w.rowid = r.warehouse_id AND w.entity = r.entity
WHERE r.entity = :entity
  AND r.snapshot_date = :snapshot_date
  AND (r.product_id > 0 AND p.rowid IS NULL OR r.warehouse_id > 0 AND w.rowid IS NULL);
```

演示数据允许 `order_id`、`product_id` 使用保留的虚拟 ID，因此不要把演示行的对象
存在性检查误报为生产错误；生产任务必须使用真实对象 ID。

## 8. Hermes 经营问答的读取范围

AI 看板页面默认只将选定日期的汇总、前 N 条延期订单、前 N 条缺料行和前 N 条呆滞
行发送给 Hermes。问答上下文可以按以下方式读取：

```sql
SELECT order_ref, customer_name, risk_level, delay_probability,
       expected_delay_days, risk_reason, shortage_count,
       linked_purchase_count, affected_amount
FROM llx_ai_dashboard_order_risk_daily
WHERE entity = :entity AND snapshot_date = :snapshot_date
ORDER BY CASE risk_level WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END,
         delay_probability DESC
LIMIT 20;

SELECT risk_type, risk_level, product_ref, product_label, warehouse_ref,
       current_stock, daily_consumption, days_to_stockout,
       forecast_stockout_date, impact_amount, affected_order_count,
       affected_order_refs, last_movement_date, risk_reason
FROM llx_ai_dashboard_inventory_risk_daily
WHERE entity = :entity AND snapshot_date = :snapshot_date
ORDER BY CASE risk_level WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END,
         impact_amount DESC
LIMIT 30;
```

Hermes 的自然语言问答默认是只读分析。不得把用户问题直接转成对 Dolibarr 核心
业务表的 `INSERT`、`UPDATE`、`DELETE` 或 `ALTER`。需要写入 AI 快照时，必须进入
第 3 节的定时任务流程，并使用本规范的实体、日期和幂等键。
