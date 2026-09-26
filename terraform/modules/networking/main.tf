# Minimal VPC for the DHG CareTrack demo. This project has no default
# network (org policy compute.skipDefaultNetworkCreation is enabled on the
# gcpcloudhub.in FAST landing zone), so Dataflow, Cloud Run, and anything
# else network-dependent needs an explicit network + subnet.

resource "google_compute_network" "vpc" {
  name                    = "dhg-caretrack-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name                     = "dhg-caretrack-subnet"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.10.0.0/24"
  private_ip_google_access = true
}

# Second subnet in a larger, more reliably-stocked region for Dataflow
# specifically - asia-south1 (Mumbai) repeatedly hit ZONE_RESOURCE_POOL_EXHAUSTED
# across all 3 of its zones. BigQuery, Healthcare API, and Pub/Sub stay in
# asia-south1; only the Dataflow job's compute runs here.
resource "google_compute_subnetwork" "dataflow_subnet" {
  name                     = "dhg-caretrack-dataflow-subnet"
  project                  = var.project_id
  region                   = var.dataflow_region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.20.0.0/24"
  private_ip_google_access = true
}

# Dataflow workers need to talk to each other on all ports within the subnet.
resource "google_compute_firewall" "allow_internal" {
  name    = "dhg-caretrack-allow-internal"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.10.0.0/24", "10.20.0.0/24"]
}

# Allows Google's health-check ranges to reach workers (used by some
# managed services; harmless to include even if not strictly required
# by Dataflow itself).
resource "google_compute_firewall" "allow_health_checks" {
  name    = "dhg-caretrack-allow-health-checks"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
}
