output "job_name" {
  value = google_cloud_run_v2_job.generator.name
}

output "artifact_registry_repo" {
  value = google_artifact_registry_repository.apps.repository_id
}

output "scheduler_job_name" {
  value = google_cloud_scheduler_job.generator_schedule.name
}
