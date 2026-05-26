output "nodebalancer_ip" {
  description = "NodeBalancer IP (available after Ingress NGINX deployment)"
  value       = "pending-after-ingress-deploy"
}

output "firewall_id" {
  description = "Linode Firewall ID — pass to root module for linode_firewall_device"
  value       = linode_firewall.cluster_fw.id
}
