variable "project_id" {
  type = string
}

variable "services" {
  type        = list(string)
  default     = ["bigquery.googleapis.com", "healthcare.googleapis.com", "dlp.googleapis.com"]
  description = "Services to enable Data Access (DATA_READ + DATA_WRITE) audit logging for"
}
