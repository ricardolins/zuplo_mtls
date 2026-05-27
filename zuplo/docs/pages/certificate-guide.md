---
title: Certificate Guide
---

# Certificate Guide

## Certificate Lifecycle

| Event | Endpoint | Auth |
|-------|----------|------|
| Issue first certificate | `POST /v1/certificates` | API Key |
| List your certificates | `GET /v1/certificates` | API Key |
| View certificate details | `GET /v1/certificates/{id}` | API Key |
| Renew before expiry | `POST /v1/certificates/{id}/renew` | mTLS |
| Revoke a certificate | `DELETE /v1/certificates/{id}` | mTLS |

## Renewing a certificate

Renew before expiry using your **current** client certificate. A new certificate is issued and the old one is revoked automatically.

```bash
curl -X POST https://your-project.zuplo.app/v1/certificates/{id}/renew \
  --cert client.crt --key client.key
```

## Revoking a certificate

```bash
curl -X DELETE https://your-project.zuplo.app/v1/certificates/{id} \
  --cert client.crt --key client.key
```

## Certificate format

Certificates are issued by the BaaS Root CA. The certificate includes:

- **Subject CN**: your organization identifier
- **Validity**: configured at issuance (default 365 days)
- **Key usage**: `digitalSignature`, `keyEncipherment`
- **Extended key usage**: `clientAuth`

## Key rotation best practice

Rotate certificates **30 days before expiry**. Set up a cron job or webhook to automate renewal.  
The `GET /v1/certificates` endpoint returns the `expiresAt` field you can monitor.

## Security notes

- Private keys are returned **once** at issuance and never stored. Keep them safe.
- If a key is compromised, revoke immediately via `DELETE /v1/certificates/{id}`.
- After revocation, the certificate is rejected within seconds via OCSP.
