output "raw_telemetry_topic_id" {
  value = module.pubsub.raw_telemetry_topic_id
}

output "bigquery_dataset_id" {
  value = module.bigquery.dataset_id
}

output "fhir_store_id" {
  value = module.healthcare_api.fhir_store_id
}

output "dataflow_job_name" {
  value = module.dataflow.job_name
}
