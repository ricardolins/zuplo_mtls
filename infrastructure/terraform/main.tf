module "lke_cluster" {
  source = "./modules/lke-cluster"

  cluster_name       = var.cluster_name
  region             = var.region
  kubernetes_version = var.kubernetes_version
  high_availability  = var.high_availability
  tags               = var.tags
  allowed_ip         = var.allowed_ip

  pki_node_type         = var.pki_node_type
  pki_node_count        = var.pki_node_count
  app_node_type         = var.app_node_type
  app_node_count        = var.app_node_count
  monitoring_node_type  = var.monitoring_node_type
  monitoring_node_count = var.monitoring_node_count
}

module "networking" {
  source = "./modules/networking"

  cluster_name = var.cluster_name
  region       = var.region
  tags         = var.tags
  allowed_ip   = var.allowed_ip
}

# Save kubeconfig locally (never commit this file)
resource "local_file" "kubeconfig" {
  content         = base64decode(module.lke_cluster.kubeconfig)
  filename        = "${path.module}/../../.kubeconfig-lke"
  file_permission = "0600"
}
