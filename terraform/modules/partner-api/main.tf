# Partner-Clinic API - matches the "[Partner-Clinic API] - Cloud Run,
# API-key auth - GET patient telemetry - OpenAPI spec published" box in
# the architecture diagram.
#
# The API key is generated here and stored in Secret Manager; the
# running service checks it at the application layer (see
# partner-api/backend/main.py). This project's Domain Restricted Sharing
# org policy blocks granting Cloud Run's own invoker role to allUsers,
# so this service is ALSO IAM-restricted to clinician_emails by default,
# same as the clinician portal - meaning it currently needs both an
# IAM-authenticated caller and a valid API key. See main.tf's header
# comment and docs/known-deviations.md for how to open this to allUsers
# if your org policy allows it.

resource "random_password" "partner_api_key" {
  length  = 40
  special = false
}

resource "google_secret_manager_secret" "partner_api_key" {
  project   = var.project_id
  secret_id = "partner-api-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "partner_api_key" {
  secret      = google_secret_manager_secret.partner_api_key.id
  secret_data = random_password.partner_api_key.result
}

resource "google_service_account" "partner_api_runtime" {
  account_id   = "dhg-caretrack-partner-api"
  display_name = "DHG CareTrack Partner-Clinic API runtime identity"
  project      = var.project_id
}

resource "google_project_iam_member" "partner_api_bq_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.partner_api_runtime.email}"
}

resource "google_project_iam_member" "partner_api_bq_jobuser" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.partner_api_runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "partner_api_secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.partner_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.partner_api_runtime.email}"
}

resource "google_cloud_run_v2_service" "partner_api" {
  name     = "dhg-caretrack-partner-api"
  location = var.region
  project  = var.project_id
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.partner_api_runtime.email

    containers {
      image = var.image
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "BQ_DATASET"
        value = var.bq_dataset
      }
      env {
        name  = "API_KEY_SECRET_NAME"
        value = "${google_secret_manager_secret.partner_api_key.id}/versions/latest"
      }
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "clinician_can_invoke" {
  for_each = toset(var.clinician_emails)

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.partner_api.name
  role     = "roles/run.invoker"
  member   = "user:${each.value}"
}
