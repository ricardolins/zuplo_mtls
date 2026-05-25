#!/usr/bin/env bash
# Exemplos de uso do mTLS com curl
# Substitua os caminhos pelos arquivos gerados pelo issue-cert.sh

GATEWAY="https://api.zuplo.baas.io"
CERT_SERVICE="https://certs.baas.io"
CERT="./certs-output/MEU_CERT_ID.crt"
KEY="./certs-output/MEU_CERT_ID.key"
TENANT_ID="meu-uuid-de-tenant"

echo "=== Emitir certificado ==="
curl -X POST "$CERT_SERVICE/v1/certificates" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Id: $TENANT_ID" \
  -d '{
    "commonName": "parceiro-a.api.baas.io",
    "organization": "Parceiro Financeiro A Ltda",
    "country": "BR",
    "ttl": "2160h"
  }' | jq .

echo ""
echo "=== Listar certificados do tenant ==="
curl "$CERT_SERVICE/v1/certificates" \
  -H "X-Tenant-Id: $TENANT_ID" | jq .

echo ""
echo "=== Chamar API protegida via mTLS ==="
curl --cert "$CERT" \
     --key  "$KEY" \
     -H "Content-Type: application/json" \
     "$GATEWAY/v1/certificates" | jq .

echo ""
echo "=== Revogar certificado ==="
curl -X DELETE "$CERT_SERVICE/v1/certificates/MEU_CERT_ID" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Id: $TENANT_ID" \
  -d '{"reason": "keyCompromise"}'
