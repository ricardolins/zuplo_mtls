variable "linode_token" {
  description = "Token de acesso à API do Linode"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Região do Linode para o cluster LKE"
  type        = string
  default     = "us-east"
}

variable "cluster_name" {
  description = "Nome do cluster LKE"
  type        = string
  default     = "mtls-baas-prod"
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes no LKE"
  type        = string
  default     = "1.29"
}

variable "pki_node_count" {
  description = "Número de nós no pool PKI"
  type        = number
  default     = 2
}

variable "app_node_count" {
  description = "Número de nós no pool de aplicação"
  type        = number
  default     = 3
}

variable "monitoring_node_count" {
  description = "Número de nós no pool de monitoramento"
  type        = number
  default     = 1
}

variable "pki_node_type" {
  description = "Tipo de instância para nós PKI (dedicado para operações criptográficas)"
  type        = string
  default     = "g6-dedicated-2"
}

variable "app_node_type" {
  description = "Tipo de instância para nós de aplicação"
  type        = string
  default     = "g6-standard-4"
}

variable "monitoring_node_type" {
  description = "Tipo de instância para nós de monitoramento"
  type        = string
  default     = "g6-standard-2"
}

variable "tags" {
  description = "Tags para todos os recursos Linode"
  type        = list(string)
  default     = ["mtls-baas", "production", "pki"]
}

variable "cert_service_domain" {
  description = "Domínio público do Certificate Service API"
  type        = string
  default     = "certs.baas.io"
}

variable "high_availability" {
  description = "Habilitar control plane HA do LKE"
  type        = bool
  default     = true
}
