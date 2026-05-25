#!/usr/bin/env bash
# revoke-cert.sh — Revokes an mTLS certificate
set -euo pipefail

CERT_SERVICE_URL="${CERT_SERVICE_URL:-https://certs.baas.io}"
TENANT_ID=""
CERT_ID=""
REASON="unspecified"

usage() {
  echo "Usage: $0 --tenant-id UUID --cert-id UUID [--reason REASON]"
  echo ""
  echo "Available reasons:"
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

echo "==> Revoking certificate $CERT_ID (reason: $REASON)..."

curl -sf -X DELETE "$CERT_SERVICE_URL/v1/certificates/$CERT_ID" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Id: $TENANT_ID" \
  -d "{\"reason\": \"$REASON\"}"

echo "Certificate $CERT_ID revoked successfully."
echo "The CRL will be updated within 24h (or immediately with --force-crl)."
