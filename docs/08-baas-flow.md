# 08 — Full BaaS Flow

## Partner Journey Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  PHASE 1: ONBOARDING (one-time, via Developer Portal)           │
│  ─────────────────────────────────────────────────────────────  │
│  Partner opens Zuplo Developer Portal                           │
│  → Registers organization → Receives API Key                    │
│  → Fills certificate request form                               │
│  → Portal calls POST /v1/certificates (X-API-Key auth)          │
│  → Downloads certificate + private key                          │
│                                                                 │
│  PHASE 2: API ACCESS (ongoing, mTLS)                            │
│  ─────────────────────────────────────────────────────────────  │
│  Partner configures their HTTP client with cert + key           │
│  → All API calls go through Zuplo Gateway with mTLS             │
│  → Zuplo validates cert, injects CN, forwards to backend        │
│                                                                 │
│  PHASE 3: MAINTENANCE (renewal/revocation, mTLS)                │
│  ─────────────────────────────────────────────────────────────  │
│  Renewal before expiry via portal (mTLS + x5c provisioner)     │
│  Revocation if key is compromised (mTLS)                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1A: Tenant Registration (Developer Portal)

```
Partner Browser        Zuplo Dev Portal       Zuplo Gateway     Cert Service
      │                      │                      │                 │
      │  Open portal URL     │                      │                 │
      │─────────────────────►│                      │                 │
      │  Fill sign-up form   │                      │                 │
      │  (name, email, org)  │                      │                 │
      │─────────────────────►│                      │                 │
      │                      │  POST /v1/tenants    │                 │
      │                      │─────────────────────►│                 │
      │                      │                      │────────────────►│
      │                      │                      │◄── {tenant_id} ─│
      │                      │◄─────────────────────│                 │
      │  API Key created &   │                      │                 │
      │  displayed in portal │                      │                 │
      │◄─────────────────────│                      │                 │
```

**Request:**
```http
POST /v1/tenants
Content-Type: application/json

{
  "name": "Fintech Alpha",
  "legalName": "Fintech Alpha Payments Inc",
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

## Phase 1B: Certificate Request (Developer Portal → API Key)

```
Partner Browser        Zuplo Dev Portal       Zuplo Gateway    Cert Service   Step-CA
      │                      │                      │                │             │
      │  Fill cert form      │                      │                │             │
      │  (CN, org, TTL)      │                      │                │             │
      │─────────────────────►│                      │                │             │
      │                      │  POST /v1/certificates               │             │
      │                      │  X-API-Key: zpka_xxx │                │             │
      │                      │─────────────────────►│                │             │
      │                      │                 [api-key-policy]      │             │
      │                      │                 validates key         │             │
      │                      │                 injects X-Tenant-Id  │             │
      │                      │                      │────────────────►│             │
      │                      │                      │                │──sign(CSR)──►│
      │                      │                      │                │◄─signed cert─│
      │                      │                      │◄───────────────│             │
      │                      │◄─────────────────────│                │             │
      │  Certificate ready   │                      │                │             │
      │  in portal UI        │                      │                │             │
      │◄─────────────────────│                      │                │             │
      │  [Download .crt]     │                      │                │             │
      │  [Download .key]     │                      │                │             │
```

**Portal sends to Gateway:**
```http
POST /v1/certificates
X-API-Key: zpka_xxxxxxxxxxxxxxxxxxxxxxxx
Content-Type: application/json

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
  "commonName": "fintech-alpha.api.baas.io",
  "certPem": "-----BEGIN CERTIFICATE-----\n...",
  "chainPem": "-----BEGIN CERTIFICATE-----\n...",
  "privateKeyPem": "-----BEGIN EC PRIVATE KEY-----\n...",
  "issuedAt": "2025-05-25T10:05:00Z",
  "expiresAt": "2025-08-23T10:05:00Z",
  "status": "active"
}
```

> **IMPORTANT:** The portal should display the `privateKeyPem` for download only once and never store it. This is the only time the private key is returned.

---

## Phase 2: API Calls via mTLS

After downloading the certificate and key from the portal, the partner configures their client:

```bash
# Store cert and key from the portal download
echo "$CERT_PEM" > client.crt
echo "$KEY_PEM"  > client.key
chmod 600 client.key
```

All subsequent calls use mTLS — no API Key needed:

```
Partner HTTP Client      Ingress NGINX          Zuplo Gateway       Backend
      │                       │                      │                  │
      │──TLS ClientHello─────►│                      │                  │
      │◄──ServerHello+Cert────│                      │                  │
      │──ClientCert+Verify───►│                      │                  │
      │   fintech-alpha.api…  │                      │                  │
      │                       │ Validate vs Root CA  │                  │
      │                       │ Inject X-Client-Cert-*                  │
      │◄──TLS Finished────────│                      │                  │
      │                       │                      │                  │
      │──GET /v1/api/payments───────────────────────►│                  │
      │                       │              [mtls-policy]              │
      │                       │              reads X-Client-Cert-DN     │
      │                       │              injects X-Authenticated-CN │
      │                       │              [cert-validation-policy]   │
      │                       │              OCSP check                 │
      │                       │                      │─────────────────►│
      │                       │                      │◄─────────────────│
      │◄──200 OK ───────────────────────────────────────────────────────│
