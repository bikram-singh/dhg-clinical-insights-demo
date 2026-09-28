# Looker Studio dashboard

An analytics dashboard over the same BigQuery data the Clinician Portal
uses, aimed at a *population* view (all patients, trends, pipeline health)
rather than the portal's per-patient drill-down. **Synthetic data only.**

The dashboard itself is built in the Looker Studio UI - there is no
Terraform resource for a Looker Studio report. What *is* in code is
everything it reads from: three BigQuery views in
[`terraform/modules/bigquery/views.tf`](../terraform/modules/bigquery/views.tf).

## Data sources

| View | Grain | Used for |
|---|---|---|
| `dashboard_patient_snapshot` | one row per patient | overview: latest vitals, latest risk, minutes since last reading |
| `dashboard_vitals_timeseries` | one row per reading, last 7 days | vitals trends, ingestion volume |
| `dashboard_risk_history` | one row per assessment | risk over time, assessments per hour |

## Governance decisions

- **The views never select the policy-tagged columns**
  (`gemini_explanation`, `report_text_redacted`). Column-level security is
  enforced by BigQuery for whoever's credentials run the query. A Looker
  Studio data source on the *owner's* credentials would let every viewer
  read whatever the owner can, silently bypassing the policy tag - so the
  protection is built into what the views expose instead of relying on who
  the viewer is.
- Columns are listed explicitly (no `SELECT *`) so a future tagged column
  cannot leak into a dashboard by accident.
- **The report must be owned by an identity with BigQuery access**, i.e. the
  organization account. The personal Gmail used for alert emails cannot be
  granted BigQuery access, because the organization's Domain Restricted
  Sharing policy blocks IAM grants to external identities.
- Whether an "anyone with the link" report is possible depends on the
  domain's Looker Studio sharing settings in the Workspace Admin console;
  if external sharing is off, share within the organization or publish
  screenshots instead.
- The older `sql/views/clinician_dashboard_view.sql` is superseded and not
  used (it reads the always-empty `patients` table and exposes
  `gemini_explanation`).

## Pages

1. **Overview** (`dashboard_patient_snapshot`) - scorecards for patients
   monitored, high-risk patients now, average heart rate and SpO2, and
   minutes since the latest reading; a patient table with risk level and
   score; a risk-level distribution chart.
2. **Vitals trends** (`dashboard_vitals_timeseries`) - patient and date
   controls; heart rate, SpO2, blood pressure and temperature over time.
3. **Risk over time** (`dashboard_risk_history`) - average risk score per
   hour, assessments per hour by level, and a patient-by-time heatmap.
4. **Pipeline health** (`dashboard_vitals_timeseries`,
   `dashboard_risk_history`) - readings per 15 minutes (the generator's
   cadence), freshest reading, assessments per hour.

Data freshness on every data source is set to 15 minutes to match the
generator's cadence; Looker Studio's default would leave the charts up to
12 hours stale.

## Rebuilding the report

The report is not in Terraform, so this is the recipe to recreate it.

**1. Open a new report with the three data sources attached** (Looker
Studio "Linking API"). Use an incognito window signed in only as the
organization account, otherwise the link may open under the wrong Google
account and the BigQuery connection is refused:

```
https://lookerstudio.google.com/reporting/create?c.mode=edit&r.reportName=DHG%20CareTrack%20-%20Clinical%20Insights&ds.ds0.connector=bigQuery&ds.ds0.datasourceName=dashboard_patient_snapshot&ds.ds0.projectId=dhg-caretrack&ds.ds0.type=TABLE&ds.ds0.datasetId=dhg_caretrack&ds.ds0.tableId=dashboard_patient_snapshot&ds.ds1.connector=bigQuery&ds.ds1.datasourceName=dashboard_vitals_timeseries&ds.ds1.projectId=dhg-caretrack&ds.ds1.type=TABLE&ds.ds1.datasetId=dhg_caretrack&ds.ds1.tableId=dashboard_vitals_timeseries&ds.ds2.connector=bigQuery&ds.ds2.datasourceName=dashboard_risk_history&ds.ds2.projectId=dhg-caretrack&ds.ds2.type=TABLE&ds.ds2.datasetId=dhg_caretrack&ds.ds2.tableId=dashboard_risk_history
```

If only the first source attaches, add the other two by hand
(Resource > Manage added data sources > Add a data source > BigQuery).

**2. On each data source**, set Data freshness to 15 minutes and leave the
data credentials on the owner's.

**3. Calculated field** on `dashboard_patient_snapshot`, named `BP`:
`CONCAT(CAST(ROUND(bp_systolic, 0) AS TEXT), "/", CAST(ROUND(bp_diastolic, 0) AS TEXT))`

**4. Colors** (same as the portal and the alert email): high `#c0392b`,
medium `#d68910`, low `#1e8449`.

**5. Charts**

| Page | Chart | Source | Dimension | Metric | Notes |
|---|---|---|---|---|---|
| Overview | Scorecard: patients monitored | snapshot | - | patient_id, Count Distinct | |
| Overview | Scorecard: high-risk now | snapshot | - | Record Count | filter risk_level = high |
| Overview | Scorecards: avg heart rate, avg SpO2 | snapshot | - | heart_rate Avg; spo2 Avg | |
| Overview | Scorecard: newest reading age (min) | snapshot | - | minutes_since_last_reading MIN | healthy if about 20 or less |
| Overview | Table | snapshot | patient_id, risk_level, BP | ml_risk_score, heart_rate, spo2, last_reading_at | sort by score desc; color risk_level |
| Overview | Donut | snapshot | risk_level | Record Count | slice colors as above |
| Vitals trends | Controls | timeseries | patient_id drop-down; date range | - | date range dimension: event_timestamp |
| Vitals trends | Time series x4 | timeseries | event_timestamp | heart_rate; spo2; bp_systolic + bp_diastolic; body_temp_c | reference lines at 100 bpm, 94 %, 145 mmHg (the risk-label thresholds) |
| Risk over time | Time series | risk_history | assessed_at (Date Hour) | ml_risk_score Avg | |
| Risk over time | Stacked columns | risk_history | assessed_at (Date Hour) | Record Count | breakdown: risk_level |
| Risk over time | Pivot heatmap | risk_history | rows: patient_id; columns: assessed_at (Date Hour) | ml_risk_score Avg | heatmap style |
| Pipeline health | Column chart | timeseries | event_timestamp (Date Hour Minute) | Record Count | bursts every 15 minutes = the generator schedule |
| Pipeline health | Column chart | risk_history | assessed_at (Date Hour) | Record Count | assessments per hour |

**6. Every page:** a "SYNTHETIC DATA - demonstration only" banner. Right-click
it and choose "Make report-level" so it appears on all pages at once.

## Known limitations

- The dashboard shows whatever the synthetic data does. Because the
  rule-derived risk label flags any of three thresholds, most patients
  score as high risk, which makes the risk charts look flatter and more
  alarming than a realistic population would.
- A "SYNTHETIC DATA - demonstration only" banner is added to every page,
  matching the portal.

## Link

_Add the report URL here once published._
