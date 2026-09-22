# Dolibarr MySQL 查询模板

这些模板默认只读。使用前先替换实体、状态、日期和字段，并用 `information_schema` 复核当前实例。

## 先核验实际结构

```sql
SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('llx_product', 'llx_product_stock', 'llx_commande', 'llx_commandedet');

SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, EXTRA
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'llx_product'
ORDER BY ORDINAL_POSITION;

SELECT TABLE_NAME, INDEX_NAME, NON_UNIQUE, SEQ_IN_INDEX, COLUMN_NAME
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('llx_commande', 'llx_commandedet')
ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX;
```

## 销售订单关联采购行

```sql
SELECT
    so.rowid AS sales_order_id,
    so.ref AS sales_order_ref,
    sod.rowid AS sales_order_line_id,
    sod.fk_product,
    sod.qty AS sales_qty,
    pod.rowid AS purchase_order_line_id,
    po.rowid AS purchase_order_id,
    po.ref AS purchase_order_ref,
    po.date_livraison,
    po.date_reception
FROM llx_commande AS so
JOIN llx_commandedet AS sod ON sod.fk_commande = so.rowid
LEFT JOIN llx_commande_fournisseurdet AS pod
       ON pod.rowid = sod.fk_commandefourndet
LEFT JOIN llx_commande_fournisseur AS po ON po.rowid = pod.fk_commande
WHERE so.entity = :entity
  AND so.fk_statut > 0
  AND so.date_commande >= :start_date
  AND so.date_commande < :end_date;
```

如果销售行没有 `fk_commandefourndet`，不要强行按产品和数量匹配；应说明该实例缺少可追溯链路，或另查 `llx_element_element` 并同时限制 `sourcetype`/`targettype`。

## 按仓库查看库存

```sql
SELECT
    p.rowid AS product_id,
    p.ref,
    p.label,
    e.rowid AS warehouse_id,
    e.ref AS warehouse_ref,
    ps.reel AS stock_qty
FROM llx_product AS p
JOIN llx_product_stock AS ps ON ps.fk_product = p.rowid
JOIN llx_entrepot AS e ON e.rowid = ps.fk_entrepot
WHERE p.entity = :entity
  AND e.entity = :entity
  AND (e.statut IS NULL OR e.statut = 1);
```

## 发票行毛利趋势

```sql
SELECT
    DATE_FORMAT(f.datef, '%Y-%m-01') AS month_start,
    SUM(fd.total_ht) AS revenue_ht,
    SUM(fd.qty * fd.buy_price_ht) AS cost_ht,
    SUM(fd.total_ht - (fd.qty * fd.buy_price_ht)) AS gross_profit_ht
FROM llx_facture AS f
JOIN llx_facturedet AS fd ON fd.fk_facture = f.rowid
WHERE f.entity = :entity
  AND f.fk_statut > 0
  AND f.datef >= :start_date
  AND f.datef < :end_date
GROUP BY DATE_FORMAT(f.datef, '%Y-%m-01')
ORDER BY month_start;
```

## 查询安全规则

- 只选业务所需字段，所有列用表别名限定。
- `entity`、状态和日期范围按实际字段确认，不要假定所有表都有 `entity`。
- 使用 `LEFT JOIN` 保留缺少采购、成本或库存记录的业务对象，并显式标记缺失。
- 空成本、退货、取消单据、币种和单位换算必须在结果口径中说明。
- 发现表或字段不存在时停止生成该路径的 SQL，先报告差异。
