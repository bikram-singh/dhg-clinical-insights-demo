terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  # Configure your HCP Terraform / GCS backend here, matching your
  # existing gcp-hcp-terraform workspace pattern.
  # backend "remote" { ... }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "pubsub" {
  source     = "../../modules/pubsub"
  project_id = var.project_id
  labels     = var.labels
}

module "bigquery" {
  source     = "../../modules/bigquery"
  project_id = var.project_id
  dataset_id = var.dataset_id
  region     = var.region
  labels     = var.labels
}

module "healthcare_api" {
  source      = "../../modules/healthcare-api"
  project_id  = var.project_id
  region      = var.region
  dataset_id  = var.dataset_id
  bq_dataset  = module.bigquery.dataset_id
  labels      = var.labels
}

module "dataflow" {
  source              = "../../modules/dataflow"
  project_id          = var.project_id
  region              = var.region
  input_topic         = module.pubsub.raw_telemetry_topic_id
  input_subscription  = module.pubsub.raw_telemetry_subscription_id
  bq_dataset          = module.bigquery.dataset_id
  fhir_store_id       = module.healthcare_api.fhir_store_id
  template_gcs_path   = var.template_gcs_path
  labels              = var.labels

  depends_on = [module.pubsub, module.healthcare_api, module.bigquery]
}
