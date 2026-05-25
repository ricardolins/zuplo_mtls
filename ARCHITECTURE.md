# Arquitetura mTLS BaaS — Documento Técnico

## 1. Conceitos Fundamentais

### O que é mTLS?

**mTLS (Mutual Transport Layer Security)** é uma extensão do TLS padrão onde **ambos os lados** — cliente e servidor — apresentam certificados X.509 para autenticação. No modelo BaaS:

- O **servidor** (Zuplo Gateway) apresenta seu certificado ao cliente (TLS padrão)
- O **cliente** (parceiro/fintech) apresenta seu certificado ao servidor (o "mutual")
- O gateway valida se o certificado do cliente foi assinado por uma CA confiável

```
Cliente                    Gateway (Zuplo)
  │                              │
  │──── ClientHello ────────────►│
  │◄─── ServerHello + Cert ──────│  servidor apresenta seu cert
  │──── ClientCert + Verify ────►│  cliente apresenta seu cert
  │◄─── Finished ────────────────│  handshake concluido
  │                              │  gateway validou cert do cliente
  │──── HTTP Request ───────────►│
  │◄─── HTTP Response ───────────│
```

### Por que usar no modelo BaaS?

| Benefício | Descrição |
|-----------|-----------|
| **Identidade forte** | Cada parceiro tem um certificado único e irrefutável |
| **Sem senha no payload** | A autenticação ocorre na camada TLS |
| **Revogação granular** | É possível revogar acesso de um parceiro sem afetar outros |
| **Auditoria** | O Common Name do certificado identifica o parceiro em todos os logs |
| **Zero-trust** | Alinha-se com arquiteturas zero-trust modernas |

---

## 2. Hierarquia de Certificados (PKI)

```
Root CA (offline / air-gapped)
│   Validade: 10 anos
│   Key: RSA 4096 ou ECDSA P-384
│   Armazenamento: HSM ou K8s Secret cifrado
│
└── Intermediate CA (online / Kubernetes)
    │   Validade: 1 ano (renovação automática via cert-manager)
    │   Key: ECDSA P-256
    │   Armazenamento: K8s Secret no namespace pki-system
    │
    ├── Leaf Certificate — Tenant A
    │       CN: tenant-a.api.baas.io
    │       Validade: 90 dias
    │       SAN: tenant-a.api.baas.io
    │
    ├── Leaf Certificate — Tenant B
    │       CN: tenant-b.api.baas.io
    │       Validade: 90 dias
    │
    └── Leaf Certificate — Tenant C (revogado)
            Status: REVOKED (CRL entry)
```

### Por que Root CA offline?

A Root CA nunca deve estar acessível pela rede. Se comprometida, toda a hierarquia de confiança é inválida. O processo seguro é:

1. Gerar Root CA em máquina air-gapped (sem rede)
2. Assinar a Intermediate CA manualmente
3. Carregar apenas o certificado da Intermediate CA no cluster
4. Manter a chave privada da Root CA em mídia física segura (HSM, USB criptografado)

---

## 3. Componentes da Plataforma

### 3.1 Step-CA (Smallstep Certificate Authority)

**Por que Step-CA?**
- Open-source, battle-tested, usado por grandes empresas
- Suporta ACME, JWK, x5c, SCEP, OAuth/OIDC
- API REST nativa para automação
- Provisionadores configuráveis por tenant
- CRL e OCSP out-of-the-box

**Configuração no cluster:**
```
Namespace: pki-system
Deployment: step-ca
Service: step-ca-svc:9000 (interno ao cluster)
PVC: step-ca-data (armazenamento de estado)
Secret: step-ca-password (senha da CA)
ConfigMap: step-ca-config (configuração ca.json)
```

### 3.2 cert-manager

**Responsabilidade:** Gerenciar o ciclo de vida dos certificados Kubernetes nativamente.

