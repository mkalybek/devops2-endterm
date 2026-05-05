# Q10 — Monitoring

## What we collect

### Metrics — kube-prometheus-stack
Helm chart `prometheus-community/kube-prometheus-stack` brings:
- **Prometheus** — TSDB, 7-day retention, 5 Gi PVC.
- **Alertmanager** — alert routing/silencing (1 Gi PVC).
- **Grafana** — visualisation (2 Gi PVC, persistent dashboards).
- **kube-state-metrics** — exports k8s object state as metrics.
- **node-exporter** — exports host CPU/RAM/disk/net.
- **prometheus-operator** — manages all the above as CRDs (`Prometheus`, `Alertmanager`, `ServiceMonitor`, `PrometheusRule`).

### Logs — loki-stack
Helm chart `grafana/loki-stack` brings:
- **Loki** — log storage (5 Gi PVC).
- **Promtail** — DaemonSet that tails every container log on the node and ships to Loki, labelled with `namespace`, `pod`, `container`.

### Visualisation — Grafana
- **Default dashboards**: cluster, nodes, pods, kubelet, API server (auto-provisioned by kube-prometheus-stack).
- **Custom dashboard**: `monitoring/grafana-dashboards/fastapi-dashboard.yaml` — a `ConfigMap` with `grafana_dashboard: "1"` label; Grafana's dashboard sidecar picks it up automatically.
  - Panels: RPS by handler, 5xx error rate, p95 latency, ready replicas.
- **Loki datasource** is registered automatically via `kube-prometheus-stack`'s `additionalDataSources`. Switch the explore mode to query logs.

## Wiring FastAPI in
- `prometheus-fastapi-instrumentator` exposes default RED metrics on `/metrics`.
- A `ServiceMonitor` in the `business` namespace tells Prometheus "scrape `fastapi:80/metrics` every 15s".
- A `NetworkPolicy` `allow-fastapi-from-monitoring` permits the scrape across namespaces (without it the default-deny would block it).

## Access for defense
```bash
# Grafana
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
# → http://localhost:3000  (admin / admin)

# Prometheus targets — to prove ServiceMonitor scraping is healthy
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
# → http://localhost:9090/targets

# Alertmanager
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093
```

## Live verification
```bash
kubectl -n monitoring get pods
kubectl get servicemonitor -A
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 &
curl -s -u admin:admin http://localhost:3000/api/health   # → {"database":"ok"}
```
