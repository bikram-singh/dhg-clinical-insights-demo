variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "reader_members" {
  type        = list(string)
  description = "IAM members (e.g. user:x@y.com, serviceAccount:a@b.iam.gserviceaccount.com) granted Fine-Grained Reader on the sensitive-data policy tag"
}
