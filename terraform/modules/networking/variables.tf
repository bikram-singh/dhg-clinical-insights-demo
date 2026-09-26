variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "dataflow_region" {
  type        = string
  description = "Region for the Dataflow-specific subnet (kept separate from the main region since asia-south1 hit capacity issues)"
  default     = "us-central1"
}
