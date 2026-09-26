variable "project_id" {
  type = string
}

variable "project_number" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "subdomain" {
  type        = string
  description = "Full subdomain the portal will be served on, e.g. dhg-caretrack.gcpcloudhub.in"
}

variable "cloud_run_service_name" {
  type        = string
  description = "Name of the clinician portal Cloud Run service"
}

variable "iap_oauth_client_id" {
  type        = string
  description = "OAuth client ID (Web application type) created manually in the console for IAP"
}

variable "iap_oauth_client_secret" {
  type        = string
  sensitive   = true
  description = "OAuth client secret paired with iap_oauth_client_id"
}

variable "clinician_email" {
  type        = string
  description = "Google account email allowed through IAP to access the portal"
}
