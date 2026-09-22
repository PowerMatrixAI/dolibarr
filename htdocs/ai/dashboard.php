<?php
/* Copyright (C) 2026      OpenAI */

/**
 * \file    htdocs/ai/dashboard.php
 * \ingroup ai
 * \brief   Hermes-powered AI manufacturing dashboard.
 */

define('CSRFCHECK_WITH_TOKEN', 1);
require '../main.inc.php';
require_once DOL_DOCUMENT_ROOT.'/ai/class/hermesclient.class.php';
require_once DOL_DOCUMENT_ROOT.'/ai/lib/ai_dashboard.lib.php';

/**
 * @var Conf $conf
 * @var DoliDB $db
 * @var Translate $langs
 * @var User $user
 */

if (!isModEnabled('ai')) {
	accessforbidden($langs->trans('ModuleNotActive'));
}
if (!$user->hasRight('ai', 'assistant', 'use')) {
	accessforbidden();
}

$langs->loadLangs(array('main', 'admin'));
$action = GETPOST('action', 'aZ09');
$question = trim(GETPOST('question', 'restricthtml'));
$requestedDate = trim(GETPOST('snapshot_date', 'alphanohtml'));
if ($requestedDate !== '' && !preg_match('/^\d{4}-\d{2}-\d{2}$/', $requestedDate)) {
	$requestedDate = '';
}

$entity = (int) $conf->entity;
$hasOrderTable = ai_dashboard_table_exists($db, AI_DASHBOARD_ORDER_TABLE);
$hasInventoryTable = ai_dashboard_table_exists($db, AI_DASHBOARD_INVENTORY_TABLE);
$latestDate = ai_dashboard_get_latest_snapshot_date($db, $entity);
$snapshotDate = $requestedDate !== '' ? $requestedDate : (string) $latestDate;
$summary = ai_dashboard_get_summary($db, $entity, $snapshotDate);
$orderRisks = ai_dashboard_fetch_order_risks($db, $entity, $snapshotDate, 10);
$shortageRisks = ai_dashboard_fetch_inventory_risks($db, $entity, $snapshotDate, 'shortage', 6);
$stagnantRisks = ai_dashboard_fetch_inventory_risks($db, $entity, $snapshotDate, 'stagnant', 6);
$answer = '';
$hermes = new HermesClient();

if ($action === 'ask') {
	if ($question === '') {
		setEventMessages($langs->trans('ErrorFieldRequired', $langs->trans('AIBusinessQA')), null, 'errors');
	} elseif (dol_strlen($question) > 2000) {
		setEventMessages($langs->trans('AIQuestionTooLong'), null, 'errors');
	} else {
		if (!$hermes->isConfigured()) {
			setEventMessages($langs->trans('AIHermesNotConfigured'), null, 'warnings');
		} else {
			$context = ai_dashboard_build_hermes_context($summary, $orderRisks, $shortageRisks, $stagnantRisks, $snapshotDate);
			$response = $hermes->ask($question, $context);
			if (!empty($response['success'])) {
				$answer = (string) $response['answer'];
			} else {
				setEventMessages((string) ($response['error'] ?? $langs->trans('Error')), null, 'errors');
			}
		}
	}
}

$pageTitle = $langs->trans('AIDashboard');
llxHeader('', $pageTitle, '', '', 0, 0, '', '', '', 'mod-ai page-dashboard');
print '<link rel="stylesheet" href="'.dol_buildpath('/ai/css/ai_dashboard.css', 1).'">';

print '<div class="ai-dashboard">';
print '<div class="ai-dashboard-header">';
print '<div><div class="ai-dashboard-eyebrow"><span class="fas fa-magic"></span> AI</div>';
print '<h1>'.$langs->trans('AIMfgAssistant').'</h1>';
print '<p>'.$langs->trans('AIHermesDailyDataSource').'</p></div>';
print '<div class="ai-dashboard-date">';
print '<form method="GET" action="'.dol_escape_htmltag($_SERVER['PHP_SELF']).'">';
print '<input type="hidden" name="mainmenu" value="home"><input type="hidden" name="leftmenu" value="home">';
print '<label for="snapshot_date">'.$langs->trans('AISnapshotDate').'</label> ';
print '<input type="date" id="snapshot_date" name="snapshot_date" value="'.dol_escape_htmltag($snapshotDate).'">';
print '<button type="submit" class="button">'.$langs->trans('Refresh').'</button>';
print '</form>';
if ($snapshotDate !== '') {
	print '<div class="ai-dashboard-date-note">'.$langs->trans('AISnapshot').' '.dol_escape_htmltag($snapshotDate).'</div>';
}
print '</div></div>';

