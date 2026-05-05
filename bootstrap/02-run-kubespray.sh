#!/usr/bin/env bash
# Step 2/6 — Clone Kubespray, copy our single-node inventory, run cluster.yml.
#
# Single-node = same host appears under [kube_control_plane] and [kube_node].
# Kubespray installs containerd as CRI and Calico as CNI (see group_vars).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

KUBESPRAY_VERSION="${KUBESPRAY_VERSION:-v2.27.0}"
KUBESPRAY_DIR="${REPO_ROOT}/kubespray"

if [ ! -d "$KUBESPRAY_DIR/.git" ]; then
  echo "==> Cloning kubespray ${KUBESPRAY_VERSION}"
  git clone --depth 1 --branch "$KUBESPRAY_VERSION" \
    https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"
fi

echo "==> Setting up venv with kubespray python deps"
if [ ! -d "$KUBESPRAY_DIR/.venv" ]; then
  python3 -m venv "$KUBESPRAY_DIR/.venv"
fi
# shellcheck disable=SC1091
source "$KUBESPRAY_DIR/.venv/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet -r "$KUBESPRAY_DIR/requirements.txt"

echo "==> Syncing our single-node inventory into kubespray"
INV_DIR="$KUBESPRAY_DIR/inventory/devops2"
rm -rf "$INV_DIR"
cp -r "$KUBESPRAY_DIR/inventory/sample" "$INV_DIR"
cp "$REPO_ROOT/bootstrap/kubespray-inventory/inventory.ini" "$INV_DIR/inventory.ini"
cp "$REPO_ROOT/bootstrap/kubespray-inventory/k8s-cluster-overrides.yml" \
   "$INV_DIR/group_vars/k8s_cluster/k8s-cluster.yml"

echo "==> Running kubespray cluster.yml (this takes ~15-20 minutes)"
cd "$KUBESPRAY_DIR"
ansible-playbook -i "inventory/devops2/inventory.ini" \
  --become --become-user=root \
  cluster.yml "$@"

echo
echo "Cluster is up. Next: bash bootstrap/03-fetch-kubeconfig.sh"
