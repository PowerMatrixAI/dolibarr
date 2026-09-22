<?php
/* Copyright (C) 2026      OpenAI */

/**
 * \file    htdocs/ai/lib/ai_dashboard.lib.php
 * \ingroup ai
 * \brief   Database helpers for the Hermes-powered AI dashboard.
 */

/** @var DoliDB $db */

/** @var string Daily order-risk table suffix */
define('AI_DASHBOARD_ORDER_TABLE', 'ai_dashboard_order_risk_daily');

/** @var string Daily inventory-risk table suffix */
define('AI_DASHBOARD_INVENTORY_TABLE', 'ai_dashboard_inventory_risk_daily');

/** @var string Hermes job-run table suffix */
define('AI_DASHBOARD_RUN_TABLE', 'ai_dashboard_run');

/**
 * Check whether a dashboard table exists in the current MySQL database.
 *
 * @param DoliDB $db    Dolibarr database handle
 * @param string $table Unprefixed table name from the fixed constants above
 * @return bool True when the table exists
 */
function ai_dashboard_table_exists($db, $table)
{
	$fullTable = $db->prefix().$table;
	$sql = "SELECT COUNT(*) AS nb FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = '".$db->escape($fullTable)."'";
	$result = $db->query($sql);
	if (!$result) {
		return false;
	}

	$object = $db->fetch_object($result);
	return $object && (int) $object->nb > 0;
}

/**
 * Return the most recent date produced by either daily data table.
 *
 * @param DoliDB $db     Dolibarr database handle
 * @param int    $entity Current Dolibarr entity
 * @return string|null ISO date or null when no snapshot exists
 */
function ai_dashboard_get_latest_snapshot_date($db, $entity)
{
	$entity = (int) $entity;
	$parts = array();
	if (ai_dashboard_table_exists($db, AI_DASHBOARD_ORDER_TABLE)) {
		$parts[] = "SELECT snapshot_date FROM ".$db->prefix().AI_DASHBOARD_ORDER_TABLE." WHERE entity = ".$entity;
	}
	if (ai_dashboard_table_exists($db, AI_DASHBOARD_INVENTORY_TABLE)) {
		$parts[] = "SELECT snapshot_date FROM ".$db->prefix().AI_DASHBOARD_INVENTORY_TABLE." WHERE entity = ".$entity;
	}
	if (empty($parts)) {
		return null;
	}

	$sql = 'SELECT MAX(snapshot_date) AS snapshot_date FROM ('.implode(' UNION ALL ', $parts).') AS snapshots';
	$result = $db->query($sql);
	if (!$result) {
		return null;
	}

	$object = $db->fetch_object($result);
	return $object && !empty($object->snapshot_date) ? (string) $object->snapshot_date : null;
}

/**
 * Get the top-line metrics for one daily snapshot.
 *
 * @param DoliDB $db     Dolibarr database handle
 * @param int    $entity Current Dolibarr entity
 * @param string $date   ISO date
 * @return array<string,int|float> Summary metrics
 */
function ai_dashboard_get_summary($db, $entity, $date)
{
	$summary = array(
		'order_risk_count' => 0,
		'shortage_count' => 0,
		'stagnant_count' => 0,
		'affected_amount' => 0.0,
		'average_probability' => 0.0,
	);
	$date = $db->escape($date);
	$entity = (int) $entity;

	if (ai_dashboard_table_exists($db, AI_DASHBOARD_ORDER_TABLE)) {
		$sql = "SELECT COUNT(*) AS nb, COALESCE(SUM(affected_amount), 0) AS amount, COALESCE(AVG(delay_probability), 0) AS probability FROM ".$db->prefix().AI_DASHBOARD_ORDER_TABLE." WHERE entity = ".$entity." AND snapshot_date = '".$date."'";
		$result = $db->query($sql);
		if ($result && ($object = $db->fetch_object($result))) {
			$summary['order_risk_count'] = (int) $object->nb;
			$summary['affected_amount'] = (float) $object->amount;
			$summary['average_probability'] = (float) $object->probability;
		}
	}

	if (ai_dashboard_table_exists($db, AI_DASHBOARD_INVENTORY_TABLE)) {
		$sql = "SELECT risk_type, COUNT(*) AS nb FROM ".$db->prefix().AI_DASHBOARD_INVENTORY_TABLE." WHERE entity = ".$entity." AND snapshot_date = '".$date."' GROUP BY risk_type";
		$result = $db->query($sql);
		if ($result) {
			while ($object = $db->fetch_object($result)) {
				if ($object->risk_type === 'shortage') {
					$summary['shortage_count'] = (int) $object->nb;
				} elseif ($object->risk_type === 'stagnant') {
					$summary['stagnant_count'] = (int) $object->nb;
				}
			}
		}
	}

	return $summary;
}

/**
 * Fetch the highest-risk orders for a dashboard snapshot.
 *
 * @param DoliDB $db     Dolibarr database handle
 * @param int    $entity Current Dolibarr entity
 * @param string $date   ISO date
 * @param int    $limit  Maximum rows
 * @return array<int,stdClass> Risk rows
 */
