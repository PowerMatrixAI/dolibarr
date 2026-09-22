# Dolibarr ERP 业务关系速查

以下是从字典和 Dolibarr 常见模型整理出的推荐路径。具体实例仍需使用 `information_schema` 和字段目录复核。

## 销售订单、采购和交付

核心表：

- `llx_commande`：销售订单头，重点字段通常包括 `rowid`、`ref`、`fk_soc`、`fk_statut`、`date_commande`、`date_livraison`、`date_valid`、`fk_warehouse`。
- `llx_commandedet`：销售订单行，重点字段通常包括 `fk_commande`、`fk_product`、`qty`、`subprice`、`total_ht`、`buy_price_ht`、`fk_commandefourndet`。
- `llx_commande_fournisseur`：采购订单头，重点字段通常包括 `fk_soc`、`fk_statut`、`date_livraison`、`date_reception`。
- `llx_commande_fournisseurdet`：采购订单行，重点字段通常包括 `fk_commande`、`fk_product`、`qty`、`subprice`、`total_ht`。
- `llx_reception`、`llx_receptiondet_batch`：收货头、批次/明细扩展；字段必须以当前实例目录为准。
- `llx_element_element`：通用多态单据关联，常见字段为 `fk_source`、`sourcetype`、`fk_target`、`targettype`、`relationtype`。

推荐链路：销售订单头 -> 销售订单行 -> `fk_commandefourndet` -> 采购订单行 -> 采购订单头。`llx_element_element` 可作为补充关联来源，但不能按普通外键直接连接，必须同时限制源/目标类型。

延期判断至少要明确：订单状态、承诺交付日期、实际收货/发货事件、当前日期、是否排除关闭或取消单据，以及一个订单多行时按订单还是按行统计。

## 库存、仓库和库存风险

- `llx_product`：产品主数据及库存策略，常见字段包括 `rowid`、`ref`、`label`、`tobuy`、`tosell`、`stock`、`pmp`、`desiredstock`、`seuil_stock_alerte`、`cost_price`。
- `llx_product_stock`：产品-仓库库存，常见字段包括 `fk_product`、`fk_entrepot`、`reel`。
- `llx_entrepot`：仓库主数据，常见字段包括 `rowid`、`ref`、`lieu`、`statut`；不要假定一定存在 `label`。
- `llx_stock_mouvement`：库存变动，常见字段包括 `datem`、`fk_product`、`fk_entrepot`、`value`、`price`、`type_mouvement`、`label`。

短缺分析应把现存库存、已确认入库、未完成销售需求和交付日期放在同一口径中。呆滞分析通常需要最后一次库存变动日期、当前库存数量和成本金额；没有变动记录时应标记为“无历史变动”，不要直接当作零库存。

## 发票和毛利

- `llx_facture`：客户发票头，常见字段包括 `datef`、`fk_soc`、`fk_statut`、`total_ht`、`total_ttc`。
- `llx_facturedet`：客户发票行，常见字段包括 `fk_product`、`qty`、`total_ht`、`buy_price_ht`。
- 供应商发票通常使用 `llx_facture_fourn` 和 `llx_facture_fourn_det`，字段以字典为准。

推荐的未税行级毛利为：

```sql
line_gross_profit = total_ht - (qty * buy_price_ht)
```

使用前必须确认退货、折扣、税率、币种、NULL 成本和成本价时间点。月度趋势应先按发票状态和日期范围过滤，再按月份聚合，避免把草稿或取消发票计入收入。

## 多实体、前缀和多态关系

`entity` 是租户/实体边界，不同表是否拥有该字段必须查目录确认。多态表中的 `fk_*` 字段可能没有数据库外键，连接时必须使用类型字段共同过滤。SQL 中使用实际前缀；可移植的 Dolibarr PHP SQL 使用 `$db->prefix()` 生成前缀。
