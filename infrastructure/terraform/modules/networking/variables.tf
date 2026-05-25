variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "allowed_ip" {
  description = "Only this IP is allowed inbound access to all services"
  type        = string
}
