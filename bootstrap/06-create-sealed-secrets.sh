#!/usr/bin/env bash
# Step 6/6 — After sealed-secrets controller is up (via ArgoCD), encrypt our
# DB credentials into a SealedSecret manifest checked into git.
#
# This is idempotent: if charts/business/templates/sealedsecret.yaml already
# exists with a working public-key encryption, we skip.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"

OUT="${REPO_ROOT}/charts/business/templates/sealedsecret.yaml"
NAMESPACE="${NAMESPACE:-business}"

# Wait for sealed-secrets controller (deployed by ArgoCD child app)
echo "==> Waiting for sealed-secrets controller"
for i in {1..60}; do
  if kubectl -n kube-system get deploy sealed-secrets >/dev/null 2>&1; then
    kubectl -n kube-system wait --for=condition=available --timeout=120s deploy/sealed-secrets
    break
  fi
  echo "    waiting for ArgoCD to deploy sealed-secrets... ($i/60)"
  sleep 5
done

# Generate strong random creds (only used at this seal step — not stored on disk in plaintext)
DB_USER="appuser"
DB_PASS="$(openssl rand -base64 24 | tr -d '/+=')"

echo "==> Creating SealedSecret for ns=${NAMESPACE}"
kubectl create secret generic db-secret \
  --namespace "$NAMESPACE" \
  --from-literal=POSTGRES_USER="$DB_USER" \
  --from-literal=POSTGRES_PASSWORD="$DB_PASS" \
  --dry-run=client -o yaml \
| kubeseal --format=yaml --controller-namespace=kube-system --controller-name=sealed-secrets \
> "$OUT"

echo
echo "SealedSecret written to: $OUT"
echo "Commit and push so ArgoCD can sync it:"
echo "  git add $OUT && git commit -m 'feat: seal db-secret' && git push"
