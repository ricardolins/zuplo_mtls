#!/usr/bin/env bash
# revoke-cert.sh — Revoga um certificado mTLS
set -euo pipefail

CERT_SERVICE_URL="${CERT_SERVICE_URL:-https://certs.baas.io}"
TENANT_ID=""
CERT_ID=""
REASON="unspecified"

usage() {
  echo "Uso: $0 --tenant-id UUID --cert-id UUID [--reason MOTIVO]"
  echo ""
  echo "Motivos disponíveis:"
  echo "  unspecified, keyCompromise, caCompromise,"
  echo "  affiliationChanged, superseded, cessationOfOperation"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --tenant-id) TENANT_ID="$2"; shift 2 ;;
    --cert-id)   CERT_ID="$2";   shift 2 ;;
    --reason)    REASON="$2";    shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$TENANT_ID" || -z "$CERT_ID" ]] && usage

echo "==> Revogando certificado $CERT_ID (motivo: $REASON)..."

curl -sf -X DELETE "$CERT_SERVICE_URL/v1/certificates/$CERT_ID" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Id: $TENANT_ID" \
  -d "{\"reason\": \"$REASON\"}"

echo "Certificado $CERT_ID revogado com sucesso."
echo "A CRL será atualizada em até 24h (ou imediatamente com --force-crl)."