if (!$hasOrderTable || !$hasInventoryTable) {
	print '<div class="ai-dashboard-notice warning">';
	print '<span class="fas fa-info-circle"></span> '.$langs->trans('AIDashboardTablesMissing');
	print '</div>';
}

print '<div class="ai-dashboard-summary">';
print '<div class="ai-dashboard-summary-card danger"><span class="fas fa-truck-loading"></span><div><strong>'.(int) $summary['order_risk_count'].'</strong><span>'.$langs->trans('AIRiskOrders').'</span></div></div>';
print '<div class="ai-dashboard-summary-card warning"><span class="fas fa-box-open"></span><div><strong>'.(int) $summary['shortage_count'].'</strong><span>'.$langs->trans('AIShortageInventory').'</span></div></div>';
print '<div class="ai-dashboard-summary-card neutral"><span class="fas fa-hourglass-half"></span><div><strong>'.(int) $summary['stagnant_count'].'</strong><span>'.$langs->trans('AIStagnantInventory').'</span></div></div>';
print '<div class="ai-dashboard-summary-card info"><span class="fas fa-chart-line"></span><div><strong>'.number_format((float) $summary['average_probability'], 1).'%</strong><span>'.$langs->trans('AIAverageDelayProbability').'</span></div></div>';
print '</div>';

print '<div class="ai-dashboard-grid">';
print '<section class="ai-dashboard-card ai-dashboard-orders">';
print '<div class="ai-dashboard-card-title"><div><h2><span class="fas fa-exclamation-triangle"></span> '.$langs->trans('AIRiskOrders').'</h2><p>'.$langs->trans('AITopRiskOrders').'</p></div><span class="ai-dashboard-count">'.count($orderRisks).'</span></div>';
if (empty($orderRisks)) {
	print '<div class="ai-dashboard-empty">'.$langs->trans('AINoDailyData').'</div>';
} else {
	print '<div class="ai-dashboard-table-wrap"><table class="liste ai-dashboard-table"><thead><tr>';
	print '<th>'.$langs->trans('Order').'</th><th>'.$langs->trans('ThirdParty').'</th><th>'.$langs->trans('AIRiskLevel').'</th><th>'.$langs->trans('AIDelayProbability').'</th><th>'.$langs->trans('AIEstimatedDelay').'</th><th>'.$langs->trans('AIRiskReason').'</th>';
	print '</tr></thead><tbody>';
	foreach ($orderRisks as $row) {
		$level = in_array($row->risk_level, array('high', 'medium', 'low'), true) ? $row->risk_level : 'low';
		print '<tr>';
		if ((int) $row->order_id > 0) {
			print '<td><a href="'.dol_buildpath('/commande/card.php?id='.(int) $row->order_id, 1).'">'.dol_escape_htmltag($row->order_ref).'</a></td>';
		} else {
			print '<td>'.dol_escape_htmltag($row->order_ref).'</td>';
		}
		print '<td>'.dol_escape_htmltag($row->customer_name).'</td>';
		print '<td><span class="ai-risk-badge '.$level.'">'.$langs->trans('AIRiskLevel'.ucfirst($level)).'</span></td>';
		print '<td class="ai-number">'.dol_escape_htmltag($row->delay_probability).'%</td>';
		print '<td class="ai-number">'.dol_escape_htmltag($row->expected_delay_days).' '.$langs->trans('Days').'</td>';
		print '<td class="ai-reason">'.dol_escape_htmltag($row->risk_reason).'</td>';
		print '</tr>';
	}
	print '</tbody></table></div>';
}
print '</section>';

