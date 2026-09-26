variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "input_topic" {
  type = string
}

variable "input_subscription" {
  type = string
}

variable "bq_dataset" {
  type        = string
  description = "BigQuery dataset ID the pipeline writes observations/diagnostic_reports into"
}

variable "fhir_store_id" {
  type = string
}

variable "template_gcs_path" {
  type        = string
  description = "GCS path to the built Flex Template spec (see main.tf header for the gcloud build steps to produce this)"
  default     = "gs://REPLACE_ME/templates/dhg-caretrack-pipeline.json"
}

variable "network_self_link" {
  type        = string
  description = "Self-link of the VPC network Dataflow workers run in (this project has no default network)"
}

variable "subnetwork_self_link" {
  type        = string
  description = "Self-link of the subnet Dataflow workers run in"
}

variable "worker_zone" {
  type        = string
  description = "Explicit zone for Dataflow workers, e.g. asia-south1-a. Leave empty to let Dataflow pick within the region (default). Set this if a specific zone reports ZONE_RESOURCE_POOL_EXHAUSTED."
  default     = ""
}

variable "labels" {
  type    = map(string)
  default = {}
}
