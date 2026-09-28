resource "google_bigquery_dataset" "caretrack" {
  dataset_id                      = var.dataset_id
  project                         = var.project_id
  location                        = var.region
  labels                          = var.labels
  default_partition_expiration_ms = null

  # CMEK - only applies to NEW tables created after this is set, not the
  # 4 existing populated tables (BigQuery doesn't retroactively
  # re-encrypt). See docs/known-deviations.md.
  dynamic "default_encryption_configuration" {
    for_each = var.kms_key_name != "" ? [1] : []
    content {
      kms_key_name = var.kms_key_name
    }
  }
}

resource "google_bigquery_table" "patients" {
  dataset_id = google_bigquery_dataset.caretrack.dataset_id
  project    = var.project_id
  table_id   = "patients"
  labels     = var.labels

  schema = file("${path.module}/schemas/patients.json")
}

resource "google_bigquery_table" "observations" {
  dataset_id = google_bigquery_dataset.caretrack.dataset_id
  project    = var.project_id
  table_id   = "observations"
  labels     = var.labels

  time_partitioning {
    type  = "DAY"
    field = "event_timestamp"
  }
  clustering = ["patient_id"]

  schema = file("${path.module}/schemas/observations.json")
}

resource "google_bigquery_table" "diagnostic_reports" {
  dataset_id = google_bigquery_dataset.caretrack.dataset_id
  project    = var.project_id
  table_id   = "diagnostic_reports"
  labels     = var.labels

  schema = templatefile("${path.module}/schemas/diagnostic_reports.json.tpl", {
    policy_tag_name = var.sensitive_policy_tag_name
  })
}

resource "google_bigquery_table" "risk_assessments" {
  dataset_id = google_bigquery_dataset.caretrack.dataset_id
  project    = var.project_id
  table_id   = "risk_assessments"
  labels     = var.labels

  schema = templatefile("${path.module}/schemas/risk_assessments.json.tpl", {
    policy_tag_name = var.sensitive_policy_tag_name
  })
}

# Data Access audit logging is enabled at the project level via the
# audit-logging module, not per-dataset here.
