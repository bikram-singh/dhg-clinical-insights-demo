# Runs our CUSTOM Apache Beam pipeline (pipeline/dataflow-beam/pipeline.py),
# not a Google-provided template. No Google-provided template writes
# directly to a Healthcare API FHIR store, and Beam's FhirIO connector is
# Java/Go only, so we built our own Flex Template.
#
# NOTE ON REGION: this job runs in var.region (us-central1 by default),
# separate from the project's primary region (asia-south1), because
# asia-south1 repeatedly hit ZONE_RESOURCE_POOL_EXHAUSTED across all 3 of
# its zones. BigQuery, Healthcare API, and Pub/Sub stay in asia-south1;
# only the Dataflow worker compute runs here. Cross-region writes to
# BigQuery/Healthcare API from Dataflow are fully supported.
#
# Prerequisite (Terraform cannot build/push container images):
#   cd pipeline/dataflow-beam
#   gcloud builds submit --tag us-docker.pkg.dev/PROJECT/dataflow/caretrack-pipeline:latest .
#   gcloud dataflow flex-template build ${var.template_gcs_path} \
#     --image us-docker.pkg.dev/PROJECT/dataflow/caretrack-pipeline:latest \
#     --sdk-language PYTHON \
#     --metadata-file metadata.json
#
# Only after that GCS template spec exists will `terraform apply` for this
# module succeed.
resource "google_dataflow_flex_template_job" "telemetry_pipeline" {
  provider                = google-beta
  name                    = "dhg-caretrack-telemetry-pipeline-v7"
  project                 = var.project_id
  region                  = var.region
  container_spec_gcs_path = var.template_gcs_path
  network                 = var.network_self_link
  subnetwork              = var.subnetwork_self_link
  ip_configuration        = "WORKER_IP_PRIVATE"

  parameters = merge(
    {
      input_subscription = var.input_subscription
      bq_dataset          = var.bq_dataset
      fhir_store          = var.fhir_store_id
    },
    var.worker_zone != "" ? { worker_zone = var.worker_zone } : {}
  )

  on_delete = "cancel"
}
