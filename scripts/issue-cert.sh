#!/usr/bin/env bash
# issue-cert.sh — Emite um certificado mTLS via Certificate Service API
set -euo pipefail

CERT_SERVICE_URL="${CERT_SERVICE_URL:-https://certs.baas.io}"
TENANT_ID=""
COMMON_NAME=""
ORGANIZATION="BaaS Partner"
COUNTRY="BR"
TTL="2160h"
OUTPUT_DIR="./certs-output"
EMERGENCY=false

usage() {
  echo "Uso: $0 --tenant-id UUID --common-name CN [opcoes]"
  echo ""
  echo "Opcoes:"
  echo "  --tenant-id     UUID do tenant (obrigatório)"
  echo "  --common-name   Common Name do certificado (obrigatório)"
  echo "  --org           Organização (padrão: BaaS Partner)"
  echo "  --country       País em 2 letras (padrão: BR)"
  echo "  --ttl           Validade, ex: 2160h, 90d (padrão: 2160h)"
  echo "  --output-dir    Diretório para salvar os arquivos (padrão: ./certs-output)"
  echo "  --emergency     Usar TTL de 24h para emissão de emergência"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --tenant-id)   TENANT_ID="$2";    shift 2 ;;
    --common-name) COMMON_NAME="$2";  shift 2 ;;
    --org)         ORGANIZATION="$2"; shift 2 ;;
    --country)     COUNTRY="$2";      shift 2 ;;
    --ttl)         TTL="$2";          shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2";   shift 2 ;;
    --emergency)   EMERGENCY=true;    shift   ;;
    *) usage ;;
  esac
done

[[ -z "$TENANT_ID" || -z "$COMMON_NAME" ]] && usage
[[ "$EMERGENCY" == true ]] && TTL="24h"

mkdir -p "$OUTPUT_DIR"

echo "==> Emitindo certificado..."
echo "    Tenant  : $TENANT_ID"
echo "    CN      : $COMMON_NAME"
echo "    TTL     : $TTL"
echo "    URL     : $CERT_SERVICE_URL"

RESPONSE=$(curl -sf -X POST "$CERT_SERVICE_URL/v1/certificates" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Id: $TENANT_ID" \
  -d "{
    \"commonName\": \"$COMMON_NAME\",
    \"organization\": \"$ORGANIZATION\",
    \"country\": \"$COUNTRY\",
    \"ttl\": \"$TTL\"
  }")

CERT_ID=$(echo "$RESPONSE" | jq -r '.id')
EXPIRES_AT=$(echo "$RESPONSE" | jq -r '.expiresAt')

echo "$RESPONSE" | jq -r '.certPem'      > "$OUTPUT_DIR/${CERT_ID}.crt"
echo "$RESPONSE" | jq -r '.chainPem'     > "$OUTPUT_DIR/${CERT_ID}-chain.crt"
echo "$RESPONSE" | jq -r '.privateKeyPem' > "$OUTPUT_DIR/${CERT_ID}.key"
chmod 600 "$OUTPUT_DIR/${CERT_ID}.key"

cat "$OUTPUT_DIR/${CERT_ID}.crt" "$OUTPUT_DIR/${CERT_ID}-chain.crt" \
  > "$OUTPUT_DIR/${CERT_ID}-fullchain.crt"

echo ""
echo "====================================================="
echo " Certificado emitido com sucesso!"
echo "   ID          : $CERT_ID"
echo "   Expira em   : $EXPIRES_AT"
echo "   Arquivos em : $OUTPUT_DIR/"
echo "     ${CERT_ID}.crt          (certificado)"
echo "     ${CERT_ID}.key          (chave privada — proteja!)"
echo "     ${CERT_ID}-fullchain.crt (certificado + cadeia)"
echo "====================================================="
echo ""
echo "Teste com curl:"
echo "  curl --cert $OUTPUT_DIR/${CERT_ID}.crt \\"
echo "       --key  $OUTPUT_DIR/${CERT_ID}.key  \\"
echo "       https://api.zuplo.baas.io/v1/ping"
