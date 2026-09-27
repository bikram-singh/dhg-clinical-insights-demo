output "policy_tag_name" {
  description = "Full resource name of the sensitive-free-text policy tag, used in BigQuery column schemas' policyTags.names"
  value       = google_data_catalog_policy_tag.sensitive_free_text.name
}
