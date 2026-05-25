resource "linode_firewall" "cluster_fw" {
  label = "${var.cluster_name}-firewall"
  tags  = var.tags

  # Default: DROP everything inbound
  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  # HTTPS — your IP only
  inbound {
    label    = "allow-https-my-ip"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = ["${var.allowed_ip}/32"]
  }

  # HTTP (redirect to HTTPS) — your IP only
  inbound {
    label    = "allow-http-my-ip"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "80"
    ipv4     = ["${var.allowed_ip}/32"]
  }

  # Kubernetes API server (kubectl) — your IP only
  inbound {
    label    = "allow-k8s-api-my-ip"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "6443"
    ipv4     = ["${var.allowed_ip}/32"]
  }

  # Step-CA internal port — cluster nodes only (RFC1918)
  inbound {
    label    = "allow-step-ca-internal"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "9000"
    ipv4     = ["10.0.0.0/8", "192.168.0.0/16", "172.16.0.0/12"]
  }

  # OCSP — your IP only
  inbound {
    label    = "allow-ocsp-my-ip"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "8080"
    ipv4     = ["${var.allowed_ip}/32"]
  }

  # NodePort range — internal cluster only
  inbound {
    label    = "allow-nodeport-internal"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "30000-32767"
    ipv4     = ["10.0.0.0/8", "192.168.0.0/16", "172.16.0.0/12"]
  }
}
