# Q4 — Business system architecture

## What the cluster runs
A simple but realistic service-with-database business app — **FastAPI + PostgreSQL** — that demonstrates the patterns a real microservice would need: persistence, configuration, secrets, ingress, observability, security.

```
                  ┌──────────────────┐
HTTP via ingress  │ ingress-nginx    │
─────────────────►│ NodePort :30080  │
                  └────────┬─────────┘
                           │ Host: business.local
                           ▼
                  ┌──────────────────┐
                  │ Service: fastapi │
                  │  ClusterIP :80   │
                  └────────┬─────────┘
                           │ round-robin → 2 Pods
                           ▼
              ┌──────────────────────────┐
              │ Deployment: fastapi      │
              │ replicas=2, RU 0/1       │
              │ readOnlyRootFS, drop ALL │
              └────────────┬─────────────┘
                           │ DATABASE_HOST=postgres
                           ▼
                  ┌──────────────────┐
                  │ Service: postgres│
                  │  ClusterIP :5432 │
                  └────────┬─────────┘
                           ▼
              ┌──────────────────────────┐
              │ StatefulSet: postgres    │
              │ replicas=1, PVC 1Gi      │
              │ local-path-provisioner   │
              └──────────────────────────┘
```

## Why FastAPI + Postgres
- **FastAPI** is Python and async — small, easy to reason about in defense, demonstrates async DB I/O via `asyncpg` + SQLAlchemy 2.0 async.
- **PostgreSQL StatefulSet** demonstrates **persistent storage** (Q7) with PVC, and **stable network identity** (`postgres-0`).
- The two together exercise: ConfigMap, SealedSecret, Service-to-Service DNS, NetworkPolicy ingress/egress isolation, Ingress with hostname, ServiceMonitor scrape, RollingUpdate with readiness probe.

## API surface
- `GET /health` → liveness, no DB call, returns version
- `GET /ready` → readiness, runs `SELECT 1` against Postgres — fails fast if DB is down
- `GET /version` → `{"version": "1.0.0"}` — used by the zero-downtime demo to *prove* the rollout actually changed code, not just rolled pods
- `GET /metrics` → Prometheus exposition (RPS, latency histogram, exception counter)
- `GET /items`, `POST /items`, `GET /items/{id}`, `DELETE /items/{id}` → CRUD against the `items` table

## Why this matters for the cluster
The cluster exists to safely host this kind of app: single tenant, persistent data, public-facing, observability-instrumented. Every infra decision (NetworkPolicy, PDB, RollingUpdate, ServiceMonitor) is justified by something the business app actually needs.
