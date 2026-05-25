resource "linode_firewall" "cluster_fw" {
  label = "${var.cluster_name}-firewall"
  tags  = var.tags

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "allow-https"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "allow-http-redirect"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "80"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # Internal CA port — cluster-only traffic
  inbound {
    label    = "allow-step-ca-internal"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "9000"
    ipv4     = ["10.0.0.0/8", "192.168.0.0/16"]
  }

  # OCSP endpoint
  inbound {
    label    = "allow-ocsp"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "8080"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }
}

output "nodebalancer_ip" {
  value = "Provisioned by LKE via Ingress NGINX"
}
