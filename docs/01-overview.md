# 01 — Visão Geral e Conceitos

## O que esta plataforma entrega

Esta plataforma implementa **mTLS como Serviço** no modelo BaaS, permitindo que fintechs e parceiros:

1. **Obtenham certificados X.509** assinados por uma CA confiável via API REST
2. **Autentiquem-se mutuamente** ao chamar APIs críticas (sem usuário/senha no payload)
3. **Gerenciem o ciclo de vida** dos certificados (emissão, renovação, revogação)
4. **Integrem ao Developer Portal** do Zuplo para documentação e onboarding

## Componentes e versões

| Componente | Versão | Função |
|-----------|--------|--------|
| **Step-CA** (Smallstep) | 0.26+ | Autoridade Certificadora |
| **cert-manager** | v1.14+ | Gestão de certificados no K8s |
| **step-issuer** | 0.7+ | Integração cert-manager ↔ Step-CA |
| **Zuplo** | latest | API Gateway + Developer Portal |
| **Linode LKE** | K8s 1.29 | Infraestrutura Kubernetes |
| **Terraform** | 1.5+ | Infraestrutura como Código |
| **Helm** | 3.12+ | Deploy de charts no K8s |
| **Ingress NGINX** | 1.9+ | Ingress controller com mTLS passthrough |

## Conceitos-chave

### PKI (Public Key Infrastructure)
Infraestrutura de chaves públicas — conjunto de políticas, procedimentos, hardware, software e pessoas necessários para criar, gerenciar, distribuir, usar, armazenar e revogar certificados digitais.

### X.509
Padrão de certificados digitais usado em TLS. Define a estrutura do certificado: quem emitiu (Issuer), para quem (Subject), período de validade, chave pública, extensões e assinatura digital.

### CSR (Certificate Signing Request)
Pedido de emissão de certificado. O requerente gera um par de chaves, cria um CSR com sua chave pública e dados de identidade, e envia para a CA assinar.

### CA (Certificate Authority)
Entidade confiável que assina certificados. Sua assinatura garante a autenticidade do certificado.

### mTLS x TLS

| | TLS | mTLS |
|-|-----|------|
| Servidor apresenta cert | Sim | Sim |
| Cliente apresenta cert | Não | Sim |
| Autenticação bidirecional | Não | Sim |
| Uso típico | HTTPS público | API B2B, serviços internos |

### Provisioner (Step-CA)
Mecanismo de autenticação que autoriza a emissão de certificados na CA. Nesta plataforma usamos:
- **JWK**: para o cert-manager emitir certificados internos
- **ACME**: para renovação automática
- **x5c**: para emissão usando um certificado de cliente existente

## Fluxo de confiança

```
Zuplo confia na Root CA
    ↓
Root CA assinou a Intermediate CA
    ↓
Intermediate CA assinou o certificado do parceiro
    ↓
Zuplo valida: "Este certificado foi emitido por alguém em quem confio"
    ↓
Parceiro autenticado → requisição processada
```

## Diferencial em relação a API Keys

| | API Key | mTLS |
|-|---------|------|
| Pode ser vazada no código | Sim | Não (chave privada nunca sai do cliente) |
| Revogação imediata | Não (depende de rotação) | Sim (CRL/OCSP) |
| Identidade forte | Não (quem tiver a key pode usar) | Sim (precisa da chave privada) |
| Auditoria | Parcial | Completa (CN no log) |
| Overhead no request | Zero | ~1ms (handshake TLS) |
