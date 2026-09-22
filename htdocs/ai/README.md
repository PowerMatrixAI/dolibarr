# AI FOR [DOLIBARR ERP CRM](https://www.dolibarr.org)

## Features

Provides AI (Artificial Intelligence) features in different part of the application. Need external AI API. 

## Licenses

### Main code

GPLv3 or (at your option) any later version. See file COPYING for more information.

### Documentation

All texts and readmes are licensed under GFDL.
# AI dashboard and Hermes integration

The AI dashboard is available from the Home left menu after the AI module is
enabled and its menu entries are refreshed. It reads daily facts from the
following tables:

- `llx_ai_dashboard_order_risk_daily`: one row per order and snapshot date.
- `llx_ai_dashboard_inventory_risk_daily`: shortage and stagnant inventory rows.
- `llx_ai_dashboard_run`: optional audit rows for Hermes scheduled runs.

Run `outputs/dolibarr-ai-dashboard.sql` once in the target MySQL database. This
file creates the AI-owned tables only; it intentionally does not insert fake AI
results. For the demo source data, review and execute
`outputs/dolibarr-ai-demo-seed-large.sql`. That script writes only Dolibarr
business tables and uses relative dates, so it provides current-looking
historical orders, purchases, stock movements and a small number of anomalies.
Hermes must read that source data, infer the risks, and then replace or upsert
the rows for each `(entity, snapshot_date)` while setting `source_run_id` when
a run record exists.

The complete workflow, including configuration discovery and the boundary
between source data and Hermes output, is documented in
`skills/dolibarr-database/references/hermes-config-and-demo-source.md` and
`skills/dolibarr-database/references/hermes-operations.md`.

## Hermes configuration

Add the following variables to the Dolibarr `conf.php` file. Keep real API
keys out of the repository. The endpoint can be a full OpenAI-compatible
`/v1/chat/completions` URL, or a base URL; the client appends the standard path
when it is missing.

```php
$dolibarr_hermes_endpoint = 'http://127.0.0.1:8000/v1/chat/completions';
$dolibarr_hermes_api_key = '';
$dolibarr_hermes_model = 'hermes';
$dolibarr_hermes_timeout = 120;
$dolibarr_hermes_system_prompt = '';
```

If Hermes runs on a private or local address, configure Dolibarr's existing
`$dolibarr_ai_allow_local_endpoints` setting according to the endpoint policy.
The dashboard sends the question and only the currently displayed snapshot
context to Hermes. Answers are rendered as escaped plain text.

These `dolibarr_hermes_*` variables configure the dashboard's interactive
question-and-answer endpoint. They are separate from the `DB_HOST`, `DB_NAME`,
`DB_USER`, `DB_PASSWORD`, entity, timezone and schedule settings used by the
Hermes job that reads ERP tables and writes AI facts. Never put database
passwords or API keys in this repository, the demo SQL files, or the skill.
