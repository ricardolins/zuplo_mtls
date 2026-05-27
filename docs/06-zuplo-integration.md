# 06 — Zuplo Integration

## Overview

The Zuplo platform serves **two distinct roles** in this architecture:

| Role | Component | Purpose |
|------|-----------|---------|
| **Developer Portal** | Zuplo Portal | Partner self-service: register, get API Key, request certificate, view docs |
| **API Gateway** | Zuplo Runtime | Route and authenticate all API calls (API Key for bootstrap, mTLS for everything else) |

The **Developer Portal is the single entry point for partners**. It guides them through onboarding and certificate issuance, then redirects all API operations to the gateway.

---

## The Two-Tier Authentication Model

This solves the **bootstrap problem**: *how do you request an mTLS certificate if you need mTLS to call the API?*

```
┌──────────────────────────────────────────────────────────────────┐
│  TIER 1 — Bootstrap (API Key)                                    │
│                                                                  │
│  1. Partner opens Developer Portal                               │
│  2. Registers tenant → receives API Key                          │
│  3. Fills certificate request form in portal                     │
│  4. Portal calls POST /v1/certificates with X-API-Key header    │
│  5. Certificate issued and displayed/downloaded in portal        │
│                                                                  │
│  Endpoints:  POST /v1/certificates                               │
│              GET  /v1/certificates                               │
│              GET  /v1/certificates/:id                           │
│  Auth:       X-API-Key header                                   │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  TIER 2 — All Subsequent Operations (mTLS)                       │
│                                                                  │
│  Once the partner has a certificate, ALL API calls use mTLS.    │
│                                                                  │
│  Endpoints:  DELETE /v1/certificates/:id  (revoke)              │
│              POST   /v1/certificates/:id/renew                   │
│              ALL    /v1/api/*  (protected business APIs)         │
│  Auth:       Client certificate (mutual TLS)                     │
└──────────────────────────────────────────────────────────────────┘
```

---

## Developer Portal Configuration

### 1. Create the Zuplo project

1. Go to https://portal.zuplo.com
2. Create new project: **"baas-mtls-gateway"**
3. Connect your GitHub repo (`your-org/your-repo`)

### 2. Configure the Developer Portal pages

The portal needs a custom **Certificate Request** page that:
1. Shows the partner's current certificates and their status
2. Provides a form to request a new certificate (CN, organization, TTL)
3. Submits the form to `POST /v1/certificates` with the partner's API Key
4. Displays the resulting certificate for download

In Zuplo, create `docs/` pages in the portal:

```
zuplo/
└── docs/
    ├── index.md              → "Welcome to BaaS mTLS Platform"
    ├── getting-started.md    → Step-by-step: register → get cert → call API
    ├── authentication.md     → Explains API Key (bootstrap) vs mTLS
    └── certificate-guide.md  → How to configure your client (curl, Node.js, Python)
```

### 3. API Key management in the portal

Zuplo Developer Portal includes built-in API Key management:

- Partners self-generate keys from the portal
- Keys are scoped to a tenant ID (stored in key metadata)
- Keys can be rotated or revoked from the portal
- The `api-key-inbound-policy` reads `keyData.metadata.tenantId` to identify the partner

### 4. Environment variables

In Zuplo > Settings > Environment Variables:

| Variable | Value |
|----------|-------|
| `CERT_SERVICE_URL` | `http://certificate-service-svc.certificate-service` |
| `BACKEND_API_URL` | URL of your protected backend services |
| `OCSP_URL` | `http://step-ca-svc.pki-system:8080` |

---

## Gateway Policies

All policies live in `zuplo/policies/`:

### `api-key-policy.ts` — Bootstrap flow

Validates the `X-API-Key` header against the Zuplo key store. Injects `X-Tenant-Id` and `X-Auth-Method: api-key` into forwarded requests.

```
POST /v1/certificates
  X-API-Key: zpka_xxx
  ──────────────────────────────────────────────►
  [api-key-inbound-policy]
    • Verify key against Zuplo key store
    • Extract tenantId from key metadata
    • Inject X-Tenant-Id header
  ──────────────────────────────────────────────►
  Certificate Service
```

