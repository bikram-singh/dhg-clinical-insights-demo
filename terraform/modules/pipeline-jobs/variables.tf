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

variable "bq_dataset" {
  type = string
}

variable "risk_processor_image" {
  type        = string
  description = "Full Artifact Registry image path for the risk-insight-processor container"
}

variable "alerting_image" {
  type        = string
  description = "Full Artifact Registry image path for the alerting container"
}

variable "alert_from_email" {
  type        = string
  description = "Sending Gmail address (must match the OAuth-authorized account)"
}

variable "alert_to_email" {
  type        = string
  description = "Clinician inbox to notify"
}

variable "alerting_lookback_hours" {
  type    = number
  default = 1
}

variable "risk_processor_schedule_cron" {
  type        = string
  default     = "5,20,35,50 * * * *"
  description = "5 minutes after each generator run (generator runs at :00,:15,:30,:45)"
}

variable "alerting_schedule_cron" {
  type        = string
  default     = "10,25,40,55 * * * *"
  description = "5 minutes after each risk-processor run"
}

variable "schedule_timezone" {
  type    = string
  default = "Asia/Kolkata"
}
