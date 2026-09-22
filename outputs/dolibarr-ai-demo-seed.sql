-- Dolibarr AI Demo seed data for the current database.
-- Live inspection on 2026-09-12 found the target business tables empty:
-- products, third parties, warehouses, stock, sales orders, supplier orders,
-- receptions, movements and invoices all contained 0 rows.
-- The BOM/MRP tables are not installed in this database, so this script does
-- not create those module tables. The demo is built on the installed core tables.
--
-- IMPORTANT:
-- 1. Review the preflight result before executing.
-- 2. Run this script once. It uses reserved demo row IDs 10001-61014.
-- 3. Take a database snapshot/backup first. This script only INSERTs demo rows
--    and does not delete or update existing rows.

-- Preflight: these counts were 0 during the live inspection.
SELECT 'llx_product' AS table_name, COUNT(*) AS row_count FROM llx_product
UNION ALL SELECT 'llx_societe', COUNT(*) FROM llx_societe
UNION ALL SELECT 'llx_entrepot', COUNT(*) FROM llx_entrepot
UNION ALL SELECT 'llx_product_stock', COUNT(*) FROM llx_product_stock
UNION ALL SELECT 'llx_stock_mouvement', COUNT(*) FROM llx_stock_mouvement
UNION ALL SELECT 'llx_commande', COUNT(*) FROM llx_commande
UNION ALL SELECT 'llx_commandedet', COUNT(*) FROM llx_commandedet
UNION ALL SELECT 'llx_commande_fournisseur', COUNT(*) FROM llx_commande_fournisseur
UNION ALL SELECT 'llx_commande_fournisseurdet', COUNT(*) FROM llx_commande_fournisseurdet
UNION ALL SELECT 'llx_reception', COUNT(*) FROM llx_reception
UNION ALL SELECT 'llx_receptiondet_batch', COUNT(*) FROM llx_receptiondet_batch
UNION ALL SELECT 'llx_element_element', COUNT(*) FROM llx_element_element
UNION ALL SELECT 'llx_facture', COUNT(*) FROM llx_facture
UNION ALL SELECT 'llx_facturedet', COUNT(*) FROM llx_facturedet;

START TRANSACTION;

-- Demo master data.
INSERT INTO llx_societe
    (rowid, nom, name_alias, entity, status, code_client, code_fournisseur,
     client, fournisseur, fk_stcomm, datec, fk_user_creat)
VALUES
    (10001, 'Demo 客户 - 星海科技', 'XH-DEMO', 1, 1, 'DEMO-C001', NULL,
     1, 0, 0, NOW(), 1),
    (10002, 'Demo 供应商 - 华南电子', 'HN-DEMO', 1, 1, NULL, 'DEMO-S001',
     0, 1, 0, NOW(), 1);

INSERT INTO llx_entrepot
    (rowid, ref, entity, description, lieu, warehouse_usage, statut, fk_user_author)
VALUES
    (10001, 'DEMO-WH', 1, 'AI Demo 主仓', '深圳', 1, 1, 1);

INSERT INTO llx_product
    (rowid, ref, entity, label, price, price_ttc, cost_price, tosell, tobuy,
     tobatch, fk_product_type, stockable_product, stock, pmp,
     desiredstock, seuil_stock_alerte, fk_default_warehouse, finished, datec)
