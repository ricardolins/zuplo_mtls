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

## 2. Certificate Hierarchy (PKI)

```
Root CA (offline / air-gapped)
│   Validity: 10 years
│   Key: RSA 4096 or ECDSA P-384
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
    │       SAN: tenant-a.api.baas.io
    │
    ├── Leaf Certificate — Tenant B
    │       CN: tenant-b.api.baas.io
    │       Validity: 90 days
    │
    └── Leaf Certificate — Tenant C (revoked)
            Status: REVOKED (CRL entry)
```

### Why keep the Root CA offline?

The Root CA must never be network-accessible. If compromised, the entire trust hierarchy is invalidated. The secure process is:

1. Generate Root CA on an air-gapped machine (no network)
2. Manually sign the Intermediate CA
3. Load only the Intermediate CA certificate into the cluster
4. Store the Root CA private key on secure offline media (HSM, encrypted USB)

---

## 3. Platform Components

### 3.1 Step-CA (Smallstep Certificate Authority)

**Why Step-CA?**
- Open-source, battle-tested, used by large organizations
- Supports ACME, JWK, x5c, SCEP, OAuth/OIDC
- Native REST API for automation
- Configurable provisioners per tenant
- Built-in CRL and OCSP

**Cluster configuration:**
```
Namespace: pki-system
Deployment: step-ca
Service: step-ca-svc:9000 (cluster-internal)
PVC: step-ca-data (state storage)
Secret: step-ca-password (CA password)
ConfigMap: step-ca-config (ca.json configuration)
```

### 3.2 cert-manager

**Responsibility:** Manage the Kubernetes-native certificate lifecycle.

- Automatically renews certificates before expiry
- Integrates with Step-CA via `StepIssuer` (CRD)
- Issues certificates for internal cluster services (ingress, services)
- Creates `Certificate` resources consumed as Secrets

### 3.3 Certificate Service API

**REST API** (Node.js/TypeScript) exposing PKI operations to partners:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `POST /v1/certificates` | POST | Issue new certificate for tenant |
| `GET /v1/certificates/{id}` | GET | Get certificate details |
| `DELETE /v1/certificates/{id}` | DELETE | Revoke certificate |
| `GET /v1/certificates` | GET | List tenant certificates |
| `POST /v1/certificates/{id}/renew` | POST | Renew certificate |
| `GET /v1/health` | GET | Health check |

### 3.4 Zuplo API Gateway

**Responsibility:** Entry point for mTLS-protected APIs.

```
┌─────────────────────────────────────────────────────────┐
│                  ZUPLO PIPELINE                          │
│                                                          │
│  Request ──► [mTLS Policy] ──► [Rate Limit] ──► Backend │
│                    │                                      │
│              [Cert Validate]                             │
│              - Signed by trusted CA?                     │
│              - Within validity period?                   │
│              - Not revoked (CRL/OCSP)?                   │
│              - CN in allowlist?                          │
└─────────────────────────────────────────────────────────┘
```

---

## 4. Kubernetes Infrastructure (Linode LKE)

### Cluster Topology

```
┌─────────────────────────────────────────────────────────────────┐
│  LKE Cluster — region: us-east (Newark)                         │
│                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌───────────────┐   │
│  │  Node Pool: PKI │  │  Node Pool: App │  │  Node Pool:   │   │
│  │  2x Dedicated   │  │  3x Standard    │  │  Monitoring   │   │
│  │  g6-dedicated-2 │  │  g6-standard-4  │  │  1x Standard  │   │
│  │  (4 vCPU, 8GB)  │  │  (4 vCPU, 8GB) │  │  g6-standard-2│   │
│  └─────────────────┘  └─────────────────┘  └───────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Namespaces                                              │    │
│  │  ├── pki-system     (step-ca, cert-manager)             │    │
│  │  ├── certificate-service  (REST API)                    │    │
│  │  ├── monitoring     (prometheus, grafana)               │    │
│  │  └── ingress-nginx  (ingress controller)                │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  NodeBalancer (Linode LB) ──► Ingress NGINX ──► Services        │
└─────────────────────────────────────────────────────────────────┘
```

### Node Pools

| Pool | Linode Type | vCPU | RAM | Purpose |
|------|-------------|------|-----|---------|
| pki | g6-dedicated-2 | 4 | 8GB | Step-CA, cert-manager |
| app | g6-standard-4 | 4 | 8GB | Certificate Service API (x3) |
| monitoring | g6-standard-2 | 2 | 4GB | Prometheus + Grafana |

### Why Dedicated Nodes for PKI?

Cryptographic operations (key generation, signing) are CPU-intensive. Dedicated nodes guarantee that other workloads do not cause latency in CA operations.

---

## 5. BaaS Partner Onboarding Flow

