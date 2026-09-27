output "risk_processor_job_name" {
  value = google_cloud_run_v2_job.risk_processor.name
}

output "alerting_job_name" {
  value = google_cloud_run_v2_job.alerting.name
}

output "alerting_token_secret_id" {
  description = "Populate this manually: gcloud secrets versions add alerting-oauth-token --data-file=alerting/token.json"
  value       = google_secret_manager_secret.alerting_oauth_token.secret_id
}
