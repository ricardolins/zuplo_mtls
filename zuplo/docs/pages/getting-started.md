---
title: Getting Started
---

# Getting Started

The BaaS mTLS Platform gives your organization a secure, certificate-based API gateway.  
All API calls after the bootstrap phase use mutual TLS (mTLS) — both you and the server present certificates.

## How it works

```
1. Register your organization  →  POST /v1/tenants  (no auth)
2. Get your API Key            →  Provided by your account admin
3. Issue your mTLS certificate →  POST /v1/certificates  (API Key)
4. Use the API with mTLS       →  GET/POST /v1/api/*  (client certificate)
```

## Step 1 — Register your organization

```bash
curl -X POST https://mtls-main-6012973.zuplo.app/v1/tenants \
  -H "Content-Type: application/json" \
  -d '{ "name": "Acme Corp", "email": "admin@acme.com" }'
```

## Step 2 — Get your API Key

Contact your account administrator or use the **API Keys** tab in this portal to retrieve your key.  
Your API Key looks like `zpka_…`.

## Step 3 — Issue your first mTLS certificate

```bash
curl -X POST https://mtls-main-6012973.zuplo.app/v1/certificates \
  -H "X-API-Key: zpka_YOUR_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "commonName": "acme-corp",
    "organization": "Acme Corp",
    "ttlDays": 365
  }'
```

The response contains your **certificate** (`.crt`) and **private key** (`.key`).  
Store the private key securely — it is never stored on our servers.

## Step 4 — Call the API using mTLS

```bash
curl --cert client.crt --key client.key \
  https://mtls-main-6012973.zuplo.app/v1/api/your-endpoint
```

## Next steps

- See the full [API Reference](/api-reference) for all available endpoints.
- Read the [Certificate Guide](/certificate-guide) for renewal, revocation, and rotation.
