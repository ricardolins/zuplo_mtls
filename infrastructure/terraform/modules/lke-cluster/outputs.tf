output "cluster_id" {
  value = linode_lke_cluster.main.id
}

output "endpoint" {
  value     = linode_lke_cluster.main.api_endpoints[0]
  sensitive = true
}

output "kubeconfig" {
  value     = linode_lke_cluster.main.kubeconfig
  sensitive = true
}

output "ca_certificate" {
  value     = linode_lke_cluster.main.kubeconfig
  sensitive = true
}

output "service_account_token" {
  value     = linode_lke_cluster.main.kubeconfig
  sensitive = true
}
