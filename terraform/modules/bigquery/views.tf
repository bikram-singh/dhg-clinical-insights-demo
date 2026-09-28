# Views that back the Looker Studio dashboard (see docs/dashboard.md).
#
# Design rules:
#  - Built ONLY on the Terraform-managed tables (observations,
#    risk_assessments), not on the older observations_wide /
#    latest_risk_scores views, which were created by hand and would make
#    these views impossible to reproduce from this repo alone.
#  - They deliberately never select the two policy-tagged columns
#    (risk_assessments.gemini_explanation, diagnostic_reports.
#    report_text_redacted). A dashboard shared beyond the people cleared
#    for those columns must not be able to read them, and a dashboard
#    running on the owner's credentials would otherwise bypass the
#    column-level security. Columns are listed explicitly (no SELECT *) so a
#    future tagged column can't leak in by accident.
#  - MAX(IF(...)) pivots collapse any duplicate rows from at-least-once
#    delivery, so readings are never double counted.

locals {
  obs_table  = "`${var.project_id}.${google_bigquery_dataset.caretrack.dataset_id}.observations`"
  risk_table = "`${var.project_id}.${google_bigquery_dataset.caretrack.dataset_id}.risk_assessments`"
}

# One row per patient reading (last 7 days), one column per vital.
resource "google_bigquery_table" "dashboard_vitals_timeseries" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.caretrack.dataset_id
  table_id            = "dashboard_vitals_timeseries"
  labels              = var.labels
  deletion_protection = false # a view holds no data and is fully rebuildable

  view {
    use_legacy_sql = false
    query          = <<-SQL
      SELECT
        patient_id,
        event_timestamp,
        MAX(IF(observation_type = 'heart_rate', value, NULL))   AS heart_rate,
        MAX(IF(observation_type = 'spo2', value, NULL))         AS spo2,
        MAX(IF(observation_type = 'bp_systolic', value, NULL))  AS bp_systolic,
        MAX(IF(observation_type = 'bp_diastolic', value, NULL)) AS bp_diastolic,
        MAX(IF(observation_type = 'body_temp_c', value, NULL))  AS body_temp_c,
        MAX(IF(observation_type = 'bmi', value, NULL))          AS bmi,
        MAX(IF(observation_type = 'steps', value, NULL))        AS steps,
        MAX(IF(observation_type = 'battery_pct', value, NULL))  AS battery_pct
      FROM ${local.obs_table}
      WHERE event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
      GROUP BY patient_id, event_timestamp
    SQL
  }

  depends_on = [google_bigquery_table.observations]
}

# Every risk assessment, WITHOUT the Gemini explanation text.
resource "google_bigquery_table" "dashboard_risk_history" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.caretrack.dataset_id
  table_id            = "dashboard_risk_history"
  labels              = var.labels
  deletion_protection = false

  view {
    use_legacy_sql = false
    query          = <<-SQL
      SELECT
        assessment_id,
        patient_id,
        created_at AS assessed_at,
        ml_risk_score,
        risk_level
      FROM ${local.risk_table}
    SQL
  }

  depends_on = [google_bigquery_table.risk_assessments]
}

# One row per patient: latest reading + latest risk assessment.
resource "google_bigquery_table" "dashboard_patient_snapshot" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.caretrack.dataset_id
  table_id            = "dashboard_patient_snapshot"
  labels              = var.labels
  deletion_protection = false

  view {
    use_legacy_sql = false
    query          = <<-SQL
      WITH latest_reading AS (
        SELECT patient_id, MAX(event_timestamp) AS last_reading_at
        FROM ${local.obs_table}
        WHERE event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
        GROUP BY patient_id
      ),
      vitals AS (
        SELECT
          o.patient_id,
          l.last_reading_at,
          MAX(IF(o.observation_type = 'heart_rate', o.value, NULL))   AS heart_rate,
          MAX(IF(o.observation_type = 'spo2', o.value, NULL))         AS spo2,
          MAX(IF(o.observation_type = 'bp_systolic', o.value, NULL))  AS bp_systolic,
          MAX(IF(o.observation_type = 'bp_diastolic', o.value, NULL)) AS bp_diastolic,
          MAX(IF(o.observation_type = 'body_temp_c', o.value, NULL))  AS body_temp_c,
          MAX(IF(o.observation_type = 'bmi', o.value, NULL))          AS bmi
        FROM ${local.obs_table} o
        JOIN latest_reading l
          ON o.patient_id = l.patient_id AND o.event_timestamp = l.last_reading_at
        WHERE o.event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
        GROUP BY o.patient_id, l.last_reading_at
      ),
      ranked_risk AS (
        SELECT
          patient_id,
          ml_risk_score,
          risk_level,
          created_at AS assessed_at,
          ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY created_at DESC) AS rn
        FROM ${local.risk_table}
      )
      SELECT
        v.patient_id,
        v.last_reading_at,
        TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), v.last_reading_at, MINUTE) AS minutes_since_last_reading,
        v.heart_rate,
        v.spo2,
        v.bp_systolic,
        v.bp_diastolic,
        v.body_temp_c,
        v.bmi,
        r.ml_risk_score,
        r.risk_level,
        r.assessed_at
      FROM vitals v
      LEFT JOIN ranked_risk r
        ON r.patient_id = v.patient_id AND r.rn = 1
    SQL
  }

  depends_on = [
    google_bigquery_table.observations,
    google_bigquery_table.risk_assessments,
  ]
}
