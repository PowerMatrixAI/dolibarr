-- Dolibarr AI Demo 数据采集脚本（只读）
-- 用途：在已经成功连接 dolibarr 的 Navicat 查询窗口执行。
-- 说明：本脚本只包含 SELECT / SHOW / information_schema 查询，不会 INSERT、UPDATE、DELETE、ALTER 或 DROP。

-- 1. 连接确认
SELECT DATABASE() AS current_database,
       CURRENT_USER() AS current_user,
       USER() AS client_user,
       VERSION() AS mysql_version,
       CURRENT_TIMESTAMP() AS checked_at;

-- 2. Demo 相关表是否存在及估算行数
SELECT TABLE_NAME,
       ENGINE,
       TABLE_ROWS,
       CREATE_TIME,
       UPDATE_TIME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN (
    'llx_product', 'llx_product_stock', 'llx_product_fournisseur_price',
    'llx_societe', 'llx_entrepot', 'llx_stock_mouvement',
    'llx_commande', 'llx_commandedet',
    'llx_commande_fournisseur', 'llx_commande_fournisseurdet',
    'llx_reception', 'llx_receptiondet_batch',
    'llx_bom_bom', 'llx_bom_bomline',
    'llx_mrp_mo', 'llx_mrp_production',
    'llx_facture', 'llx_facturedet',
    'llx_facture_fourn', 'llx_facture_fourn_det'
  )
ORDER BY TABLE_NAME;

-- 3. Demo 相关表的实际字段（用于核对线上版本和字段差异）
SELECT TABLE_NAME,
       ORDINAL_POSITION,
       COLUMN_NAME,
       COLUMN_TYPE,
       IS_NULLABLE,
       COLUMN_KEY,
       COLUMN_DEFAULT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN (
    'llx_product', 'llx_product_stock', 'llx_product_fournisseur_price',
    'llx_societe', 'llx_entrepot', 'llx_stock_mouvement',
    'llx_commande', 'llx_commandedet',
    'llx_commande_fournisseur', 'llx_commande_fournisseurdet',
    'llx_reception', 'llx_receptiondet_batch',
    'llx_bom_bom', 'llx_bom_bomline',
    'llx_mrp_mo', 'llx_mrp_production',
    'llx_facture', 'llx_facturedet',
    'llx_facture_fourn', 'llx_facture_fourn_det'
  )
ORDER BY TABLE_NAME, ORDINAL_POSITION;

-- 4. 产品主数据和库存汇总（不包含产品描述、备注等长文本）
SELECT rowid, ref, label, fk_product_type, tosell, tobuy, tobatch,
       price, cost_price, stock, pmp, desiredstock, seuil_stock_alerte,
       fk_default_warehouse, fk_default_bom, finished, stockable_product,
       datec, tms
FROM llx_product
ORDER BY rowid
LIMIT 500;

SELECT ps.rowid, ps.fk_product, p.ref AS product_ref, p.label AS product_label,
       ps.fk_entrepot, e.ref AS warehouse_ref, e.label AS warehouse_label,
       ps.reel
FROM llx_product_stock ps
LEFT JOIN llx_product p ON p.rowid = ps.fk_product
LEFT JOIN llx_entrepot e ON e.rowid = ps.fk_entrepot
ORDER BY ps.fk_product, ps.fk_entrepot
LIMIT 1000;

-- 5. 客户/供应商和仓库（仅保留 Demo 展示所需的非联系方式字段）
SELECT rowid, nom, name_alias, code_client, code_fournisseur,
       client, fournisseur, status
FROM llx_societe
ORDER BY rowid
LIMIT 500;

SELECT rowid, ref, label, lieu, warehouse_usage, statut
FROM llx_entrepot
ORDER BY rowid
LIMIT 100;

-- 6. 销售订单及订单行：用于交付延期、毛利和关联采购链路
SELECT rowid, ref, entity, fk_soc, date_commande, date_creation,
       date_valid, fk_statut, amount_ht, total_ht, total_ttc,
       date_livraison, fk_warehouse, module_source, source
FROM llx_commande
ORDER BY COALESCE(date_commande, DATE(date_creation)) DESC, rowid DESC
LIMIT 500;

SELECT cd.rowid, cd.fk_commande, c.ref AS order_ref,
       cd.fk_product, p.ref AS product_ref, COALESCE(cd.label, p.label) AS product_label,
       cd.qty, cd.subprice, cd.buy_price_ht, cd.total_ht,
       cd.fk_commandefourndet, cd.date_start, cd.date_end
FROM llx_commandedet cd
LEFT JOIN llx_commande c ON c.rowid = cd.fk_commande
LEFT JOIN llx_product p ON p.rowid = cd.fk_product
ORDER BY cd.fk_commande DESC, cd.rang, cd.rowid
LIMIT 2000;

SELECT fk_statut, COUNT(*) AS order_count,
       SUM(total_ht) AS total_ht
FROM llx_commande
GROUP BY fk_statut
ORDER BY fk_statut;

-- 7. 采购订单及订单行：用于到货预测和销售订单-采购订单链路
SELECT rowid, ref, entity, fk_soc, date_commande, date_creation,
       date_valid, date_approve, fk_statut, billed, amount_ht,
       total_ht, total_ttc, date_livraison, date_reception
FROM llx_commande_fournisseur
ORDER BY COALESCE(date_commande, DATE(date_creation)) DESC, rowid DESC
LIMIT 500;