VALUES
    (20001, 'RM-204', 1, '高密度连接器（原材料）', 25.00000000, 28.25000000, 12.50000000,
     1, 1, 0, 0, 1, 4.00000000, 12.50000000, 30.00000000, 10.00000000, 10001, 0, NOW()),
    (20002, 'RM-205', 1, '工业级树脂（呆滞原材料）', 16.00000000, 18.08000000, 8.00000000,
     0, 1, 0, 0, 1, 120.00000000, 8.00000000, 20.00000000, 10.00000000, 10001, 0, NOW()),
    (20003, 'FG-108', 1, '智能控制模块', 399.00000000, 450.87000000, 180.00000000,
     1, 1, 0, 0, 1, 0.00000000, 180.00000000, 25.00000000, 5.00000000, 10001, 1, NOW()),
    (20004, 'FG-109', 1, '边缘计算网关', 499.00000000, 563.87000000, 260.00000000,
     1, 1, 0, 0, 1, 3.00000000, 260.00000000, 10.00000000, 5.00000000, 10001, 1, NOW()),
    (20005, 'FG-110', 1, '工业数据采集器', 229.00000000, 258.77000000, 95.00000000,
     1, 1, 0, 0, 1, 18.00000000, 95.00000000, 10.00000000, 5.00000000, 10001, 1, NOW()),
    (20006, 'FG-111', 1, '标准通讯转换器', 109.00000000, 123.17000000, 40.00000000,
     1, 1, 0, 0, 1, 60.00000000, 40.00000000, 20.00000000, 5.00000000, 10001, 1, NOW());

-- Supplier price references used by the purchasing and margin views.
INSERT INTO llx_product_fournisseur_price
    (rowid, entity, datec, fk_product, fk_soc, ref_fourn, price, quantity,
     unitprice, tva_tx, delivery_time_days, supplier_reputation, fk_user, status)
VALUES
    (21001, 1, NOW(), 20001, 10002, 'HN-RM204', 12.50000000, 1, 12.50000000, 13.0000, 18, 'A', 1, 1),
    (21002, 1, NOW(), 20003, 10002, 'HN-FG108', 180.00000000, 1, 180.00000000, 13.0000, 25, 'B', 1, 1),
    (21003, 1, NOW(), 20004, 10002, 'HN-FG109', 350.00000000, 1, 350.00000000, 13.0000, 12, 'B', 1, 1),
    (21004, 1, NOW(), 20005, 10002, 'HN-FG110', 95.00000000, 1, 95.00000000, 13.0000, 7, 'A', 1, 1);

-- Per-warehouse stock balances.
INSERT INTO llx_product_stock
    (rowid, fk_product, fk_entrepot, reel)
VALUES
    (22001, 20001, 10001, 4.00000000),
    (22002, 20002, 10001, 120.00000000),
    (22003, 20003, 10001, 0.00000000),
    (22004, 20004, 10001, 3.00000000),
    (22005, 20005, 10001, 18.00000000),
    (22006, 20006, 10001, 60.00000000);

-- Inventory history: RM-205 and FG-111 have no recent movement and are used
-- for stagnant-stock detection. RM-204 and FG-108 are shortage candidates.
INSERT INTO llx_stock_mouvement
    (rowid, datem, fk_product, fk_entrepot, value, price, type_mouvement,
     fk_user_author, label, fk_projet)
VALUES
    (23001, DATE_SUB(NOW(), INTERVAL 160 DAY), 20001, 10001, 20.00000000, 12.50000000, 3, 1, 'Demo initial receipt', 0),
    (23002, DATE_SUB(NOW(), INTERVAL 15 DAY), 20001, 10001, -16.00000000, 12.50000000, 2, 1, 'Demo order consumption', 0),
    (23003, DATE_SUB(NOW(), INTERVAL 140 DAY), 20002, 10001, 120.00000000, 8.00000000, 3, 1, 'Demo initial receipt', 0),
    (23004, DATE_SUB(NOW(), INTERVAL 140 DAY), 20003, 10001, 15.00000000, 180.00000000, 3, 1, 'Demo initial receipt', 0),
    (23005, DATE_SUB(NOW(), INTERVAL 20 DAY), 20003, 10001, -15.00000000, 180.00000000, 2, 1, 'Demo order consumption', 0),
    (23006, DATE_SUB(NOW(), INTERVAL 60 DAY), 20004, 10001, 20.00000000, 260.00000000, 3, 1, 'Demo initial receipt', 0),
    (23007, DATE_SUB(NOW(), INTERVAL 20 DAY), 20004, 10001, -17.00000000, 260.00000000, 2, 1, 'Demo order consumption', 0),
    (23008, DATE_SUB(NOW(), INTERVAL 70 DAY), 20005, 10001, 15.00000000, 95.00000000, 3, 1, 'Demo initial receipt', 0),
    (23009, DATE_SUB(NOW(), INTERVAL 18 DAY), 20005, 10001, 15.00000000, 95.00000000, 3, 1, 'Demo supplier reception', 0),
    (23010, DATE_SUB(NOW(), INTERVAL 10 DAY), 20005, 10001, -12.00000000, 95.00000000, 2, 1, 'Demo order consumption', 0),
    (23011, DATE_SUB(NOW(), INTERVAL 130 DAY), 20006, 10001, 60.00000000, 40.00000000, 3, 1, 'Demo initial receipt', 0);

