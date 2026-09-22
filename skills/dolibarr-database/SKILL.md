---
name: dolibarr-database
description: Answer Dolibarr MySQL schema questions and design safe read-only ERP queries from the bundled data dictionary.
version: 1.2.0
author: Local project
license: MIT
platforms:
  - win32
  - linux
  - macos
metadata:
  hermes:
    tags:
      - dolibarr
      - mysql
      - erp
      - database
      - schema
    category: development
---

# Dolibarr MySQL 数据库技能

当用户询问 Dolibarr 的表、字段、索引、外键、ERP 业务关系、库存、订单、采购、收货、发票、制造，或要求生成 AI Demo 查询 SQL 时使用本技能。

## 数据来源与边界

本技能引用目录来自项目内的 `dolibarr-database-dictionary.xlsx`，对应 `htdocs/install/mysql/tables` 的 MySQL DDL，提取基线为 `develop` 分支提交 `f90c44ae4d7`。它是代码库字典，不等同于任意线上实例；线上回答或执行建议必须先用 `information_schema` 核验实际表、字段、索引和字符集。

不要在技能内容、回答或生成文件中记录数据库密码、连接地址或其他凭据。

## 引用目录路由

- `references/schema-overview.md`：数据范围、统计和使用边界。
- `references/table-catalog.tsv`：按表名、模块、表角色查找表。
- `references/field-catalog.tsv`：查精确字段、类型、可空、默认值、索引和外键目标。
- `references/indexes-and-constraints.tsv`：核实索引、主键和唯一约束。
- `references/foreign-key-relations.tsv`：核实显式外键关系。
- `references/module-statistics.tsv`：按业务模块定位表群。
- `references/business-map.md`：订单、采购、库存、收货、发票和制造的推荐连接路径。
- `references/query-patterns.md`：只读校验和分析 SQL 模板。
- `references/hermes-operations.md`：AI 看板每日快照的写入、幂等、事务、失败处理和 Hermes 读取规范；凡是涉及 Hermes 写入或 AI 看板数据维护时必须读取。
- `references/hermes-config-and-demo-source.md`：Demo 源业务数据、Hermes 配置发现、权限边界和“源数据 → Hermes 推断 → AI 看板”的完整操作链；凡是准备 Demo 数据或配置 Hermes 定时任务时必须读取。
- `scripts/hermes_dolibarr_db.py`：Hermes 使用的参数化 MySQL 桥接脚本，提供 `preflight`、`context` 和 `write` 三个阶段；不得绕过结果校验直接使用。

## 工作流程

1. 先在表目录中定位候选表，再在字段目录中确认精确字段名和类型。
2. 查看索引和外键目录，确认连接条件；显式外键缺失时，说明这是业务约定或多态关系，不要伪称为数据库外键。
3. 对线上库先执行 `information_schema` 校验；表或字段不存在时停止推断并明确报告。
4. 说明 entity、状态、日期、单位、金额和 NULL 处理假设；不要把状态数字直接翻译成业务含义，除非已核实项目常量或代码。
5. 默认只给 `SELECT`、`SHOW` 和 `information_schema` 查询。涉及 `INSERT`、`UPDATE`、`DELETE` 或 `ALTER` 时，必须明确影响范围、幂等键、备份/回滚方案，并等待用户明确授权。

## Dolibarr 常见约定

- 主键通常为 `rowid`；多实体安装常见 `entity` 字段，查询必须按业务范围补充 entity 过滤。
- 常见审计字段包括 `tms`、`datec`、`date_creation`、`fk_user_creat` 和 `fk_user_modif`，以实际表结构为准。
- 物理表通常带 `llx_` 前缀；PHP 代码中应使用 `$db->prefix()`，不要硬编码前缀。
- SQL 使用显式列名、表别名和限定列名；金额、数量、日期字段保留 NULL 语义，避免无依据地 `COALESCE` 成零。
- 推荐先写小范围抽样查询，再扩展到聚合；涉及库存、金额或状态时同时给出数据口径和限制。

## AI Demo 常用映射

- 交付延期：`llx_commande` + `llx_commandedet`，结合 `llx_commande_fournisseur`、`llx_commande_fournisseurdet`、`llx_reception` 和 `llx_receptiondet_batch`；销售行到采购行常见 `fk_commandefourndet`，另检查 `llx_element_element` 的多态关联。
- 库存风险：`llx_product` + `llx_product_stock` + `llx_entrepot` + `llx_stock_mouvement`，再结合未完成销售订单和采购订单判断短缺或呆滞。
- 毛利趋势：`llx_facture` + `llx_facturedet`；常见行级毛利口径为 `total_ht - qty * buy_price_ht`，必须确认字段是否为 NULL、含税/未税和退货处理。
- 制造分析：先检查 `llx_bom_bom`、`llx_bom_bomline`、`llx_mrp_mo`、`llx_mrp_production` 是否存在；制造模块可能未安装，缺表时不要生成不可执行 SQL。

## Hermes AI 看板操作

当任务涉及 Hermes 定时任务、AI 看板每日数据、延期风险订单、缺料/呆滞库存的写入或问答上下文时，必须先读取 [`references/hermes-operations.md`](references/hermes-operations.md)。该参考文件定义三张 AI 专用表的字段口径、每日快照生命周期、幂等键、事务边界、失败处理和校验 SQL。

当任务涉及 Demo 源数据、Hermes 配置、定时任务输入或“先造 ERP 数据、再让 Hermes 推断”的流程时，还必须读取 [`references/hermes-config-and-demo-source.md`](references/hermes-config-and-demo-source.md)。Demo 数据只能写入 Dolibarr 核心业务表；不得把预设的风险结果直接写入 AI 看板表来伪造 Hermes 产出。

Hermes 默认只能读取 Dolibarr 核心业务表，并写入 `llx_ai_dashboard_run`、`llx_ai_dashboard_order_risk_daily` 和 `llx_ai_dashboard_inventory_risk_daily`；不得因为生成风险分析而直接修改 `llx_commande`、`llx_product`、`llx_product_stock` 或其他 Dolibarr 业务表。写入真实库前，必须确认实体、业务日期、快照模式（全量/增量）和用户授权；全量快照删除也只能限定到指定 `entity + snapshot_date`。

Hermes 连接凭据、API 密钥和数据库密码不属于 skill 内容，必须从运行环境的安全配置读取。

输出结论时，给出表和字段依据、连接路径、过滤条件、指标公式、样例 SQL、数据缺口及线上核验建议。
