# 09 — Observabilidade

## Stack de Monitoramento

```
Step-CA ──► Prometheus ──► Grafana (dashboards)
Cert Service ──►    │
Ingress NGINX ──►   │
                    └──► Alertmanager ──► Webhook / PagerDuty
```

## 1. Métricas expostas

### Step-CA (porta 9100)

| Métrica | Tipo | Descrição |
|---------|------|-----------|
| `step_ca_sign_requests_total` | Counter | Total de requisições de assinatura |
| `step_ca_sign_duration_seconds` | Histogram | Latência de assinatura |
| `step_ca_revoke_requests_total` | Counter | Total de revogações |
| `step_ca_active_certificates` | Gauge | Certificados ativos |

### Certificate Service (porta 3001)

| Métrica | Tipo | Descrição |
|---------|------|-----------|
| `mtls_certificates_issued_total` | Counter | Certificados emitidos (por tenant) |
| `mtls_certificates_revoked_total` | Counter | Certificados revogados |
| `mtls_cert_expiry_seconds` | Gauge | Segundos até expiração (por cert) |
| `http_request_duration_seconds` | Histogram | Latência HTTP (por rota) |

### Ingress NGINX

| Métrica | Tipo | Descrição |
|---------|------|-----------|
| `nginx_ingress_controller_ssl_expire_time_seconds` | Gauge | Expiração dos certs do servidor |
| `nginx_ingress_controller_requests` | Counter | Requisições (por status) |

## 2. Alertas configurados

### Regras Prometheus (criar em `kubernetes/monitoring/prometheus/alerts.yaml`)

```yaml
groups:
  - name: mtls-baas
    rules:
      - alert: CertExpiryWarning
        expr: |
          mtls_cert_expiry_seconds < 15 * 24 * 3600
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Certificado expira em menos de 15 dias"
          description: "Tenant {{ $labels.tenant_id }} tem certificado expirando em {{ $value | humanizeDuration }}"

      - alert: CARootExpiry
        expr: |
          step_ca_root_expiry_seconds < 180 * 24 * 3600
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "Root CA expira em menos de 180 dias"

      - alert: HighRevocationRate
        expr: |
          rate(mtls_certificates_revoked_total[1h]) > 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Taxa alta de revogações — possível incidente de segurança"

      - alert: CAUnavailable
        expr: |
          up{job="step-ca"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Step-CA indisponível"

      - alert: HighSignLatency
        expr: |
          histogram_quantile(0.99, rate(step_ca_sign_duration_seconds_bucket[5m])) > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Latência p99 de assinatura > 2s"
```

## 3. Dashboard Grafana recomendado

### Painel: "mTLS BaaS Overview"

```
┌────────────────────────────────────────────────────────┐
│  Certs Emitidos (7d)  │  Certs Ativos  │  Revogados    │
│       1,234           │      987       │      12       │
├────────────────────────────────────────────────────────┤
│  Latência de Assinatura (p50/p95/p99)                   │
│  [gráfico de linha temporal]                            │
├────────────────────────────────────────────────────────┤
│  Certificados por Status   │  Emissões por Tenant       │
│  [pie chart]               │  [bar chart]               │
├────────────────────────────────────────────────────────┤
│  Próximos a Vencer (< 30 dias)                         │
│  [tabela: tenant_id | cn | expires_at | dias restantes]│
└────────────────────────────────────────────────────────┘
```

## 4. Acessar Grafana

```bash
# Port-forward para acesso local
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Acessar: http://localhost:3000
# Usuário: admin
# Senha: obtida via kubectl get secret
kubectl get secret kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

## 5. Logging estruturado

O Certificate Service usa Winston com saída JSON — todos os logs incluem:

```json
{
  "timestamp": "2025-05-25T10:05:00.000Z",
  "level": "info",
  "service": "certificate-service",
  "msg": "Certificate issued",
  "certId": "7f3d9a2e-...",
  "tenantId": "550e8400-...",
  "cn": "fintech-alpha.api.baas.io"
}
```

Para centralizar logs, configure um DaemonSet Fluent Bit apontando para seu destino (CloudWatch, Loki, Datadog):

```bash
helm repo add fluent https://fluent.github.io/helm-charts
helm upgrade --install fluent-bit fluent/fluent-bit \
  --namespace monitoring \
  --set backend.type=loki \
  --set backend.loki.host=loki.monitoring.svc.cluster.local
```
