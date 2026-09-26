output "dataset_id" {
  value = google_bigquery_dataset.caretrack.dataset_id
}

output "patients_table_id" {
  value = google_bigquery_table.patients.table_id
}

output "observations_table_id" {
  value = google_bigquery_table.observations.table_id
}