- Renova automaticamente certificados antes do vencimento
- Integra com Step-CA via `StepIssuer` (CRD)
- Emite certificados para serviços internos do cluster (ingress, serviços)
- Cria `Certificate` resources que são consumidos como Secrets

### 3.3 Certificate Service API

**REST API** (Node.js/TypeScript) que expõe operações de PKI para parceiros:

| Endpoint | Método | Descrição |
|----------|--------|-----------|
| `POST /v1/certificates` | POST | Emite novo certificado para tenant |
| `GET /v1/certificates/{id}` | GET | Consulta certificado |
| `DELETE /v1/certificates/{id}` | DELETE | Revoga certificado |
| `GET /v1/certificates` | GET | Lista certificados do tenant |
| `POST /v1/certificates/{id}/renew` | POST | Renova certificado |
| `GET /v1/health` | GET | Health check |

### 3.4 Zuplo API Gateway

**Responsabilidade:** Ponto de entrada para APIs protegidas por mTLS.

```
┌─────────────────────────────────────────────────────────┐
│                  ZUPLO PIPELINE                          │
│                                                          │
│  Request ──► [mTLS Policy] ──► [Rate Limit] ──► Backend │
│                    │                                      │
│              [Cert Validate]                             │
│              - Assinado pela CA?                         │
│              - Dentro da validade?                       │
│              - Nao revogado (CRL/OCSP)?                  │
│              - CN na allowlist?                          │
└─────────────────────────────────────────────────────────┘
```

---

## 4. Infraestrutura Kubernetes (Linode LKE)

### Topologia do Cluster

```
┌─────────────────────────────────────────────────────────────────┐
│  LKE Cluster — regiao: us-east (Newark)                         │
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
│  │  ├── certificate-service  (API REST)                    │    │
│  │  ├── monitoring     (prometheus, grafana)               │    │
│  │  └── ingress-nginx  (ingress controller)                │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  NodeBalancer (Linode LB) ──► Ingress NGINX ──► Services        │
└─────────────────────────────────────────────────────────────────┘
```

### Node Pools

| Pool | Tipo Linode | vCPU | RAM | Propósito |
|------|-------------|------|-----|-----------|
| pki | g6-dedicated-2 | 4 | 8GB | Step-CA, cert-manager |
| app | g6-standard-4 | 4 | 8GB | Certificate Service API (x3) |
| monitoring | g6-standard-2 | 2 | 4GB | Prometheus + Grafana |

### Por que Dedicated para PKI?

Operações criptográficas (geração de chaves, assinatura) são CPU-intensivas. Nós dedicados garantem que outros workloads não causem latência nas operações da CA.

---

## 5. Fluxo de Onboarding de Parceiro BaaS

```
Parceiro (Fintech)         Certificate Service          Step-CA
       │                          │                         │
       │  1. Solicita onboarding  │                         │
       │──POST /v1/tenants ──────►│                         │
       │                          │ 2. Valida dados         │
       │◄── {tenant_id} ──────────│                         │
       │                          │                         │
       │  3. Requisita cert mTLS  │                         │
       │──POST /v1/certificates──►│                         │
       │  Body: {cn, org, ttl}    │                         │
       │                          │ 4. Gera CSR             │
       │                          │──sign(CSR)─────────────►│
       │                          │◄── signed cert ─────────│
       │                          │                         │
       │  5. Certificado entregue │                         │
       │◄── {cert_pem, chain_pem, │                         │
       │     private_key_pem,     │                         │
       │     cert_id, expires_at} │                         │
       │                          │                         │
       │  6. Configura client mTLS│                         │
       │     (armazena cert + key)│                         │
       │                          │                         │
       │  7. Chama API via mTLS   │                         │
       │──TLS Handshake (cert)──────────────────────────────────►Zuplo
       │◄────────────────────────────────────────────────────────────│
```

---

## 6. Segurança e Compliance

### Modelo de Ameaças