print '<section class="ai-dashboard-card ai-dashboard-inventory">';
print '<div class="ai-dashboard-card-title"><div><h2><span class="fas fa-boxes"></span> '.$langs->trans('AIInventoryRisks').'</h2><p>'.$langs->trans('AIInventoryRiskDescription').'</p></div></div>';
print '<div class="ai-inventory-subtitle shortage"><span class="fas fa-bolt"></span> '.$langs->trans('AIShortageInventory').'</div>';
if (empty($shortageRisks)) {
	print '<div class="ai-dashboard-empty compact">'.$langs->trans('AINoDailyData').'</div>';
} else {
	foreach ($shortageRisks as $row) {
		print '<div class="ai-inventory-row"><div><strong>'.dol_escape_htmltag($row->product_ref).' '.dol_escape_htmltag($row->product_label).'</strong><small>'.dol_escape_htmltag($row->warehouse_ref).' · '.$langs->trans('AICurrentStock').' '.dol_escape_htmltag($row->current_stock).' · '.$langs->trans('AIAffectedOrders').' '.(int) $row->affected_order_count.'</small></div><span class="ai-risk-badge '.(in_array($row->risk_level, array('high', 'medium', 'low'), true) ? $row->risk_level : 'low').'">'.dol_escape_htmltag($row->days_to_stockout).' '.$langs->trans('AIDaysLeft').'</span></div>';
	}
}
print '<div class="ai-inventory-subtitle stagnant"><span class="fas fa-clock"></span> '.$langs->trans('AIStagnantInventory').'</div>';
if (empty($stagnantRisks)) {
	print '<div class="ai-dashboard-empty compact">'.$langs->trans('AINoDailyData').'</div>';
} else {
	foreach ($stagnantRisks as $row) {
		print '<div class="ai-inventory-row"><div><strong>'.dol_escape_htmltag($row->product_ref).' '.dol_escape_htmltag($row->product_label).'</strong><small>'.dol_escape_htmltag($row->warehouse_ref).' · '.$langs->trans('AICurrentStock').' '.dol_escape_htmltag($row->current_stock).' · '.$langs->trans('AILastMovement').' '.dol_escape_htmltag($row->last_movement_date).'</small></div><span class="ai-inventory-amount">'.number_format((float) $row->impact_amount, 2).'</span></div>';
	}
}
print '</section>';
print '</div>';

print '<section class="ai-dashboard-card ai-dashboard-qa">';
$hermesStatusClass = $hermes->isConfigured() ? 'configured' : 'unconfigured';
$hermesStatusText = $hermes->isConfigured() ? 'Hermes' : $langs->trans('AIHermesNotConfiguredShort');
print '<div class="ai-dashboard-card-title"><div><h2><span class="fas fa-comments"></span> '.$langs->trans('AIBusinessQA').'</h2><p>'.$langs->trans('AIAskHint').'</p></div><span class="ai-hermes-status '.$hermesStatusClass.'"><span class="fas fa-circle"></span> '.$hermesStatusText.'</span></div>';
print '<form method="POST" action="'.dol_escape_htmltag($_SERVER['PHP_SELF']).'">';
print '<input type="hidden" name="token" value="'.newToken().'">';
print '<input type="hidden" name="action" value="ask">';
print '<input type="hidden" name="mainmenu" value="home"><input type="hidden" name="leftmenu" value="home">';
print '<input type="hidden" name="snapshot_date" value="'.dol_escape_htmltag($snapshotDate).'">';
print '<div class="ai-qa-input"><textarea name="question" rows="3" maxlength="2000" placeholder="'.$langs->trans('AIAskPlaceholder').'">'.dol_escape_htmltag($question).'</textarea><button type="submit" class="button button-primary"><span class="fas fa-paper-plane"></span> '.$langs->trans('AIAskHermes').'</button></div>';
print '<div class="ai-qa-examples"><span>'.$langs->trans('AIExamples').'</span><button type="button" class="ai-example" data-question="'.$langs->trans('AIExampleQuestion1').'">'.$langs->trans('AIExampleQuestion1').'</button><button type="button" class="ai-example" data-question="'.$langs->trans('AIExampleQuestion2').'">'.$langs->trans('AIExampleQuestion2').'</button></div>';
print '</form>';
if ($answer !== '') {
	print '<div class="ai-answer"><div class="ai-answer-title"><span class="fas fa-robot"></span> Hermes '.$langs->trans('AIAnswer').'</div><div class="ai-answer-content">'.dol_htmlentitiesbr($answer).'</div></div>';
}
print '</section>';

print '</div>';
print '<script>
document.querySelectorAll(".ai-example").forEach(function (button) {
	button.addEventListener("click", function () {
		var textarea = document.querySelector(".ai-qa-input textarea");
		if (textarea) { textarea.value = button.getAttribute("data-question") || ""; textarea.focus(); }
	});
});
</script>';

llxFooter();
