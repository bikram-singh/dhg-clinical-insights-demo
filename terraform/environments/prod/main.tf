terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  # Shared state backend - both your local machine and GitHub Actions CI
  # read/write the SAME state here, instead of each having their own
  # private local state (which is what caused CI to try creating all 87
  # resources from scratch the first time it ran).
  backend "gcs" {
    bucket = "dhg-caretrack-tfstate"
    prefix = "prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# google_dataflow_flex_template_job is beta-only in the provider.
provider "google-beta" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {
  project_id = var.project_id
}

module "pubsub" {
  source     = "../../modules/pubsub"
  project_id = var.project_id
  labels     = var.labels
}

module "data_governance" {
  source     = "../../modules/data-governance"
  project_id = var.project_id
  region     = var.region
  reader_members = [
    "user:${var.clinician_emails[0]}",
    "serviceAccount:dhg-caretrack-portal@${var.project_id}.iam.gserviceaccount.com",
    "serviceAccount:dhg-caretrack-riskproc@${var.project_id}.iam.gserviceaccount.com",
    "serviceAccount:dhg-caretrack-alerting@${var.project_id}.iam.gserviceaccount.com",
  ]
}

module "audit_logging" {
  source     = "../../modules/audit-logging"
  project_id = var.project_id
}

module "bigquery" {
  source                    = "../../modules/bigquery"
  project_id                = var.project_id
  dataset_id                = var.dataset_id
  region                    = var.region
  labels                    = var.labels
  sensitive_policy_tag_name = module.data_governance.policy_tag_name
}

module "healthcare_api" {
  source      = "../../modules/healthcare-api"
  project_id  = var.project_id
  region      = var.region
  dataset_id  = var.dataset_id
  bq_dataset  = module.bigquery.dataset_id
  labels      = var.labels
}

module "networking" {
  source          = "../../modules/networking"
  project_id      = var.project_id
  region          = var.region
  dataflow_region = var.dataflow_region
}

module "dataflow" {
  source                = "../../modules/dataflow"
  project_id            = var.project_id
  region                = var.dataflow_region
  input_topic           = module.pubsub.raw_telemetry_topic_id
  input_subscription    = module.pubsub.raw_telemetry_subscription_id
  bq_dataset            = module.bigquery.dataset_id
  fhir_store_id         = module.healthcare_api.fhir_store_id
  template_gcs_path     = var.template_gcs_path
  network_self_link     = module.networking.network_self_link
  subnetwork_self_link  = module.networking.dataflow_subnetwork_self_link
  worker_zone           = var.worker_zone
  labels                = var.labels

  depends_on = [module.pubsub, module.healthcare_api, module.bigquery, module.networking]
}

module "cloud_run_generator" {
  source          = "../../modules/cloud-run-generator"
  project_id      = var.project_id
  project_number  = data.google_project.current.number
  region          = var.dataflow_region
  image           = var.generator_image
  topic_name      = "patient-telemetry-raw"
  events_per_run  = var.generator_events_per_run
  schedule_cron   = var.generator_schedule_cron

  depends_on = [module.pubsub]
}

module "clinician_portal" {
  source           = "../../modules/clinician-portal"
  project_id       = var.project_id
  region           = var.dataflow_region
  image            = var.portal_image
  bq_dataset       = module.bigquery.dataset_id
  clinician_emails = var.clinician_emails
  ingress          = var.portal_ingress

  depends_on = [module.bigquery]
}

module "portal_edge" {
  source                  = "../../modules/portal-edge"
  project_id              = var.project_id
  project_number          = data.google_project.current.number
  region                  = var.dataflow_region
  subdomain               = var.portal_subdomain
  cloud_run_service_name  = module.clinician_portal.service_name
  iap_oauth_client_id     = var.iap_oauth_client_id
  iap_oauth_client_secret = var.iap_oauth_client_secret
  clinician_email         = var.clinician_emails[0]

  depends_on = [module.clinician_portal]
}

module "partner_api" {
  source           = "../../modules/partner-api"
  project_id       = var.project_id
  region           = var.dataflow_region
  image            = var.partner_api_image
  bq_dataset       = module.bigquery.dataset_id
  clinician_emails = var.clinician_emails

  depends_on = [module.bigquery]
}

module "pipeline_jobs" {
  source                = "../../modules/pipeline-jobs"
  project_id            = var.project_id
  project_number        = data.google_project.current.number
  region                = var.dataflow_region
  bq_dataset            = module.bigquery.dataset_id
  risk_processor_image  = var.risk_processor_image
  alerting_image        = var.alerting_image
  alert_from_email      = var.alert_from_email
  alert_to_email        = var.clinician_emails[0]

  depends_on = [module.bigquery]
}

module "github_actions_wif" {
  source      = "../../modules/github-actions-wif"
  project_id  = var.project_id
  github_repo = var.github_repo
}
