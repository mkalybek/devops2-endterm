#!/usr/bin/env bash
# Hard wipe of the Kubernetes single-node VM.
#
# Use when the cluster is wedged (stale IP, half-finished kubespray, broken
# etcd) and you want to redeploy from a clean Ubuntu host with
# `terraform apply -var=run_bootstrap=true`. Safer/faster than chasing
# `kubespray reset.yml`, which fails idempotency once containerd is gone.
#
# NOT touched: home dirs, SSH keys, fstab, kernel modules, apt packages,
# NIC config — only Kubernetes / etcd / CNI state.
#
# Usage:  VM_HOST=192.168.10.68 bash bootstrap/wipe-vm.sh
#         (or rely on the Terraform-managed tfvars IP — picked up automatically)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Pick IP from arg → env → terraform.tfvars in that order.
if [ -n "${1:-}" ]; then
  VM_HOST="$1"
elif [ -n "${VM_HOST:-}" ]; then
  :
elif [ -f "${REPO_ROOT}/terraform/terraform.tfvars" ]; then
  VM_HOST="$(awk -F'"' '/^vm_ip/ {print $2}' "${REPO_ROOT}/terraform/terraform.tfvars")"
else
  echo "usage: $0 <vm-ip>   (or set VM_HOST, or populate terraform/terraform.tfvars)" >&2
  exit 2
fi
VM_USER="${VM_USER:-root}"

echo "==> Wiping ${VM_USER}@${VM_HOST}"
read -r -p "    type 'WIPE' to confirm: " ack
[ "$ack" = "WIPE" ] || { echo "aborted"; exit 1; }

ssh -o ConnectTimeout=10 "${VM_USER}@${VM_HOST}" 'bash -s' <<'REMOTE'
set +e
echo "==> [1/6] Stop + disable services"
systemctl stop kubelet etcd etcd-events containerd cri-dockerd cri-dockerd.socket calico-node 2>/dev/null
systemctl disable kubelet etcd etcd-events containerd cri-dockerd calico-node 2>/dev/null
systemctl reset-failed 2>/dev/null

echo "==> [2/6] Remove control-plane + node state"
rm -rf /etc/kubernetes
rm -rf /var/lib/etcd /var/lib/etcd-events
rm -rf /var/lib/kubelet
rm -rf /var/lib/calico /var/lib/cni
rm -rf /etc/cni /opt/cni
rm -rf /run/calico /run/flannel
rm -f  /etc/etcd.env
rm -f  /etc/etcd.env.bak.*
rm -f  /etc/systemd/system/kubelet.service
rm -f  /etc/systemd/system/etcd.service /etc/systemd/system/etcd-events.service
rm -f  /etc/systemd/system/calico-node.service
rm -rf /etc/systemd/system/kubelet.service.d
rm -rf /etc/systemd/system/containerd.service.d
rm -rf /var/lib/containerd
rm -f  /usr/local/bin/kubelet /usr/local/bin/kubeadm /usr/local/bin/kubectl
rm -f  /usr/local/bin/crictl /usr/local/bin/etcd /usr/local/bin/etcdctl
rm -rf /opt/containerd /etc/containerd
rm -rf /var/log/pods /var/log/containers
rm -rf /root/.kube

echo "==> [3/6] Flush iptables (all tables) + ipvs"
for t in filter nat mangle raw; do
  iptables  -t "$t" -F 2>/dev/null; iptables  -t "$t" -X 2>/dev/null
  ip6tables -t "$t" -F 2>/dev/null; ip6tables -t "$t" -X 2>/dev/null
done
ipvsadm -C 2>/dev/null

echo "==> [4/6] Drop residual CNI interfaces"
for i in cni0 flannel.1 kube-ipvs0 vxlan.calico tunl0 docker0; do
  ip link show "$i" >/dev/null 2>&1 && ip link delete "$i"
done
ip link show | awk -F: '/cali[0-9a-f]+@/ {gsub(/@.*/,"",$2); print $2}' \
  | xargs -r -I{} ip link delete {} 2>/dev/null

echo "==> [5/6] systemd daemon-reload"
systemctl daemon-reload
systemctl reset-failed

echo "==> [6/6] Verify"
echo "--- listening on :6443/:2379/:10250 ---"
ss -tlnp 2>/dev/null | grep -E ":6443|:2379|:10250" || echo "(none - good)"
echo "--- /etc/kubernetes ---"
ls /etc/kubernetes 2>/dev/null || echo "(absent - good)"
echo "--- /var/lib/etcd ---"
ls /var/lib/etcd 2>/dev/null || echo "(absent - good)"
echo "--- iptables filter line count ---"
iptables -L -n 2>/dev/null | wc -l
echo "WIPE COMPLETE"
REMOTE
