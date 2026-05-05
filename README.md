# DevOps2 Endterm — Single-Node Kubernetes Platform

Production-style single-node Kubernetes cluster on Ubuntu 25.10 (ARM64) with full GitOps, monitoring, and security best practices.

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
                      │  VM: 192.168.10.12 (Ubuntu 25.10)   │
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

# 5. Bootstrap ArgoCD + sealed-secrets + apply root-app
bash bootstrap/05-install-argocd.sh
bash bootstrap/06-create-sealed-secrets.sh

# 6. Apply root-app (ArgoCD manages everything from here)
kubectl apply -f argocd/root-app.yaml
```

## Verify

```bash
bash scripts/verify.sh           # full health check
bash scripts/demo-zero-downtime.sh  # rolling update with curl loop
bash scripts/demo-netpol.sh      # prove NetworkPolicies work
```

## Defense Q&A

See `docs/01-topology.md` ... `docs/10-monitoring.md`.
