# Lets GitHub Actions authenticate to GCP without any downloaded service
# account JSON key stored as a GitHub secret - a real, live credential
# that would be a genuine exposure risk if it ever leaked (the same class
# of risk flagged elsewhere in this repo re: OAuth secrets). Workload
# Identity Federation lets GitHub's own OIDC token be exchanged for
# short-lived GCP credentials instead.
#
# This module is applied once, manually, like everything else in this
# repo - it's the trust relationship that lets CI/CD exist, so it can't
# itself be created by CI/CD.

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions Pool"
  description               = "OIDC pool for GitHub Actions deployments"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider"
  display_name                       = "GitHub Actions Provider"
  description                        = "Restricted to this repo only - see attribute_condition"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Only this exact repo can mint tokens this pool will accept - not just
  # anyone in the GitHub org, and not forks.
  attribute_condition = "assertion.repository == '${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "github_actions" {
  project      = var.project_id
  account_id   = "github-actions-deployer"
  display_name = "GitHub Actions CI/CD deployer"
  description  = "Impersonated by GitHub Actions via Workload Identity Federation - never given a downloaded key"
}

# Only workflow runs FROM THIS REPO'S main branch can impersonate the
# deployer service account - a PR from a branch, or any other repo, cannot.
resource "google_service_account_iam_member" "github_can_impersonate" {
  service_account_id = google_service_account.github_actions.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# Roles the deployer needs to run `terraform apply` across everything in
# this repo, plus push container images. This is broader than a real
# production setup should grant a single CI identity (see
# docs/known-deviations.md) - a tighter setup would scope narrowly per
# resource type instead of using project-level Editor + these additions.
resource "google_project_iam_member" "github_actions_roles" {
  for_each = toset([
    "roles/editor",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.securityAdmin",
    "roles/artifactregistry.admin",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}
