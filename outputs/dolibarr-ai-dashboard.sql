-- Dolibarr AI dashboard schema for MySQL.
-- Review the table prefix before execution if MAIN_DB_PREFIX is not llx_.
-- This file creates AI-owned tables only. It intentionally inserts no demo
-- facts; Hermes must read the Dolibarr source tables, infer risks, and write
-- the daily snapshot tables.

CREATE TABLE IF NOT EXISTS llx_ai_dashboard_run (
  rowid integer AUTO_INCREMENT PRIMARY KEY,
  entity integer NOT NULL DEFAULT 1,
  run_type varchar(32) NOT NULL,
  snapshot_date date NOT NULL,
  status varchar(16) NOT NULL DEFAULT 'success',
  started_at datetime NOT NULL,
  finished_at datetime DEFAULT NULL,
  row_count integer NOT NULL DEFAULT 0,
  source varchar(64) DEFAULT NULL,
  summary text,
  error_message text,
  tms timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uk_ai_dashboard_run (entity, run_type, snapshot_date),
  KEY idx_ai_dashboard_run_date (entity, snapshot_date)
) ENGINE=innodb;

CREATE TABLE IF NOT EXISTS llx_ai_dashboard_order_risk_daily (
  rowid integer AUTO_INCREMENT PRIMARY KEY,
  entity integer NOT NULL DEFAULT 1,
  snapshot_date date NOT NULL,
  order_id integer NOT NULL DEFAULT 0,
  order_ref varchar(64) NOT NULL,
  customer_id integer DEFAULT NULL,
  customer_name varchar(255) DEFAULT NULL,
  risk_level varchar(16) NOT NULL DEFAULT 'medium',
  delay_probability decimal(5,2) DEFAULT NULL,
  expected_delay_days decimal(10,2) DEFAULT NULL,
  risk_reason text,
  shortage_count integer NOT NULL DEFAULT 0,
  linked_purchase_count integer NOT NULL DEFAULT 0,
  affected_amount decimal(24,8) DEFAULT NULL,
  source_run_id integer DEFAULT NULL,
  created_at datetime NOT NULL,
  tms timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uk_ai_order_risk_daily (entity, snapshot_date, order_id),
  KEY idx_ai_order_risk_daily_date (entity, snapshot_date),
  KEY idx_ai_order_risk_daily_level (entity, snapshot_date, risk_level)
) ENGINE=innodb;

CREATE TABLE IF NOT EXISTS llx_ai_dashboard_inventory_risk_daily (
  rowid integer AUTO_INCREMENT PRIMARY KEY,
  entity integer NOT NULL DEFAULT 1,
  snapshot_date date NOT NULL,
  risk_type varchar(16) NOT NULL,
  risk_level varchar(16) NOT NULL DEFAULT 'medium',
  product_id integer NOT NULL DEFAULT 0,
  product_ref varchar(128) NOT NULL,
  product_label varchar(255) DEFAULT NULL,
  warehouse_id integer DEFAULT NULL,
  warehouse_ref varchar(64) DEFAULT NULL,
  current_stock decimal(24,8) DEFAULT NULL,
  daily_consumption decimal(24,8) DEFAULT NULL,
  days_to_stockout decimal(10,2) DEFAULT NULL,
  forecast_stockout_date date DEFAULT NULL,
  desired_stock decimal(24,8) DEFAULT NULL,
  alert_stock decimal(24,8) DEFAULT NULL,
  impact_amount decimal(24,8) DEFAULT NULL,
  affected_order_count integer NOT NULL DEFAULT 0,
  affected_order_refs text,
  last_movement_date date DEFAULT NULL,
  risk_reason text,
  source_run_id integer DEFAULT NULL,
  created_at datetime NOT NULL,
  tms timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uk_ai_inventory_risk_daily (entity, snapshot_date, risk_type, product_id, warehouse_id),
  KEY idx_ai_inventory_risk_daily_date (entity, snapshot_date),
  KEY idx_ai_inventory_risk_daily_type (entity, snapshot_date, risk_type),
  KEY idx_ai_inventory_risk_daily_level (entity, snapshot_date, risk_level)
) ENGINE=innodb;

-- After this schema is installed, use the source-only dataset in
-- outputs/dolibarr-ai-demo-seed-large.sql, then run Hermes according to
-- skills/dolibarr-database/references/hermes-config-and-demo-source.md and
-- skills/dolibarr-database/references/hermes-operations.md.
