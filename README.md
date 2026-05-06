# devops2-endterm

Single-node Kubernetes cluster on Ubuntu 25.10 (ARM64). GitOps with ArgoCD, full Prometheus + Loki + Grafana stack, FastAPI + PostgreSQL business app, NetworkPolicies and sealed secrets. Bootstrapped with Ansible + kubespray.

## Stack

| Layer | Component |
|---|---|
| Cluster | Kubernetes (kubespray, single-node all-in-one) |
| CRI | containerd |
| CNI | Calico |
| Storage | local-path-provisioner |
| Secrets | sealed-secrets (Bitnami) |
| GitOps | ArgoCD (app-of-apps) |
| Ingress | ingress-nginx (NodePort 30080) |
| Metrics | kube-prometheus-stack (Prometheus + Alertmanager + Grafana) |
| Logs | loki-stack (Loki + Promtail) |
| Business app | FastAPI + PostgreSQL (Helm chart) |

## Topology

```
                      ┌─────────────────────────────────────┐
                      │  VM: 172.20.10.4 (Ubuntu 25.10)   │
                      │  4 CPU · 7.2 Gi RAM · 32 Gi disk    │
                      │                                     │
   ssh -L 8080:30080  │   ┌─────────────────────────┐       │
   ───────────────────┼──►│ ingress-nginx :30080    │       │
                      │   └────────────┬────────────┘       │
                      │                │                    │
                      │                ▼                    │
                      │   ┌─────────────────────────┐       │
                      │   │ ns: business            │       │
                      │   │ ┌─────────┐ ┌─────────┐ │       │
                      │   │ │ FastAPI │→│Postgres │ │       │
                      │   │ │ x2 reps │ │ x1 sts  │ │       │
                      │   │ └─────────┘ └─────────┘ │       │
                      │   └─────────────────────────┘       │
                      │                                     │
                      │   ┌─────────────────────────┐       │
                      │   │ ns: monitoring          │       │
                      │   │ Prometheus + Grafana    │       │
                      │   │ Alertmanager + Loki     │       │
                      │   └─────────────────────────┘       │
                      │                                     │
                      │   ┌─────────────────────────┐       │
                      │   │ ns: argocd              │       │
                      │   │ app-of-apps reconciler  │       │
                      │   └─────────────────────────┘       │
                      └─────────────────────────────────────┘
```

## Quick start

```bash
# 1. Prep VM (idempotent)
bash bootstrap/01-prepare-vm.sh

# 2. Run kubespray (clones kubespray locally, ~15 min)
bash bootstrap/02-run-kubespray.sh

# 3. Fetch kubeconfig to ./kubeconfig
bash bootstrap/03-fetch-kubeconfig.sh
export KUBECONFIG=$(pwd)/kubeconfig

# 4. Untaint single-node master so workloads schedule
bash bootstrap/04-untaint-master.sh

# 5. Install ArgoCD + apply root-app (everything else flows via GitOps)
bash bootstrap/05-install-argocd.sh

# 6. Seal DB credentials (one-time, after sealed-secrets controller is up)
bash bootstrap/06-create-sealed-secrets.sh
```

## Verify

```bash
bash scripts/verify.sh           # full health check
bash scripts/demo-zero-downtime.sh  # rolling update with curl loop
bash scripts/demo-netpol.sh      # prove NetworkPolicies work
```

## Docs

`docs/` covers each area of the system in detail — topology, deployment, access, architecture, security, networking, storage, rollout, extensions, monitoring.
