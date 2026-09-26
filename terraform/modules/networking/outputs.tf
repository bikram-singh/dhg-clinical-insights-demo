output "network_self_link" {
  value = google_compute_network.vpc.self_link
}

output "subnetwork_self_link" {
  value = google_compute_subnetwork.subnet.self_link
}

output "dataflow_subnetwork_self_link" {
  value = google_compute_subnetwork.dataflow_subnet.self_link
}
