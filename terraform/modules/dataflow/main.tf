# Uses Google's provided "Pub/Sub to Healthcare API FHIR" Dataflow template
# for now, as an infra-first placeholder. Replace with a custom template if
# validation/enrichment logic beyond FHIR-mapping is needed.
resource "google_dataflow_flex_template_job" "telemetry_to_fhir" {
  provider                = google
  name                    = "patient-telemetry-to-fhir"
  project                 = var.project_id
  region                  = var.region
  container_spec_gcs_path = var.template_gcs_path

  parameters = {
    inputSubscription = var.input_subscription
    fhirStore         = var.fhir_store_id
  }

  on_delete = "cancel"
}
