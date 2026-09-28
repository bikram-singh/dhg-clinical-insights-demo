resource "google_healthcare_dataset" "caretrack" {
  name     = "dhg-caretrack-dataset"
  location = var.region
  project  = var.project_id
}

resource "google_healthcare_fhir_store" "caretrack_fhir" {
  name    = "dhg-caretrack-fhir-store"
  dataset = google_healthcare_dataset.caretrack.id
  version = "R4"

  enable_update_create = true
  disable_referential_integrity = false
  disable_resource_versioning   = false

  # Streams FHIR resource changes into BigQuery for analytics
  stream_configs {
    bigquery_destination {
      dataset_uri = "bq://${var.project_id}.${var.bq_dataset}"
      schema_config {
        schema_type               = "ANALYTICS"
        recursive_structure_depth = 2
      }
    }
  }
}

# NOTE: this grant is only created when var.pipeline_service_account is set,
# and nothing in this repo sets it - the Dataflow workers' FHIR access was
# granted by hand instead (no iam-security module exists). See
# docs/known-deviations.md.
resource "google_healthcare_dataset_iam_member" "fhir_writer" {
  count      = var.pipeline_service_account != "" ? 1 : 0
  dataset_id = google_healthcare_dataset.caretrack.id
  role       = "roles/healthcare.fhirResourceEditor"
  member     = "serviceAccount:${var.pipeline_service_account}"
}