-- Supplier orders. The first two are intentionally late or tight relative to
-- the linked sales orders; the third one is already received; the fourth is a
-- late replenishment for RM-204.
INSERT INTO llx_commande_fournisseur
    (rowid, ref, entity, fk_soc, date_creation, date_commande, date_valid,
     date_approve, source, fk_statut, billed, amount_ht, total_ht, total_ttc,
     date_livraison, date_reception, fk_user_author)
VALUES
    (30001, 'DEMO-PO-RED', 1, 10002, DATE_SUB(NOW(), INTERVAL 2 DAY), DATE_SUB(CURDATE(), INTERVAL 2 DAY),
     DATE_SUB(NOW(), INTERVAL 2 DAY), DATE_SUB(NOW(), INTERVAL 2 DAY), 0, 1, 0,
     3600.00000000, 3600.00000000, 4068.00000000, DATE_ADD(NOW(), INTERVAL 25 DAY), NULL, 1),
    (30002, 'DEMO-PO-YELLOW', 1, 10002, DATE_SUB(NOW(), INTERVAL 3 DAY), DATE_SUB(CURDATE(), INTERVAL 3 DAY),
     DATE_SUB(NOW(), INTERVAL 3 DAY), DATE_SUB(NOW(), INTERVAL 3 DAY), 0, 1, 0,
     2450.00000000, 2450.00000000, 2768.50000000, DATE_ADD(NOW(), INTERVAL 12 DAY), NULL, 1),
    (30003, 'DEMO-PO-GREEN', 1, 10002, DATE_SUB(NOW(), INTERVAL 25 DAY), DATE_SUB(CURDATE(), INTERVAL 25 DAY),
     DATE_SUB(NOW(), INTERVAL 25 DAY), DATE_SUB(NOW(), INTERVAL 24 DAY), 0, 2, 0,
     1425.00000000, 1425.00000000, 1607.25000000, DATE_SUB(NOW(), INTERVAL 20 DAY), DATE_SUB(NOW(), INTERVAL 18 DAY), 1),
    (30004, 'DEMO-PO-RM204', 1, 10002, DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(CURDATE(), INTERVAL 1 DAY),
     DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY), 0, 1, 0,
     375.00000000, 375.00000000, 423.75000000, DATE_ADD(NOW(), INTERVAL 18 DAY), NULL, 1);

INSERT INTO llx_commande_fournisseurdet
    (rowid, fk_commande, fk_product, ref, label, tva_tx, qty, subprice,
     subprice_ttc, total_ht, total_tva, total_ttc, product_type, rang)
VALUES
    (31001, 30001, 20003, 'HN-FG108', '智能控制模块', 13.0000, 20.00000000, 180.00000000,
     203.40000000, 3600.00000000, 468.00000000, 4068.00000000, 0, 1),
    (31002, 30002, 20004, 'HN-FG109', '边缘计算网关', 13.0000, 7.00000000, 350.00000000,
     395.50000000, 2450.00000000, 318.50000000, 2768.50000000, 0, 1),
    (31003, 30003, 20005, 'HN-FG110', '工业数据采集器', 13.0000, 15.00000000, 95.00000000,
     107.35000000, 1425.00000000, 185.25000000, 1607.25000000, 0, 1),
    (31004, 30004, 20001, 'HN-RM204', '高密度连接器（原材料）', 13.0000, 30.00000000, 12.50000000,
     14.12500000, 375.00000000, 48.75000000, 423.75000000, 0, 1);

