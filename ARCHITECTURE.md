# mTLS BaaS Architecture — Technical Document

## 1. Core Concepts

### What is mTLS?

**mTLS (Mutual Transport Layer Security)** is a TLS extension where **both sides** — client and server — present X.509 certificates for authentication. In the BaaS model:

- The **server** (Zuplo Gateway) presents its certificate to the client (standard TLS)
- The **client** (partner/fintech) presents its certificate to the server (the "mutual" part)
- The gateway validates that the client certificate was signed by a trusted CA

```
Client                     Gateway (Zuplo)
  │                              │
  │──── ClientHello ────────────►│
  │◄─── ServerHello + Cert ──────│  server presents its cert
  │──── ClientCert + Verify ────►│  client presents its cert
  │◄─── Finished ────────────────│  handshake complete
  │                              │  gateway validated client cert
  │──── HTTP Request ───────────►│
  │◄─── HTTP Response ───────────│
```

### Why use it in the BaaS model?

| Benefit | Description |
|---------|-------------|
| **Strong identity** | Each partner has a unique, non-repudiable certificate |
| **No credentials in payload** | Authentication happens at the TLS layer |
| **Granular revocation** | Revoke one partner's access without affecting others |
| **Auditing** | The certificate CN identifies the partner in all logs |
| **Zero-trust** | Aligns with modern zero-trust architectures |

---

## 2. High-Level Platform Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      PARTNER / FINTECH                                   │
│                                                                          │
│  Step 1 (one-time): Visit Zuplo Developer Portal                        │
│  Step 2 (one-time): Request mTLS certificate via portal form            │
│  Step 3 (ongoing):  Call protected APIs using the issued certificate     │
└──────────────────┬──────────────────────────────┬───────────────────────┘
                   │                              │
          HTTPS + API Key                  HTTPS + mTLS
          (first-time only)               (ongoing calls)
                   │                              │
                   ▼                              ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                        ZUPLO PLATFORM                                    │
