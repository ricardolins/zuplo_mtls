#!/usr/bin/env bash
# setup-ca.sh — Inicializa e configura a Autoridade Certificadora (Step-CA)
#
# Fluxo:
#   1. Gera Root CA (offline — deve ser executado em máquina sem rede em produção)
#   2. Gera Intermediate CA assinada pelo Root CA
#   3. Cria K8s Secrets com os certificados e chaves
#   4. Configura o StepClusterIssuer no cert-manager
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
KUBECONFIG="${KUBECONFIG:-$ROOT_DIR/.kubeconfig-lke}"
CA_WORK_DIR="$(mktemp -d)"

export KUBECONFIG

CA_NAME="${CA_NAME:-BaaS mTLS CA}"
CA_DNS="${CA_DNS:-ca.baas.io}"
ROOT_TTL="${ROOT_TTL:-87600h}"       # 10 anos
INTER_TTL="${INTER_TTL:-8760h}"      # 1 ano
PROVISIONER_NAME="${PROVISIONER_NAME:-cert-manager}"

cleanup() { rm -rf "$CA_WORK_DIR"; }
trap cleanup EXIT

echo "==> Diretório de trabalho temporário: $CA_WORK_DIR"
echo "    (apague manualmente se necessário)"

# ---- 1. Inicializar Step-CA ----
echo ""
echo "==> Inicializando Step-CA..."
step ca init \
  --name "$CA_NAME" \
  --dns "$CA_DNS" \
  --dns "step-ca-svc.pki-system.svc.cluster.local" \
  --address ":9000" \
  --provisioner "$PROVISIONER_NAME" \
  --root "$CA_WORK_DIR/root_ca.crt" \
  --key "$CA_WORK_DIR/root_ca.key" \
  --intermediate-cert "$CA_WORK_DIR/intermediate_ca.crt" \
  --intermediate-key "$CA_WORK_DIR/intermediate_ca.key" \
  --root-ttl "$ROOT_TTL" \
  --intermediate-ttl "$INTER_TTL" \
  --no-db

echo ""
echo "==> Fingerprint da Root CA:"
FINGERPRINT=$(step certificate fingerprint "$CA_WORK_DIR/root_ca.crt")
echo "    $FINGERPRINT"

# ---- 2. Criar Kubernetes Secrets ----
echo ""
echo "==> Criando Kubernetes Secrets..."

kubectl create secret generic step-ca-root-cert \
  --namespace pki-system \
  --from-file=root_ca.crt="$CA_WORK_DIR/root_ca.crt" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic step-ca-intermediate-cert \
  --namespace pki-system \
  --from-file=intermediate_ca.crt="$CA_WORK_DIR/intermediate_ca.crt" \
  --from-file=intermediate_ca.key="$CA_WORK_DIR/intermediate_ca.key" \
  --dry-run=client -o yaml | kubectl apply -f -

# ---- 3. Obter kid do provisioner JWK ----
echo ""
echo "==> Obtendo kid do provisioner JWK..."
PROVISIONER_KID=$(step ca provisioner list 2>/dev/null | \
  python3 -c "import sys,json; p=[x for x in json.load(sys.stdin) if x['name']=='$PROVISIONER_NAME']; print(p[0]['key']['kid'])" \
  || echo "")

echo "    kid: $PROVISIONER_KID"

# ---- 4. Atualizar ConfigMap com fingerprint e kid ----
kubectl create configmap certificate-service-config \
  --namespace certificate-service \
  --from-literal=step_ca_fingerprint="$FINGERPRINT" \
  --from-literal=provisioner_name="$PROVISIONER_NAME" \
  --from-literal=provisioner_kid="$PROVISIONER_KID" \
  --dry-run=client -o yaml | kubectl apply -f -

# ---- 5. Aplicar StepClusterIssuer com CA bundle ----
CA_BUNDLE=$(base64 < "$CA_WORK_DIR/root_ca.crt" | tr -d '\n')

kubectl apply -f - <<EOF
apiVersion: certmanager.step.sm/v1beta1
kind: StepClusterIssuer
metadata:
  name: step-ca-issuer
spec:
  url: https://step-ca-svc.pki-system.svc.cluster.local:9000
  caBundle: $CA_BUNDLE
  provisioner:
    name: $PROVISIONER_NAME
    kid: "$PROVISIONER_KID"
    passwordRef:
      name: step-ca-provisioner-password
      namespace: pki-system
      key: password
EOF

echo ""
echo "====================================================="
echo " CA configurada com sucesso!"
echo ""
echo " IMPORTANTE — guarde estas informações com segurança:"
echo "   Root CA fingerprint : $FINGERPRINT"
echo "   Provisioner kid     : $PROVISIONER_KID"
echo ""
echo " Arquivos gerados em: $CA_WORK_DIR"
echo " (serão apagados ao fim do script — faça backup do"
echo "  root_ca.key em mídia offline antes de prosseguir)"
echo "====================================================="
