# 03 — Setup Linode Kubernetes Engine (LKE)

## Pré-requisitos

1. Conta Linode ativa: https://cloud.linode.com
2. Token de API com escopo `Kubernetes Read/Write`
3. `linode-cli` instalado: `pip install linode-cli`
4. Terraform >= 1.5

## 1. Gerar token de API

1. Acesse: https://cloud.linode.com/profile/tokens
2. Clique em "Create A Personal Access Token"
3. Escopos necessários:
   - **Kubernetes**: Read/Write
   - **Linodes**: Read/Write
   - **NodeBalancers**: Read/Write
   - **Firewall**: Read/Write
4. Copie o token — ele só é exibido uma vez

## 2. Configurar Terraform

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars com seu token e configurações
```

## 3. Provisionamento

```bash
# Inicializar providers
terraform init

# Revisar o plano de execução
terraform plan -out=mtls-baas.tfplan

# Aplicar (leva ~5 minutos)
terraform apply mtls-baas.tfplan
```

## 4. Configurar kubeconfig

```bash
# Opção 1: Via Terraform output
terraform output -raw kubeconfig_path
export KUBECONFIG=$(terraform output -raw kubeconfig_path)

# Opção 2: Via linode-cli
linode-cli lke kubeconfig-view $(terraform output -raw cluster_id) \
  --no-defaults \
  > ~/.kube/lke-mtls.yaml
export KUBECONFIG=~/.kube/lke-mtls.yaml

# Verificar
kubectl get nodes
```

## 5. Topologia de nós resultante

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

## 6. Taints e labels

O Terraform configura automaticamente taints nos nós PKI para garantir isolamento:

```bash
# Verificar taints nos nós PKI
kubectl get nodes -l role=pki -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints[*]}{"\n"}{end}'

# Verificar labels
kubectl get nodes --show-labels
```

## 7. Storage classes Linode

```bash
kubectl get storageclass

# linode-block-storage          — padrão, deleta volume ao deletar PVC
# linode-block-storage-retain   — mantém volume (usado para CA e banco)
```

Todos os PVCs da CA usam `linode-block-storage-retain` para não perder dados da CA acidentalmente.

## 8. Verificação de saúde do cluster

```bash
# Todos os nós prontos
kubectl get nodes

# Componentes do control plane
kubectl get componentstatuses

# Pods do sistema
kubectl get pods -n kube-system

# Verificar RBAC
kubectl auth can-i create pods --namespace pki-system
```

## 9. Upgrade do Kubernetes

O LKE suporta upgrade in-place:

```bash
# Ver versões disponíveis
linode-cli lke versions-list

# Atualizar via Terraform (alterar kubernetes_version no tfvars)
terraform apply -target=module.lke_cluster

# Ou via linode-cli
linode-cli lke cluster-update $(terraform output -raw cluster_id) \
  --k8s_version 1.30
```

## Custos estimados (us-east, 2025)

| Recurso | Tipo | Qtd | Custo/mês |
|---------|------|-----|-----------|
| Nós PKI | g6-dedicated-2 | 2 | ~$60 |
| Nós App | g6-standard-4 | 3 | ~$72 |
| Nó Monitoring | g6-standard-2 | 1 | ~$12 |
| NodeBalancer | - | 1 | ~$10 |
| Block Storage (CA) | 10GB retain | 2 | ~$2 |
| **Total** | | | **~$156/mês** |
