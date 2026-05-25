output "cluster_id" {
  description = "LKE cluster ID"
  value       = module.lke_cluster.cluster_id
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.lke_cluster.endpoint
  sensitive   = true
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig file"
  value       = "${path.module}/../../.kubeconfig-lke"
}

output "nodebalancer_ip" {
  description = "Public IP of the NodeBalancer (Linode LB)"
  value       = module.networking.nodebalancer_ip
}

output "cert_service_url" {
  description = "Public URL of the Certificate Service"
  value       = "https://${var.cert_service_domain}"
}
