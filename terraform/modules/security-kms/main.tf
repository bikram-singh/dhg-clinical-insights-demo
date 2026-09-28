# Cloud KMS (CMEK) - matches the "encryption at rest" line from the
# original security design. Applied to the BigQuery dataset's default
# encryption config (affects NEW tables created after this point, not
# the 4 existing populated tables - BigQuery doesn't retroactively
# re-encrypt existing tables when a dataset's default key changes; that
# would require recreating each table).
#
# Deliberately NOT applied to the existing Pub/Sub topics - changing
# kms_key_name on an existing topic forces Terraform to destroy and
# recreate it, which would disrupt the live, actively-publishing
# generator and its subscriptions. The key below is ready to use for a
# fresh topic or a deliberate, carefully-timed topic recreation later.
# See docs/known-deviations.md.

resource "google_kms_key_ring" "main" {
  project  = var.project_id
  name     = "dhg-caretrack-keyring"
  location = var.region
}

resource "google_kms_crypto_key" "main" {
  name            = "dhg-caretrack-key"
  key_ring        = google_kms_key_ring.main.id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = false # relax for a demo project; a real prod key should protect this
  }
}

# BigQuery's CMEK service agent uses this documented, stable static
# address - it is a separate identity from BigQuery's general service
# agent, specific to encryption.
resource "google_kms_crypto_key_iam_member" "bigquery_encrypter" {
  crypto_key_id = google_kms_crypto_key.main.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:bq-${var.project_number}@bigquery-encryption.iam.gserviceaccount.com"
}

# Pub/Sub's service agent, granted access now so the key is ready
# whenever Pub/Sub CMEK is actually adopted (see header comment).
resource "google_project_service_identity" "pubsub_sa" {
  provider = google-beta
  project  = var.project_id
  service  = "pubsub.googleapis.com"
}

resource "google_kms_crypto_key_iam_member" "pubsub_encrypter" {
  crypto_key_id = google_kms_crypto_key.main.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.pubsub_sa.email}"
}
