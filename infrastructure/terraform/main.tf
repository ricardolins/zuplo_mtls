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

# Attach firewall to every LKE node — blocks all inbound traffic not from var.allowed_ip
resource "linode_firewall_device" "lke_nodes" {
  for_each    = toset([for id in module.lke_cluster.node_instance_ids : tostring(id)])
  firewall_id = module.networking.firewall_id
  entity_id   = tonumber(each.value)
  entity_type = "linode"
}

# Save kubeconfig locally (never commit this file)
resource "local_file" "kubeconfig" {
  content         = base64decode(module.lke_cluster.kubeconfig)
  filename        = "${path.module}/../../.kubeconfig-lke"
  file_permission = "0600"
}
