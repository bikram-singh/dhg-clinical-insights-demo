variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "image" {
  type        = string
  description = "Full Artifact Registry image path for the portal container"
}

variable "bq_dataset" {
  type = string
}

variable "clinician_emails" {
  type        = list(string)
  description = "Google account emails allowed to invoke (view) the portal"
}
