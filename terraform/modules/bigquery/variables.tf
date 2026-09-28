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

variable "kms_key_name" {
  type        = string
  default     = ""
  description = "CMEK key for the dataset's default encryption config. Empty string = use Google-managed encryption (the default). Only affects tables created after this is set."
}
