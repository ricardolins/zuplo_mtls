# 03 — Linode Kubernetes Engine (LKE) Setup

## Prerequisites

1. Active Linode account: https://cloud.linode.com
2. API token with `Kubernetes Read/Write` scope
3. `linode-cli` installed: `pip install linode-cli`
4. Terraform >= 1.5

## 1. Generate an API Token

1. Go to: https://cloud.linode.com/profile/tokens
2. Click "Create A Personal Access Token"
3. Required scopes:
   - **Kubernetes**: Read/Write
   - **Linodes**: Read/Write
   - **NodeBalancers**: Read/Write
   - **Firewall**: Read/Write
4. Copy the token — it is only displayed once

## 2. Configure Terraform

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your token and settings
```

## 3. Provisioning

```bash
# Initialize providers
terraform init

# Review the execution plan
terraform plan -out=mtls-baas.tfplan

# Apply (takes ~5 minutes)
terraform apply mtls-baas.tfplan
```

## 4. Configure kubeconfig

```bash
# Option 1: Via Terraform output
terraform output -raw kubeconfig_path
export KUBECONFIG=$(terraform output -raw kubeconfig_path)

# Option 2: Via linode-cli
linode-cli lke kubeconfig-view $(terraform output -raw cluster_id) \
  --no-defaults \
  > ~/.kube/lke-mtls.yaml
export KUBECONFIG=~/.kube/lke-mtls.yaml

# Verify
kubectl get nodes
```

## 5. Resulting node topology

```
$ kubectl get nodes -o wide

NAME                        STATUS   ROLES    AGE   VERSION
lke-mtls-pki-pool-a         Ready    <none>   2m    v1.29     ← Step-CA, cert-manager
lke-mtls-pki-pool-b         Ready    <none>   2m    v1.29
lke-mtls-app-pool-a         Ready    <none>   2m    v1.29     ← Certificate Service API
lke-mtls-app-pool-b         Ready    <none>   2m    v1.29
lke-mtls-app-pool-c         Ready    <none>   2m    v1.29
lke-mtls-monitoring-pool-a  Ready    <none>   2m    v1.29     ← Prometheus + Grafana
```

## 6. Taints and labels

Terraform automatically configures taints on PKI nodes to ensure workload isolation:

```bash
# Check taints on PKI nodes
kubectl get nodes -l role=pki -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints[*]}{"\n"}{end}'

# Check labels
kubectl get nodes --show-labels
```

## 7. Linode storage classes

```bash
kubectl get storageclass

# linode-block-storage          — default, deletes volume when PVC is deleted
# linode-block-storage-retain   — retains volume (used for CA and database)
```

All CA PVCs use `linode-block-storage-retain` to prevent accidental data loss.

## 8. Cluster health check

```bash
# All nodes ready
kubectl get nodes

# Control plane components
kubectl get componentstatuses

# System pods
kubectl get pods -n kube-system

# Verify RBAC
kubectl auth can-i create pods --namespace pki-system
```

## 9. Kubernetes upgrade

LKE supports in-place upgrades:

```bash
# List available versions
linode-cli lke versions-list

# Upgrade via Terraform (change kubernetes_version in tfvars)
terraform apply -target=module.lke_cluster

# Or via linode-cli
linode-cli lke cluster-update $(terraform output -raw cluster_id) \
  --k8s_version 1.30
```

## Estimated costs (us-east, 2025)

| Resource | Type | Qty | Cost/month |
|----------|------|-----|-----------|
| PKI nodes | g6-dedicated-2 | 2 | ~$60 |
| App nodes | g6-standard-4 | 3 | ~$72 |
| Monitoring node | g6-standard-2 | 1 | ~$12 |
| NodeBalancer | - | 1 | ~$10 |
| Block Storage (CA) | 10GB retain | 2 | ~$2 |
| **Total** | | | **~$156/month** |
