#!/usr/bin/env bash
# Step 3/6 — Pull kubeconfig from VM, rewrite localhost → VM IP, save to repo root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VM_HOST="${VM_HOST:-192.168.10.12}"
VM_USER="${VM_USER:-root}"
KUBECONFIG_PATH="${REPO_ROOT}/kubeconfig"

echo "==> Fetching kubeconfig from ${VM_USER}@${VM_HOST}"
ssh "${VM_USER}@${VM_HOST}" "cat /etc/kubernetes/admin.conf" \
  | sed "s|server: https://127.0.0.1:6443|server: https://${VM_HOST}:6443|g" \
  > "$KUBECONFIG_PATH"
chmod 600 "$KUBECONFIG_PATH"

echo "==> Verifying"
KUBECONFIG="$KUBECONFIG_PATH" kubectl get nodes

echo
echo "kubeconfig saved to: $KUBECONFIG_PATH"
echo "Use it: export KUBECONFIG=$KUBECONFIG_PATH"
