# Q8 — Rollout strategy

## Strategy: RollingUpdate with `maxUnavailable: 0`

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0   # ← never drop below replicas during rollout
    maxSurge: 1         # ← may temporarily run replicas+1 to swap one in
```
Combined with:
- `replicas: 2`
- `readinessProbe` on `/ready` (which checks Postgres connectivity), so a new pod doesn't get traffic until it can actually serve requests
- `PodDisruptionBudget minAvailable: 1` to protect from voluntary drains during maintenance

… we get **zero-downtime updates by construction**, not by hope.

## How an update flows (GitOps)
1. Build new image: `scripts/build-image.sh 2.0.0`
2. Edit `charts/business/values.yaml` → bump `fastapi.image.tag` to `2.0.0`
3. `git commit && git push`
4. ArgoCD reconciles within ~30s, applies the new chart, kubelet rolls the Deployment
5. Curl loop running in parallel sees ALL HTTP 200s — never a 5xx, never a connection refused

This is the **canonical GitOps update**: the diff in git IS the change, the cluster catches up.

## Live demo: `scripts/demo-zero-downtime.sh <new_tag>`
```bash
# Terminal 1: drive the demo
./scripts/demo-zero-downtime.sh 2.0.0
```
The script:
1. Starts a port-forward to ingress-nginx
2. Runs a curl loop hitting `/version` every 200 ms — colour-coded green=200, red=anything else
3. Patches `values.yaml` to the new tag, prompts for commit/push
4. Watches `kubectl rollout status` in foreground

Expected output: ~50 green 200s, all reading version `1.0.0`, then ~50 green 200s reading `2.0.0`. Never a red.

## Auto-scaling (next step, not in 9.35 scope)
- HPA on FastAPI by `metric: http_requests_per_second` (custom metric served by `/metrics`).
- Currently `replicas: 2` is fixed — sufficient to demonstrate zero-downtime; HPA would add the autoscaling story for the final-Perfection bump (40 points).

## Rollback
- Either `git revert` the bump commit (preferred — preserves audit trail), OR
- `argocd app rollback business <revision>` for an emergency revert.
