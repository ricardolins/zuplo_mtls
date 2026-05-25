#!/usr/bin/env bash
# bootstrap-cluster.sh — Instala todos os componentes no LKE após provisionamento Terraform
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
KUBECONFIG="${KUBECONFIG:-$ROOT_DIR/.kubeconfig-lke}"

export KUBECONFIG

echo "==> Verificando conexão com o cluster..."
kubectl cluster-info

echo "==> Criando namespaces..."
kubectl apply -f "$ROOT_DIR/kubernetes/namespaces/namespaces.yaml"

echo "==> Instalando ingress-nginx..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/linode-loadbalancer-throttle"="4" \
  --set controller.extraArgs.enable-ssl-passthrough="" \
  --wait --timeout 5m

echo "==> Aguardando IP do LoadBalancer..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "    NodeBalancer IP: $LB_IP"

echo "==> Instalando cert-manager..."
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace pki-system \
  --version v1.14.0 \
  --values "$ROOT_DIR/kubernetes/cert-manager/values.yaml" \
  --wait --timeout 5m

echo "==> Instalando step-issuer (CRD para cert-manager + Step-CA)..."
helm repo add smallstep https://smallstep.github.io/helm-charts
helm repo update
helm upgrade --install step-issuer smallstep/step-issuer \
  --namespace pki-system \
  --wait --timeout 3m

echo "==> Instalando Step-CA..."
helm upgrade --install step-certificates smallstep/step-certificates \
  --namespace pki-system \
  --values "$ROOT_DIR/kubernetes/step-ca/values.yaml" \
  --wait --timeout 5m

echo "==> Instalando kube-prometheus-stack (Prometheus + Grafana)..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values "$ROOT_DIR/kubernetes/monitoring/prometheus/values.yaml" \
  --wait --timeout 10m

echo ""
echo "====================================================="
echo " Bootstrap concluido!"
echo " Proximos passos:"
echo "   1. Execute: ./scripts/setup-ca.sh"
echo "   2. Aponte seu DNS para: $LB_IP"
echo "====================================================="
