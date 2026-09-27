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

variable "ingress" {
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  description = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER (locked to IAP) or INGRESS_TRAFFIC_ALL (temporary, for gcloud run services proxy access while DNS is unresolved)"
}
