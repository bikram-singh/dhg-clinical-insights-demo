variable "project_id" {
  type = string
}

variable "project_number" {
  type        = string
  description = "GCP project number (not ID) - required for the Cloud Scheduler v1 namespaces URI format"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "image" {
  type        = string
  description = "Full Artifact Registry image path for the generator container, e.g. us-central1-docker.pkg.dev/PROJECT/apps/generator:latest"
}

variable "topic_name" {
  type        = string
  description = "Pub/Sub topic name the generator publishes to"
}

variable "events_per_run" {
  type        = number
  default     = 20
  description = "Number of synthetic events to publish per scheduled run"
}

variable "schedule_cron" {
  type        = string
  default     = "*/15 * * * *"
  description = "Cron schedule for how often the generator runs (default: every 15 minutes)"
}

variable "schedule_timezone" {
  type    = string
  default = "Asia/Kolkata"
}
