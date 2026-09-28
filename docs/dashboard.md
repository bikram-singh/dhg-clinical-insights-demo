# Analytics dashboard

The Clinician Portal's `/analytics` page is the project's dashboard: a
*population* view across all patients, next to the portal's per-patient
drill-down. **Synthetic data only.**

It is defined entirely in code (`portal/backend/main.py` and
`portal/backend/templates/analytics.html`), deployed by the same pipeline as
the rest of the portal, and reachable only through the load balancer (IAP +
Cloud Armor), so it is private by design.

## What it shows

- **KPI cards:** patients monitored, high risk now, high-risk assessments in
  the last 24 hours, average heart rate, average SpO2, and how many minutes
  ago the newest reading arrived.
- **Charts:** risk level split (latest assessment per patient); average vitals
  by hour (24 h); risk assessments per hour by level (24 h); readings ingested
  per 15 minutes (6 h), where a steady bar per 15 minutes shows the generator
  and pipeline running without gaps.
- **Patient table,** highest risk first, with blood pressure, heart rate,
  SpO2 and last reading; each patient links to their detail page.
- **"updating" marker.** A risk badge marked "updating" means the assessment
  was computed before that patient's newest reading arrived (the scorer runs a
  few minutes after each ingest), so the vitals and the risk shown can briefly
  disagree.

## Data sources

Three BigQuery views, defined in
[`terraform/modules/bigquery/views.tf`](../terraform/modules/bigquery/views.tf):

| View | Grain | Used for |
|---|---|---|
| `dashboard_patient_snapshot` | one row per patient | KPI cards, patient table, risk split |
| `dashboard_vitals_timeseries` | one row per reading, last 7 days | vitals by hour, ingestion cadence |
| `dashboard_risk_history` | one row per assessment | assessments per hour, 24 h high-risk count |

## Governance decisions

- **The views never select the policy-tagged columns** (`gemini_explanation`,
  `report_text_redacted`), and every column is listed explicitly (no
  `SELECT *`), so a future tagged column cannot leak into the dashboard by
  accident. The page itself runs as the portal's service account, which is
  cleared for those columns (the patient detail page needs them), so the
  protection here is by construction: the analytics queries touch only these
  views.
- The views are built only on the Terraform-managed tables, not on the older
  hand-created `observations_wide` / `latest_risk_scores` views, so they can be
  reproduced from this repo alone.
- The older `sql/views/clinician_dashboard_view.sql` is superseded and not
  used: it reads the always-empty `patients` table and exposes
  `gemini_explanation`.
- Query results are cached in the portal for 60 seconds, and the page
  refreshes itself every 5 minutes.

## Why not Looker Studio

A Looker Studio dashboard was in the original design and was started (a
report with the three data sources connected). It was dropped because a
Looker Studio report cannot be defined in code: there is no Terraform
resource, its API cannot create charts, and its Linking API only copies an
existing report. Building it meant clicking every chart together by hand, with
nothing to review or reproduce. The views were written to be BI-tool-agnostic,
so a BI tool can still be pointed at them later. See
[known-deviations.md](known-deviations.md).

## Known limitations

- **Private.** There is no public link to share; use screenshots.
- **The risk mix is modest.** Roughly 10-20% of assessments come out high (the
  rule-derived label fires when any of three thresholds is crossed), so at any
  moment the snapshot can show zero or a few high-risk patients. The
  assessments-per-hour chart shows the share over time.
- **Scores are effectively binary** (0.00 or 1.00) and no "medium" assessment
  appears; see the AI/ML section of [known-deviations.md](known-deviations.md).
- **Partial edge buckets.** The first and last hourly bars cover partial hours,
  so they look shorter.
- **Tested with faked data.** The page's rendering and calculations were tested
  against faked BigQuery results; the SQL itself only runs against real
  BigQuery.
