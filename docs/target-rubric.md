# Target-level rubric mapping

The endterm rubric defines **target** as:

> Everything is deployed through GitOps approach, all infrastructure preparations
> made on Ansible/Terraform/Puppet, apps/networking/user access following
> security best practices.

This document walks each clause and pins it to the artifact in the repo.

## 1. Everything is deployed through GitOps

| Capability | Artifact |
|---|---|
| Cluster state declared in git | `argocd/` — every Application is a YAML file |
| Single root-app reconciles all | `argocd/root-app.yaml` (app-of-apps) |
| Prune + selfHeal on every child | `syncPolicy.automated.{prune,selfHeal}: true` in every `argocd/apps/*.yaml` |
| Ordered rollout | `argocd.argoproj.io/sync-wave` annotations (wave 0 → 10) |
| Server-side apply | `syncOptions: [ServerSideApply=true]` |
| No imperative `kubectl apply` after bootstrap | Confirmed: every workload lives under an Application |

Child Applications (in sync-wave order):

| Wave | App | Why |
|---|---|---|
| 0 | sealed-secrets | provides `SealedSecret` CRD |
| 1 | local-path-provisioner | provides default `StorageClass` |
| 2 | ingress-nginx | required by Ingress resources |
| 2 | **cert-manager** | provides `Certificate`/`Issuer` CRDs |
| 2 | **kyverno** | provides admission controller |
| 3 | **cluster-issuer** | self-signed root CA + `cluster-ca-issuer` |
| 3 | kube-prometheus-stack | Prometheus + Grafana + Alertmanager |
| 4 | loki-stack | logs |
| 4 | **kyverno-policies** | 5 `ClusterPolicy` resources |
| 5 | grafana-dashboards | dashboards via configmaps |
| 6 | extras (argocd-ingress) | self-hosted ArgoCD ingress, TLS |
| 10 | business | the actual app + db + backup + RBAC + netpol + alerts |

## 2. All infrastructure preparations on Ansible/Terraform/Puppet

| Phase | Tool | Artifact |
|---|---|---|
| Inventory generation | Terraform | `terraform/main.tf` — single source of truth for VM IP |
| OS prep (apt, swap, kernel modules, sysctl) | Ansible | `ansible/prepare-vm.yml` |
| Kubernetes install | Ansible (kubespray) | `ansible/site.yml` → kubespray play |
| Kubeconfig fetch | Ansible | `ansible/site.yml` → "Fetch kubeconfig" |
| Post-cluster (untaint, PSA labels) | Ansible | `ansible/site.yml` → "Post-cluster" |
| ArgoCD install + root-app | Ansible | `ansible/site.yml` → "Install ArgoCD" (uses `kubernetes.core.k8s`) |
| Sealing one-time DB creds | Ansible | `ansible/site.yml` → "Seal DB credentials" |

The legacy `bootstrap/*.sh` scripts are kept as escape hatches for debugging but
`ansible-playbook site.yml` replaces all six in one invocation.

`terraform apply -var=run_bootstrap=true` is the only command needed from a
clean machine: it generates both inventories and triggers Ansible via
`local-exec`.

## 3. Apps following security best practices

| Control | Where |
|---|---|
| `runAsNonRoot=true`, `runAsUser=1000` (Pod + container) | `charts/business/templates/fastapi.yaml`, `postgres.yaml`, `backup.yaml` |
| `readOnlyRootFilesystem=true` | fastapi, backup |
| `allowPrivilegeEscalation=false` | every container |
| `capabilities.drop: [ALL]` | every container |
| `seccompProfile.type: RuntimeDefault` | Pod-level + container-level on all workloads |
| `imagePullPolicy: Never` for local builds | fastapi |
| Resource requests + limits enforced | by `LimitRange` + Kyverno `require-resources` |
| `:latest` forbidden | Kyverno `disallow-latest-tag` (Enforce) |
| Approved registries only | Kyverno `restrict-image-registries` (Audit) |
| `hostPID/hostIPC/hostNetwork` forbidden | Kyverno `disallow-host-namespaces` |
| Pod Security Admission `restricted` | `charts/business/templates/namespace.yaml` |
| Vulnerability scanning | `.github/workflows/security-scan.yml` (Trivy image + IaC) |
| Backups | `charts/business/templates/backup.yaml` (pg_dump, retain 7) |
| Alerting | `charts/business/templates/prometheusrules.yaml` (8 rules) |

## 4. Networking following security best practices

| Control | Where |
|---|---|
| CNI with NetworkPolicy support | Calico (set in kubespray overrides) |
| Default-deny ingress + egress in app ns | `networkpolicies.yaml` rule #1 |
| Explicit allows: ingress→fastapi, fastapi→postgres, monitoring→fastapi, backup→postgres | rules #2..#6 |
| Egress allow-list (DNS + postgres only) | rules #3b, #4, #5 |
| TLS on every external Ingress | cert-manager via `cluster-ca-issuer` (business, argocd, grafana) |
| `ssl-redirect: "true"` annotation on every Ingress | enforced in templates |
| In-cluster root CA, 10y self-signed | `extras/cluster-issuer/selfsigned.yaml` |
| NetworkPolicy live demo | `scripts/demo-netpol.sh` (3 probes, two denied, one allowed) |

## 5. User access following security best practices

| Control | Where |
|---|---|
| No plaintext secrets in git | Bitnami sealed-secrets; `.gitignore` blocks `secret-*.yaml` |
| ArgoCD admin password sealed | (bootstrap seals via `kubeseal`; see `docs/access.md`) |
| Grafana admin from `existingSecret` | `monitoring/kube-prometheus-stack-values.yaml` |
| Kubeconfig stored locally only, chmod 600 | `ansible/site.yml` "Fetch kubeconfig" |
| Cluster admin via PKI cert (not password) | kubespray-issued client cert |
| Least-privilege RBAC | `charts/business/templates/rbac.yaml` — `dev-readonly` Role + Binding |
| Per-user CSR flow documented | `docs/access.md` § "Per-user kubeconfig via CSR" |
| Service account for in-cluster ops | `business-ops` SA bound to `dev-readonly` Role |

## How to verify on a live cluster

```bash
export KUBECONFIG=$(pwd)/kubeconfig

# GitOps
kubectl -n argocd get app -o wide                 # all Synced/Healthy

# IaC
terraform -chdir=terraform plan                   # no drift
ansible-playbook -i ansible/inventory.ini ansible/site.yml --check

# Security
kubectl get clusterpolicy                         # Kyverno enforce-mode policies
kubectl get certificate -A                        # TLS certs Ready
kubectl get networkpolicy -A                      # 7 in business ns
kubectl get psa --all-namespaces 2>/dev/null \
  || kubectl get ns -L pod-security.kubernetes.io/enforce
bash scripts/demo-netpol.sh                       # netpol live proof

# Backup
kubectl -n business get cronjob postgres-backup
kubectl -n business get pvc postgres-backup

# Alerts
kubectl get prometheusrule -A
```
