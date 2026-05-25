# 09 — Observability

## Monitoring Stack

```
Step-CA ──► Prometheus ──► Grafana (dashboards)
Cert Service ──►    │
Ingress NGINX ──►   │
                    └──► Alertmanager ──► Webhook / PagerDuty
```

## 1. Exposed metrics

### Step-CA (port 9100)

| Metric | Type | Description |
|--------|------|-------------|
| `step_ca_sign_requests_total` | Counter | Total signing requests |
| `step_ca_sign_duration_seconds` | Histogram | Signing latency |
| `step_ca_revoke_requests_total` | Counter | Total revocations |
| `step_ca_active_certificates` | Gauge | Active certificates |

### Certificate Service (port 3001)

| Metric | Type | Description |
|--------|------|-------------|
| `mtls_certificates_issued_total` | Counter | Certificates issued (per tenant) |
| `mtls_certificates_revoked_total` | Counter | Certificates revoked |
| `mtls_cert_expiry_seconds` | Gauge | Seconds until expiry (per cert) |
| `http_request_duration_seconds` | Histogram | HTTP latency (per route) |

### Ingress NGINX

| Metric | Type | Description |
|--------|------|-------------|
| `nginx_ingress_controller_ssl_expire_time_seconds` | Gauge | Server cert expiry |
| `nginx_ingress_controller_requests` | Counter | Requests (by status) |

## 2. Configured alerts

### Prometheus rules (create in `kubernetes/monitoring/prometheus/alerts.yaml`)

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
          summary: "Certificate expires in less than 15 days"
          description: "Tenant {{ $labels.tenant_id }} has a certificate expiring in {{ $value | humanizeDuration }}"

      - alert: CARootExpiry
        expr: |
          step_ca_root_expiry_seconds < 180 * 24 * 3600
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "Root CA expires in less than 180 days"

      - alert: HighRevocationRate
        expr: |
          rate(mtls_certificates_revoked_total[1h]) > 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High revocation rate — possible security incident"

      - alert: CAUnavailable
        expr: |
          up{job="step-ca"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Step-CA unavailable"

      - alert: HighSignLatency
        expr: |
          histogram_quantile(0.99, rate(step_ca_sign_duration_seconds_bucket[5m])) > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "p99 signing latency > 2s"
```

## 3. Recommended Grafana dashboard

### Panel: "mTLS BaaS Overview"

```
┌────────────────────────────────────────────────────────┐
│  Certs Issued (7d)    │  Active Certs  │  Revoked       │
│       1,234           │      987       │      12        │
├────────────────────────────────────────────────────────┤
│  Signing Latency (p50/p95/p99)                          │
│  [time-series chart]                                    │
├────────────────────────────────────────────────────────┤
│  Certificates by Status    │  Issuances by Tenant       │
│  [pie chart]               │  [bar chart]               │
├────────────────────────────────────────────────────────┤
│  Expiring Soon (< 30 days)                             │
│  [table: tenant_id | cn | expires_at | days remaining] │
└────────────────────────────────────────────────────────┘
```

## 4. Access Grafana

```bash
# Port-forward for local access
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Access: http://localhost:3000
# Username: admin
# Password: obtained via kubectl
kubectl get secret kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

## 5. Structured logging

The Certificate Service uses Winston with JSON output — all logs include:

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

To centralize logs, configure a Fluent Bit DaemonSet pointing to your destination (CloudWatch, Loki, Datadog):

```bash
helm repo add fluent https://fluent.github.io/helm-charts
helm upgrade --install fluent-bit fluent/fluent-bit \
  --namespace monitoring \
  --set backend.type=loki \
  --set backend.loki.host=loki.monitoring.svc.cluster.local
```