-- Sales orders: red = insufficient stock and late replenishment, yellow =
-- exactly covered by the expected purchase, green = enough stock.
INSERT INTO llx_commande
    (rowid, ref, entity, fk_soc, date_creation, date_commande, date_valid,
     fk_statut, amount_ht, total_ht, total_ttc, date_livraison, fk_warehouse,
     facture, source, fk_user_author)
VALUES
    (40001, 'DEMO-SO-RED', 1, 10001, NOW(), CURDATE(), NOW(), 1,
     7980.00000000, 7980.00000000, 9017.40000000, DATE_ADD(NOW(), INTERVAL 10 DAY), 10001, 0, 0, 1),
    (40002, 'DEMO-SO-YELLOW', 1, 10001, NOW(), CURDATE(), NOW(), 1,
     4990.00000000, 4990.00000000, 5638.70000000, DATE_ADD(NOW(), INTERVAL 12 DAY), 10001, 0, 0, 1),
    (40003, 'DEMO-SO-GREEN', 1, 10001, NOW(), CURDATE(), NOW(), 1,
     1145.00000000, 1145.00000000, 1293.85000000, DATE_ADD(NOW(), INTERVAL 20 DAY), 10001, 0, 0, 1),
    (40004, 'DEMO-SO-RM204', 1, 10001, NOW(), CURDATE(), NOW(), 1,
     300.00000000, 300.00000000, 339.00000000, DATE_ADD(NOW(), INTERVAL 10 DAY), 10001, 0, 0, 1);

INSERT INTO llx_commandedet
    (rowid, fk_commande, fk_product, label, tva_tx, qty, subprice,
     subprice_ttc, total_ht, total_tva, total_ttc, product_type,
     buy_price_ht, fk_commandefourndet, rang)
VALUES
    (41001, 40001, 20003, '智能控制模块', 13.0000, 20.00000000, 399.00000000,
     450.87000000, 7980.00000000, 1037.40000000, 9017.40000000, 0,
     180.00000000, 31001, 1),
    (41002, 40002, 20004, '边缘计算网关', 13.0000, 10.00000000, 499.00000000,
     563.87000000, 4990.00000000, 648.70000000, 5638.70000000, 0,
     350.00000000, 31002, 1),
    (41003, 40003, 20005, '工业数据采集器', 13.0000, 5.00000000, 229.00000000,
     258.77000000, 1145.00000000, 148.85000000, 1293.85000000, 0,
     95.00000000, NULL, 1),
    (41004, 40004, 20001, '高密度连接器（原材料）', 13.0000, 12.00000000, 25.00000000,
     28.25000000, 300.00000000, 39.00000000, 339.00000000, 0,
     12.50000000, 31004, 1);

-- Generic object links used by Dolibarr's linked-document panels.
INSERT INTO llx_element_element
    (rowid, fk_source, sourcetype, fk_target, targettype, relationtype, fk_user_creat, date_creation)
VALUES
    (42001, 40001, 'commande', 30001, 'commande_fournisseur', 'replenishment', 1, NOW()),
    (42002, 40002, 'commande', 30002, 'commande_fournisseur', 'replenishment', 1, NOW()),
    (42003, 40004, 'commande', 30004, 'commande_fournisseur', 'replenishment', 1, NOW()),
    (42004, 30003, 'commande_fournisseur', 50001, 'reception', 'reception', 1, NOW());

-- Historical reception for the green scenario.
INSERT INTO llx_reception
    (rowid, ref, entity, fk_soc, date_creation, date_valid, date_delivery,
     date_reception, fk_statut, billed, fk_user_author)
