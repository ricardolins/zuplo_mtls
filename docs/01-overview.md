# 01 — Overview and Concepts

## What this platform delivers

This platform implements **mTLS as a Service** in the BaaS model, enabling fintechs and partners to:

1. **Obtain X.509 certificates** signed by a trusted CA via REST API
2. **Mutually authenticate** when calling critical APIs (no username/password in the payload)
3. **Manage the certificate lifecycle** (issuance, renewal, revocation)
4. **Integrate with Zuplo's Developer Portal** for documentation and onboarding

## Components and versions

| Component | Version | Role |
|-----------|---------|------|
| **Step-CA** (Smallstep) | 0.26+ | Certificate Authority |
| **cert-manager** | v1.14+ | K8s certificate lifecycle management |
| **step-issuer** | 0.7+ | cert-manager ↔ Step-CA integration |
| **Zuplo** | latest | API Gateway + Developer Portal |
| **Linode LKE** | K8s 1.29 | Kubernetes infrastructure |
| **Terraform** | 1.5+ | Infrastructure as Code |
| **Helm** | 3.12+ | Kubernetes chart deployment |
| **Ingress NGINX** | 1.9+ | Ingress controller with mTLS passthrough |

## Key Concepts

### PKI (Public Key Infrastructure)
The set of policies, procedures, hardware, software, and people needed to create, manage, distribute, use, store, and revoke digital certificates.

### X.509
The standard for digital certificates used in TLS. Defines the certificate structure: who issued it (Issuer), to whom (Subject), validity period, public key, extensions, and digital signature.

### CSR (Certificate Signing Request)
A certificate issuance request. The requester generates a key pair, creates a CSR with their public key and identity data, and sends it to the CA for signing.

### CA (Certificate Authority)
A trusted entity that signs certificates. Its signature guarantees the authenticity of the certificate.

### mTLS vs TLS

| | TLS | mTLS |
|-|-----|------|
| Server presents cert | Yes | Yes |
| Client presents cert | No | Yes |
| Mutual authentication | No | Yes |
| Typical use | Public HTTPS | B2B APIs, internal services |

### Provisioner (Step-CA)
An authentication mechanism that authorizes certificate issuance on the CA. This platform uses:
- **JWK**: for cert-manager to issue internal certificates
- **ACME**: for automatic renewal
- **x5c**: for issuance using an existing client certificate

## Trust chain

```
Zuplo trusts the Root CA
    ↓
Root CA signed the Intermediate CA
    ↓
Intermediate CA signed the partner's certificate
    ↓
Zuplo validates: "This certificate was issued by someone I trust"
    ↓
Partner authenticated → request processed
```

## Advantage over API Keys

| | API Key | mTLS |
|-|---------|------|
| Can be leaked in code | Yes | No (private key never leaves the client) |
| Immediate revocation | No (requires rotation) | Yes (CRL/OCSP) |
| Strong identity | No (anyone with the key can use it) | Yes (requires private key) |
| Auditing | Partial | Full (CN in every log line) |
| Per-request overhead | Zero | ~1ms (TLS handshake) |
