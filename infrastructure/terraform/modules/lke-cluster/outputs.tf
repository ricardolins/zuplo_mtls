output "cluster_id" {
  value = linode_lke_cluster.main.id
}

output "node_instance_ids" {
  description = "Linode instance IDs for all LKE nodes — used to attach the firewall"
  value = flatten([
    for pool in linode_lke_cluster.main.pool : [
      for node in pool.nodes : node.instance_id
    ]
  ])
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
