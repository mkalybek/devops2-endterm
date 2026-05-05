#!/usr/bin/env bash
# Post-kubespray bootstrap: untaint master, fetch kubeconfig to Mac, install
# ArgoCD on the VM (so the apply uses the VM's working DNS), apply root-app.
#
# Run AFTER cluster.yml has completed successfully.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VM_HOST="${VM_HOST:-192.168.10.12}"
VM_USER="${VM_USER:-root}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v3.0.0}"

bold() { printf "\n\033[1m== %s ==\033[0m\n" "$*"; }

bold "[1/5] Verify kubespray cluster on VM"
ssh "${VM_USER}@${VM_HOST}" '
  export KUBECONFIG=/etc/kubernetes/admin.conf
  kubectl get nodes -o wide
  echo
  kubectl get pods -A | head -20
'

bold "[2/5] Untaint single-node master so workloads schedule"
ssh "${VM_USER}@${VM_HOST}" '
  export KUBECONFIG=/etc/kubernetes/admin.conf
  NODE=$(kubectl get nodes -o jsonpath="{.items[0].metadata.name}")
  kubectl taint nodes "$NODE" node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
  kubectl taint nodes "$NODE" node-role.kubernetes.io/master:NoSchedule- 2>/dev/null || true
  echo "remaining taints:"
  kubectl get node "$NODE" -o jsonpath="{.spec.taints}" || echo "(none)"
  echo
'

bold "[3/5] Fetch kubeconfig to Mac (rewrite 127.0.0.1 -> ${VM_HOST})"
ssh "${VM_USER}@${VM_HOST}" "cat /etc/kubernetes/admin.conf" \
  | sed "s|server: https://127.0.0.1:6443|server: https://${VM_HOST}:6443|g" \
  > "${REPO_ROOT}/kubeconfig"
chmod 600 "${REPO_ROOT}/kubeconfig"
KUBECONFIG="${REPO_ROOT}/kubeconfig" kubectl get nodes
echo "kubeconfig saved → ${REPO_ROOT}/kubeconfig"

bold "[4/5] Install ArgoCD on the VM (uses VM DNS for github fetch)"
ssh "${VM_USER}@${VM_HOST}" "
  export KUBECONFIG=/etc/kubernetes/admin.conf
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml
  kubectl -n argocd wait --for=condition=available --timeout=300s deploy/argocd-server
  echo
  echo 'Initial admin password:'
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  echo
"

bold "[5/5] Apply root-app via VM (so ArgoCD pulls our github repo)"
scp "${REPO_ROOT}/argocd/root-app.yaml" "${VM_USER}@${VM_HOST}:/tmp/root-app.yaml"
ssh "${VM_USER}@${VM_HOST}" "
  export KUBECONFIG=/etc/kubernetes/admin.conf
  kubectl apply -f /tmp/root-app.yaml
  rm /tmp/root-app.yaml
  echo
  echo 'ArgoCD applications (will populate as it syncs):'
  kubectl -n argocd get applications
"

bold "Done"
echo "Next steps:"
echo "  1. Watch ArgoCD sync:  KUBECONFIG=${REPO_ROOT}/kubeconfig kubectl -n argocd get app -w"
echo "  2. ArgoCD UI:          KUBECONFIG=${REPO_ROOT}/kubeconfig kubectl -n argocd port-forward svc/argocd-server 8081:443"
echo "  3. Build app image:    bash scripts/build-image.sh 1.0.0"
echo "  4. Seal db secret:     bash bootstrap/06-create-sealed-secrets.sh"
