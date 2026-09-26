# Clinician Portal - matches the "[Clinician Portal] - Cloud Run, behind
# IAP - patient list, vitals charts, risk insight" box in the architecture
# diagram.
#
# AUTH: real Identity-Aware Proxy, enabled via the separate
# terraform/modules/portal-edge module (DNS + Load Balancer + IAP +
# Cloud Armor). Ingress here is locked to load-balancer-only, so this
# Cloud Run service only accepts traffic that has already passed through
# IAP - it is not reachable directly via its own .run.app URL.

resource "google_service_account" "portal_runtime" {
  account_id   = "dhg-caretrack-portal"
  display_name = "DHG CareTrack Clinician Portal runtime identity"
  project      = var.project_id
}

resource "google_project_iam_member" "portal_bq_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.portal_runtime.email}"
}

resource "google_project_iam_member" "portal_bq_jobuser" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.portal_runtime.email}"
}

resource "google_cloud_run_v2_service" "portal" {
  name     = "dhg-caretrack-portal"
  location = var.region
  project  = var.project_id

  # Only traffic that has already passed through the LB + IAP stack
  # (terraform/modules/portal-edge) can reach this service.
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = google_service_account.portal_runtime.email

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
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
  }
}

# Kept for direct CLI/debugging access (e.g. gcloud run services proxy);
# with ingress now locked to load-balancer-only, browser access goes
# through the IAP-protected domain instead, set up in portal-edge.
resource "google_cloud_run_v2_service_iam_member" "clinician_can_invoke" {
  for_each = toset(var.clinician_emails)

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.portal.name
  role     = "roles/run.invoker"
  member   = "user:${each.value}"
}

