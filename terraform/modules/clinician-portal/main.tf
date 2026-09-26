# Clinician Portal - matches the "[Clinician Portal] - Cloud Run, behind
# IAP - patient list, vitals charts, risk insight" box in the architecture
# diagram.
#
# AUTH NOTE: deployed with no public invoker binding (Cloud Run's default
# deny-all), not full Identity-Aware Proxy. Real IAP needs an external
# HTTPS Load Balancer + reserved static IP + managed SSL cert tied to a
# real domain - out of scope for this demo. This gives the same practical
# protection (only IAM-authenticated identities can reach it); it just
# lacks IAP's branded consent screen. See docs/known-deviations.md.

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

  # Deny-all by default: no ingress restriction override needed since we
  # simply never grant roles/run.invoker to allUsers below.
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

# Grant only the named clinician account(s) permission to invoke this
# service - access it via:
#   gcloud run services proxy dhg-caretrack-portal --region=REGION
# which tunnels authenticated traffic to a local browser.
resource "google_cloud_run_v2_service_iam_member" "clinician_can_invoke" {
  for_each = toset(var.clinician_emails)

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.portal.name
  role     = "roles/run.invoker"
  member   = "user:${each.value}"
}
