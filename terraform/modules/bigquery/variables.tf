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
