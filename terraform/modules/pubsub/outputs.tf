output "raw_telemetry_topic_id" {
  value = google_pubsub_topic.raw_telemetry.id
}

output "raw_telemetry_subscription_id" {
  value = google_pubsub_subscription.raw_telemetry_sub.id
}

output "dead_letter_topic_id" {
  value = google_pubsub_topic.dead_letter.id
}
