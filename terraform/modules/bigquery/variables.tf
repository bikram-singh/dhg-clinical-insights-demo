variable "project_id" {
  type = string
}

variable "dataset_id" {
  type = string
}

variable "region" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "sensitive_policy_tag_name" {
  type        = string
  description = "Full Data Catalog policy tag resource name applied to sensitive free-text columns (report_text_redacted, gemini_explanation)"
}
