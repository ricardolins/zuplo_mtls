# mTLS BaaS Platform — Zuplo + Linode Kubernetes

A **Mutual TLS (mTLS) as a Service** platform inspired by the Banking as a Service (BaaS) model, integrating:

- **Step-CA (Smallstep)** — Open-source, enterprise-grade Certificate Authority
- **cert-manager** — Kubernetes-native certificate lifecycle management
- **Zuplo** — Developer Portal (certificate request UI) + API Gateway (mTLS enforcement)
- **Linode LKE** — Kubernetes Enterprise infrastructure
- **Terraform** — Infrastructure as Code (IaC)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          PARTNER / FINTECH                               │
│                                                                         │
│  FIRST TIME ONLY                          ONGOING API CALLS             │
│  ─────────────────────                    ────────────────────          │
│  1. Open Developer Portal                 3. Configure HTTP client      │
│  2. Register → get API Key                   with cert + private key    │
│     → fill cert form                      4. Call APIs via mTLS         │
│     → download certificate                                              │
└──────────────┬───────────────────────────────────┬──────────────────────┘
               │ HTTPS + API Key                   │ HTTPS + mTLS
               │ (bootstrap only)                  │ (all API calls)
               ▼                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          ZUPLO PLATFORM                                  │
│                                                                         │
│  ┌─────────────────────────────┐   ┌─────────────────────────────────┐  │
│  │      DEVELOPER PORTAL       │   │          API GATEWAY            │  │
│  │                             │   │                                 │  │
│  │  • Partner self-onboarding  │   │  /v1/certificates  (API Key)   │  │
│  │  • Certificate request form │   │  /v1/api/*         (mTLS)      │  │
│  │  • Certificate status view  │   │                                 │  │
│  │  • API documentation        │   │  Policies:                      │  │
│  │  • API Key management       │   │  • api-key-policy (bootstrap)   │  │
│  │                             │   │  • mtls-policy (ongoing)        │  │
│  │  Calls gateway for all      │   │  • cert-validation-policy       │  │
│  │  API operations             │   │  • rate-limit-policy            │  │
│  └─────────────────────────────┘   └─────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                           │
                                           ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      LINODE KUBERNETES ENGINE (LKE)                      │
│                                                                         │
│  ┌─────────────────────┐   ┌──────────────────┐   ┌─────────────────┐  │
│  │  Certificate Service│   │  Step-CA          │   │  Prometheus +   │  │
│  │  REST API           │──►│  (Root + Inter CA)│   │  Grafana        │  │
│  └─────────────────────┘   └──────────────────┘   └─────────────────┘  │
│  cert-manager + step-issuer  (Kubernetes certificate lifecycle)         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Authentication Model

| Stage | Authentication | How |
|-------|---------------|-----|
| Register tenant | None | Public endpoint, rate limited |
| Request certificate | **API Key** | From Developer Portal after signup |
| All subsequent API calls | **mTLS** | Client certificate issued in previous step |
| Renew certificate | **mTLS** | x5c provisioner (current cert proves identity) |
| Revoke certificate | **mTLS** | Presents current active certificate |

This solves the **bootstrap problem**: you need a certificate to use mTLS, so the first certificate is obtained using an API Key from the Developer Portal.

---

## Repository Structure

```
zuplo_mtls/
├── README.md                      # This file
├── ARCHITECTURE.md                # Detailed architecture + ADRs
├── .gitignore
├── docs/
│   ├── 01-overview.md            # Concepts: mTLS, PKI, X.509
│   ├── 03-linode-kubernetes.md   # LKE setup + cost estimate
│   ├── 04-step-ca-setup.md       # CA initialization + operations
│   ├── 06-zuplo-integration.md   # Portal + Gateway configuration
│   ├── 08-baas-flow.md           # Full partner journey with diagrams
│   └── 09-monitoring.md          # Prometheus, Grafana, alerts
├── infrastructure/terraform/      # IaC for Linode LKE
├── kubernetes/                    # K8s manifests + Helm values
├── zuplo/
│   ├── routes.oas.json           # OpenAPI routes (API Key + mTLS tiers)
│   └── policies/
│       ├── api-key-policy.ts     # Bootstrap: validates X-API-Key
│       ├── mtls-policy.ts        # Ongoing: validates client certificate
│       └── cert-validation-policy.ts  # CN allowlist + OCSP check
├── certificate-service/           # Internal API (Node.js/TypeScript)
├── scripts/                       # Operational scripts
└── examples/                      # curl, Node.js client, Postman
```

---

## Prerequisites

| Tool | Min version | Purpose |
|------|-------------|---------|
| `terraform` | >= 1.5 | LKE provisioning |
| `kubectl` | >= 1.28 | Kubernetes management |
| `helm` | >= 3.12 | Chart deployment |
| `step` CLI | >= 0.24 | CA management |
| `openssl` | >= 3.0 | Certificate operations |
| `jq` | >= 1.6 | JSON processing |

---

## Quick Start

### 1. Provision Linode infrastructure

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Linode token
terraform init && terraform apply
```

### 2. Bootstrap the cluster

```bash
export KUBECONFIG=.kubeconfig-lke
./scripts/bootstrap-cluster.sh
```

### 3. Initialize the CA

```bash
./scripts/setup-ca.sh
```

### 4. Partner onboarding (via Zuplo Developer Portal)

```
1. Partner opens https://baas-mtls-gateway.zuplo.io
2. Registers → receives API Key
3. Fills certificate request form
4. Downloads certificate + private key
5. Configures mTLS client
```

### 5. Issue a test certificate (CLI)

```bash
./scripts/issue-cert.sh \
  --tenant-id "tenant-001" \
  --common-name "partner.api.baas.io" \
  --org "Financial Partner Inc"
```

### 6. Test mTLS

```bash
./scripts/test-mtls.sh
```

---

## Documentation

- [Overview and Concepts](docs/01-overview.md)
- [Linode Kubernetes Setup](docs/03-linode-kubernetes.md)
- [Step-CA Configuration](docs/04-step-ca-setup.md)
- [Zuplo Integration (Portal + Gateway)](docs/06-zuplo-integration.md)
- [Full BaaS Flow](docs/08-baas-flow.md)
- [Observability](docs/09-monitoring.md)

---

## Security

- Root CA private key generated offline (air-gapped), never in cluster
- Intermediate CA on cluster with 1-year validity, auto-renewed by cert-manager
- Partner certificates: 90-day TTL, renewable via mTLS (x5c)
- API Keys: bootstrap only, scoped to one tenant, replaceable from Developer Portal
- CRL + OCSP for real-time revocation status
- All secrets in Kubernetes Secrets (encrypted at rest)

---

## License

MIT — see [LICENSE](LICENSE)
