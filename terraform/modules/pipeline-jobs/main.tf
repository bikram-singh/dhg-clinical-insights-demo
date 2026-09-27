# Automates the two pipeline stages that previously had to be run by hand:
# BigQuery ML + Gemini risk scoring, and the alerting email. Matches the
# same pattern as cloud-run-generator (Cloud Run Job + Cloud Scheduler),
# staggered a few minutes after the generator's own schedule so each stage
# has fresh upstream data to work from.
#
# See docs/known-deviations.md for why this isn't true event-driven
# chaining (e.g. Pub/Sub/Eventarc triggering the next job on completion) -
# it's cron-staggered instead, which is simpler but means each stage waits
# out a fixed offset rather than reacting immediately.

# ---------------------------------------------------------------------
# Risk Insight Processor (BigQuery ML + Gemini)
# ---------------------------------------------------------------------

resource "google_service_account" "risk_processor_runtime" {
  account_id   = "dhg-caretrack-riskproc"
  display_name = "DHG CareTrack risk-insight-processor runtime identity"
  project      = var.project_id
}

resource "google_project_iam_member" "risk_processor_bq_dataeditor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.risk_processor_runtime.email}"
}

resource "google_project_iam_member" "risk_processor_bq_jobuser" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.risk_processor_runtime.email}"
}

resource "google_project_iam_member" "risk_processor_aiplatform" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.risk_processor_runtime.email}"
}

resource "google_cloud_run_v2_job" "risk_processor" {
  name     = "dhg-caretrack-risk-processor"
  location = var.region
  project  = var.project_id

  template {
    template {
      service_account = google_service_account.risk_processor_runtime.email
      max_retries     = 1
      timeout         = "540s"

      containers {
        image = var.risk_processor_image
        args = [
          "--project-id", var.project_id,
          "--bq-dataset", var.bq_dataset,
        ]
      }
    }
  }
}

resource "google_service_account" "risk_processor_invoker" {
  account_id   = "dhg-caretrack-riskproc-inv"
  display_name = "Cloud Scheduler invoker for the risk-insight-processor job"
  project      = var.project_id
}

resource "google_cloud_run_v2_job_iam_member" "risk_processor_scheduler_can_invoke" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.risk_processor.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.risk_processor_invoker.email}"
}

resource "google_cloud_scheduler_job" "risk_processor_schedule" {
  name        = "dhg-caretrack-risk-processor-schedule"
  description = "Runs BigQuery ML scoring + Gemini risk explanation on a recurring schedule"
  project     = var.project_id
  region      = var.region
  schedule    = var.risk_processor_schedule_cron
  time_zone   = var.schedule_timezone

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_number}/jobs/${google_cloud_run_v2_job.risk_processor.name}:run"

    oauth_token {
      service_account_email = google_service_account.risk_processor_invoker.email
    }
  }

  depends_on = [google_cloud_run_v2_job_iam_member.risk_processor_scheduler_can_invoke]
}

# ---------------------------------------------------------------------
# Alerting (Gmail API email on high risk)
# ---------------------------------------------------------------------

# Placeholder secret only - Terraform never has the real OAuth token
# value. Populate it manually once, from a machine that already has a
# working alerting/token.json (see docs/known-deviations.md for the
# Testing-mode refresh-token-expiry caveat this doesn't remove):
#   gcloud secrets versions add alerting-oauth-token \
#     --data-file=alerting/token.json --project=dhg-caretrack
resource "google_secret_manager_secret" "alerting_oauth_token" {
  project   = var.project_id
  secret_id = "alerting-oauth-token"

  replication {
    auto {}
  }
}

resource "google_service_account" "alerting_runtime" {
  account_id   = "dhg-caretrack-alerting"
  display_name = "DHG CareTrack alerting runtime identity"
  project      = var.project_id
}

resource "google_project_iam_member" "alerting_bq_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.alerting_runtime.email}"
}

resource "google_project_iam_member" "alerting_bq_jobuser" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.alerting_runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "alerting_token_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.alerting_oauth_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.alerting_runtime.email}"
}

resource "google_cloud_run_v2_job" "alerting" {
  name     = "dhg-caretrack-alerting"
  location = var.region
  project  = var.project_id

  template {
    template {
      service_account = google_service_account.alerting_runtime.email
      max_retries     = 1
      timeout         = "300s"

      containers {
        image = var.alerting_image
        args = [
          "--project-id", var.project_id,
          "--bq-dataset", var.bq_dataset,
          "--from-email", var.alert_from_email,
          "--to-email", var.alert_to_email,
          "--lookback-hours", tostring(var.alerting_lookback_hours),
        ]
        env {
          name  = "TOKEN_SECRET_NAME"
          value = "${google_secret_manager_secret.alerting_oauth_token.id}/versions/latest"
        }
      }
    }
  }
}

resource "google_service_account" "alerting_invoker" {
  account_id   = "dhg-caretrack-alerting-inv"
  display_name = "Cloud Scheduler invoker for the alerting job"
  project      = var.project_id
}

resource "google_cloud_run_v2_job_iam_member" "alerting_scheduler_can_invoke" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.alerting.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.alerting_invoker.email}"
}

resource "google_cloud_scheduler_job" "alerting_schedule" {
  name        = "dhg-caretrack-alerting-schedule"
  description = "Emails the clinician on high-risk assessments, on a recurring schedule"
  project     = var.project_id
  region      = var.region
  schedule    = var.alerting_schedule_cron
  time_zone   = var.schedule_timezone

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_number}/jobs/${google_cloud_run_v2_job.alerting.name}:run"

    oauth_token {
      service_account_email = google_service_account.alerting_invoker.email
    }
  }

  depends_on = [google_cloud_run_v2_job_iam_member.alerting_scheduler_can_invoke]
}
