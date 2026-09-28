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

# Locked to the load balancer: all browser traffic goes through the
# IAP + Cloud Armor path on dhg-caretrack.gcpcloudhub.in. The direct
# Cloud Run URL and `gcloud run services proxy` no longer reach the
# portal. To temporarily reopen direct access for debugging, set this to
# "INGRESS_TRAFFIC_ALL" and apply - and set it back afterwards.
portal_ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
partner_api_image = "us-central1-docker.pkg.dev/dhg-caretrack/apps/partner-api:latest"
risk_processor_image = "us-central1-docker.pkg.dev/dhg-caretrack/apps/risk-processor:latest"
alerting_image = "us-central1-docker.pkg.dev/dhg-caretrack/apps/alerting:latest"
alert_from_email = "bikram23march@gmail.com"
notification_email = "bikram23march@gmail.com"
