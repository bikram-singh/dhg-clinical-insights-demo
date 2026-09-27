variable "project_id" {
  type = string
}

variable "github_repo" {
  type        = string
  description = "GitHub repo in owner/name form, e.g. bikram-singh/dhg-clinical-insights-demo - only this exact repo can authenticate"
}
