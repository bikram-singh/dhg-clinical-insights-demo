output "dns_zone_name_servers" {
  description = "Add these NS records for the subdomain at wherever gcpcloudhub.in is registered"
  value       = google_dns_managed_zone.portal.name_servers
}

output "load_balancer_ip" {
  value = google_compute_global_address.portal_ip.address
}

output "portal_url" {
  value = "https://${var.subdomain}"
}

output "ssl_certificate_status" {
  description = "Check this after DNS delegation - stays PROVISIONING until the domain resolves correctly"
  value       = google_compute_managed_ssl_certificate.portal.id
}
