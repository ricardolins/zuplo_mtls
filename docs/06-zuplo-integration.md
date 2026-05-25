# 06 — Integração com Zuplo

## Visão geral

O Zuplo atua como **API Gateway de entrada** para todas as APIs protegidas por mTLS. Ele:

1. **Recebe** requisições HTTPS com certificado de cliente (mTLS)
2. **Valida** o certificado via política customizada
3. **Injeta** a identidade do certificado nos headers da requisição
4. **Encaminha** para o backend (Certificate Service ou APIs downstream)
5. **Documenta** via Developer Portal integrado

## Arquitetura Zuplo + Ingress NGINX

```
Internet
    │
    ▼ HTTPS (porta 443)
NodeBalancer (Linode LB)
    │
    ▼
Ingress NGINX
    │  ssl_passthrough=false
    │  nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
    │  nginx.ingress.kubernetes.io/auth-tls-secret: "pki-system/step-ca-root-cert"
    │  Injeta headers: X-Client-Cert, X-Client-Cert-DN, X-Client-Cert-Serial
    │
    ▼
Zuplo Gateway (runtime)
    │  Política: mtls-inbound-policy (lê headers injetados)
    │  Política: cert-validation-policy (valida CN, OCSP)
    │  Política: rate-limit-policy
    │
    ▼
Backend Service
```

## 1. Criar projeto Zuplo

1. Acesse https://portal.zuplo.com
2. Crie novo projeto: **"baas-mtls-gateway"**
3. Ambiente: Production → apontar para `api.zuplo.baas.io`

## 2. Configurar variáveis de ambiente

No painel Zuplo > Settings > Environment Variables:

| Variável | Valor |
|----------|-------|
| `CERT_SERVICE_URL` | `http://certificate-service-svc.certificate-service` |
| `CA_FINGERPRINT` | fingerprint da Root CA |
| `OCSP_URL` | `http://step-ca-svc.pki-system:8080` |

## 3. Adicionar políticas ao projeto

Copie os arquivos de [zuplo/policies/](../zuplo/policies/) para o seu projeto Zuplo:

```
zuplo/
├── policies/
│   ├── mtls-policy.ts             → política principal mTLS
│   └── cert-validation-policy.ts  → validação CN + OCSP
└── routes.oas.json                → rotas com políticas aplicadas
```

## 4. Configurar política mTLS no Developer Portal

No arquivo `zuplo.jsonc` do projeto:

```jsonc
{
  "policies": [
    {
      "name": "mtls-inbound-policy",
      "policyType": "custom-code-inbound",
      "handler": {
        "export": "mtlsInboundPolicy",
        "module": "$import(./policies/mtls-policy)"
      }
    },
    {
      "name": "cert-validation-policy",
      "policyType": "custom-code-inbound",
      "handler": {
        "export": "certValidationPolicy",
        "module": "$import(./policies/cert-validation-policy)",
        "options": {
          "allowedCommonNames": ["*.api.baas.io"],
          "checkOcsp": true,
          "ocspUrl": "$env(OCSP_URL)"
        }
      }
    },
    {
      "name": "rate-limit-policy",
      "policyType": "rate-limit-inbound",
      "handler": {
        "rateLimitBy": "header",
        "headerName": "X-Authenticated-CN",
        "requestsAllowed": 1000,
        "timeWindowMinutes": 1
      }
    }
  ]
}
```

## 5. Developer Portal (Zuplo)

O Zuplo gera automaticamente um Developer Portal com:

- Documentação OpenAPI das rotas
- Playground para testar requisições
- Guias de onboarding para parceiros

### Customizar o portal

```
zuplo/
└── docs/
    ├── index.md           → página inicial do portal
    ├── authentication.md  → guia de mTLS para parceiros
    └── quickstart.md      → primeiros passos
```

### URL do Developer Portal

Após deploy: `https://baas-mtls-gateway.zuplo.io`

## 6. Testar no Zuplo

```bash
# Sem certificado — deve retornar 401
curl https://baas-mtls-gateway.zuplo.io/v1/certificates

# Com certificado válido — deve retornar 200
curl --cert ./certs-output/client.crt \
     --key  ./certs-output/client.key \
     https://baas-mtls-gateway.zuplo.io/v1/certificates
```

## 7. Configuração mTLS no Ingress NGINX

O Ingress NGINX precisa ter o CA bundle para validar o certificado do cliente:

```bash
# Criar Secret com o CA bundle no namespace pki-system
kubectl create secret generic step-ca-root-cert \
  --namespace pki-system \
  --from-file=ca.crt=./root_ca.crt

# Verificar a configuração
kubectl get ingress certificate-service-ingress -n certificate-service -o yaml
```

### Annotations críticas no Ingress

```yaml
nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
# "on"       = mTLS obrigatório
# "optional" = mTLS opcional (permite requisições sem cert)
# "off"      = desabilita mTLS

nginx.ingress.kubernetes.io/auth-tls-secret: "pki-system/step-ca-root-cert"
nginx.ingress.kubernetes.io/auth-tls-verify-depth: "2"
nginx.ingress.kubernetes.io/auth-tls-pass-certificate-to-upstream: "true"
# Injeta o cert como header X-Client-Cert para o Zuplo processar
```

## 8. Headers injetados pelo Ingress

Após validação do mTLS pelo Ingress NGINX, os seguintes headers chegam ao Zuplo:

| Header | Valor exemplo |
|--------|--------------|
| `X-Client-Cert` | PEM URL-encoded do certificado |
| `X-Client-Cert-DN` | `CN=parceiro-a.api.baas.io,O=Parceiro A` |
| `X-Client-Cert-Serial` | `3a:f2:...` |
| `X-Client-Cert-Expiry` | `Dec 31 23:59:59 2025 GMT` |
| `X-Client-Cert-Issuer` | `CN=BaaS mTLS Intermediate CA` |

A política `mtls-inbound-policy.ts` lê esses headers e injeta `X-Authenticated-CN` para uso nos backends.
