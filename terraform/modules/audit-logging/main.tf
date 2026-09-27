# Cloud Audit Logs (Data Access) - matches the "Cloud Audit Logs (Data
# Access) enabled" line in the architecture diagram. Data Access logs
# (DATA_READ + DATA_WRITE) are off by default in GCP because of their
# volume/cost; this turns them on for the three services in this
# architecture that actually touch patient-adjacent data.

resource "google_project_iam_audit_config" "data_access" {
  for_each = toset(var.services)

  project = var.project_id
  service = each.value

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}
