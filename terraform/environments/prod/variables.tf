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

variable "portal_subdomain" {
  description = "Subdomain the portal is served on, e.g. dhg-caretrack.gcpcloudhub.in"
  type        = string
  default     = "dhg-caretrack.gcpcloudhub.in"
}

variable "portal_ingress" {
  description = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER (locked to IAP, the real end state) or INGRESS_TRAFFIC_ALL (temporary, for gcloud run services proxy access while gcpcloudhub.in's root DNS is broken)"
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
}

variable "iap_oauth_client_id" {
  description = "OAuth client ID (Web application type) created manually in the console for IAP"
  type        = string
}

variable "iap_oauth_client_secret" {
  description = "OAuth client secret paired with iap_oauth_client_id"
  type        = string
  sensitive   = true
}

variable "partner_api_image" {
  description = "Full Artifact Registry image path for the partner-clinic API container"
  type        = string
  default     = "us-central1-docker.pkg.dev/REPLACE_ME/apps/partner-api:latest"
}

variable "risk_processor_image" {
  description = "Full Artifact Registry image path for the risk-insight-processor container"
  type        = string
  default     = "us-central1-docker.pkg.dev/REPLACE_ME/apps/risk-processor:latest"
}

variable "alerting_image" {
  description = "Full Artifact Registry image path for the alerting container"
  type        = string
  default     = "us-central1-docker.pkg.dev/REPLACE_ME/apps/alerting:latest"
}

variable "notification_email" {
  description = "Mailbox that receives alert emails (high-risk alerts and Cloud Monitoring job-error alerts). Must be a real, mail-capable address. Deliberately separate from clinician_emails, which are Google sign-in identities for IAM/IAP and may have no mailbox at all."
  type        = string
}

variable "alert_from_email" {
  description = "Sending Gmail address for alerting (must match the OAuth-authorized account in alerting-oauth-token)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repo in owner/name form, e.g. bikram-singh/dhg-clinical-insights-demo"
  type        = string
  default     = "bikram-singh/dhg-clinical-insights-demo"
}