│                                                                          │
│  ┌──────────────────────────────┐  ┌────────────────────────────────┐   │
│  │      DEVELOPER PORTAL        │  │         API GATEWAY            │   │
│  │                              │  │                                │   │
│  │  • Partner self-onboarding   │  │  Route A: /v1/certificates/*   │   │
│  │  • Certificate request form  │  │    Policy: api-key-auth        │   │
│  │  • API documentation         │  │    → Certificate Service       │   │
│  │  • Certificate status view   │  │                                │   │
│  │  • API key management        │  │  Route B: /v1/api/*            │   │
│  │                              │  │    Policy: mtls-auth           │   │
│  │  Redirects to API Gateway    │  │    Policy: cert-validation     │   │
│  │  for all API operations      │  │    → Protected services        │   │
│  └──────────────────────────────┘  └────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                      LINODE KUBERNETES ENGINE (LKE)                      │
│                                                                          │
│  ┌────────────────────────┐    ┌──────────────┐    ┌─────────────────┐  │
│  │  Certificate Service   │    │   Step-CA    │    │   Prometheus    │  │
│  │  REST API              │───►│   (Root CA + │    │   + Grafana     │  │
│  │  (Node.js/TypeScript)  │    │   Inter CA)  │    │                 │  │
│  └────────────────────────┘    └──────────────┘    └─────────────────┘  │
│                                                                          │
│  cert-manager + step-issuer (automatic certificate lifecycle in K8s)    │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 3. The Bootstrap Problem & Solution

**Problem:** How does a partner request their first mTLS certificate if mTLS is required to call the API?

**Solution:** Two separate authentication tiers in the Zuplo gateway:

```
┌────────────────────────────────────────────────────────────────────┐
│  TIER 1 — Certificate Issuance (API Key auth)                      │
│                                                                    │
│  POST /v1/certificates    ← API Key (issued via Developer Portal)  │
│  GET  /v1/certificates    ← API Key                                │
│  POST /v1/tenants         ← No auth (public registration)          │
│                                                                    │
│  Partner gets API Key from the Developer Portal during signup.     │
│  Uses it ONLY to bootstrap their first mTLS certificate.          │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│  TIER 2 — Protected APIs (mTLS auth)                               │
│                                                                    │
│  ALL /v1/api/*            ← mTLS (client certificate required)     │
│  DELETE /v1/certificates/:id  ← mTLS                              │
│  POST  /v1/certificates/:id/renew  ← mTLS (x5c provisioner)       │
│                                                                    │
│  Once the partner has a certificate, ALL operations use mTLS.     │
└────────────────────────────────────────────────────────────────────┘
```

---

## 4. Certificate Hierarchy (PKI)

```
Root CA (offline / air-gapped)
│   Validity: 10 years
│   Key: ECDSA P-384
│   Storage: HSM or encrypted K8s Secret
│
└── Intermediate CA (online / Kubernetes)
    │   Validity: 1 year (automatic renewal via cert-manager)
    │   Key: ECDSA P-256
    │   Storage: K8s Secret in pki-system namespace
    │
    ├── Leaf Certificate — Tenant A
    │       CN: tenant-a.api.baas.io
    │       Validity: 90 days
    │
    ├── Leaf Certificate — Tenant B
    │       CN: tenant-b.api.baas.io
    │       Validity: 90 days
    │
    └── Leaf Certificate — Tenant C (revoked)
            Status: REVOKED (CRL entry)
```

---

## 5. Complete Partner Onboarding Flow via Developer Portal

```
Partner Browser         Zuplo Dev Portal       Zuplo Gateway      Cert Service    Step-CA
      │                       │                      │                  │              │
      │  1. Open portal       │                      │                  │              │
      │──────────────────────►│                      │                  │              │
      │  2. Sign up / login   │                      │                  │              │
      │──────────────────────►│                      │                  │              │
      │◄── API Key issued ────│                      │                  │              │
      │                       │                      │                  │              │
      │  3. Fill cert form    │                      │                  │              │
      │     (CN, org, TTL)    │                      │                  │              │
      │──────────────────────►│                      │                  │              │
      │                       │  4. POST /v1/certificates               │              │
      │                       │     X-API-Key: <key> │                  │              │
      │                       │─────────────────────►│                  │              │
      │                       │                      │─────────────────►│              │
      │                       │                      │                  │──sign(CSR)──►│
      │                       │                      │                  │◄─signed cert─│
      │                       │                      │◄─────────────────│              │
      │                       │◄─────────────────────│                  │              │
      │  5. Certificate ready │                      │                  │              │
      │◄──────────────────────│                      │                  │              │
      │     Download .crt     │                      │                  │              │
      │     Download .key     │                      │                  │              │
      │                       │                      │                  │              │
      │  6. Configure client  │                      │                  │              │
      │     with cert + key   │                      │                  │              │
      │                       │                      │                  │              │
      │  7. Call protected API (mTLS from now on)    │                  │              │
      │─────────────────────────────────────────────►│                  │              │
      │     TLS ClientCert presented                 │                  │              │
      │◄─────────────────────────────────────────────│                  │              │
```

---

## 6. Zuplo Route Configuration

### Route A — Certificate Issuance (API Key)

```
POST   /v1/certificates          → api-key-inbound-policy → Certificate Service
GET    /v1/certificates          → api-key-inbound-policy → Certificate Service
GET    /v1/certificates/:id      → api-key-inbound-policy → Certificate Service
```

### Route B — Certificate Management (mTLS)

```
DELETE /v1/certificates/:id      → mtls-inbound-policy → cert-validation-policy → Certificate Service
POST   /v1/certificates/:id/renew → mtls-inbound-policy → cert-validation-policy → Certificate Service
```

### Route C — Protected APIs (mTLS)

```
ALL    /v1/api/*                 → mtls-inbound-policy → cert-validation-policy → Backend Services
```

---

## 7. Platform Components

### 7.1 Step-CA (Smallstep Certificate Authority)

- Open-source, battle-tested, used by large organizations
- Native REST API for automation
- Multiple provisioners (JWK, ACME, x5c)
- Built-in CRL and OCSP

### 7.2 cert-manager

- Automates certificate renewal for Kubernetes-internal services
- Integrates with Step-CA via `StepIssuer` CRD

### 7.3 Certificate Service API

REST API (Node.js/TypeScript) — internal service, **never directly exposed to clients**. Only reachable through the Zuplo Gateway.

| Endpoint | Auth tier | Description |
|----------|-----------|-------------|
| `POST /v1/certificates` | API Key | Issue new certificate |
| `GET /v1/certificates` | API Key | List tenant certificates |
| `GET /v1/certificates/:id` | API Key | Get certificate details |
| `DELETE /v1/certificates/:id` | mTLS | Revoke certificate |
| `POST /v1/certificates/:id/renew` | mTLS | Renew certificate |

### 7.4 Zuplo Developer Portal

- Partner self-service: register, get API key, request certificate
- Displays certificate status and expiry
- API documentation (OpenAPI rendered)
- Redirects all API operations to the Zuplo Gateway

---

## 8. Security Model

### Threat Model

| Threat | Mitigation |
|--------|-----------|
| Root CA key compromised | Root CA offline, never in cluster |
| Partner certificate compromised | Immediate revocation via CRL/OCSP |
| API Key leaked | API Keys expire; certificate replaces them after bootstrap |
| Man-in-the-middle | mTLS on all post-bootstrap communications |
| Unauthorized certificate issuance | API Key scoped to one tenant; validated by Certificate Service |
| Tenant ID enumeration | Random UUIDs |

### Authentication lifecycle

```
T=0:    Partner registers on Zuplo Developer Portal → receives API Key
T=1:    Partner requests certificate via portal (API Key auth)
T=2:    Partner configures mTLS client with issued certificate
T=3+:   All API calls use mTLS; API Key is no longer needed for protected routes
T=75d:  Certificate approaching expiry → partner renews via portal (mTLS + x5c)
T=90d:  Old certificate expires
```

---

## 9. Architecture Decision Records (ADRs)

### ADR-001: Developer Portal as certificate issuance entry point

**Decision:** Route all certificate requests through the Zuplo Developer Portal, not directly to the Certificate Service.

**Rationale:** Partners have a single, documented, self-service interface. The portal handles API Key management, tracks certificate status, and provides a guided onboarding experience. The Certificate Service remains an internal implementation detail.

### ADR-002: API Key for bootstrap, mTLS for everything else

**Decision:** API Key authentication only for the certificate issuance bootstrap flow; mTLS for all subsequent operations.

**Rationale:** Solves the chicken-and-egg problem (you need a cert to use mTLS, but you need mTLS to get a cert). API Keys have limited scope and short lifetime; they are superseded by the issued certificate.

### ADR-003: Step-CA vs. HashiCorp Vault PKI

**Decision:** Use Step-CA as the primary CA.

**Rationale:** Exclusively focused on PKI, simpler to operate, open-source. Vault PKI is better suited when Vault is already part of the stack.

### ADR-004: 90-day TTL for partner certificates

**Decision:** Maximum TTL of 90 days, automatic renewal at 25% of remaining TTL.

**Rationale:** Aligns with Let's Encrypt / CA/Browser Forum practices. Limits exposure window for a compromised key.
