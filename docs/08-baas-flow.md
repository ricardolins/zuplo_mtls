# 08 — Full BaaS Flow

## Partner Journey (from zero to mTLS in production)

### Phase 1: Onboarding

```
Partner                  API                    Back-office
   │                      │                          │
   │  Registration        │                          │
   │──POST /v1/tenants───►│                          │
   │  {name, cnpj, email} │                          │
   │                      │  Validate data           │
   │                      │─────────────────────────►│
   │                      │◄─────────────────────────│
   │◄── {tenant_id} ──────│                          │
   │                      │                          │
```

**Request:**
```http
POST /v1/tenants
Content-Type: application/json

{
  "name": "Fintech Alpha",
  "legalName": "Fintech Alpha Payments Inc",
  "cnpj": "12345678000190",
  "contactEmail": "tech@fintechalpha.com"
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

### Phase 2: mTLS Certificate Issuance

```
Partner              Certificate Service       Step-CA
   │                         │                     │
   │  POST /v1/certificates  │                     │
   │──X-Tenant-Id: uuid ────►│                     │
   │  {cn, org, ttl}         │                     │
   │                         │  1. Generate ECDSA  │
   │                         │     key pair        │
   │                         │  2. Create CSR      │
   │                         │  3. Get OTT token   │
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
  "organization": "Fintech Alpha Payments Inc",
  "country": "US",
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

> **IMPORTANT:** Store `privateKeyPem` in a secure location. This is the only time the private key is returned.

---

### Phase 3: Client Configuration

The partner saves the certificate and private key:

```bash
# Save certificate and key
echo "$CERT_PEM" > client.crt
echo "$KEY_PEM"  > client.key
chmod 600 client.key

# Verify the certificate
openssl x509 -in client.crt -noout -text | grep -E "Subject:|Not After:"
# Subject: CN=fintech-alpha.api.baas.io, O=Fintech Alpha...
# Not After: Aug 23 10:05:00 2025 GMT
```

---

### Phase 4: API Call via mTLS

```
Partner                       Ingress NGINX          Zuplo           Backend
   │                               │                    │                │
   │──TLS ClientHello─────────────►│                    │                │
   │◄──ServerHello + ServerCert────│                    │                │
   │──ClientCert + ClientVerify───►│                    │                │
   │   (fintech-alpha.api.baas.io) │                    │                │
   │                               │ Validate vs CA     │                │
   │                               │ Inject headers     │                │
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

**Request with mTLS:**
```bash
curl --cert ./client.crt \
     --key  ./client.key \
     https://api.zuplo.baas.io/v1/certificates \
     -H "X-Tenant-Id: 550e8400-e29b-41d4-a716-446655440000"
```

---

### Phase 5: Automatic Renewal (before the 90-day expiry)

```
cert-manager           Step-CA           Partner
     │                    │                  │
     │ Detects TTL < 25%  │                  │
     │──CertificateRequest►│                  │
     │◄──signed cert───────│                  │
     │                    │                  │
     │  Updates K8s Secret │                  │
     │                    │  Notification    │
     │                    │──webhook────────►│
     │                    │  (new cert)      │
```

Renewal for partner certificates **is not automatic** — the partner must:
1. Receive the expiry notification (webhook or email)
2. Call `POST /v1/certificates/{id}/renew`
3. Or call `POST /v1/certificates` to issue a new certificate

---

### Phase 6: Revocation

```
Partner              Certificate Service       Step-CA        Zuplo
   │                         │                     │              │
   │  DELETE /v1/certs/{id}  │                     │              │
   │──X-Tenant-Id: uuid ────►│                     │              │
   │  {reason: keyCompromise}│                     │              │
   │                         │──revoke(serial)────►│              │
   │                         │◄──ok────────────────│              │
   │◄──204 No Content────────│                     │              │
   │                         │  CRL updated        │              │
   │                         │  OCSP responds      │              │
   │                         │  "revoked"          │              │
   │                         │                     │              │
   │  Attempt to use revoked cert                  │              │
   │──mTLS request───────────────────────────────►│              │
   │                         │                     │ OCSP check  │
   │                         │                     │◄────────────│
   │                         │                     │ "revoked"   │
   │◄──401 CERT_REVOKED──────────────────────────── │            │
```

---

## Security considerations per phase

| Phase | Risk | Mitigation |
|-------|------|-----------|
| Issuance | Tenant impersonation | Strong authentication on /v1/certificates |
| Delivery | Private key interception | HTTPS required + key delivered only once |
| Storage | Key leakage | HSM or secret manager on partner side |
| Usage (mTLS) | Man-in-the-middle | Mutual TLS |
| Renewal | Expired cert in production | 30-day notification + automatic renewal |
| Revocation | Propagation delay | Real-time OCSP + short cache (5 min) |
