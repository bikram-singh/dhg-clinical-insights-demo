# Cloud Monitoring - matches the "observability" line from the original
# design. Scope: alert the clinician's inbox if any of the 3 scheduled
# Cloud Run Jobs (generator, risk-processor, alerting) log an ERROR or
# higher. Deliberately simple (log-based metric + threshold alert)
# rather than reaching for Dataflow-specific system metrics or uptime
# checks (the portal/partner-api are IAM-protected, so a standard
# anonymous uptime check against them would always fail and just be
# noise - not a real health signal).

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "DHG CareTrack alerts"
  type         = "email"

  labels = {
    email_address = var.notify_email
  }
}

resource "google_logging_metric" "job_errors" {
  project = var.project_id
  name    = "dhg-caretrack-job-errors"
  filter  = "resource.type=\"cloud_run_job\" AND severity>=ERROR"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "job_errors" {
  project      = var.project_id
  display_name = "DHG CareTrack - Cloud Run Job errors"
  combiner     = "OR"

  conditions {
    display_name = "ERROR+ log entries from any scheduled job"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.job_errors.name}\" AND resource.type=\"cloud_run_job\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "900s" # 15 min - matches the pipeline's own cadence
        per_series_aligner = "ALIGN_COUNT"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  documentation {
    content   = "One of the scheduled Cloud Run Jobs (generator, risk-processor, or alerting) logged an error. Check: gcloud logging read \"resource.type=cloud_run_job AND severity>=ERROR\" --project=${var.project_id} --limit=20"
    mime_type = "text/markdown"
  }
}
