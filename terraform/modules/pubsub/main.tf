resource "google_pubsub_topic" "raw_telemetry" {
  name    = "patient-telemetry-raw"
  project = var.project_id
  labels  = var.labels
}

resource "google_pubsub_topic" "dead_letter" {
  name    = "patient-telemetry-deadletter"
  project = var.project_id
  labels  = var.labels
}

resource "google_pubsub_subscription" "raw_telemetry_sub" {
  name    = "patient-telemetry-raw-sub"
  topic   = google_pubsub_topic.raw_telemetry.id
  project = var.project_id
  labels  = var.labels

  ack_deadline_seconds = 30

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  expiration_policy {
    ttl = "" # never expires
  }
}

resource "google_pubsub_subscription" "dead_letter_sub" {
  name    = "patient-telemetry-deadletter-sub"
  topic   = google_pubsub_topic.dead_letter.id
  project = var.project_id
  labels  = var.labels
}
