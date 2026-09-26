# Scheduled Cloud Run Job that runs the synthetic telemetry generator
# (generator/main.py) on a recurring schedule via Cloud Scheduler, matching
# the "[Synthetic Data Generator] (Cloud Run job, scheduled)" box in the
# original architecture diagram - previously run only as a manual script.

resource "google_artifact_registry_repository" "apps" {
  repository_id = "apps"
  location      = var.region
  project       = var.project_id
  format        = "DOCKER"
  description   = "Application images for scheduled Cloud Run jobs (generator, etc.)"
}

# Dedicated, minimal-privilege identity the generator job runs as - only
# needs to publish to the one Pub/Sub topic, nothing else.
resource "google_service_account" "generator_runtime" {
  account_id   = "dhg-caretrack-generator"
  display_name = "DHG CareTrack generator Cloud Run Job runtime identity"
  project      = var.project_id
}

resource "google_project_iam_member" "generator_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.generator_runtime.email}"
}

resource "google_cloud_run_v2_job" "generator" {
  name     = "dhg-caretrack-generator"
  location = var.region
  project  = var.project_id

  template {
    template {
      service_account = google_service_account.generator_runtime.email
      max_retries      = 1
      timeout          = "300s"

      containers {
        image = var.image
        args = [
          "--project-id", var.project_id,
          "--topic", var.topic_name,
          "--count", tostring(var.events_per_run),
        ]
      }
    }
  }
}

# Separate identity for Cloud Scheduler to invoke the job - distinct from
# the job's own runtime identity, so the "who can trigger this" permission
# is separate from "what this job is allowed to do once running".
resource "google_service_account" "scheduler_invoker" {
  account_id   = "dhg-caretrack-gen-invoker"
  display_name = "Cloud Scheduler invoker for the DHG CareTrack generator job"
  project      = var.project_id
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_can_invoke" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.generator.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_invoker.email}"
}

resource "google_cloud_scheduler_job" "generator_schedule" {
  name        = "dhg-caretrack-generator-schedule"
  description = "Runs the DHG CareTrack synthetic telemetry generator on a recurring schedule"
  project     = var.project_id
  region      = var.region
  schedule    = var.schedule_cron
  time_zone   = var.schedule_timezone

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_number}/jobs/${google_cloud_run_v2_job.generator.name}:run"

    oauth_token {
      service_account_email = google_service_account.scheduler_invoker.email
    }
  }

  depends_on = [google_cloud_run_v2_job_iam_member.scheduler_can_invoke]
}
