# devops2-endterm

Single-node Kubernetes cluster on Ubuntu 25.10 (ARM64). GitOps with ArgoCD, full Prometheus + Loki + Grafana stack, FastAPI + PostgreSQL business app, defense-in-depth security (NetworkPolicies, Kyverno, cert-manager TLS, Sealed Secrets, PSA `restricted`). Infra-as-Code with **Terraform + Ansible (kubespray)** — one `terraform apply` and an `ansible-playbook site.yml` produce a fully bootstrapped cluster.

## Stack

| Layer | Component |
|---|---|
| IaC (orchestrator) | **Terraform** — owns inventory + triggers Ansible |
| Provisioning | **Ansible** — OS prep, kubespray, ArgoCD install, sealing |
| Cluster | Kubernetes (kubespray, single-node all-in-one) |
| CRI | containerd |
| CNI | Calico (enables NetworkPolicy) |
| Storage | local-path-provisioner |
| Secrets | sealed-secrets (Bitnami) |
| GitOps | ArgoCD (app-of-apps) |
| Ingress | ingress-nginx (NodePort 30080/30443) |
| TLS | **cert-manager + in-cluster CA ClusterIssuer** |
| Policy | **Kyverno** (5 ClusterPolicies, baseline + supply-chain) |
| Metrics | kube-prometheus-stack (Prometheus + Alertmanager + Grafana) + custom PrometheusRules |
| Logs | loki-stack (Loki + Promtail) |
| Business app | FastAPI + PostgreSQL (Helm chart) + nightly **pg_dump CronJob** |

## Target-level rubric coverage

| Requirement | Where |
|---|---|
| GitOps end-to-end | `argocd/` app-of-apps — 12 child Applications, sync-waves, prune+selfHeal |
| IaC for infra | `terraform/` (inventory + orchestration), `ansible/site.yml` (OS prep + kubespray + post-install) |
| App security | `runAsNonRoot`, read-only FS, drop ALL caps, seccomp `RuntimeDefault`, no `:latest` (Kyverno-enforced) |
| Network security | Calico + 7 NetworkPolicies (default-deny + explicit allows), TLS on every Ingress |
| User access | Sealed admin creds, dev-readonly RBAC Role+Binding, per-user CSR flow (docs/access.md) |
| Policy enforcement | Kyverno: disallow-latest, require-resources, require-non-root, disallow-host-namespaces, restrict-registries |
| Supply chain | Trivy image scan + IaC scan in CI, fails on HIGH/CRITICAL (`.github/workflows/security-scan.yml`) |
| Backup/DR | Daily `pg_dump` CronJob → dedicated PVC, retains 7 dumps |
| Observability | kube-prometheus-stack + Loki + Grafana TLS ingress + custom `PrometheusRule` alerts |
| PSA | `business` ns enforces `restricted`; others `baseline` |

## Topology

```
                      ┌─────────────────────────────────────┐
                      │  VM: 172.20.10.4 (Ubuntu 25.10)     │
                      │  4 CPU · 7.2 Gi RAM · 32 Gi disk    │
                      │                                     │
   ssh -L 8443:30443  │   ┌─────────────────────────┐       │
   ───────────────────┼──►│ ingress-nginx :30443    │ TLS   │
                      │   └────────────┬────────────┘       │
                      │                │                    │
                      │                ▼                    │
                      │   ┌─────────────────────────┐       │
                      │   │ ns: business (PSA: restricted) │
                      │   │ ┌─────────┐ ┌─────────┐ │       │
                      │   │ │ FastAPI │→│Postgres │ │       │
                      │   │ └─────────┘ └────┬────┘ │       │
                      │   │ ┌──────────────┐ │      │       │
                      │   │ │ pg-backup CJ │─┘      │       │
                      │   │ └──────────────┘        │       │
                      │   └─────────────────────────┘       │
                      │                                     │
                      │   ┌──────────┐ ┌──────────┐         │
                      │   │ Kyverno  │ │cert-mgr  │         │
                      │   └──────────┘ └──────────┘         │
                      │   ┌─────────────────────────┐       │
                      │   │ monitoring + logging    │       │
                      │   └─────────────────────────┘       │
                      └─────────────────────────────────────┘
```

## Quick start

```bash
# 0. (One-time) Install Ansible collections
cd ansible && ansible-galaxy install -r requirements.yml && cd ..

# 1. Generate inventories from Terraform, then bootstrap end-to-end
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit vm_ip if needed
terraform init
terraform apply -var=run_bootstrap=true        # runs ansible-playbook site.yml
cd ..

# 2. (Optional) re-run any single phase
ansible-playbook -i ansible/inventory.ini ansible/site.yml --tags kubespray
```

Everything downstream — ArgoCD, cert-manager, Kyverno, monitoring, logging, business app, backups, policies — installs automatically via ArgoCD app-of-apps. No manual `kubectl apply`.

## Verify

```bash
export KUBECONFIG=$(pwd)/kubeconfig

bash scripts/verify.sh              # full health check
bash scripts/demo-zero-downtime.sh  # rolling update with curl loop
bash scripts/demo-netpol.sh         # prove NetworkPolicies work

kubectl get clusterpolicy           # Kyverno policies
kubectl get clusterissuer           # cert-manager issuers
kubectl get certificate -A          # issued TLS certs
kubectl -n business get cronjob,pvc # backup job + PVC
kubectl get prometheusrule -A       # alert rules
```

## Layout

```
terraform/                  Terraform — VM inventory + Ansible trigger
ansible/                    site.yml + prepare-vm.yml + roles
bootstrap/                  legacy shell helpers (still callable; site.yml supersedes)
argocd/                     app-of-apps; one Application per concern
charts/business/            Helm chart: app, db, backup, RBAC, netpol, PSA, alerts
extras/cluster-issuer/      cert-manager ClusterIssuers
extras/kyverno-policies/    5 ClusterPolicies
.github/workflows/          Trivy + Kyverno-validate + helm-lint CI
monitoring/                 reference values for kube-prometheus-stack / loki
docs/                       per-area deep dives (security, networking, access, …)
```

## Docs

`docs/` covers each area: topology, deployment, access, architecture, security, networking, storage, rollout, extensions, monitoring.
