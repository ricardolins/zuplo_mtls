resource "linode_lke_cluster" "main" {
  label       = var.cluster_name
  region      = var.region
  k8s_version = var.kubernetes_version
  tags        = var.tags

  control_plane {
    high_availability = var.high_availability

    # Kubernetes API server accessible ONLY from your IP
    acl {
      enabled = true
      addresses {
        ipv4 = ["${var.allowed_ip}/32"]
      }
    }
  }

  # Dedicated pool for PKI workloads (step-ca, cert-manager)
  pool {
    type  = var.pki_node_type
    count = var.pki_node_count

    labels = {
      "role"     = "pki"
      "workload" = "certificate-authority"
    }

    taint {
      key    = "dedicated"
      value  = "pki"
      effect = "NoSchedule"
    }
  }

  # Pool for Certificate Service API
  pool {
    type  = var.app_node_type
    count = var.app_node_count

    labels = {
      "role"     = "app"
      "workload" = "certificate-service"
    }
  }

  # Pool for monitoring
  pool {
    type  = var.monitoring_node_type
    count = var.monitoring_node_count

    labels = {
      "role"     = "monitoring"
      "workload" = "observability"
    }
  }
}
