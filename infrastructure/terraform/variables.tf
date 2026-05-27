variable "linode_token" {
  description = "Linode API access token"
  type        = string
  sensitive   = true
}

variable "allowed_ip" {
  description = "Your public IP — ONLY this IP can access the cluster API, ingress and all services"
  type        = string
  # Set in terraform.tfvars — do not hardcode here
}

variable "region" {
  description = "Linode region for the LKE cluster"
  type        = string
  default     = "br-gru"
}

variable "cluster_name" {
  description = "LKE cluster name"
  type        = string
  default     = "mtls-baas"
}

variable "kubernetes_version" {
  description = "Kubernetes version on LKE"
  type        = string
  default     = "1.34"
}

variable "pki_node_count" {
  description = "Number of nodes in the PKI pool"
  type        = number
  default     = 1
}

variable "app_node_count" {
  description = "Number of nodes in the application pool"
  type        = number
  default     = 1
}

variable "monitoring_node_count" {
  description = "Number of nodes in the monitoring pool"
  type        = number
  default     = 1
}

variable "pki_node_type" {
  description = "Instance type for PKI nodes"
  type        = string
  default     = "g6-standard-2"
}

variable "app_node_type" {
  description = "Instance type for application nodes"
  type        = string
  default     = "g6-standard-2"
}

variable "monitoring_node_type" {
  description = "Instance type for monitoring nodes"
  type        = string
  default     = "g6-standard-1"
}

variable "tags" {
  description = "Tags for all Linode resources"
  type        = list(string)
  default     = ["mtls-baas", "dev"]
}

variable "cert_service_domain" {
  description = "Public domain for the Certificate Service API (e.g. certs.yourdomain.com)"
  type        = string
  # Set in terraform.tfvars
}

variable "base_domain" {
  description = "Base domain for all services (e.g. yourdomain.com)"
  type        = string
  # Set in terraform.tfvars
}

variable "high_availability" {
  description = "Enable LKE HA control plane"
  type        = bool
  default     = false
}
