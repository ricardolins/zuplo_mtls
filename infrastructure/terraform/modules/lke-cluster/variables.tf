variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "high_availability" {
  type    = bool
  default = true
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "pki_node_type" {
  type = string
}

variable "pki_node_count" {
  type = number
}

variable "app_node_type" {
  type = string
}

variable "app_node_count" {
  type = number
}

variable "monitoring_node_type" {
  type = string
}

variable "monitoring_node_count" {
  type = number
}
