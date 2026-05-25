# 08 — Fluxo BaaS Completo

## Jornada do Parceiro (do zero ao mTLS em produção)

### Fase 1: Onboarding

```
Parceiro                API                    Back-office
   │                     │                          │
   │  Cadastro           │                          │
   │──POST /v1/tenants──►│                          │
   │  {name, cnpj, email}│                          │
   │                     │  Valida dados            │
   │                     │─────────────────────────►│
   │                     │◄─────────────────────────│
   │◄── {tenant_id} ─────│                          │
   │                     │                          │
```

**Request:**
```http
POST /v1/tenants
Content-Type: application/json

{
  "name": "Fintech Alpha",
  "legalName": "Fintech Alpha Pagamentos S.A.",
  "cnpj": "12345678000190",
  "contactEmail": "tech@fintechalpha.com.br"
}
```

**Response:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Fintech Alpha",
  "status": "active",
  "createdAt": "2025-05-25T10:00:00Z"
}
```

---

### Fase 2: Emissão do Certificado mTLS

```
Parceiro              Certificate Service       Step-CA
   │                         │                     │
   │  POST /v1/certificates  │                     │
   │──X-Tenant-Id: uuid ────►│                     │
   │  {cn, org, ttl}         │                     │
   │                         │  1. Gera par de     │
   │                         │     chaves ECDSA     │
   │                         │  2. Cria CSR         │
   │                         │  3. Obtém token OTT  │
   │                         │─────sign(CSR)───────►│
   │                         │◄────signed cert ─────│
   │                         │                     │
   │◄─{cert, key, chain}─────│                     │
```

**Request:**
```http
POST /v1/certificates
Content-Type: application/json
X-Tenant-Id: 550e8400-e29b-41d4-a716-446655440000

{
  "commonName": "fintech-alpha.api.baas.io",
  "organization": "Fintech Alpha Pagamentos S.A.",
  "country": "BR",
  "san": ["fintech-alpha.api.baas.io"],
  "ttl": "2160h"
}
```

**Response:**
```json
{
  "id": "7f3d9a2e-1234-5678-abcd-ef0123456789",
  "serialNumber": "4a:b2:c3:d4:e5:f6",
  "commonName": "fintech-alpha.api.baas.io",
  "certPem": "-----BEGIN CERTIFICATE-----\n...",
  "chainPem": "-----BEGIN CERTIFICATE-----\n...",
  "privateKeyPem": "-----BEGIN EC PRIVATE KEY-----\n...",
  "issuedAt": "2025-05-25T10:05:00Z",
  "expiresAt": "2025-08-23T10:05:00Z",
  "status": "active"
}
```

> **IMPORTANTE:** Armazene `privateKeyPem` em local seguro. Esta é a única vez que a chave privada é retornada.

---

### Fase 3: Configuração do Cliente

O parceiro salva o certificado e chave privada:

```bash
# Salvar certificado e chave
echo "$CERT_PEM" > client.crt
echo "$KEY_PEM"  > client.key
chmod 600 client.key

# Verificar certificado
openssl x509 -in client.crt -noout -text | grep -E "Subject:|Not After:"
# Subject: CN=fintech-alpha.api.baas.io, O=Fintech Alpha...
# Not After: Aug 23 10:05:00 2025 GMT
```

---

### Fase 4: Chamada de API via mTLS

```
Parceiro                      Ingress NGINX          Zuplo           Backend
   │                               │                    │                │
   │──TLS ClientHello─────────────►│                    │                │
   │◄──ServerHello + ServerCert────│                    │                │
   │──ClientCert + ClientVerify───►│                    │                │
   │   (fintech-alpha.api.baas.io) │                    │                │
   │                               │ Valida contra CA   │                │
   │                               │ Injeta headers     │                │
   │◄──TLS Finished────────────────│                    │                │
   │                               │                    │                │
   │──GET /v1/certificates─────────────────────────────►│                │
   │   X-Client-Cert-DN: CN=...    │                    │                │
   │                               │                    │ mtls-policy    │
   │                               │                    │ cert-validate  │
   │                               │                    │────────────────►│
   │                               │                    │◄────────────────│
   │◄──200 OK──────────────────────────────────────────────────────────── │
```

**Request com mTLS:**
```bash
curl --cert ./client.crt \
     --key  ./client.key \
     https://api.zuplo.baas.io/v1/certificates \
     -H "X-Tenant-Id: 550e8400-e29b-41d4-a716-446655440000"
```

---

### Fase 5: Renovação Automática (90 dias antes do vencimento)

```
cert-manager           Step-CA           Parceiro
     │                    │                  │
     │ Detecta TTL < 25%  │                  │
     │──CertificateRequest►│                  │
     │◄──signed cert───────│                  │
     │                    │                  │
     │  Atualiza Secret K8s│                  │
     │                    │  Notificação     │
     │                    │──webhook────────►│
     │                    │  (novo cert)     │
```

A renovação para certificados de parceiros **não é automática** — o parceiro deve:
1. Receber a notificação de vencimento (webhook ou e-mail)
2. Chamar `POST /v1/certificates/{id}/renew`
3. Ou chamar `POST /v1/certificates` para emitir um novo certificado

---

### Fase 6: Revogação

```
Parceiro              Certificate Service       Step-CA        Zuplo
   │                         │                     │              │
   │  DELETE /v1/certs/{id}  │                     │              │
   │──X-Tenant-Id: uuid ────►│                     │              │
   │  {reason: keyCompromise}│                     │              │
   │                         │──revoke(serial)────►│              │
   │                         │◄──ok────────────────│              │
   │◄──204 No Content────────│                     │              │
   │                         │  CRL atualizada     │              │
   │                         │  OCSP responde      │              │
   │                         │  "revoked"          │              │
   │                         │                     │              │
   │  Tenta usar cert revogado│                    │              │
   │──mTLS request───────────────────────────────►│              │
   │                         │                     │ OCSP check  │
   │                         │                     │◄────────────│
   │                         │                     │ "revoked"   │
   │◄──401 CERT_REVOKED──────────────────────────── │            │
```

---

## Considerações de segurança por fase

| Fase | Risco | Mitigação |
|------|-------|-----------|
| Emissão | Impersonação de tenant | Autenticação forte no endpoint /v1/certificates |
| Entrega do cert | Intercepção da chave privada | HTTPS obrigatório + key entregue apenas 1x |
| Armazenamento | Vazamento da chave | HSM ou secret manager no lado do parceiro |
| Uso (mTLS) | Man-in-the-middle | mTLS bidirecional |
| Renovação | Cert expirado em produção | Notificação 30 dias antes + renovação automática |
| Revogação | Delay na propagação | OCSP em tempo real + cache curto (5 min) |
