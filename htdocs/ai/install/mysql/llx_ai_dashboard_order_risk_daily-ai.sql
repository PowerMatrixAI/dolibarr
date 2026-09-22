-- Daily order delay-risk facts produced by the Hermes scheduled job.
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