```
Partner (Fintech)          Certificate Service          Step-CA
       │                          │                         │
       │  1. Request onboarding   │                         │
       │──POST /v1/tenants ──────►│                         │
       │                          │ 2. Validate tenant data │
       │◄── {tenant_id} ──────────│                         │
       │                          │                         │
       │  3. Request mTLS cert    │                         │
       │──POST /v1/certificates──►│                         │
       │  Body: {cn, org, ttl}    │                         │
       │                          │ 4. Generate CSR         │
       │                          │──sign(CSR)─────────────►│
       │                          │◄── signed cert ─────────│
       │                          │                         │
       │  5. Certificate delivered│                         │
       │◄── {cert_pem, chain_pem, │                         │
       │     private_key_pem,     │                         │
       │     cert_id, expires_at} │                         │
       │                          │                         │
       │  6. Configure mTLS client│                         │
       │     (store cert + key)   │                         │
       │                          │                         │
       │  7. Call API via mTLS    │                         │
       │──TLS Handshake (cert)──────────────────────────────────►Zuplo
       │◄────────────────────────────────────────────────────────────│
```

---

## 6. Security and Compliance

### Threat Model

| Threat | Mitigation |
|--------|-----------|
| Root CA private key compromised | Root CA offline, never in cluster |
| Partner certificate compromised | Immediate revocation via CRL/OCSP |
| Unauthorized CA API access | Strong authentication for operators |
| Man-in-the-middle | mTLS on all communications |
| Replay attack | Short certificate TTL (90 days) |
| Tenant ID enumeration | Random UUIDs, non-sequential |

### Certificate Rotation

```
T=0:   Certificate issued (TTL=90d)
T=75d: cert-manager detects < 25% TTL remaining → requests renewal
T=77d: New certificate issued
T=80d: Partner notified via webhook
T=90d: Original certificate expires
```

### CRL and OCSP

- **CRL**: Revocation list published every 24h at the `/crl` endpoint
- **OCSP**: Real-time response via Step-CA (endpoint `/ocsp`)
- Zuplo checks OCSP on every request (5-minute cache)

---

## 7. Observability

### Metrics (Prometheus)

| Metric | Description |
|--------|-------------|
| `mtls_certificates_issued_total` | Total certificates issued |
| `mtls_certificates_revoked_total` | Total certificates revoked |
| `mtls_tls_handshake_errors_total` | mTLS handshake errors at Zuplo |
| `mtls_cert_expiry_seconds` | Time until expiry (per tenant) |
| `step_ca_sign_duration_seconds` | CA signing latency |

### Alerts

- `CertExpiryWarning`: certificate expires in < 15 days without renewal
- `CARootExpiry`: Root CA expires in < 180 days
- `HighRevocationRate`: > 10 revocations in 1h (possible incident)
- `CAUnavailable`: Step-CA unresponsive for > 30s

---

## 8. Architecture Decision Records (ADRs)

### ADR-001: Step-CA vs. HashiCorp Vault PKI

**Decision:** Use Step-CA as the primary CA.

**Rationale:** Step-CA is exclusively focused on PKI, simpler to operate, open-source with no enterprise lock-in. Vault PKI is better suited when Vault is already part of the stack.

**Trade-off:** Vault offers richer integration with general secrets management. Step-CA can be integrated with Vault as a storage backend in the future.

### ADR-002: cert-manager vs. manual operations

**Decision:** Use cert-manager for Kubernetes-native certificates.

**Rationale:** Automated renewal eliminates the risk of expired certificates on internal services.

### ADR-003: ECDSA P-256 vs. RSA 2048 for leaf certs

**Decision:** ECDSA P-256 for Intermediate CA and leaf certs.

**Rationale:** Equivalent security to RSA 3072 with smaller keys (64 bytes vs. 256 bytes) and faster TLS handshakes.

### ADR-004: 90-day TTL for partner certificates

**Decision:** Maximum TTL of 90 days, automatic renewal at 25% of remaining TTL.

**Rationale:** Aligns with Let's Encrypt / CA/Browser Forum practices. Limits the exposure window for a compromised key.

---

## 9. Runbooks

### Issue an emergency certificate

```bash
./scripts/issue-cert.sh \
  --tenant-id TENANT_UUID \
  --common-name CN \
  --ttl 24h \
  --emergency
```

### Revoke a compromised certificate

```bash
./scripts/revoke-cert.sh --cert-id CERT_UUID --reason keyCompromise
# Force immediate CRL update:
kubectl exec -n pki-system deploy/step-ca -- step ca revoke --offline
```

### Renew the Intermediate CA

```bash
# cert-manager does this automatically.
# If it fails, trigger manually:
kubectl delete secret step-ca-intermediate-cert -n pki-system
# cert-manager will recreate it automatically via CertificateRequest
```
