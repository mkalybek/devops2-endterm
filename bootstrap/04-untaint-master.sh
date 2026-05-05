#!/usr/bin/env bash
# Step 4/6 — Single-node: remove the control-plane NoSchedule taint so workloads
# can land on the only node we have.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"

NODE="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
echo "==> Untainting node: $NODE"

# Idempotent — '|| true' so rerun is safe
kubectl taint nodes "$NODE" node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
kubectl taint nodes "$NODE" node-role.kubernetes.io/master:NoSchedule- 2>/dev/null || true

echo "==> Final taints:"
kubectl get node "$NODE" -o jsonpath='{.spec.taints}' || echo "(none)"
echo