function ai_dashboard_fetch_order_risks($db, $entity, $date, $limit = 8)
{
	if (!ai_dashboard_table_exists($db, AI_DASHBOARD_ORDER_TABLE)) {
		return array();
	}

	$entity = (int) $entity;
	$limit = max(1, min(50, (int) $limit));
	$date = $db->escape($date);
	$sql = "SELECT rowid, order_id, order_ref, customer_id, customer_name, risk_level, delay_probability, expected_delay_days, risk_reason, shortage_count, linked_purchase_count, affected_amount FROM ".$db->prefix().AI_DASHBOARD_ORDER_TABLE." WHERE entity = ".$entity." AND snapshot_date = '".$date."' ORDER BY CASE risk_level WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END, delay_probability DESC, expected_delay_days DESC LIMIT ".$limit;
	$result = $db->query($sql);
	$rows = array();
	if (!$result) {
		return $rows;
	}
	while ($object = $db->fetch_object($result)) {
		$rows[] = $object;
	}

	return $rows;
}

/**
 * Fetch the highest-impact inventory risks for a dashboard snapshot.
 *
 * @param DoliDB $db        Dolibarr database handle
 * @param int    $entity    Current Dolibarr entity
 * @param string $date      ISO date
 * @param string $riskType  shortage or stagnant
 * @param int    $limit     Maximum rows
 * @return array<int,stdClass> Risk rows
 */
function ai_dashboard_fetch_inventory_risks($db, $entity, $date, $riskType, $limit = 8)
{
	if (!ai_dashboard_table_exists($db, AI_DASHBOARD_INVENTORY_TABLE) || !in_array($riskType, array('shortage', 'stagnant'), true)) {
		return array();
	}

	$entity = (int) $entity;
	$limit = max(1, min(50, (int) $limit));
	$date = $db->escape($date);
	$riskType = $db->escape($riskType);
	$sql = "SELECT rowid, risk_type, risk_level, product_id, product_ref, product_label, warehouse_id, warehouse_ref, current_stock, daily_consumption, days_to_stockout, forecast_stockout_date, desired_stock, alert_stock, impact_amount, affected_order_count, affected_order_refs, last_movement_date, risk_reason FROM ".$db->prefix().AI_DASHBOARD_INVENTORY_TABLE." WHERE entity = ".$entity." AND snapshot_date = '".$date."' AND risk_type = '".$riskType."' ORDER BY CASE risk_level WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END, impact_amount DESC, affected_order_count DESC LIMIT ".$limit;
	$result = $db->query($sql);
	$rows = array();
	if (!$result) {
		return $rows;
	}
	while ($object = $db->fetch_object($result)) {
		$rows[] = $object;
	}

	return $rows;
}

/**
 * Build a compact, factual context for Hermes from the visible dashboard.
 *
 * @param array<string,int|float> $summary Dashboard totals
 * @param array<int,stdClass>     $orders  Visible order risks
 * @param array<int,stdClass>     $shortage Visible shortage risks
 * @param array<int,stdClass>     $stagnant Visible stagnant risks
 * @param string                  $date Snapshot date
 * @return string Plain-text context
 */
function ai_dashboard_build_hermes_context($summary, $orders, $shortage, $stagnant, $date)
{
	$lines = array(
		'数据日期：'.$date,
		'延期风险订单数：'.(int) $summary['order_risk_count'],
		'缺料库存数：'.(int) $summary['shortage_count'],
		'呆滞库存数：'.(int) $summary['stagnant_count'],
		'延期风险订单影响金额：'.number_format((float) $summary['affected_amount'], 2, '.', ''),
		'延期概率平均值：'.number_format((float) $summary['average_probability'], 2, '.', '').'%',
		'',
		'延期风险订单（看板当前列表）：',
	);
	foreach ($orders as $row) {
		$lines[] = '- '.$row->order_ref.' / 客户：'.$row->customer_name.' / 风险：'.$row->risk_level.' / 延期概率：'.$row->delay_probability.'% / 预计延期：'.$row->expected_delay_days.'天 / 原因：'.$row->risk_reason;
	}
	$lines[] = '';
	$lines[] = '缺料库存（看板当前列表）：';
	foreach ($shortage as $row) {
		$lines[] = '- '.$row->product_ref.' '.$row->product_label.' / 仓库：'.$row->warehouse_ref.' / 当前库存：'.$row->current_stock.' / 可用天数：'.$row->days_to_stockout.' / 关联订单：'.$row->affected_order_refs.' / 原因：'.$row->risk_reason;
	}
	$lines[] = '';
	$lines[] = '呆滞库存（看板当前列表）：';
	foreach ($stagnant as $row) {
		$lines[] = '- '.$row->product_ref.' '.$row->product_label.' / 仓库：'.$row->warehouse_ref.' / 当前库存：'.$row->current_stock.' / 最后消耗：'.$row->last_movement_date.' / 影响金额：'.$row->impact_amount.' / 原因：'.$row->risk_reason;
	}

	return implode("\n", $lines);
}
