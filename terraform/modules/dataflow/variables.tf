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

variable "fhir_store_id" {
  type = string
}

variable "template_gcs_path" {
  type        = string
  description = "GCS path to the Dataflow flex template spec. Placeholder - set once template is built/chosen."
  default     = "gs://REPLACE_ME/templates/patient-telemetry-to-fhir.json"
}

variable "labels" {
  type    = map(string)
  default = {}
}
