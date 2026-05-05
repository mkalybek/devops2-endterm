#!/usr/bin/env bash
# Step 5/6 — Install ArgoCD, then apply the root-app (app-of-apps).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"

ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.2}"

echo "==> Creating argocd namespace"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing ArgoCD ${ARGOCD_VERSION}"
kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for argocd-server to become Ready"
kubectl -n argocd wait --for=condition=available --timeout=300s deploy/argocd-server

echo "==> Initial admin password (save this — argocd-cli login uses it):"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo

echo "==> Applying root-app (app-of-apps)"
kubectl apply -f "${REPO_ROOT}/argocd/root-app.yaml"

echo
echo "ArgoCD installed. Next: bash bootstrap/06-create-sealed-secrets.sh"
echo "UI: kubectl -n argocd port-forward svc/argocd-server 8081:443"
echo "Then: argocd login localhost:8081 --insecure --username admin --password <above>"