| Ameaça | Mitigação |
|--------|-----------|
| Chave privada da Root CA comprometida | Root CA offline, nunca no cluster |
| Certificado de parceiro comprometido | Revogação imediata via CRL/OCSP |
| Acesso indevido à CA API | Autenticação forte para operadores |
| Man-in-the-middle | mTLS em todas as comunicações |
| Replay attack | Certificados com TTL curto (90 dias) |
| Enumeração de tenant IDs | UUIDs aleatórios, não sequenciais |

### Rotação de Certificados

```
T=0:   Certificado emitido (TTL=90d)
T=75d: cert-manager detecta < 25% TTL restante → solicita renovação
T=77d: Novo certificado emitido
T=80d: Parceiro notificado via webhook
T=90d: Certificado original expira
```

### CRL e OCSP

- **CRL**: Lista de revogação publicada a cada 24h no endpoint `/crl`
- **OCSP**: Resposta em tempo real via Step-CA (endpoint `/ocsp`)
- Zuplo verifica OCSP em cada requisição (cache de 5 min)

---

## 7. Observabilidade

### Métricas (Prometheus)

| Métrica | Descrição |
|---------|-----------|
| `mtls_certificates_issued_total` | Total de certificados emitidos |
| `mtls_certificates_revoked_total` | Total de certificados revogados |
| `mtls_tls_handshake_errors_total` | Erros de handshake mTLS no Zuplo |
| `mtls_cert_expiry_seconds` | Tempo até expiração (por tenant) |
| `step_ca_sign_duration_seconds` | Latência de assinatura na CA |

### Alertas

- `CertExpiryWarning`: certificado expira em < 15 dias sem renovação
- `CARootExpiry`: Root CA expira em < 180 dias
- `HighRevocationRate`: > 10 revogações em 1h (possível incidente)
- `CAUnavailable`: Step-CA sem resposta por > 30s

---

## 8. Decisões de Arquitetura (ADRs)

### ADR-001: Step-CA vs. HashiCorp Vault PKI

**Decisão:** Usar Step-CA como CA principal.

**Razão:** Step-CA é focado exclusivamente em PKI, mais simples de operar, open-source sem enterprise lock-in. Vault PKI é mais adequado quando Vault já é parte do stack.

**Trade-off:** Vault tem integração mais rica com secrets management geral. Step-CA pode ser integrado ao Vault como backend de storage futuramente.

### ADR-002: cert-manager vs. operações manuais

**Decisão:** Usar cert-manager para certificados Kubernetes-nativos.

**Razão:** Automação de renovação elimina riscos de certificados expirados em serviços internos.

### ADR-003: ECDSA P-256 vs. RSA 2048 para leaf certs

**Decisão:** ECDSA P-256 para Intermediate CA e leaf certs.

**Razão:** Equivalente em segurança ao RSA 3072, mas chaves menores (64 bytes vs. 256 bytes), handshake TLS mais rápido.

### ADR-004: TTL de 90 dias para certificados de parceiros

**Decisão:** TTL máximo de 90 dias, renovação automática a 25% do TTL restante.

**Razão:** Alinhamento com práticas Let's Encrypt. Limita janela de exposição de chave comprometida.

---

## 9. Runbooks

### Emitir certificado de emergência

```bash
./scripts/issue-cert.sh \
  --tenant-id TENANT_UUID \
  --common-name CN \
  --ttl 24h \
  --emergency
```

### Revogar certificado comprometido

```bash
./scripts/revoke-cert.sh --cert-id CERT_UUID --reason keyCompromise
# Forcar atualizacao da CRL imediatamente:
kubectl exec -n pki-system deploy/step-ca -- step ca revoke --offline
```

### Renovar Intermediate CA

```bash
# cert-manager faz isso automaticamente.
# Em caso de falha manual:
kubectl delete secret step-ca-intermediate-cert -n pki-system
# cert-manager recria automaticamente via CertificateRequest
```
