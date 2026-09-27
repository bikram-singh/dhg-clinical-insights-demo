output "service_name" {
  value = google_cloud_run_v2_service.partner_api.name
}

output "service_uri" {
  value = google_cloud_run_v2_service.partner_api.uri
}

output "api_key_secret_id" {
  description = "Secret Manager secret ID holding the API key - retrieve with: gcloud secrets versions access latest --secret=partner-api-key"
  value       = google_secret_manager_secret.partner_api_key.secret_id
}
