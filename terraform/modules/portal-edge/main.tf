# DNS + external HTTPS Load Balancer + IAP + Cloud Armor in front of the
# clinician portal Cloud Run service, on a real subdomain of gcpcloudhub.in.
#
# This is the "real IAP" upgrade over the simpler Cloud Run IAM-only
# access used before: real Google-branded sign-in, real HTTPS via a
# managed certificate, and a Cloud Armor WAF policy (rate limiting).
#
# MANUAL PREREQUISITE: the IAP OAuth client (Web application type) must
# be created via the console first - Terraform does not manage OAuth
# brand/client creation here, since a brand already exists for this
# project (created earlier for Gmail API access) and brand creation is
# a one-time, largely irreversible per-project operation not safe to
# re-attempt via Terraform. Pass the resulting client ID/secret in as
# variables.
#
# MANUAL STEP AFTER APPLY: this creates a new Cloud DNS zone scoped to
# just the "dhg-caretrack.gcpcloudhub.in" subdomain. Take the zone's NS
# records (see the dns_zone_name_servers output) and add them as NS
# records for this subdomain at wherever gcpcloudhub.in is currently
# registered/managed. The managed SSL certificate will not finish
# provisioning until that DNS delegation is live and has propagated.

resource "google_dns_managed_zone" "portal" {
  name        = "dhg-caretrack-portal-zone"
  project     = var.project_id
  dns_name    = "${var.subdomain}."
  description = "Delegated subdomain for the DHG CareTrack clinician portal"
}

resource "google_compute_global_address" "portal_ip" {
  name    = "dhg-caretrack-portal-ip"
  project = var.project_id
}

resource "google_dns_record_set" "portal_a" {
  name         = "${var.subdomain}."
  project      = var.project_id
  managed_zone = google_dns_managed_zone.portal.name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.portal_ip.address]
}

resource "google_compute_region_network_endpoint_group" "portal_neg" {
  name                  = "dhg-caretrack-portal-neg"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.cloud_run_service_name
  }
}

resource "google_compute_security_policy" "portal_armor" {
  name    = "dhg-caretrack-portal-armor"
  project = var.project_id

  # Required baseline default rule.
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }

  # Basic rate limiting: more than 100 requests/minute per IP gets a
  # temporary ban, to protect against abuse.
  rule {
    action   = "rate_based_ban"
    priority = 1000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      ban_duration_sec = 600
    }
    description = "Rate limit: 100 req/min per IP, 10 min ban if exceeded"
  }
}

resource "google_compute_backend_service" "portal" {
  name                  = "dhg-caretrack-portal-backend"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = google_compute_security_policy.portal_armor.id

  backend {
    group = google_compute_region_network_endpoint_group.portal_neg.id
  }

  iap {
    oauth2_client_id     = var.iap_oauth_client_id
    oauth2_client_secret = var.iap_oauth_client_secret
  }
}

resource "random_id" "cert_suffix" {
  byte_length = 4
}

resource "google_compute_managed_ssl_certificate" "portal" {
  name    = "dhg-caretrack-portal-cert-${random_id.cert_suffix.hex}"
  project = var.project_id

  managed {
    domains = [var.subdomain]
  }

  # Without this, replacing the cert (e.g. after a DNS fix requires a
  # fresh validation attempt) fails: GCP won't let Terraform delete a
  # cert that's still attached to the HTTPS proxy below. This makes
  # Terraform create the new cert and repoint the proxy first, then
  # delete the old cert last. The random_id suffix in the name is
  # required alongside this, since GCP won't allow two certs with the
  # same name to exist even momentarily during the swap - to force a
  # fresh validation attempt later, taint both this resource and
  # random_id.cert_suffix together.
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_url_map" "portal" {
  name            = "dhg-caretrack-portal-urlmap"
  project         = var.project_id
  default_service = google_compute_backend_service.portal.id
}

resource "google_compute_target_https_proxy" "portal" {
  name             = "dhg-caretrack-portal-https-proxy"
  project          = var.project_id
  url_map          = google_compute_url_map.portal.id
  ssl_certificates = [google_compute_managed_ssl_certificate.portal.id]
}

resource "google_compute_global_forwarding_rule" "portal" {
  name                  = "dhg-caretrack-portal-fr"
  project               = var.project_id
  target                = google_compute_target_https_proxy.portal.id
  port_range            = "443"
  ip_address            = google_compute_global_address.portal_ip.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# IAP itself needs permission to invoke the Cloud Run service, once a
# user has been authenticated. The IAP service agent identity is only
# provisioned on first real use, so we force its creation explicitly
# rather than assuming it already exists.
resource "google_project_service_identity" "iap_sa" {
  provider = google-beta
  project  = var.project_id
  service  = "iap.googleapis.com"
}

resource "google_cloud_run_v2_service_iam_member" "iap_can_invoke" {
  project  = var.project_id
  location = var.region
  name     = var.cloud_run_service_name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_project_service_identity.iap_sa.email}"

  depends_on = [google_project_service_identity.iap_sa]
}

# Grants the clinician permission to pass through IAP's sign-in check
# for this specific backend service.
resource "google_iap_web_backend_service_iam_member" "clinician_iap_access" {
  project              = var.project_id
  web_backend_service  = google_compute_backend_service.portal.name
  role                 = "roles/iap.httpsResourceAccessor"
  member               = "user:${var.clinician_email}"
}
