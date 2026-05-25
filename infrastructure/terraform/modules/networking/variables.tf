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
