output "cluster_id" {
  description = "ID do cluster LKE"
  value       = module.lke_cluster.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint da API do Kubernetes"
  value       = module.lke_cluster.endpoint
  sensitive   = true
}

output "kubeconfig_path" {
  description = "Caminho para o arquivo kubeconfig gerado"
  value       = "${path.module}/../../.kubeconfig-lke"
}

output "nodebalancer_ip" {
  description = "IP publico do NodeBalancer (Linode LB)"
  value       = module.networking.nodebalancer_ip
}

output "cert_service_url" {
  description = "URL publica do Certificate Service"
  value       = "https://${var.cert_service_domain}"
}
