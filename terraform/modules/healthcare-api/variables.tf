variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "dataset_id" {
  type        = string
  description = "Logical dataset name label, distinct from bq_dataset"
}

variable "bq_dataset" {
  type        = string
  description = "BigQuery dataset ID that the FHIR store streams analytics exports into"
}

variable "pipeline_service_account" {
  type        = string
  description = "Service account email used by the fhir-ingestion pipeline component"
  default     = ""
}

variable "labels" {
  type    = map(string)
  default = {}
}
