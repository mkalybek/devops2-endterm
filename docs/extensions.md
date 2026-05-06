# Custom extensions / CRDs

## Currently deployed CRDs (from operators)
The cluster runs multiple CRDs through bundled operators — none of which we authored, but their presence and our use of them does count as "custom extensions to the API surface":

| CRD | Operator | What we do with it |
|---|---|---|
| `SealedSecret` | bitnami sealed-secrets | encrypted DB credentials in git |
| `ServiceMonitor` | prometheus-operator | tells Prometheus to scrape `fastapi` `/metrics` |
| `PodMonitor`, `PrometheusRule` | prometheus-operator | (available, not yet used) |
| `Alertmanager`, `Prometheus` | prometheus-operator | the operator's own resource model |

The custom resource we *actively use* is `ServiceMonitor` — see `charts/business/templates/servicemonitor.yaml`. It tells Prometheus how to discover and scrape FastAPI without us touching Prometheus's own config.

## Roadmap: a custom controller
A proof-of-concept controller from `lab12/controller.sh` (a shell loop that detects Deployments missing labels/limits) is the obvious starting point. To level up to a real CRD-backed operator, the next step would be:

1. Define a `ResourceLimitPolicy` CRD with fields `defaultRequests`, `defaultLimits`, `namespaceSelector`.
2. Write a controller in **kopf** (Python) — ~150 lines.
3. Watch `Deployment` objects, mutate to inject defaults if missing, emit a status event.
4. Package as a chart, deploy via ArgoCD as another sync-wave.

This is the natural upgrade path when we want to manage policies as cluster API objects rather than ad-hoc shell loops.

## Live verification
```bash
kubectl get crd | sort
kubectl -n business get servicemonitor fastapi
kubectl -n monitoring get prometheus,alertmanager
kubectl -n kube-system get sealedsecret 2>/dev/null   # sealed creds
```
