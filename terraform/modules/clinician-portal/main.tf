# Clinician Portal - matches the "[Clinician Portal] - Cloud Run, behind
# IAP - patient list, vitals charts, risk insight" box in the architecture
# diagram.
#
# AUTH: real Identity-Aware Proxy, enabled via the separate
# terraform/modules/portal-edge module (DNS + Load Balancer + IAP +
# Cloud Armor). var.ingress controls how locked-down this is:
#   - "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" (the real end state): only
#     traffic that has already passed through IAP can reach this service;
#     gcloud run services proxy stops working, since that bypasses the LB.
#   - "INGRESS_TRAFFIC_ALL" (temporary): reopens direct/proxy access,
#     useful while the custom domain's DNS delegation is still being
#     sorted out. Switch back to LB-only once the real domain path works.

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

  ingress = var.ingress

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
# only usable while var.ingress = "INGRESS_TRAFFIC_ALL". Once locked to
# load-balancer-only, browser access goes through the IAP-protected
# domain instead, set up in portal-edge.
resource "google_cloud_run_v2_service_iam_member" "clinician_can_invoke" {
  for_each = toset(var.clinician_emails)

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.portal.name
  role     = "roles/run.invoker"
  member   = "user:${each.value}"
}

