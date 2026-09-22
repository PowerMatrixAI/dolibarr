#!/usr/bin/env python3
"""Small, parameterized MySQL bridge for the Hermes Dolibarr skill.

The bridge deliberately separates source reads from AI-fact writes:
  preflight  - connection/schema/count checks only
  context    - read ERP source data as JSON for Hermes to analyze
  write      - write only validated Hermes results to AI-owned tables

Credentials are read from DOLIBARR_DB_ENV_FILE (default:
/root/.hermes/dolibarr-db.env). No credential is accepted in a command-line
argument and no credential is printed.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from decimal import Decimal
from typing import Any, Dict, Iterable, List, Mapping, Sequence
from zoneinfo import ZoneInfo

import pymysql
from pymysql.cursors import DictCursor


PREFIX_RE = re.compile(r"^[A-Za-z0-9_]+$")
RISK_LEVELS = {"high", "medium", "low"}
RISK_TYPES = {"shortage", "stagnant"}


def load_env(path: str) -> Dict[str, str]:
    values: Dict[str, str] = {}
    with open(path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].lstrip()
            if "=" not in line:
                continue
            name, value = line.split("=", 1)
            name = name.strip()
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
                value = value[1:-1]
            values[name] = value
    return values


def settings() -> Dict[str, Any]:
    env_path = os.environ.get("DOLIBARR_DB_ENV_FILE", "/root/.hermes/dolibarr-db.env")
    values = load_env(env_path)
    required = ("DOLIBARR_DB_HOST", "DOLIBARR_DB_PORT", "DOLIBARR_DB_NAME", "DOLIBARR_DB_USER", "DOLIBARR_DB_PASSWORD")
    missing = [name for name in required if not values.get(name)]
    if missing:
        raise RuntimeError("Missing database settings: " + ", ".join(missing))
    prefix = values.get("DOLIBARR_DB_PREFIX", "llx_")
    if not PREFIX_RE.fullmatch(prefix):
        raise RuntimeError("Invalid DOLIBARR_DB_PREFIX")
    return {
        "env_path": env_path,
        "host": values["DOLIBARR_DB_HOST"],
        "port": int(values.get("DOLIBARR_DB_PORT", "3306")),
        "database": values["DOLIBARR_DB_NAME"],
        "user": values["DOLIBARR_DB_USER"],
        "password": values["DOLIBARR_DB_PASSWORD"],
        "prefix": prefix,
        "entity": int(values.get("DOLIBARR_ENTITY", "1")),
        "timezone": values.get("DOLIBARR_DB_TIMEZONE", "Asia/Shanghai"),
        "source_ref_prefix": values.get("DOLIBARR_SOURCE_REF_PREFIX", ""),
        "stagnant_days": int(values.get("DOLIBARR_STAGNANT_DAYS", "120")),
        "consumption_days": int(values.get("DOLIBARR_CONSUMPTION_DAYS", "90")),
    }


def connect(cfg: Mapping[str, Any]):
    return pymysql.connect(
        host=cfg["host"],
        port=cfg["port"],
        user=cfg["user"],
        password=cfg["password"],
        database=cfg["database"],
        charset="utf8mb4",
        cursorclass=DictCursor,
        autocommit=False,
        connect_timeout=15,
        read_timeout=60,
        write_timeout=60,
    )


def table(cfg: Mapping[str, Any], name: str) -> str:
    return cfg["prefix"] + name


def json_value(value: Any) -> Any:
    if isinstance(value, (dt.datetime, dt.date, dt.time)):
        return value.isoformat(sep=" ") if isinstance(value, dt.datetime) else value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def json_dump(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, default=json_value, indent=2))


def table_names(cfg: Mapping[str, Any]) -> List[str]:
    return [
        table(cfg, "societe"),
        table(cfg, "entrepot"),
        table(cfg, "product"),
        table(cfg, "product_stock"),
        table(cfg, "stock_mouvement"),
        table(cfg, "commande"),
        table(cfg, "commandedet"),
        table(cfg, "commande_fournisseur"),
        table(cfg, "commande_fournisseurdet"),
        table(cfg, "ai_dashboard_run"),
        table(cfg, "ai_dashboard_order_risk_daily"),
        table(cfg, "ai_dashboard_inventory_risk_daily"),
    ]


def existing_tables(cursor, cfg: Mapping[str, Any]) -> List[str]:
    names = table_names(cfg)
    placeholders = ",".join(["%s"] * len(names))
    cursor.execute(
        "SELECT TABLE_NAME FROM information_schema.TABLES "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN (" + placeholders + ")",
        names,
    )
    return sorted(row["TABLE_NAME"] for row in cursor.fetchall())


def source_filter(cfg: Mapping[str, Any], column: str = "ref") -> tuple[str, List[Any]]:
    prefix = cfg["source_ref_prefix"]
    if prefix:
        return f" AND {column} LIKE %s", [prefix + "%"]
    return "", []


def preflight(cfg: Mapping[str, Any]) -> None:
    connection = connect(cfg)
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT DATABASE() AS database_name, CURRENT_USER() AS current_user_value, @@session.time_zone AS session_time_zone")
            identity = cursor.fetchone()
            present = existing_tables(cursor, cfg)
            required = table_names(cfg)
            counts: Dict[str, int] = {}
            for short_name in ("product", "product_stock", "stock_mouvement", "commande", "commandedet", "commande_fournisseur", "commande_fournisseurdet"):
                full_name = table(cfg, short_name)
                if full_name not in present:
                    continue
                suffix, params = source_filter(cfg)
                if short_name in ("product_stock", "stock_mouvement", "commandedet", "commande_fournisseurdet"):
                    query = f"SELECT COUNT(*) AS row_count FROM `{full_name}`"
                    query_params: Sequence[Any] = []
                else:
                    query = f"SELECT COUNT(*) AS row_count FROM `{full_name}` WHERE entity = %s"
                    query_params = [cfg["entity"]]
                    if short_name in ("commande", "commande_fournisseur"):
                        query += suffix
                        query_params = list(query_params) + params
                cursor.execute(query, query_params)
                counts[short_name] = int(cursor.fetchone()["row_count"])
            json_dump({
                "ok": set(required).issubset(set(present)),
                "database": identity,
                "entity": cfg["entity"],
                "prefix": cfg["prefix"],
                "required_tables": required,
                "present_tables": present,
                "missing_tables": sorted(set(required) - set(present)),
                "source_ref_prefix": cfg["source_ref_prefix"] or None,
                "source_counts": counts,
            })
    finally:
        connection.close()


def fetch_all(cursor, query: str, params: Sequence[Any]) -> List[Dict[str, Any]]:
    cursor.execute(query, params)
    return list(cursor.fetchall())


def context(cfg: Mapping[str, Any], snapshot_date: str) -> None:
    connection = connect(cfg)
    p = cfg["prefix"]
    order_filter, order_params = source_filter(cfg, "c.ref")
    purchase_filter, purchase_params = source_filter(cfg, "cf.ref")
    # The demo uses AIH- references for orders but RM-xxx-AI / FG-xxx-AI
    # references for products. Inventory is therefore scoped by actual stock
    # rows instead of reusing the order reference prefix.
    product_filter, product_params = "", []
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                f"SELECT c.rowid AS order_id, c.ref AS order_ref, c.fk_soc AS customer_id, "
                f"s.nom AS customer_name, c.fk_statut AS order_status, c.date_commande, "
                f"c.date_livraison, c.total_ht, c.fk_warehouse "
                f"FROM `{p}commande` c LEFT JOIN `{p}societe` s ON s.rowid = c.fk_soc "
                f"WHERE c.entity = %s AND c.date_commande >= DATE_SUB(%s, INTERVAL 400 DAY)"
                + order_filter + " ORDER BY c.date_livraison IS NULL, c.date_livraison, c.rowid",
                [cfg["entity"], snapshot_date] + order_params,
            )
            orders = list(cursor.fetchall())

            order_lines = fetch_all(
                cursor,
                f"SELECT cd.rowid AS order_line_id, cd.fk_commande AS order_id, "
                f"cd.fk_product AS product_id, p.ref AS product_ref, p.label AS product_label, "
                f"cd.qty, cd.subprice, cd.total_ht, cd.fk_commandefourndet AS linked_purchase_line_id, "
                f"ps.reel AS current_stock, p.desiredstock, p.seuil_stock_alerte, "
                f"cfd.fk_commande AS linked_purchase_id, cf.ref AS linked_purchase_ref, "
                f"cf.fk_statut AS linked_purchase_status, cf.date_livraison AS linked_purchase_due_date "
                f"FROM `{p}commandedet` cd JOIN `{p}commande` c ON c.rowid = cd.fk_commande "
                f"LEFT JOIN `{p}product` p ON p.rowid = cd.fk_product "
                f"LEFT JOIN `{p}product_stock` ps ON ps.fk_product = cd.fk_product AND ps.fk_entrepot = c.fk_warehouse "
                f"LEFT JOIN `{p}commande_fournisseurdet` cfd ON cfd.rowid = cd.fk_commandefourndet "
                f"LEFT JOIN `{p}commande_fournisseur` cf ON cf.rowid = cfd.fk_commande "
                f"WHERE c.entity = %s AND c.date_commande >= DATE_SUB(%s, INTERVAL 400 DAY)"
                + order_filter + " ORDER BY cd.fk_commande, cd.rowid",
                [cfg["entity"], snapshot_date] + order_params,
            )

            purchases = fetch_all(
                cursor,
                f"SELECT cf.rowid AS purchase_id, cf.ref AS purchase_ref, cf.fk_soc AS supplier_id, "
                f"s.nom AS supplier_name, cf.fk_statut AS purchase_status, cf.date_commande, "
                f"cf.date_livraison, cf.total_ht "
                f"FROM `{p}commande_fournisseur` cf LEFT JOIN `{p}societe` s ON s.rowid = cf.fk_soc "
                f"WHERE cf.entity = %s AND cf.date_commande >= DATE_SUB(%s, INTERVAL 400 DAY)"
                + purchase_filter + " ORDER BY cf.date_livraison IS NULL, cf.date_livraison, cf.rowid",
                [cfg["entity"], snapshot_date] + purchase_params,
            )
            purchase_lines = fetch_all(
                cursor,
                f"SELECT cfd.rowid AS purchase_line_id, cfd.fk_commande AS purchase_id, "
                f"cfd.fk_product AS product_id, p.ref AS product_ref, p.label AS product_label, "
                f"cfd.qty, cfd.subprice, cfd.total_ht "
                f"FROM `{p}commande_fournisseurdet` cfd JOIN `{p}commande_fournisseur` cf ON cf.rowid = cfd.fk_commande "
                f"LEFT JOIN `{p}product` p ON p.rowid = cfd.fk_product "
                f"WHERE cf.entity = %s AND cf.date_commande >= DATE_SUB(%s, INTERVAL 400 DAY)"
                + purchase_filter + " ORDER BY cfd.fk_commande, cfd.rowid",
                [cfg["entity"], snapshot_date] + purchase_params,
            )

            inventory = fetch_all(
                cursor,
                f"SELECT p.rowid AS product_id, p.ref AS product_ref, p.label AS product_label, "
                f"p.cost_price, p.desiredstock, p.seuil_stock_alerte, p.fk_default_warehouse, "
                f"e.ref AS warehouse_ref, ps.fk_entrepot AS warehouse_id, ps.reel AS current_stock, "
                f"MAX(sm.datem) AS last_movement_date, "
                f"COALESCE(SUM(CASE WHEN sm.datem >= DATE_SUB(%s, INTERVAL %s DAY) AND sm.value < 0 THEN -sm.value ELSE 0 END), 0) AS recent_consumption "
                f"FROM `{p}product` p JOIN `{p}product_stock` ps ON ps.fk_product = p.rowid "
                f"LEFT JOIN `{p}entrepot` e ON e.rowid = ps.fk_entrepot "
                f"LEFT JOIN `{p}stock_mouvement` sm ON sm.fk_product = p.rowid AND sm.fk_entrepot = ps.fk_entrepot "
                f"WHERE p.entity = %s" + product_filter + " "
                f"GROUP BY p.rowid, p.ref, p.label, p.cost_price, p.desiredstock, p.seuil_stock_alerte, "
                f"p.fk_default_warehouse, e.ref, ps.fk_entrepot, ps.reel "
                f"ORDER BY p.ref, ps.fk_entrepot",
                [snapshot_date, cfg["consumption_days"], cfg["entity"]] + product_params,
            )

            json_dump({
                "source": "dolibarr_core_tables",
                "entity": cfg["entity"],
                "snapshot_date": snapshot_date,
                "timezone": cfg["timezone"],
                "status_note": "Validate fk_statut meanings against the installed Dolibarr version before applying thresholds.",
                "thresholds": {
                    "stagnant_days": cfg["stagnant_days"],
                    "consumption_window_days": cfg["consumption_days"],
                },
                "orders": orders,
                "order_lines": order_lines,
                "purchases": purchases,
                "purchase_lines": purchase_lines,
                "inventory": inventory,
            })
    finally:
        connection.close()


def required_number(value: Any, name: str) -> int:
    try:
        number = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{name} must be an integer") from exc
    if number <= 0:
        raise ValueError(f"{name} must be positive")
    return number


def validate_results(cursor, cfg: Mapping[str, Any], payload: Mapping[str, Any]) -> tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    entity = required_number(payload.get("entity"), "entity")
    if entity != cfg["entity"]:
        raise ValueError("entity does not match DOLIBARR_ENTITY")
    snapshot_date = str(payload.get("snapshot_date", ""))
    try:
        dt.date.fromisoformat(snapshot_date)
    except ValueError as exc:
        raise ValueError("snapshot_date must be YYYY-MM-DD") from exc

    orders_in = payload.get("orders", [])
    inventory_in = payload.get("inventory", [])
    if not isinstance(orders_in, list) or not isinstance(inventory_in, list):
        raise ValueError("orders and inventory must be arrays")
    order_ids = [required_number(item.get("order_id"), "order_id") for item in orders_in]
    product_ids = [required_number(item.get("product_id"), "product_id") for item in inventory_in]
    warehouse_ids = [required_number(item.get("warehouse_id"), "warehouse_id") for item in inventory_in]

    p = cfg["prefix"]
    order_map: Dict[int, Dict[str, Any]] = {}
    if order_ids:
        placeholders = ",".join(["%s"] * len(order_ids))
        cursor.execute(f"SELECT rowid, ref, total_ht FROM `{p}commande` WHERE entity = %s AND rowid IN ({placeholders})", [entity] + order_ids)
        order_map = {int(row["rowid"]): row for row in cursor.fetchall()}
    if len(order_map) != len(set(order_ids)):
        raise ValueError("at least one order_id does not exist in the configured entity")

    product_map: Dict[int, Dict[str, Any]] = {}
    if product_ids:
        placeholders = ",".join(["%s"] * len(product_ids))
        cursor.execute(f"SELECT rowid, ref, label FROM `{p}product` WHERE entity = %s AND rowid IN ({placeholders})", [entity] + list(set(product_ids)))
        product_map = {int(row["rowid"]): row for row in cursor.fetchall()}
    if len(product_map) != len(set(product_ids)):
        raise ValueError("at least one product_id does not exist in the configured entity")

    warehouse_map: Dict[int, Dict[str, Any]] = {}
    if warehouse_ids:
        placeholders = ",".join(["%s"] * len(set(warehouse_ids)))
        cursor.execute(f"SELECT rowid, ref FROM `{p}entrepot` WHERE entity = %s AND rowid IN ({placeholders})", [entity] + list(set(warehouse_ids)))
        warehouse_map = {int(row["rowid"]): row for row in cursor.fetchall()}
    if len(warehouse_map) != len(set(warehouse_ids)):
        raise ValueError("at least one warehouse_id does not exist in the configured entity")

    orders: List[Dict[str, Any]] = []
    for item, order_id in zip(orders_in, order_ids):
        if item.get("order_ref") != order_map[order_id]["ref"]:
            raise ValueError(f"order_ref does not match order_id {order_id}")
        level = str(item.get("risk_level", "medium"))
        if level not in RISK_LEVELS:
            raise ValueError("invalid order risk_level")
        probability = float(item.get("delay_probability", 0))
        if probability < 0 or probability > 100:
            raise ValueError("delay_probability must be between 0 and 100")
        orders.append({
            "order_id": order_id,
            "order_ref": item["order_ref"],
            "customer_id": item.get("customer_id"),
            "customer_name": item.get("customer_name"),
            "risk_level": level,
            "delay_probability": probability,
            "expected_delay_days": item.get("expected_delay_days"),
            "risk_reason": str(item.get("risk_reason", ""))[:10000],
            "shortage_count": int(item.get("shortage_count", 0)),
            "linked_purchase_count": int(item.get("linked_purchase_count", 0)),
            "affected_amount": item.get("affected_amount", order_map[order_id].get("total_ht")),
        })

    inventory: List[Dict[str, Any]] = []
    for item, product_id, warehouse_id in zip(inventory_in, product_ids, warehouse_ids):
        if item.get("product_ref") != product_map[product_id]["ref"]:
            raise ValueError(f"product_ref does not match product_id {product_id}")
        risk_type = str(item.get("risk_type", ""))
        if risk_type not in RISK_TYPES:
            raise ValueError("invalid inventory risk_type")
        level = str(item.get("risk_level", "medium"))
        if level not in RISK_LEVELS:
            raise ValueError("invalid inventory risk_level")
        inventory.append({
            "risk_type": risk_type,
            "risk_level": level,
            "product_id": product_id,
            "product_ref": item["product_ref"],
            "product_label": item.get("product_label", product_map[product_id].get("label")),
            "warehouse_id": warehouse_id,
            "warehouse_ref": item.get("warehouse_ref", warehouse_map[warehouse_id].get("ref")),
            "current_stock": item.get("current_stock"),
            "daily_consumption": item.get("daily_consumption"),
            "days_to_stockout": item.get("days_to_stockout"),
            "forecast_stockout_date": item.get("forecast_stockout_date"),
            "desired_stock": item.get("desired_stock"),
            "alert_stock": item.get("alert_stock"),
            "impact_amount": item.get("impact_amount"),
            "affected_order_count": int(item.get("affected_order_count", 0)),
            "affected_order_refs": str(item.get("affected_order_refs", ""))[:10000],
            "last_movement_date": item.get("last_movement_date"),
            "risk_reason": str(item.get("risk_reason", ""))[:10000],
        })
    return orders, inventory


def write_results(cfg: Mapping[str, Any], input_path: str) -> None:
    with open(input_path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
    connection = connect(cfg)
    p = cfg["prefix"]
    try:
        with connection.cursor() as cursor:
            orders, inventory = validate_results(cursor, cfg, payload)
            entity = int(payload["entity"])
            snapshot_date = str(payload["snapshot_date"])
            started_at = dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
            cursor.execute(
                f"INSERT INTO `{p}ai_dashboard_run` "
                "(entity, run_type, snapshot_date, status, started_at, finished_at, row_count, source, summary, error_message) "
                "VALUES (%s, 'manufacturing_risk', %s, 'running', %s, NULL, 0, 'hermes', %s, NULL) "
                "ON DUPLICATE KEY UPDATE rowid = LAST_INSERT_ID(rowid), status = 'running', started_at = VALUES(started_at), finished_at = NULL, row_count = 0, source = VALUES(source), summary = VALUES(summary), error_message = NULL",
                (entity, snapshot_date, started_at, str(payload.get("summary", ""))[:10000]),
            )
            run_id = int(cursor.lastrowid)
            cursor.execute(f"DELETE FROM `{p}ai_dashboard_order_risk_daily` WHERE entity = %s AND snapshot_date = %s", (entity, snapshot_date))
            cursor.execute(f"DELETE FROM `{p}ai_dashboard_inventory_risk_daily` WHERE entity = %s AND snapshot_date = %s", (entity, snapshot_date))
            for item in orders:
                cursor.execute(
                    f"INSERT INTO `{p}ai_dashboard_order_risk_daily` "
                    "(entity, snapshot_date, order_id, order_ref, customer_id, customer_name, risk_level, delay_probability, expected_delay_days, risk_reason, shortage_count, linked_purchase_count, affected_amount, source_run_id, created_at) "
                    "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NOW())",
                    (entity, snapshot_date, item["order_id"], item["order_ref"], item["customer_id"], item["customer_name"], item["risk_level"], item["delay_probability"], item["expected_delay_days"], item["risk_reason"], item["shortage_count"], item["linked_purchase_count"], item["affected_amount"], run_id),
                )
            for item in inventory:
                cursor.execute(
                    f"INSERT INTO `{p}ai_dashboard_inventory_risk_daily` "
                    "(entity, snapshot_date, risk_type, risk_level, product_id, product_ref, product_label, warehouse_id, warehouse_ref, current_stock, daily_consumption, days_to_stockout, forecast_stockout_date, desired_stock, alert_stock, impact_amount, affected_order_count, affected_order_refs, last_movement_date, risk_reason, source_run_id, created_at) "
                    "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NOW())",
                    (entity, snapshot_date, item["risk_type"], item["risk_level"], item["product_id"], item["product_ref"], item["product_label"], item["warehouse_id"], item["warehouse_ref"], item["current_stock"], item["daily_consumption"], item["days_to_stockout"], item["forecast_stockout_date"], item["desired_stock"], item["alert_stock"], item["impact_amount"], item["affected_order_count"], item["affected_order_refs"], item["last_movement_date"], item["risk_reason"], run_id),
                )
            row_count = len(orders) + len(inventory)
            cursor.execute(
                f"UPDATE `{p}ai_dashboard_run` SET status = 'success', finished_at = NOW(), row_count = %s, error_message = NULL WHERE rowid = %s",
                (row_count, run_id),
            )
        connection.commit()
        json_dump({"ok": True, "run_id": run_id, "entity": entity, "snapshot_date": snapshot_date, "order_rows": len(orders), "inventory_rows": len(inventory), "row_count": row_count})
    except Exception as exc:
        connection.rollback()
        try:
            with connection.cursor() as cursor:
                entity = int(payload.get("entity", cfg["entity"]))
                snapshot_date = str(payload.get("snapshot_date", ""))
                cursor.execute(
                    f"INSERT INTO `{p}ai_dashboard_run` (entity, run_type, snapshot_date, status, started_at, finished_at, row_count, source, summary, error_message) "
                    "VALUES (%s, 'manufacturing_risk', %s, 'failed', NOW(), NOW(), 0, 'hermes', %s, %s) "
                    "ON DUPLICATE KEY UPDATE status = 'failed', finished_at = NOW(), error_message = VALUES(error_message), summary = VALUES(summary)",
                    (entity, snapshot_date, str(payload.get("summary", ""))[:10000], str(exc)[:2000]),
                )
            connection.commit()
        except Exception:
            connection.rollback()
        raise
    finally:
        connection.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Hermes Dolibarr MySQL bridge")
    parser.add_argument("command", choices=("preflight", "context", "write"))
    parser.add_argument("--date", dest="snapshot_date", default=None, help="Business date YYYY-MM-DD")
    parser.add_argument("--input", dest="input_path", default=None, help="Hermes result JSON for write")
    args = parser.parse_args()
    try:
        cfg = settings()
        if args.command == "preflight":
            preflight(cfg)
        elif args.command == "context":
            snapshot_date = args.snapshot_date or dt.datetime.now(ZoneInfo(cfg["timezone"])).date().isoformat()
            context(cfg, snapshot_date)
        else:
            if not args.input_path:
                raise ValueError("write requires --input")
            write_results(cfg, args.input_path)
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)[:2000]}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
