# 06 — Zuplo Integration

## Overview

Zuplo acts as the **entry-point API Gateway** for all mTLS-protected APIs. It:

1. **Receives** HTTPS requests with a client certificate (mTLS)
2. **Validates** the certificate via a custom policy
3. **Injects** the certificate identity into request headers
4. **Forwards** to the backend (Certificate Service or downstream APIs)
5. **Documents** via the built-in Developer Portal

## Architecture: Zuplo + Ingress NGINX

```
Internet
    │
    ▼ HTTPS (port 443)
NodeBalancer (Linode LB)
    │
    ▼
Ingress NGINX
    │  ssl_passthrough=false
    │  nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
    │  nginx.ingress.kubernetes.io/auth-tls-secret: "pki-system/step-ca-root-cert"
    │  Injects headers: X-Client-Cert, X-Client-Cert-DN, X-Client-Cert-Serial
    │
    ▼
Zuplo Gateway (runtime)
    │  Policy: mtls-inbound-policy (reads injected headers)
    │  Policy: cert-validation-policy (validates CN, OCSP)
    │  Policy: rate-limit-policy
    │
    ▼
Backend Service
```

## 1. Create a Zuplo project

1. Go to https://portal.zuplo.com
2. Create a new project: **"baas-mtls-gateway"**
3. Environment: Production → point to `api.zuplo.baas.io`

## 2. Configure environment variables

In Zuplo panel > Settings > Environment Variables:

| Variable | Value |
|----------|-------|
| `CERT_SERVICE_URL` | `http://certificate-service-svc.certificate-service` |
| `CA_FINGERPRINT` | Root CA fingerprint |
| `OCSP_URL` | `http://step-ca-svc.pki-system:8080` |

## 3. Add policies to the project

Copy the files from [zuplo/policies/](../zuplo/policies/) into your Zuplo project:

```
zuplo/
├── policies/
│   ├── mtls-policy.ts             → main mTLS policy
│   └── cert-validation-policy.ts  → CN validation + OCSP
└── routes.oas.json                → routes with applied policies
```

## 4. Configure the mTLS policy in the Developer Portal

In the project's `zuplo.jsonc` file:

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

Zuplo automatically generates a Developer Portal with:

- OpenAPI documentation for all routes
- Request playground for testing
- Onboarding guides for partners

### Customize the portal

```
zuplo/
└── docs/
    ├── index.md           → portal landing page
    ├── authentication.md  → mTLS guide for partners
    └── quickstart.md      → getting started
```

### Developer Portal URL

After deployment: `https://baas-mtls-gateway.zuplo.io`

## 6. Testing in Zuplo

```bash
# Without certificate — should return 401
curl https://baas-mtls-gateway.zuplo.io/v1/certificates

# With valid certificate — should return 200
curl --cert ./certs-output/client.crt \
     --key  ./certs-output/client.key \
     https://baas-mtls-gateway.zuplo.io/v1/certificates
```

## 7. mTLS configuration in Ingress NGINX

Ingress NGINX needs the CA bundle to validate the client certificate:

```bash
# Create Secret with CA bundle in pki-system namespace
kubectl create secret generic step-ca-root-cert \
  --namespace pki-system \
  --from-file=ca.crt=./root_ca.crt

# Verify the configuration
kubectl get ingress certificate-service-ingress -n certificate-service -o yaml
```

### Critical Ingress annotations

```yaml
nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
# "on"       = mTLS required
# "optional" = mTLS optional (allows requests without cert)
# "off"      = disable mTLS

nginx.ingress.kubernetes.io/auth-tls-secret: "pki-system/step-ca-root-cert"
nginx.ingress.kubernetes.io/auth-tls-verify-depth: "2"
nginx.ingress.kubernetes.io/auth-tls-pass-certificate-to-upstream: "true"
# Injects the cert as X-Client-Cert header for Zuplo to process
```

## 8. Headers injected by Ingress

After mTLS validation by Ingress NGINX, the following headers reach Zuplo:

| Header | Example value |
|--------|--------------|
| `X-Client-Cert` | URL-encoded PEM certificate |
| `X-Client-Cert-DN` | `CN=partner-a.api.baas.io,O=Partner A` |
| `X-Client-Cert-Serial` | `3a:f2:...` |
| `X-Client-Cert-Expiry` | `Dec 31 23:59:59 2025 GMT` |
| `X-Client-Cert-Issuer` | `CN=BaaS mTLS Intermediate CA` |

The `mtls-inbound-policy.ts` policy reads these headers and injects `X-Authenticated-CN` for use by backends.
