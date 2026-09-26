output "dataset_id" {
  value = google_healthcare_dataset.caretrack.id
}

output "fhir_store_id" {
  value = google_healthcare_fhir_store.caretrack_fhir.id
}