```

**Request (curl example):**
```bash
curl --cert ./client.crt \
     --key  ./client.key \
     https://api.zuplo.baas.io/v1/api/payments \
     -H "Content-Type: application/json"
```

---

## Phase 3A: Certificate Renewal (mTLS)

Renewal uses the **x5c provisioner** — the existing cert proves identity, a new cert is issued:

```
Partner                  Zuplo Gateway        Cert Service    Step-CA (x5c)
   │                          │                    │               │
   │  POST /v1/certs/:id/renew│                    │               │
   │  (mTLS with current cert)│                    │               │
   │─────────────────────────►│                    │               │
   │                    [mtls-policy validates]     │               │
   │                          │───────────────────►│               │
   │                          │                    │──x5c sign────►│
   │                          │                    │  (old cert     │
   │                          │                    │   as proof)    │
   │                          │                    │◄──new cert─────│
   │                          │                    │  old cert      │
   │                          │                    │  revoked       │
   │                          │◄───────────────────│               │
   │◄─────────────────────────│                    │               │
   │  New cert returned       │                    │               │
   │  (update client config)  │                    │               │
```

---

## Phase 3B: Certificate Revocation (mTLS)

```
Partner                  Zuplo Gateway        Cert Service    Step-CA
   │                          │                    │              │
   │  DELETE /v1/certs/:id    │                    │              │
   │  (mTLS + reason)         │                    │              │
   │─────────────────────────►│                    │              │
   │                          │───────────────────►│              │
   │                          │                    │──revoke──────►│
   │                          │                    │◄─ok───────────│
   │                          │◄───────────────────│              │
   │◄── 204 No Content ───────│                    │              │
   │                          │  CRL updated        │              │
   │                          │  OCSP: "revoked"    │              │
   │                          │                    │              │
   │  Subsequent attempt with │                    │              │
   │  revoked cert:           │                    │              │
   │─────────────────────────►│                    │              │
   │                 [cert-validation-policy]       │              │
   │                 OCSP → "revoked"              │              │
   │◄── 401 CERT_REVOKED ─────│                    │              │
```

---

## Authentication State Machine

```
                   ┌─────────────┐
                   │  Unregistered│
                   └──────┬──────┘
                          │ POST /v1/tenants (no auth)
                          ▼
                   ┌─────────────┐
                   │  Registered  │ ← has API Key from portal
                   └──────┬──────┘
                          │ POST /v1/certificates (API Key)
                          ▼
                   ┌─────────────┐
                   │  Certified   │ ← has mTLS certificate
                   └──────┬──────┘
                          │ mTLS on all subsequent API calls
                          ▼
                   ┌─────────────────────────┐
                   │  Fully Operational (mTLS)│
                   └─────────────────────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
        cert expiring             key compromised
              │                       │
     POST .../renew            DELETE .../revoke
     (mTLS + x5c)              (mTLS + reason)
              │                       │
       new cert issued         cert revoked → back to "Registered"
```

---

## Security Notes

| Phase | Risk | Mitigation |
|-------|------|-----------|
| Portal registration | Fake tenant creation | Rate limiting + email verification |
| API Key issuance | Key leaked from portal | Keys have short TTL; replaced by cert after bootstrap |
| Cert delivery | Private key interception | HTTPS-only; key displayed once in portal, never stored |
| mTLS calls | Man-in-the-middle | Mutual TLS; cert pinned to Root CA |
| Renewal | Expired cert in production | Portal shows expiry warnings; webhook notifications at T-30d |
| Revocation | Delay in CRL propagation | OCSP real-time check (5-min cache) |
