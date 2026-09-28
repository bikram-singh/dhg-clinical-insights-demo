variable "project_id" {
  type = string
}

variable "notify_email" {
  type        = string
  description = "Email address to notify on Cloud Run Job errors"
}
