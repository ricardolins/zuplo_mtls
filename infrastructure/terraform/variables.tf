variable "linode_token" {
  description = "Linode API access token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Linode region for the LKE cluster"
  type        = string
  default     = "us-east"
}

variable "cluster_name" {
  description = "LKE cluster name"
  type        = string
  default     = "mtls-baas-prod"
}

variable "kubernetes_version" {
  description = "Kubernetes version on LKE"
  type        = string
  default     = "1.29"
}

variable "pki_node_count" {
  description = "Number of nodes in the PKI pool"
  type        = number
  default     = 2
}

variable "app_node_count" {
  description = "Number of nodes in the application pool"
  type        = number
  default     = 3
}

variable "monitoring_node_count" {
  description = "Number of nodes in the monitoring pool"
  type        = number
  default     = 1
}

variable "pki_node_type" {
  description = "Instance type for PKI nodes (dedicated for cryptographic operations)"
  type        = string
  default     = "g6-dedicated-2"
}

variable "app_node_type" {
  description = "Instance type for application nodes"
  type        = string
  default     = "g6-standard-4"
}

variable "monitoring_node_type" {
  description = "Instance type for monitoring nodes"
  type        = string
  default     = "g6-standard-2"
}

variable "tags" {
  description = "Tags for all Linode resources"
  type        = list(string)
  default     = ["mtls-baas", "production", "pki"]
}

variable "cert_service_domain" {
  description = "Public domain for the Certificate Service API"
  type        = string
  default     = "certs.baas.io"
}

variable "high_availability" {
  description = "Enable LKE HA control plane"
  type        = bool
  default     = true
}
