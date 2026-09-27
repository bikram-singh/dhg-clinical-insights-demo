project_id = "dhg-caretrack"
region     = "asia-south1"
dataset_id = "dhg_caretrack"
template_gcs_path = "gs://dhg-caretrack-dataflow-templates/templates/dhg-caretrack-pipeline.json"
worker_zone = ""
dataflow_region = "us-central1"
generator_image = "us-central1-docker.pkg.dev/dhg-caretrack/apps/generator:latest"
generator_events_per_run = 20
generator_schedule_cron = "*/15 * * * *"
portal_image = "us-central1-docker.pkg.dev/dhg-caretrack/apps/portal:latest"
clinician_emails = ["admin@gcpcloudhub.in"]

# TEMPORARY: gcpcloudhub.in's root DNS is broken (SERVFAIL / FAILED_CAA_CHECKING),
# so the real IAP/domain path can't work yet. Reopening ingress lets
# `gcloud run services proxy` reach the portal directly in the meantime.
# Set back to "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" once the domain's
# DNS is actually fixed.
portal_ingress = "INGRESS_TRAFFIC_ALL"
