#!/usr/bin/env bash
# test-mtls.sh — Tests the mTLS connection against the Zuplo Gateway
set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-https://api.zuplo.baas.io}"
CERT_DIR="${1:-./certs-output}"
CERT_FILE=""
KEY_FILE=""

# Find the first available certificate in the directory
if [[ -z "$CERT_FILE" ]]; then
  CERT_FILE=$(find "$CERT_DIR" -name "*.crt" ! -name "*chain*" ! -name "*fullchain*" | head -1)
  KEY_FILE="${CERT_FILE%.crt}.key"
fi

if [[ -z "$CERT_FILE" || ! -f "$CERT_FILE" ]]; then
  echo "ERROR: No certificate found in $CERT_DIR"
  echo "Run first: ./scripts/issue-cert.sh"
  exit 1
fi

echo "==> Certificate information:"
openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates

echo ""
echo "==> Testing mTLS connection to $GATEWAY_URL..."
echo ""

# Test 1: Health check without mTLS (should fail with 401)
echo "-- Test 1: Without client certificate (expected: 401)"
HTTP_CODE=$(curl -sw "%{http_code}" -o /dev/null "$GATEWAY_URL/v1/health" 2>/dev/null || true)
if [[ "$HTTP_CODE" == "401" ]]; then
  echo "   PASSED: 401 returned as expected"
else
  echo "   WARNING: Returned $HTTP_CODE (expected 401)"
fi

echo ""

# Test 2: With valid certificate
echo "-- Test 2: With valid certificate (expected: 200)"
HTTP_CODE=$(curl -sw "%{http_code}" -o /dev/null \
  --cert "$CERT_FILE" \
  --key  "$KEY_FILE" \
  "$GATEWAY_URL/v1/health" 2>/dev/null || true)
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "   PASSED: 200 returned"
else
  echo "   FAILED: Returned $HTTP_CODE (expected 200)"
fi

echo ""

# Test 3: Verify injected headers
echo "-- Test 3: Verify injected authentication headers"
RESPONSE=$(curl -sf \
  --cert "$CERT_FILE" \
  --key  "$KEY_FILE" \
  "$GATEWAY_URL/v1/health" 2>/dev/null || echo "{}")

echo "   Response: $RESPONSE"

echo ""
echo "==> Detailed TLS handshake test:"
openssl s_client \
  -connect "${GATEWAY_URL#https://}:443" \
  -cert "$CERT_FILE" \
  -key  "$KEY_FILE" \
  -verify_return_error \
  -brief 2>&1 | head -20

echo ""
echo "==> Tests complete."
