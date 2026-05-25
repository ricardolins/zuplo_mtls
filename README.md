# mTLS BaaS Platform — Zuplo + Linode Kubernetes

A **Mutual TLS (mTLS) as a Service** platform inspired by the Banking as a Service (BaaS) model, integrating:

- **Step-CA (Smallstep)** — Open-source, enterprise-grade Certificate Authority
- **cert-manager** — Kubernetes-native certificate lifecycle management
- **Zuplo** — API Gateway with mTLS enforcement and Developer Portal
- **Linode LKE** — Kubernetes Enterprise infrastructure
- **Terraform** — Infrastructure as Code (IaC)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        CLIENT / BaaS PARTNER                         │
│                                                                      │
│   1. Requests a certificate via REST API                            │
│   2. Receives a certificate signed by the CA                        │
│   3. Uses the certificate for mTLS calls to the gateway             │
└──────────────────────────┬──────────────────────────────────────────┘
                           │ HTTPS + mTLS
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    ZUPLO API GATEWAY                                 │
│                                                                      │
│  ┌─────────────────┐  ┌──────────────────┐  ┌──────────────────┐   │
│  │  mTLS Policy    │  │  Rate Limit      │  │  Auth Policy     │   │
│  │  (cert verify)  │  │  Policy          │  │  (JWT / API Key) │   │
│  └─────────────────┘  └──────────────────┘  └──────────────────┘   │
│                                                                      │
│  Developer Portal: documentation, onboarding, key management        │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│              LINODE KUBERNETES ENGINE (LKE)                          │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Namespace: pki-system                                       │    │
│  │                                                              │    │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │    │
│  │  │  Step-CA     │    │ cert-manager │    │  Certificate │   │    │
│  │  │  (Root CA +  │◄───│  (Issuer /   │    │  Service API │   │    │
│  │  │   Inter CA)  │    │   CertReq)   │    │  (REST API)  │   │    │
│  │  └──────────────┘    └──────────────┘    └──────────────┘   │    │
│  │                                                              │    │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │    │
│  │  │  PostgreSQL  │    │  Prometheus  │    │  Grafana     │   │    │
│  │  │  (cert store)│    │  (metrics)   │    │  (dashboard) │   │    │
│  │  └──────────────┘    └──────────────┘    └──────────────┘   │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## BaaS Certificate Issuance Flow

```
Partner           Certificate Service      Step-CA           Zuplo
   │                      │                   │                 │
   │──POST /certificates──►│                   │                 │
   │  {tenant_id, cn, org} │                   │                 │
   │                      │──sign_request─────►│                 │
   │                      │◄──signed_cert──────│                 │
   │◄──{cert, chain, key}──│                   │                 │
   │                      │                   │                 │
   │──── mTLS Request ────────────────────────────────────────►│
   │     (client cert)    │                   │   validate cert  │
   │                      │                   │◄────────────────│
   │                      │                   │─────────────────►│
   │◄── API Response ────────────────────────────────────────── │
```

---

## Repository Structure

```
zuplo_mtls/
├── README.md                      # This file
├── ARCHITECTURE.md                # Detailed architecture
├── .gitignore
├── docs/
│   ├── 01-overview.md            # Overview and concepts
│   ├── 02-pki-design.md          # PKI design (Root CA, Inter CA)
│   ├── 03-linode-kubernetes.md   # LKE setup
│   ├── 04-step-ca-setup.md       # CA configuration
│   ├── 05-cert-manager-setup.md  # cert-manager on K8s
│   ├── 06-zuplo-integration.md   # Zuplo integration
│   ├── 07-certificate-lifecycle.md # Certificate lifecycle
│   ├── 08-baas-flow.md           # Full BaaS flow
│   └── 09-monitoring.md          # Observability
├── infrastructure/
│   └── terraform/                # IaC for Linode LKE
│       ├── main.tf
│       ├── providers.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── modules/
│           ├── lke-cluster/
│           └── networking/
├── kubernetes/
│   ├── namespaces/               # Namespace definitions
│   ├── cert-manager/             # Helm values + ClusterIssuer
│   ├── step-ca/                  # CA deployment
│   ├── certificate-service/      # Certificate API
│   └── monitoring/               # Prometheus + Grafana
├── zuplo/
│   ├── routes.oas.json           # OpenAPI routes
│   └── policies/                 # mTLS policies
├── certificate-service/          # Node.js/TypeScript API
│   ├── src/
│   ├── Dockerfile
│   └── package.json
├── scripts/
│   ├── bootstrap-cluster.sh      # Initial cluster setup
│   ├── setup-ca.sh               # Initialize the CA
│   ├── issue-cert.sh             # Issue a certificate manually
│   ├── revoke-cert.sh            # Revoke a certificate
│   └── test-mtls.sh              # Test mTLS connection
└── examples/
    ├── client-curl/              # curl examples
    ├── client-node/              # Node.js mTLS client
    └── postman/                  # Postman collection
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
terraform init
terraform plan
terraform apply
```

### 2. Bootstrap the Kubernetes cluster

```bash
# Configure kubeconfig
export KUBECONFIG=~/.kube/lke-mtls.yaml
terraform -chdir=infrastructure/terraform output -raw kubeconfig | base64 -d > $KUBECONFIG

# Bootstrap: installs cert-manager, step-ca, certificate-service
./scripts/bootstrap-cluster.sh
```

### 3. Initialize the CA

```bash
./scripts/setup-ca.sh
```

### 4. Issue a test certificate

```bash
./scripts/issue-cert.sh \
  --tenant-id "tenant-001" \
  --common-name "partner.baas.local" \
  --org "Financial Partner Inc"
```

### 5. Test mTLS with Zuplo

```bash
./scripts/test-mtls.sh
```

---

## Documentation

- [Overview and Concepts](docs/01-overview.md)
- [PKI Design](docs/02-pki-design.md)
- [Linode Kubernetes Setup](docs/03-linode-kubernetes.md)
- [Step-CA Configuration](docs/04-step-ca-setup.md)
- [cert-manager on Kubernetes](docs/05-cert-manager-setup.md)
- [Zuplo Integration](docs/06-zuplo-integration.md)
- [Certificate Lifecycle](docs/07-certificate-lifecycle.md)
- [Full BaaS Flow](docs/08-baas-flow.md)
- [Observability](docs/09-monitoring.md)

---

## Security

- Root CA private keys generated offline (air-gapped) and stored in encrypted Kubernetes Secrets
- Intermediate CA with 1-year validity; Root CA with 10-year validity
- Leaf certificates with 90-day TTL (BaaS standard)
- CRL (Certificate Revocation List) and OCSP enabled
- All secrets managed via Kubernetes Secrets with optional HashiCorp Vault integration

---

## License

MIT — see [LICENSE](LICENSE)
