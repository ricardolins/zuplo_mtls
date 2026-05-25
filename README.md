# mTLS BaaS Platform — Zuplo + Linode Kubernetes

Plataforma de **Mutual TLS (mTLS) como Serviço** inspirada no modelo Banking as a Service (BaaS), integrando:

- **Step-CA (Smallstep)** — Autoridade Certificadora (CA) open-source enterprise-grade
- **cert-manager** — Gerenciamento nativo de certificados no Kubernetes
- **Zuplo** — API Gateway com enforcement de mTLS e Developer Portal
- **Linode LKE** — Kubernetes Enterprise como infraestrutura
- **Terraform** — Infraestrutura como Código (IaC)

---

## Visão Geral da Arquitetura

```
┌─────────────────────────────────────────────────────────────────────┐
│                        CLIENTE / PARCEIRO BaaS                      │
│                                                                      │
│   1. Requisita certificado via REST API                             │
│   2. Recebe certificado assinado pela CA                            │
│   3. Usa certificado para chamadas mTLS ao gateway                  │
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
│  Developer Portal: documentação, onboarding, gestão de chaves       │
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

## Fluxo BaaS de Emissão de Certificado

```
Parceiro          Certificate Service      Step-CA           Zuplo
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

## Estrutura do Repositório

```
zuplo_mtls/
├── README.md                      # Este arquivo
├── ARCHITECTURE.md                # Arquitetura detalhada
├── .gitignore
├── docs/
│   ├── 01-overview.md            # Visão geral e conceitos
│   ├── 02-pki-design.md          # Design da PKI (Root CA, Inter CA)
│   ├── 03-linode-kubernetes.md   # Setup do LKE
│   ├── 04-step-ca-setup.md       # Configuração da CA
│   ├── 05-cert-manager-setup.md  # cert-manager no K8s
│   ├── 06-zuplo-integration.md   # Integração com Zuplo
│   ├── 07-certificate-lifecycle.md # Ciclo de vida dos certificados
│   ├── 08-baas-flow.md           # Fluxo BaaS completo
│   └── 09-monitoring.md          # Observabilidade
├── infrastructure/
│   └── terraform/                # IaC para Linode LKE
│       ├── main.tf
│       ├── providers.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── modules/
│           ├── lke-cluster/
│           └── networking/
├── kubernetes/
│   ├── namespaces/               # Definições de namespaces
│   ├── cert-manager/             # Helm values + ClusterIssuer
│   ├── step-ca/                  # Deploy da CA
│   ├── certificate-service/      # API de certificados
│   └── monitoring/               # Prometheus + Grafana
├── zuplo/
│   ├── routes.oas.json           # OpenAPI routes
│   └── policies/                 # Políticas mTLS
├── certificate-service/          # API Node.js/TypeScript
│   ├── src/
│   ├── Dockerfile
│   └── package.json
├── scripts/
│   ├── bootstrap-cluster.sh      # Setup inicial do cluster
│   ├── setup-ca.sh               # Inicializa a CA
│   ├── issue-cert.sh             # Emite certificado manualmente
│   ├── revoke-cert.sh            # Revoga certificado
│   └── test-mtls.sh              # Testa conexão mTLS
└── examples/
    ├── client-curl/              # Exemplos com curl
    ├── client-node/              # Cliente Node.js com mTLS
    └── postman/                  # Collection Postman
```

---

## Pré-requisitos

| Ferramenta | Versão mínima | Finalidade |
|-----------|---------------|-----------|
| `terraform` | >= 1.5 | Provisionamento LKE |
| `kubectl` | >= 1.28 | Gerenciamento K8s |
| `helm` | >= 3.12 | Deploy de charts |
| `step` CLI | >= 0.24 | Gerenciamento CA |
| `openssl` | >= 3.0 | Operações de certificado |
| `jq` | >= 1.6 | Processamento JSON |

---

## Quick Start

### 1. Provisionar infraestrutura no Linode

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars com seu token Linode
terraform init
terraform plan
terraform apply
```

### 2. Bootstrap do cluster Kubernetes

```bash
# Configurar kubeconfig
export KUBECONFIG=~/.kube/lke-mtls.yaml
terraform -chdir=infrastructure/terraform output -raw kubeconfig | base64 -d > $KUBECONFIG

# Bootstrap: instala cert-manager, step-ca, certificate-service
./scripts/bootstrap-cluster.sh
```

### 3. Inicializar a CA

```bash
./scripts/setup-ca.sh
```

### 4. Emitir um certificado de teste

```bash
./scripts/issue-cert.sh \
  --tenant-id "tenant-001" \
  --common-name "parceiro.baas.local" \
  --org "Parceiro Financeiro Ltda"
```

### 5. Testar mTLS com Zuplo

```bash
./scripts/test-mtls.sh
```

---

## Documentação Detalhada

- [Visão Geral e Conceitos](docs/01-overview.md)
- [Design da PKI](docs/02-pki-design.md)
- [Setup Linode Kubernetes](docs/03-linode-kubernetes.md)
- [Configuração Step-CA](docs/04-step-ca-setup.md)
- [cert-manager no Kubernetes](docs/05-cert-manager-setup.md)
- [Integração Zuplo](docs/06-zuplo-integration.md)
- [Ciclo de Vida dos Certificados](docs/07-certificate-lifecycle.md)
- [Fluxo BaaS Completo](docs/08-baas-flow.md)
- [Observabilidade](docs/09-monitoring.md)

---

## Segurança

- Chaves privadas da Root CA geradas offline (air-gapped) e armazenadas em Kubernetes Secrets (cifradas em repouso)
- Intermediate CA com validade de 1 ano, Root CA com validade de 10 anos
- Certificados de leaf com validade de 90 dias (padrão BaaS)
- CRL (Certificate Revocation List) e OCSP habilitados
- Todos os secrets gerenciados via Kubernetes Secrets + possibilidade de integração com HashiCorp Vault

---

## Licença

MIT — veja [LICENSE](LICENSE)
