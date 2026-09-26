variable "project_id" {
  description = "GCP project ID for the DHG CareTrack demo"
  type        = string
}

variable "region" {
  description = "Primary GCP region"
  type        = string
  default     = "asia-south1"
}

variable "dataset_id" {
  description = "BigQuery dataset ID for CareTrack data"
  type        = string
  default     = "dhg_caretrack"
}

variable "environment" {
  description = "Environment label, e.g. prod, dev"
  type        = string
  default     = "prod"
}

variable "labels" {
  description = "Common resource labels for cost tracking"
  type        = map(string)
  default = {
    project     = "dhg-caretrack"
    environment = "prod"
    managed_by  = "terraform"
  }
}

variable "template_gcs_path" {
  description = "GCS path to the built Dataflow Flex Template spec (pipeline/dataflow-beam)"
  type        = string
  default     = "gs://REPLACE_ME/templates/dhg-caretrack-pipeline.json"
}
