output "workload_identity_provider" {
  description = "Set as workload_identity_provider in the GitHub Actions auth step"
  value       = "projects/${var.project_id}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
}

output "service_account_email" {
  description = "Set as service_account in the GitHub Actions auth step"
  value       = google_service_account.github_actions.email
}
