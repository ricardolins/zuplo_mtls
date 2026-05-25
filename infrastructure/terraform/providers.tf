terraform {
  required_version = ">= 1.5.0"

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.23"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }

  # Backend remoto recomendado para producao:
  # backend "s3" {
  #   bucket = "seu-bucket-tfstate"
  #   key    = "mtls-baas/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "linode" {
  token = var.linode_token
}

provider "kubernetes" {
  host                   = module.lke_cluster.endpoint
  token                  = module.lke_cluster.service_account_token
  cluster_ca_certificate = base64decode(module.lke_cluster.ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.lke_cluster.endpoint
    token                  = module.lke_cluster.service_account_token
    cluster_ca_certificate = base64decode(module.lke_cluster.ca_certificate)
  }
}
