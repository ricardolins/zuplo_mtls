# 04 — Configuração da Step-CA

## O que é o Step-CA?

[Smallstep step-ca](https://smallstep.com/docs/step-ca/) é uma CA open-source, cloud-native, que suporta:
- API REST para emissão e revogação automática
- Múltiplos provisioners (JWK, ACME, OIDC, x5c, etc.)
- OCSP e CRL nativos
- HA com storage compartilhado
- Rotação automática de certificados via `step-ca renew`

## Hierarquia de CA nesta plataforma

```
Root CA
├── Validade: 10 anos
├── Algoritmo: ECDSA P-384
├── Armazenamento: K8s Secret (cifrado em repouso)
└── Intermediate CA
    ├── Validade: 1 ano (renovação automática)
    ├── Algoritmo: ECDSA P-256
    ├── Online no cluster
    └── Emite leaf certs para parceiros (TTL: 90 dias)
```

## 1. Inicialização (executada pelo setup-ca.sh)

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

Isso gera:
- `root_ca.crt` / `root_ca.key` — Root CA (guardar offline!)
- `intermediate_ca.crt` / `intermediate_ca.key` — Intermediate CA (no cluster)
- `$(step path)/config/ca.json` — Configuração da CA

## 2. Provisioners configurados

### JWK (JSON Web Key) — para cert-manager

Usado pelo cert-manager para emitir certificados Kubernetes-nativos.

```bash
# Listar provisioners
step ca provisioner list

# Adicionar novo provisioner JWK
step ca provisioner add novo-parceiro --type JWK
```

### ACME — para renovação automática

```bash
# Testar endpoint ACME
curl https://step-ca-svc.pki-system.svc.cluster.local:9000/acme/acme/directory
```

### x5c — para emissão com cert de cliente

Permite que um parceiro com certificado válido emita novos certificados (auto-renovação).

## 3. Verificação da CA

```bash
# Dentro do cluster
kubectl exec -n pki-system deploy/step-certificates -- \
  step ca health

# Ver informações da CA
kubectl exec -n pki-system deploy/step-certificates -- \
  step ca roots

# Fingerprint da Root CA
kubectl exec -n pki-system deploy/step-certificates -- \
  step certificate fingerprint /home/step/certs/root_ca.crt
```

## 4. Emissão manual de certificado (debug)

```bash
# Instalar step CLI localmente
brew install step

# Configurar step para usar a CA do cluster
# (via port-forward para teste local)
kubectl port-forward -n pki-system svc/step-ca-svc 9000:9000 &

step ca bootstrap \
  --ca-url https://localhost:9000 \
  --fingerprint SEU_FINGERPRINT \
  --install

# Emitir certificado de teste
step ca certificate \
  "test.parceiro.baas.io" \
  test.crt test.key \
  --provisioner cert-manager \
  --not-after 24h
```

## 5. Configuração de CRL e OCSP

O `ca.json` (no ConfigMap) já inclui:

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

### Verificar CRL

```bash
# Baixar CRL da CA
curl -sk https://step-ca-svc.pki-system.svc.cluster.local:9000/1.0/crl \
  | openssl crl -inform DER -noout -text
```

### Verificar status OCSP

```bash
openssl ocsp \
  -issuer intermediate_ca.crt \
  -cert   cliente.crt \
  -url    https://step-ca-svc.pki-system.svc.cluster.local:8080 \
  -resp_text
```

## 6. Renovação da Intermediate CA

A cert-manager renova automaticamente quando TTL < 25% restante. Em caso de falha:

```bash
# Forçar renovação manual via cert-manager
kubectl annotate certificate step-ca-intermediate \
  -n pki-system \
  cert-manager.io/issuer-kind=ClusterIssuer \
  --overwrite

# Ou deletar o Secret para forçar recriação
kubectl delete secret step-ca-intermediate-cert -n pki-system
```

## 7. Backup da CA

```bash
# Backup do PVC da CA (state: DB de emissões)
kubectl exec -n pki-system deploy/step-certificates -- \
  tar czf - /home/step/db | \
  gzip > "step-ca-backup-$(date +%Y%m%d).tar.gz"

# O root_ca.key deve estar armazenado offline
# O intermediate_ca.key está no K8s Secret step-ca-intermediate-cert
kubectl get secret step-ca-intermediate-cert -n pki-system \
  -o jsonpath='{.data.intermediate_ca\.key}' | base64 -d
```
