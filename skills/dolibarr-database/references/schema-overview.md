# Dolibarr 数据字典概览

该引用目录来自项目内的 `dolibarr-database-dictionary.xlsx`，数据源为 Dolibarr MySQL DDL。

- DDL 基线：`htdocs/install/mysql/tables`
- 分支：`develop`
- 提取时的代码提交：`f90c44ae4d7`
- 表：414
- 字段：5394
- 索引与主键记录：1126
- 显式外键关系：237
- 业务模块统计：58

## 如何使用

先在 `table-catalog.tsv` 按表名或模块筛选，再到 `field-catalog.tsv` 查字段；需要确认连接路径时，同时查看 `foreign-key-relations.tsv` 和 `indexes-and-constraints.tsv`。

这是一份代码库 DDL 字典，不保证等同于当前部署库。回答线上问题或生成执行 SQL 前，应先用 `information_schema` 检查表、字段、索引和字符集；若表不存在，停止推断并明确报告。