VALUES
    (50001, 'DEMO-REC-001', 1, 10002, DATE_SUB(NOW(), INTERVAL 18 DAY),
     DATE_SUB(NOW(), INTERVAL 18 DAY), DATE_SUB(NOW(), INTERVAL 20 DAY),
     DATE_SUB(NOW(), INTERVAL 18 DAY), 1, 0, 1);

INSERT INTO llx_receptiondet_batch
    (rowid, fk_reception, fk_element, fk_elementdet, element_type, fk_product,
     qty, fk_entrepot, status, datec)
VALUES
    (51001, 50001, 30003, 31003, 'supplier_order', 20005, 15.00000000, 10001, 1,
     DATE_SUB(NOW(), INTERVAL 18 DAY));

-- Customer invoice history for the AI business Q&A gross-margin scenario.
-- Margin declines over time due to mix shift toward FG-109, rising buy prices,
-- and recent selling-price discounts on FG-108/FG-111.
INSERT INTO llx_facture
    (rowid, ref, entity, fk_soc, datec, datef, type, fk_statut, paye,
     fk_cond_reglement, total_ht, total_tva, total_ttc, fk_user_author)
VALUES
    (60001, 'DEMO-INV-001', 1, 10001, DATE_SUB(NOW(), INTERVAL 5 MONTH), DATE_SUB(CURDATE(), INTERVAL 5 MONTH), 0, 1, 0, 1,
     2835.00000000, 368.55000000, 3203.55000000, 1),
    (60002, 'DEMO-INV-002', 1, 10001, DATE_SUB(NOW(), INTERVAL 4 MONTH), DATE_SUB(CURDATE(), INTERVAL 4 MONTH), 0, 1, 0, 1,
     5142.00000000, 668.46000000, 5810.46000000, 1),
    (60003, 'DEMO-INV-003', 1, 10001, DATE_SUB(NOW(), INTERVAL 3 MONTH), DATE_SUB(CURDATE(), INTERVAL 3 MONTH), 0, 1, 0, 1,
     6627.00000000, 861.51000000, 7488.51000000, 1),
    (60004, 'DEMO-INV-004', 1, 10001, DATE_SUB(NOW(), INTERVAL 2 MONTH), DATE_SUB(CURDATE(), INTERVAL 2 MONTH), 0, 1, 0, 1,
     5878.00000000, 764.14000000, 6642.14000000, 1),
    (60005, 'DEMO-INV-005', 1, 10001, DATE_SUB(NOW(), INTERVAL 1 MONTH), DATE_SUB(CURDATE(), INTERVAL 1 MONTH), 0, 1, 0, 1,
     10517.00000000, 1367.21000000, 11884.21000000, 1),
    (60006, 'DEMO-INV-006', 1, 10001, DATE_SUB(NOW(), INTERVAL 5 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY), 0, 1, 0, 1,
     15150.00000000, 1969.50000000, 17119.50000000, 1);

INSERT INTO llx_facturedet
    (rowid, fk_facture, fk_product, label, tva_tx, qty, subprice,
     subprice_ttc, total_ht, total_tva, total_ttc, product_type,
     buy_price_ht, fk_code_ventilation, situation_percent, rang)
