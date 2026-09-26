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

variable "worker_zone" {
  description = "Explicit zone for Dataflow workers (e.g. asia-south1-a). Empty = let Dataflow pick within region."
  type        = string
  default     = ""
}

variable "dataflow_region" {
  description = "Region for Dataflow compute specifically, separate from var.region, since asia-south1 hit capacity issues across all 3 zones"
  type        = string
  default     = "us-central1"
}

variable "generator_image" {
  description = "Full Artifact Registry image path for the scheduled generator Cloud Run Job"
  type        = string
  default     = "us-central1-docker.pkg.dev/REPLACE_ME/apps/generator:latest"
}

variable "generator_events_per_run" {
  description = "Number of synthetic events the scheduled generator publishes per run"
  type        = number
  default     = 20
}

variable "generator_schedule_cron" {
  description = "Cron schedule for the generator Cloud Run Job"
  type        = string
  default     = "*/15 * * * *"
}

variable "portal_image" {
  description = "Full Artifact Registry image path for the clinician portal container"
  type        = string
  default     = "us-central1-docker.pkg.dev/REPLACE_ME/apps/portal:latest"
}

variable "clinician_emails" {
  description = "Google account emails allowed to invoke the clinician portal"
  type        = list(string)
}
