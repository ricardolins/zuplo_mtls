#!/usr/bin/env bash
# issue-cert.sh — Issues an mTLS certificate via the Certificate Service API
set -euo pipefail

CERT_SERVICE_URL="${CERT_SERVICE_URL:-https://certs.baas.io}"
TENANT_ID=""
COMMON_NAME=""
ORGANIZATION="BaaS Partner"
COUNTRY="US"
TTL="2160h"
OUTPUT_DIR="./certs-output"
EMERGENCY=false

usage() {
  echo "Usage: $0 --tenant-id UUID --common-name CN [options]"
  echo ""
  echo "Options:"
  echo "  --tenant-id     Tenant UUID (required)"
  echo "  --common-name   Certificate Common Name (required)"
  echo "  --org           Organization (default: BaaS Partner)"
  echo "  --country       Two-letter country code (default: US)"
  echo "  --ttl           Validity period, e.g.: 2160h, 90d (default: 2160h)"
  echo "  --output-dir    Directory to save files (default: ./certs-output)"
  echo "  --emergency     Use 24h TTL for emergency issuance"
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

echo "==> Issuing certificate..."
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

echo "$RESPONSE" | jq -r '.certPem'       > "$OUTPUT_DIR/${CERT_ID}.crt"
echo "$RESPONSE" | jq -r '.chainPem'      > "$OUTPUT_DIR/${CERT_ID}-chain.crt"
echo "$RESPONSE" | jq -r '.privateKeyPem' > "$OUTPUT_DIR/${CERT_ID}.key"
chmod 600 "$OUTPUT_DIR/${CERT_ID}.key"

cat "$OUTPUT_DIR/${CERT_ID}.crt" "$OUTPUT_DIR/${CERT_ID}-chain.crt" \
  > "$OUTPUT_DIR/${CERT_ID}-fullchain.crt"

echo ""
echo "====================================================="
echo " Certificate issued successfully!"
echo "   ID          : $CERT_ID"
echo "   Expires at  : $EXPIRES_AT"
echo "   Files in    : $OUTPUT_DIR/"
echo "     ${CERT_ID}.crt          (certificate)"
echo "     ${CERT_ID}.key          (private key — protect it!)"
echo "     ${CERT_ID}-fullchain.crt (certificate + chain)"
echo "====================================================="
echo ""
echo "Test with curl:"
echo "  curl --cert $OUTPUT_DIR/${CERT_ID}.crt \\"
echo "       --key  $OUTPUT_DIR/${CERT_ID}.key  \\"
echo "       https://api.zuplo.baas.io/v1/ping"