SELECT cfd.rowid, cfd.fk_commande, cf.ref AS supplier_order_ref,
       cf.fk_soc AS supplier_id, cfd.fk_product, p.ref AS product_ref,
       COALESCE(cfd.label, p.label) AS product_label,
       cfd.qty, cfd.subprice, cfd.total_ht
FROM llx_commande_fournisseurdet cfd
LEFT JOIN llx_commande_fournisseur cf ON cf.rowid = cfd.fk_commande
LEFT JOIN llx_product p ON p.rowid = cfd.fk_product
ORDER BY cfd.fk_commande DESC, cfd.rang, cfd.rowid
LIMIT 2000;

SELECT fk_statut, COUNT(*) AS supplier_order_count,
       SUM(total_ht) AS total_ht
FROM llx_commande_fournisseur
GROUP BY fk_statut
ORDER BY fk_statut;

-- 8. 收货和最近库存流水：用于到货时点、消耗趋势和呆滞判断
SELECT rowid, ref, fk_soc, date_creation, date_valid,
       date_delivery, date_reception, fk_statut, billed
FROM llx_reception
ORDER BY COALESCE(date_reception, date_delivery, date_creation) DESC, rowid DESC
LIMIT 500;

SELECT rdb.rowid, rdb.fk_reception, r.ref AS reception_ref,
       rdb.fk_element AS supplier_order_id, rdb.fk_elementdet AS supplier_order_line_id,
       rdb.fk_product, p.ref AS product_ref, COALESCE(rdb.description, p.label) AS product_label,
       rdb.qty, rdb.fk_entrepot, rdb.batch, rdb.status, rdb.datec
FROM llx_receptiondet_batch rdb
LEFT JOIN llx_reception r ON r.rowid = rdb.fk_reception
LEFT JOIN llx_product p ON p.rowid = rdb.fk_product
ORDER BY rdb.datec DESC, rdb.rowid DESC
LIMIT 2000;

SELECT sm.fk_product, p.ref AS product_ref, p.label AS product_label,
       sm.fk_entrepot, e.ref AS warehouse_ref, e.label AS warehouse_label,
       DATE(sm.datem) AS movement_date,
       SUM(CASE WHEN sm.value > 0 THEN sm.value ELSE 0 END) AS qty_in,
       SUM(CASE WHEN sm.value < 0 THEN -sm.value ELSE 0 END) AS qty_out,
       SUM(sm.value) AS net_qty,
       SUM(ABS(sm.value) * COALESCE(sm.price, 0)) AS movement_value
FROM llx_stock_mouvement sm
LEFT JOIN llx_product p ON p.rowid = sm.fk_product
LEFT JOIN llx_entrepot e ON e.rowid = sm.fk_entrepot
WHERE sm.datem >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
GROUP BY sm.fk_product, p.ref, p.label, sm.fk_entrepot,
         e.ref, e.label, DATE(sm.datem)
ORDER BY movement_date DESC, sm.fk_product, sm.fk_entrepot
LIMIT 3000;

-- 9. BOM/MRP（如数据库未安装对应模块，这两组语句会提示表不存在，可忽略）
SELECT rowid, ref, label, fk_product, qty, efficiency, duration,
       fk_warehouse, date_creation, date_valid, status
FROM llx_bom_bom
ORDER BY rowid
LIMIT 500;

SELECT bl.rowid, bl.fk_bom, b.ref AS bom_ref,
       bl.fk_product, p.ref AS component_ref, p.label AS component_label,
       bl.qty, bl.efficiency, bl.position
FROM llx_bom_bomline bl
LEFT JOIN llx_bom_bom b ON b.rowid = bl.fk_bom
LEFT JOIN llx_product p ON p.rowid = bl.fk_product
ORDER BY bl.fk_bom, bl.position, bl.rowid
LIMIT 2000;

SELECT rowid, ref, label, mrptype, qty, fk_product,
       fk_warehouse, fk_soc, status, date_creation,
       date_start_planned, date_end_planned, fk_bom
FROM llx_mrp_mo
ORDER BY COALESCE(date_end_planned, date_creation) DESC, rowid DESC
LIMIT 500;

SELECT mp.rowid, mp.fk_mo, mo.ref AS mo_ref,
       mp.fk_product, p.ref AS product_ref, p.label AS product_label,
       mp.fk_warehouse, mp.qty, mp.role, mp.fk_mrp_production,
       mp.fk_stock_movement, mp.date_creation
FROM llx_mrp_production mp
LEFT JOIN llx_mrp_mo mo ON mo.rowid = mp.fk_mo
LEFT JOIN llx_product p ON p.rowid = mp.fk_product
ORDER BY mp.fk_mo, mp.position, mp.rowid
LIMIT 3000;

-- 10. 显式外键关系：核对线上结构与数据字典是否一致
SELECT TABLE_NAME, COLUMN_NAME, CONSTRAINT_NAME,
       REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = DATABASE()
  AND REFERENCED_TABLE_NAME IS NOT NULL
  AND TABLE_NAME IN (
    'llx_product_stock', 'llx_stock_mouvement', 'llx_commande', 'llx_commandedet',
    'llx_commande_fournisseur', 'llx_commande_fournisseurdet',
    'llx_reception', 'llx_receptiondet_batch', 'llx_bom_bom', 'llx_bom_bomline',
    'llx_mrp_mo', 'llx_mrp_production'
  )
ORDER BY TABLE_NAME, CONSTRAINT_NAME, ORDINAL_POSITION;
