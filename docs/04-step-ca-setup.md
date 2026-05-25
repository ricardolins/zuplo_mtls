# 04 — Step-CA Configuration

## What is Step-CA?

[Smallstep step-ca](https://smallstep.com/docs/step-ca/) is an open-source, cloud-native CA that supports:
- REST API for automated issuance and revocation
- Multiple provisioners (JWK, ACME, OIDC, x5c, etc.)
- Native OCSP and CRL
- HA with shared storage
- Automatic certificate rotation via `step-ca renew`

## CA hierarchy in this platform

```
Root CA
├── Validity: 10 years
├── Algorithm: ECDSA P-384
├── Storage: K8s Secret (encrypted at rest)
└── Intermediate CA
    ├── Validity: 1 year (automatic renewal)
    ├── Algorithm: ECDSA P-256
    ├── Online in the cluster
    └── Issues leaf certs for partners (TTL: 90 days)
```

## 1. Initialization (executed by setup-ca.sh)

```bash
step ca init \
  --name "BaaS mTLS CA" \
  --dns "ca.baas.io" \
  --dns "step-ca-svc.pki-system.svc.cluster.local" \
  --address ":9000" \
  --provisioner "cert-manager" \
  --root ./root_ca.crt \
  --key  ./root_ca.key \
  --intermediate-cert ./intermediate_ca.crt \
  --intermediate-key  ./intermediate_ca.key \
  --root-ttl 87600h \
  --intermediate-ttl 8760h
```

This generates:
- `root_ca.crt` / `root_ca.key` — Root CA (store offline!)
- `intermediate_ca.crt` / `intermediate_ca.key` — Intermediate CA (in cluster)
- `$(step path)/config/ca.json` — CA configuration

## 2. Configured provisioners

### JWK (JSON Web Key) — for cert-manager

Used by cert-manager to issue Kubernetes-native certificates.

```bash
# List provisioners
step ca provisioner list

# Add a new JWK provisioner
step ca provisioner add new-partner --type JWK
```

### ACME — for automatic renewal

```bash
# Test ACME endpoint
curl https://step-ca-svc.pki-system.svc.cluster.local:9000/acme/acme/directory
```

### x5c — for issuance with a client certificate

Allows a partner with a valid certificate to issue new certificates (self-renewal).

## 3. CA verification

```bash
# From inside the cluster
kubectl exec -n pki-system deploy/step-certificates -- \
  step ca health

# View CA information
kubectl exec -n pki-system deploy/step-certificates -- \
  step ca roots

# Root CA fingerprint
kubectl exec -n pki-system deploy/step-certificates -- \
  step certificate fingerprint /home/step/certs/root_ca.crt
```

## 4. Manual certificate issuance (debugging)

```bash
# Install step CLI locally
brew install step

# Configure step to use the cluster CA
# (via port-forward for local testing)
kubectl port-forward -n pki-system svc/step-ca-svc 9000:9000 &

step ca bootstrap \
  --ca-url https://localhost:9000 \
  --fingerprint YOUR_FINGERPRINT \
  --install

# Issue a test certificate
step ca certificate \
  "test.partner.baas.io" \
  test.crt test.key \
  --provisioner cert-manager \
  --not-after 24h
```

## 5. CRL and OCSP configuration

The `ca.json` (in the ConfigMap) already includes:

```json
{
  "crl": {
    "enabled": true,
    "generateOnRevoke": true,
    "cacheDuration": "24h",
    "renewBefore": "6h"
  }
}
```

### Verify CRL

```bash
# Download CRL from the CA
curl -sk https://step-ca-svc.pki-system.svc.cluster.local:9000/1.0/crl \
  | openssl crl -inform DER -noout -text
```

### Check OCSP status

```bash
openssl ocsp \
  -issuer intermediate_ca.crt \
  -cert   client.crt \
  -url    https://step-ca-svc.pki-system.svc.cluster.local:8080 \
  -resp_text
```

## 6. Intermediate CA renewal

cert-manager renews automatically when TTL < 25% remaining. If it fails:

```bash
# Force manual renewal via cert-manager
kubectl annotate certificate step-ca-intermediate \
  -n pki-system \
  cert-manager.io/issuer-kind=ClusterIssuer \
  --overwrite

# Or delete the Secret to force recreation
kubectl delete secret step-ca-intermediate-cert -n pki-system
```

## 7. CA backup

```bash
# Backup the CA PVC (issuance DB state)
kubectl exec -n pki-system deploy/step-certificates -- \
  tar czf - /home/step/db | \
  gzip > "step-ca-backup-$(date +%Y%m%d).tar.gz"

# The root_ca.key must be stored offline
# The intermediate_ca.key is in the K8s Secret step-ca-intermediate-cert
kubectl get secret step-ca-intermediate-cert -n pki-system \
  -o jsonpath='{.data.intermediate_ca\.key}' | base64 -d
```