### `mtls-policy.ts` — Ongoing API calls

Reads the client certificate injected by Ingress NGINX as `X-Client-Cert-*` headers. Validates expiry and extracts CN.

```
DELETE /v1/certificates/:id
  (TLS with client certificate)
  ──────────────────────────────────────────────►
  [Ingress NGINX validates cert against Root CA]
  [Injects X-Client-Cert-DN, X-Client-Cert-Expiry]
  ──────────────────────────────────────────────►
  [mtls-inbound-policy]
    • Read X-Client-Cert-DN header
    • Validate expiry
    • Inject X-Authenticated-CN
  ──────────────────────────────────────────────►
  [cert-validation-policy]
    • CN allowlist check (optional)
    • OCSP real-time check (optional)
  ──────────────────────────────────────────────►
  Certificate Service
```

### `cert-validation-policy.ts` — CN allowlist + OCSP

Applied after `mtls-policy`. Optionally checks the CN against a per-route allowlist and queries the OCSP endpoint for real-time revocation status.

---

## Full Route Map

| Method | Path | Auth | Backend |
|--------|------|------|---------|
| POST | `/v1/tenants` | None (rate limited) | Certificate Service |
| POST | `/v1/certificates` | API Key | Certificate Service |
| GET | `/v1/certificates` | API Key | Certificate Service |
| GET | `/v1/certificates/:id` | API Key | Certificate Service |
| DELETE | `/v1/certificates/:id` | mTLS | Certificate Service |
| POST | `/v1/certificates/:id/renew` | mTLS | Certificate Service |
| * | `/v1/api/*` | mTLS | Backend services |

---

## Ingress NGINX — mTLS termination

Ingress NGINX validates the client certificate and injects headers **before** the request reaches Zuplo:

```yaml
# Critical annotations on the Ingress resource
nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
nginx.ingress.kubernetes.io/auth-tls-secret: "pki-system/step-ca-root-cert"
nginx.ingress.kubernetes.io/auth-tls-verify-depth: "2"
nginx.ingress.kubernetes.io/auth-tls-pass-certificate-to-upstream: "true"
```

Headers injected for Zuplo to consume:

| Header | Value |
|--------|-------|
| `X-Client-Cert` | URL-encoded PEM |
| `X-Client-Cert-DN` | `CN=partner-a.api.baas.io,O=Partner A` |
| `X-Client-Cert-Serial` | `3a:f2:...` |
| `X-Client-Cert-Expiry` | `Aug 23 10:05:00 2025 GMT` |
| `X-Client-Cert-Issuer` | `CN=BaaS mTLS Intermediate CA` |

> **Note:** The API Key endpoints (`/v1/certificates` POST/GET) do **not** require a client certificate. On those routes, Ingress NGINX must be set to `auth-tls-verify-client: "optional"` so requests without a cert are still forwarded to Zuplo (where the API Key policy handles auth).

---

## Testing

```bash
# === Bootstrap flow (API Key) ===

# 1. Register tenant (no auth)
curl -X POST https://api.zuplo.baas.io/v1/tenants \
  -H "Content-Type: application/json" \
  -d '{"name":"Fintech Alpha","legalName":"Fintech Alpha Inc","contactEmail":"tech@fa.com"}'

# 2. Issue certificate (API Key from portal)
curl -X POST https://api.zuplo.baas.io/v1/certificates \
  -H "X-API-Key: zpka_your_key_here" \
  -H "Content-Type: application/json" \
  -d '{"commonName":"fintech-alpha.api.baas.io","organization":"Fintech Alpha Inc","ttl":"2160h"}'

# === mTLS flow ===

# 3. Call protected API (certificate required)
curl --cert ./certs-output/client.crt \
     --key  ./certs-output/client.key \
     https://api.zuplo.baas.io/v1/api/payments

# 4. Renew certificate (mTLS)
curl --cert ./certs-output/client.crt \
     --key  ./certs-output/client.key \
     -X POST https://api.zuplo.baas.io/v1/certificates/CERT_ID/renew
```
