-- AI dashboard job executions. Hermes should upsert one row per entity/type/day.
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