VALUES
    (61001, 60001, 20005, '工业数据采集器', 13.0000, 10.00000000, 229.00000000, 258.77000000, 2290.00000000, 297.70000000, 2587.70000000, 0, 95.00000000, 0, 100, 1),
    (61002, 60001, 20006, '标准通讯转换器', 13.0000, 5.00000000, 109.00000000, 123.17000000, 545.00000000, 70.85000000, 615.85000000, 0, 40.00000000, 0, 100, 2),
    (61003, 60002, 20005, '工业数据采集器', 13.0000, 12.00000000, 229.00000000, 258.77000000, 2748.00000000, 357.24000000, 3105.24000000, 0, 95.00000000, 0, 100, 1),
    (61004, 60002, 20003, '智能控制模块', 13.0000, 6.00000000, 399.00000000, 450.87000000, 2394.00000000, 311.22000000, 2705.22000000, 0, 180.00000000, 0, 100, 2),
    (61005, 60003, 20005, '工业数据采集器', 13.0000, 15.00000000, 229.00000000, 258.77000000, 3435.00000000, 446.55000000, 3881.55000000, 0, 95.00000000, 0, 100, 1),
    (61006, 60003, 20003, '智能控制模块', 13.0000, 8.00000000, 399.00000000, 450.87000000, 3192.00000000, 414.96000000, 3606.96000000, 0, 180.00000000, 0, 100, 2),
    (61007, 60004, 20003, '智能控制模块', 13.0000, 12.00000000, 399.00000000, 450.87000000, 4788.00000000, 622.44000000, 5410.44000000, 0, 220.00000000, 0, 100, 1),
    (61008, 60004, 20006, '标准通讯转换器', 13.0000, 10.00000000, 109.00000000, 123.17000000, 1090.00000000, 141.70000000, 1231.70000000, 0, 40.00000000, 0, 100, 2),
    (61009, 60005, 20004, '边缘计算网关', 13.0000, 15.00000000, 499.00000000, 563.87000000, 7485.00000000, 973.05000000, 8458.05000000, 0, 350.00000000, 0, 100, 1),
    (61010, 60005, 20003, '智能控制模块', 13.0000, 8.00000000, 379.00000000, 427.27000000, 3032.00000000, 394.16000000, 3426.16000000, 0, 220.00000000, 0, 100, 2),
    (61011, 60006, 20004, '边缘计算网关', 13.0000, 20.00000000, 479.00000000, 541.27000000, 9580.00000000, 1245.40000000, 10825.40000000, 0, 350.00000000, 0, 100, 1),
    (61012, 60006, 20003, '智能控制模块', 13.0000, 10.00000000, 359.00000000, 405.67000000, 3590.00000000, 466.70000000, 4056.70000000, 0, 240.00000000, 0, 100, 2),
    (61013, 60006, 20006, '标准通讯转换器', 13.0000, 20.00000000, 99.00000000, 111.87000000, 1980.00000000, 257.40000000, 2237.40000000, 0, 40.00000000, 0, 100, 3);

COMMIT;

-- Postflight: verify the main demo records.
SELECT ref, label, stock, desiredstock, seuil_stock_alerte, cost_price, price
FROM llx_product
WHERE ref IN ('RM-204', 'RM-205', 'FG-108', 'FG-109', 'FG-110', 'FG-111')
ORDER BY ref;

SELECT c.ref AS sales_order_ref, c.date_livraison, c.fk_statut,
       p.ref AS product_ref, cd.qty, cd.fk_commandefourndet,
       cf.ref AS supplier_order_ref, cf.date_livraison AS supplier_expected_date
FROM llx_commande c
JOIN llx_commandedet cd ON cd.fk_commande = c.rowid
LEFT JOIN llx_product p ON p.rowid = cd.fk_product
LEFT JOIN llx_commande_fournisseurdet cfd ON cfd.rowid = cd.fk_commandefourndet
LEFT JOIN llx_commande_fournisseur cf ON cf.rowid = cfd.fk_commande
WHERE c.ref LIKE 'DEMO-%'
ORDER BY c.rowid, cd.rang;

SELECT DATE_FORMAT(f.datef, '%Y-%m') AS invoice_month,
       ROUND(SUM(fd.total_ht), 2) AS revenue_ht,
       ROUND(SUM(fd.qty * fd.buy_price_ht), 2) AS cost_ht,
       ROUND(SUM(fd.total_ht - fd.qty * fd.buy_price_ht), 2) AS gross_profit,
       ROUND(100 * SUM(fd.total_ht - fd.qty * fd.buy_price_ht) / NULLIF(SUM(fd.total_ht), 0), 2) AS gross_margin_pct
FROM llx_facture f
JOIN llx_facturedet fd ON fd.fk_facture = f.rowid
WHERE f.ref LIKE 'DEMO-%'
GROUP BY DATE_FORMAT(f.datef, '%Y-%m')
ORDER BY invoice_month;
