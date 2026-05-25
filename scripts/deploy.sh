#!/usr/bin/env bash
# deploy.sh — Full interactive deployment of the mTLS BaaS platform
# Run from the repo root: ./scripts/deploy.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/infrastructure/terraform"
TFVARS="$TF_DIR/terraform.tfvars"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}==>${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
die()     { echo -e "${RED}✗${NC} $*"; exit 1; }

# ─── Prerequisite check ───────────────────────────────────────────────────────
check_prereqs() {
  info "Checking prerequisites..."
  local missing=()
  for cmd in terraform kubectl helm step jq curl; do
    if ! command -v "$cmd" &>/dev/null; then missing+=("$cmd"); fi
  done
  [[ ${#missing[@]} -gt 0 ]] && die "Missing tools: ${missing[*]}. Install them first."
  success "All tools present (terraform $(terraform version -json | jq -r '.terraform_version'), kubectl $(kubectl version --client -o json | jq -r '.clientVersion.gitVersion'), helm $(helm version --short), step $(step version | head -1))"
}

# ─── Linode token & tfvars ────────────────────────────────────────────────────
setup_tfvars() {
  if [[ -f "$TFVARS" ]]; then
    warn "terraform.tfvars already exists — skipping."
    return
  fi

  echo ""
  echo -e "${YELLOW}You need a Linode API token.${NC}"
  echo "  Create one at: https://cloud.linode.com/profile/tokens"
  echo "  Required scopes (Read/Write): Kubernetes, Linodes, NodeBalancers, Firewall, IPs"
  echo ""
  read -rsp "Paste your Linode token (input hidden): " LINODE_TOKEN
  echo ""
  [[ -z "$LINODE_TOKEN" ]] && die "Token cannot be empty."

  cat > "$TFVARS" <<EOF
linode_token          = "$LINODE_TOKEN"
region                = "br-gru"
cluster_name          = "mtls-baas"
kubernetes_version    = "1.31"
high_availability     = false

pki_node_type         = "g6-standard-2"
pki_node_count        = 1

app_node_type         = "g6-standard-2"
app_node_count        = 1

monitoring_node_type  = "g6-standard-1"
monitoring_node_count = 1

cert_service_domain   = "certs.ricardolins.dev.br"
base_domain           = "ricardolins.dev.br"

tags = ["mtls-baas", "dev"]
EOF
  chmod 600 "$TFVARS"
  success "terraform.tfvars created."
}

# ─── Terraform provision ──────────────────────────────────────────────────────
provision_cluster() {
  info "Provisioning LKE cluster in São Paulo (br-gru)..."
  cd "$TF_DIR"

  terraform init -upgrade

  echo ""
  info "Review the plan:"
  terraform plan -out=deploy.tfplan

  echo ""
  read -rp "Apply? (yes/no): " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && die "Aborted."

  terraform apply deploy.tfplan
  success "Cluster provisioned."

  # Export kubeconfig
  KUBECONFIG_PATH="$ROOT_DIR/.kubeconfig-lke"
  terraform output -raw kubeconfig 2>/dev/null | base64 -d > "$KUBECONFIG_PATH" 2>/dev/null \
    || cp "$KUBECONFIG_PATH" "$KUBECONFIG_PATH"  # already written by local_file resource
  chmod 600 "$KUBECONFIG_PATH"
  export KUBECONFIG="$KUBECONFIG_PATH"
  success "kubeconfig saved to $KUBECONFIG_PATH"

  cd "$ROOT_DIR"
}

# ─── Bootstrap cluster ────────────────────────────────────────────────────────
bootstrap() {
  info "Bootstrapping cluster components..."
  export KUBECONFIG="$ROOT_DIR/.kubeconfig-lke"

  kubectl cluster-info

  "$ROOT_DIR/scripts/bootstrap-cluster.sh"
  success "Cluster bootstrapped."
}

# ─── CA setup ─────────────────────────────────────────────────────────────────
setup_ca() {
  info "Initializing Certificate Authority..."
  export KUBECONFIG="$ROOT_DIR/.kubeconfig-lke"

  "$ROOT_DIR/scripts/setup-ca.sh"
  success "CA ready."
}

# ─── Certificate Service deploy ───────────────────────────────────────────────
deploy_cert_service() {
  info "Deploying Certificate Service..."
  export KUBECONFIG="$ROOT_DIR/.kubeconfig-lke"

  # Build and push Docker image (requires docker + registry)
  if command -v docker &>/dev/null; then
    info "Building Certificate Service Docker image..."
    cd "$ROOT_DIR/certificate-service"
    docker build -t ghcr.io/ricardolins/zuplo-mtls/certificate-service:latest .
    warn "Push the image: docker push ghcr.io/ricardolins/zuplo-mtls/certificate-service:latest"
    cd "$ROOT_DIR"
  else
    warn "Docker not found — skipping image build. Push the image manually before continuing."
  fi

  kubectl apply -f "$ROOT_DIR/kubernetes/certificate-service/deployment.yaml"
  kubectl apply -f "$ROOT_DIR/kubernetes/certificate-service/ingress.yaml"

  info "Waiting for Certificate Service rollout..."
  kubectl rollout status deployment/certificate-service -n certificate-service --timeout=120s
  success "Certificate Service deployed."
}

# ─── DNS instructions ─────────────────────────────────────────────────────────
print_dns_instructions() {
  export KUBECONFIG="$ROOT_DIR/.kubeconfig-lke"

  info "Fetching LoadBalancer IP..."
  LB_IP=""
  for i in $(seq 1 20); do
    LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [[ -n "$LB_IP" ]] && break
    echo "  Waiting for IP... ($i/20)"
    sleep 10
  done

  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN} Deployment complete!${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "${YELLOW}ACTION REQUIRED — Create DNS records:${NC}"
  echo ""
  echo "  In your DNS provider (ricardolins.dev.br), add A records:"
  echo ""
  echo "    certs.ricardolins.dev.br  →  $LB_IP"
  echo "    ca.ricardolins.dev.br     →  $LB_IP"
  echo ""
  echo "  Then test:"
  echo "    curl https://certs.ricardolins.dev.br/v1/health"
  echo ""
  echo -e "${YELLOW}Zuplo configuration:${NC}"
  echo "  Set env var CERT_SERVICE_URL = http://certificate-service-svc.certificate-service"
  echo "  Deploy policies from: zuplo/policies/"
  echo "  Upload routes:        zuplo/routes.oas.json"
  echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     mTLS BaaS Platform — Full Deployment         ║${NC}"
echo -e "${BLUE}║     Domain: ricardolins.dev.br                   ║${NC}"
echo -e "${BLUE}║     Region: br-gru (São Paulo)                   ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""

STEP="${1:-all}"

case "$STEP" in
  prereqs)   check_prereqs ;;
  tfvars)    setup_tfvars ;;
  provision) check_prereqs; setup_tfvars; provision_cluster ;;
  bootstrap) bootstrap ;;
  ca)        setup_ca ;;
  app)       deploy_cert_service ;;
  dns)       print_dns_instructions ;;
  all)
    check_prereqs
    setup_tfvars
    provision_cluster
    bootstrap
    setup_ca
    deploy_cert_service
    print_dns_instructions
    ;;
  *)
    echo "Usage: $0 [prereqs|tfvars|provision|bootstrap|ca|app|dns|all]"
    echo "  all        — full deployment (default)"
    echo "  prereqs    — check tools only"
    echo "  tfvars     — create terraform.tfvars"
    echo "  provision  — provision LKE cluster"
    echo "  bootstrap  — install ingress-nginx, cert-manager, step-ca, prometheus"
    echo "  ca         — initialize the Certificate Authority"
    echo "  app        — deploy Certificate Service API"
    echo "  dns        — show DNS configuration instructions"
    ;;
esac
