#!/usr/bin/env bash
# One-shot repair script for when the VM's IP changes (e.g. moved to a different
# WiFi / phone hotspot). Patches all the static-pod manifests and kubeconfigs
# that hard-bake the old IP, restarts the relevant components, and refreshes
# the local Mac kubeconfig.
#
# Usage:  VM_HOST_NEW=172.20.10.4 bash bootstrap/repair-after-ip-change.sh
#
# Required env:
#   VM_HOST_NEW   the VM's current IP
# Optional:
#   VM_USER       defaults to root
#   VM_HOST_OLD   defaults to 'auto-detect from /etc/kubernetes/admin.conf'

set -euo pipefail

VM_HOST_NEW="${VM_HOST_NEW:?usage: VM_HOST_NEW=<ip> $0}"
VM_USER="${VM_USER:-root}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> [1/5] Detect old IP from VM"
OLD_IP=$(ssh "${VM_USER}@${VM_HOST_NEW}" "grep -oE 'https://[0-9.]+:6443' /etc/kubernetes/admin.conf | head -1 | sed 's|https://||;s|:6443||'")
echo "  old=${OLD_IP}  new=${VM_HOST_NEW}"
if [ "$OLD_IP" = "$VM_HOST_NEW" ]; then
  echo "  IP unchanged, nothing to do"
  exit 0
fi

echo "==> [2/5] Patch all kubeconfigs and apiserver manifest on VM (-> 127.0.0.1 for cluster-internal)"
ssh "${VM_USER}@${VM_HOST_NEW}" "
  set -e
  sed -i \"s|--advertise-address=${OLD_IP}|--advertise-address=${VM_HOST_NEW}|; s|advertise-address.endpoint: ${OLD_IP}:6443|advertise-address.endpoint: ${VM_HOST_NEW}:6443|; s|https://${OLD_IP}:6443|https://127.0.0.1:6443|g\" /etc/kubernetes/manifests/kube-apiserver.yaml
  for f in /etc/kubernetes/*.conf /etc/kubernetes/*.yaml; do
    [ -f \"\$f\" ] && sed -i \"s|https://${OLD_IP}:6443|https://127.0.0.1:6443|g\" \"\$f\" 2>/dev/null || true
  done
  sed -i \"s|--node-ip=${OLD_IP}|--node-ip=${VM_HOST_NEW}|\" /etc/kubernetes/kubelet.env
"

echo "==> [3/5] Restart kubelet and control-plane static pods"
ssh "${VM_USER}@${VM_HOST_NEW}" "
  systemctl restart kubelet
  sleep 5
  for c in kube-apiserver kube-controller-manager kube-scheduler; do
    cid=\$(crictl ps --name \$c -q | head -1)
    [ -n \"\$cid\" ] && crictl stop \$cid >/dev/null 2>&1 || true
  done
  sleep 8
"

echo "==> [4/5] Re-register node with new IP"
ssh "${VM_USER}@${VM_HOST_NEW}" "
  for i in {1..20}; do
    KUBECONFIG=/etc/kubernetes/admin.conf kubectl --request-timeout=3s get nodes >/dev/null 2>&1 && break
    sleep 4
  done
  KUBECONFIG=/etc/kubernetes/admin.conf kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}' | grep -q \"${VM_HOST_NEW}\" || {
    KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete node node1 --ignore-not-found
    sleep 12
    KUBECONFIG=/etc/kubernetes/admin.conf kubectl label node node1 node-role.kubernetes.io/control-plane= 2>/dev/null || true
  }
  echo
  KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide
"

echo "==> [5/5] Refresh Mac kubeconfig (insecure-skip-tls-verify because cert SAN doesn't include new IP)"
ssh "${VM_USER}@${VM_HOST_NEW}" 'cat /etc/kubernetes/admin.conf' \
  | sed "s|server: https://127.0.0.1:6443|server: https://${VM_HOST_NEW}:6443|; s|certificate-authority-data:.*|insecure-skip-tls-verify: true|" \
  > "${REPO_ROOT}/kubeconfig"
chmod 600 "${REPO_ROOT}/kubeconfig"

echo "==> Force restart components that cached the old apiserver address"
KUBECONFIG="${REPO_ROOT}/kubeconfig" kubectl -n monitoring rollout restart deploy monitoring-kube-state-metrics 2>/dev/null || true
KUBECONFIG="${REPO_ROOT}/kubeconfig" kubectl -n monitoring rollout restart ds monitoring-prometheus-node-exporter 2>/dev/null || true

echo
echo "Repair complete. Verify with:"
echo "  KUBECONFIG=${REPO_ROOT}/kubeconfig kubectl get nodes -o wide"
echo
echo "Don't forget to update /etc/hosts on Mac:"
echo "  sudo sed -i.bak \"/business.local\\|grafana.local\\|argocd.local/d\" /etc/hosts"
echo "  echo \"${VM_HOST_NEW} business.local grafana.local argocd.local\" | sudo tee -a /etc/hosts"
