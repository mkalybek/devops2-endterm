---
marp: true
theme: default
paginate: true
size: 16:9
---

# DevOps2 Endterm
## Single-node Kubernetes platform

`mkalybek` · 2026-05-06

---

## Topology

```
┌─────────────────────────────────────────────────────────────┐
│  VM  192.168.10.12  ·  Ubuntu 25.10  ·  arm64  ·  4 CPU     │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Kubernetes 1.32  ·  kubespray  ·  containerd  ·       │  │
│  │  Calico CNI  ·  CoreDNS  ·  iptables kube-proxy        │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                            ▲
                            │  SSH port-forward
                            ▼
                    Mac (kubectl + git)
```

**1 node** = control-plane + worker · taint removed · single-node mode

---

## Components by layer

| Layer | Component | Purpose |
|---|---|---|
| **Cluster** | kubespray + Ansible | declarative cluster install |
| **Runtime** | containerd, Calico, CoreDNS | CRI / CNI / DNS |
| **GitOps** | ArgoCD v3.0.0 | app-of-apps from `mkalybek/devops2-endterm` |
| **Secrets** | sealed-secrets | encrypt creds at rest in git |
| **Storage** | local-path-provisioner | dynamic PVCs (default SC) |
| **Ingress** | ingress-nginx (NodePort 30080) | north-south traffic |
| **Metrics** | Prometheus + Alertmanager + Grafana | kube-prometheus-stack |
| **Logs** | Loki + Promtail | log aggregation, Grafana datasource |
| **Business** | FastAPI + PostgreSQL | items CRUD with `/metrics` |

---

## ArgoCD app-of-apps

```
                   ┌─────────────────┐
                   │  root           │
                   │  (app-of-apps)  │
                   └────────┬────────┘
                            │
       ┌────────────┬───────┼──────────┬──────────┬───────────┐
       ▼            ▼       ▼          ▼          ▼           ▼
  sealed-      local-path  ingress-  monitoring  loki     business
  secrets      provis.     nginx     (kube-prom) (stack)  (FastAPI+
   wave 0       wave 1     wave 2    wave 3      wave 3   Postgres)
                                                          wave 10
```

Sync-waves enforce ordering · `automated{prune,selfHeal}` · `ServerSideApply`

---

## Security guardrails (Q5)

| Control | Where |
|---|---|
| **NetworkPolicy** default-deny + 6 explicit allows | `business` ns |
| **SecurityContext** runAsNonRoot, readOnlyRoot, drop ALL caps | every container |
| **ResourceQuota** 2 cpu / 2 Gi req · 4 cpu / 4 Gi limit | `business` ns |
| **LimitRange** per-container defaults | `business` ns |
| **PodDisruptionBudget** minAvailable: 1 | fastapi |
| **SealedSecret** encrypted DB creds in git | bitnami sealed-secrets |
| **RBAC** kubeconfig with X.509 client cert | kubespray PKI |

---

## Business app — request path

```
client                                                                 │
  │                                                                    │
  │  curl -H "Host: business.local" http://<vm>:30080/items            │
  ▼                                                                    │
ingress-nginx (NodePort 30080)                                         │
  │                                                                    │
  ▼                                                                    │
Service fastapi (ClusterIP :80)                                        │
  │                                                                    │
  │  round-robin → 2 replicas, RollingUpdate maxUnavailable=0          │
  ▼                                                                    │
fastapi pods (FastAPI + asyncpg)                                       │
  │                                                                    │
  │  DATABASE_HOST=postgres (Service DNS)                              │
  ▼                                                                    │
Service postgres (ClusterIP :5432)                                     │
  │                                                                    │
  ▼                                                                    │
StatefulSet postgres-0 → PVC `data-postgres-0` 1 Gi (local-path)
```

---

## Observability — metrics flow

```
fastapi pod  ──/metrics──►  Prometheus (via ServiceMonitor CRD)
                                   │
                                   ├──► Alertmanager (rules)
                                   │
                                   └──► Grafana datasource
                                              │
                                              ▼
                                   Custom "Business — FastAPI"
                                   dashboard (RPS, 5xx, p95)


promtail  ──tails /var/log/pods──►  Loki  ──►  Grafana datasource
                                                    │
                                                    ▼
                                            Explore mode
```

`prometheus-fastapi-instrumentator` → RED metrics for free

---

## Live access

```bash
export KUBECONFIG=$(pwd)/kubeconfig

# ArgoCD UI         admin / v0Hjzf9EQ8lHFaSa
kubectl -n argocd port-forward svc/argocd-server 8081:443

# Grafana           admin / admin
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80

# Business app (через VM)
ssh root@192.168.10.12 'curl -s -H "Host: business.local" http://127.0.0.1:30080/items'
```

---

## Demo scripts

```bash
bash scripts/verify.sh             # full health snapshot
bash scripts/demo-netpol.sh        # prove NetworkPolicies deny
bash scripts/demo-zero-downtime.sh 2.0.0   # rolling update with 0 downtime
```

`demo-zero-downtime.sh` запускает curl loop в фоне · бампит image tag в git · ArgoCD reconcile → `RollingUpdate maxUnavailable=0` → 100% 200 OK во время rollout

---

## Defense Q-map

| # | Q | File |
|---|---|---|
| 1 | Topology | `docs/01-topology.md` |
| 2 | Deployment process | `docs/02-deployment.md` |
| 3 | Access / config mgmt | `docs/03-access.md` |
| 4 | Business architecture | `docs/04-architecture.md` |
| 5 | Workload security | `docs/05-security.md` |
| 6 | Networking | `docs/06-networking.md` |
| 7 | Storage | `docs/07-storage.md` |
| 8 | Rollout | `docs/08-rollout.md` |
| 9 | Custom extensions | `docs/09-extensions.md` |
| 10 | Monitoring | `docs/10-monitoring.md` |
