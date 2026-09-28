output "crypto_key_id" {
  value = google_kms_crypto_key.main.id

  # Anything consuming this key for BigQuery CMEK must wait until the
  # BigQuery encryption service account has actually been granted access,
  # otherwise the dataset update races the IAM grant and fails with a 403.
  depends_on = [google_kms_crypto_key_iam_member.bigquery_encrypter]
}
