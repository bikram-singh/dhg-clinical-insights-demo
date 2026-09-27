# Column-level security for sensitive free-text fields - matches the
# "Dataplex column-level security tags on sensitive fields" line in the
# architecture diagram. Implemented via a Data Catalog taxonomy + policy
# tag (the underlying mechanism BigQuery column-level security uses,
# managed through Dataplex/Data Catalog).
#
# Anyone querying a tagged column without roles/datacatalog.
# categoryFineGrainedReader on this policy tag gets a permission error
# from BigQuery - the column is genuinely inaccessible to them, not just
# hidden in a UI.

resource "google_data_catalog_taxonomy" "sensitive" {
  provider               = google-beta
  project                = var.project_id
  region                 = var.region
  display_name           = "dhg-caretrack-sensitive-data"
  description            = "Classification for sensitive free-text fields in DHG CareTrack (synthetic data demo)"
  activated_policy_types = ["FINE_GRAINED_ACCESS_CONTROL"]
}

resource "google_data_catalog_policy_tag" "sensitive_free_text" {
  provider     = google-beta
  taxonomy     = google_data_catalog_taxonomy.sensitive.id
  display_name = "Sensitive Free Text"
  description  = "Free-text fields that may contain narrative or quasi-identifying content (diagnostic notes, risk explanations)"
}

resource "google_data_catalog_policy_tag_iam_member" "fine_grained_readers" {
  for_each = toset(var.reader_members)

  provider  = google-beta
  policy_tag = google_data_catalog_policy_tag.sensitive_free_text.name
  role      = "roles/datacatalog.categoryFineGrainedReader"
  member    = each.value
}
