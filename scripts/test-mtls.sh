#!/usr/bin/env bash
# test-mtls.sh — Testa a conexão mTLS contra o Zuplo Gateway
set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-https://api.zuplo.baas.io}"
CERT_DIR="${1:-./certs-output}"
CERT_FILE=""
KEY_FILE=""

# Encontrar o primeiro certificado disponível no diretório
if [[ -z "$CERT_FILE" ]]; then
  CERT_FILE=$(find "$CERT_DIR" -name "*.crt" ! -name "*chain*" ! -name "*fullchain*" | head -1)
  KEY_FILE="${CERT_FILE%.crt}.key"
fi

if [[ -z "$CERT_FILE" || ! -f "$CERT_FILE" ]]; then
  echo "ERRO: Nenhum certificado encontrado em $CERT_DIR"
  echo "Execute primeiro: ./scripts/issue-cert.sh"
  exit 1
fi

echo "==> Informações do certificado:"
openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates

echo ""
echo "==> Testando conexão mTLS com $GATEWAY_URL..."
echo ""

# Teste 1: Health check sem mTLS (deve falhar com 401)
echo "-- Teste 1: Sem certificado de cliente (esperado: 401)"
HTTP_CODE=$(curl -sw "%{http_code}" -o /dev/null "$GATEWAY_URL/v1/health" 2>/dev/null || true)
if [[ "$HTTP_CODE" == "401" ]]; then
  echo "   PASSOU: 401 retornado conforme esperado"
else
  echo "   ATENÇÃO: Retornou $HTTP_CODE (esperado 401)"
fi

echo ""

# Teste 2: Com certificado válido
echo "-- Teste 2: Com certificado válido (esperado: 200)"
HTTP_CODE=$(curl -sw "%{http_code}" -o /dev/null \
  --cert "$CERT_FILE" \
  --key  "$KEY_FILE" \
  "$GATEWAY_URL/v1/health" 2>/dev/null || true)
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "   PASSOU: 200 retornado"
else
  echo "   FALHOU: Retornou $HTTP_CODE (esperado 200)"
fi

echo ""

# Teste 3: Verificar headers injetados
echo "-- Teste 3: Verificar headers de autenticação injetados"
RESPONSE=$(curl -sf \
  --cert "$CERT_FILE" \
  --key  "$KEY_FILE" \
  "$GATEWAY_URL/v1/health" 2>/dev/null || echo "{}")

echo "   Resposta: $RESPONSE"

echo ""
echo "==> Teste de handshake TLS detalhado:"
openssl s_client \
  -connect "${GATEWAY_URL#https://}:443" \
  -cert "$CERT_FILE" \
  -key  "$KEY_FILE" \
  -verify_return_error \
  -brief 2>&1 | head -20

echo ""
echo "==> Testes concluídos."
