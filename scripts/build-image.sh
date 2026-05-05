#!/usr/bin/env bash
# Build the FastAPI image directly into containerd's k8s.io namespace on the
# VM, so single-node Pods can use it without a registry (imagePullPolicy=Never).
#
# Usage:  scripts/build-image.sh <tag>          # e.g. 1.0.0
#         scripts/build-image.sh 2.0.0          # for the zero-downtime demo

set -euo pipefail

TAG="${1:?usage: $0 <tag>   e.g. 1.0.0}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VM_HOST="${VM_HOST:-192.168.10.12}"
VM_USER="${VM_USER:-root}"

IMAGE="business-fastapi:${TAG}"
REMOTE_DIR="/root/build-business-fastapi"

echo "==> [1/4] Sync sources to ${VM_USER}@${VM_HOST}:${REMOTE_DIR}"
ssh "${VM_USER}@${VM_HOST}" "mkdir -p ${REMOTE_DIR}"
rsync -a --delete \
  --exclude='__pycache__' --exclude='.venv' --exclude='*.pyc' \
  "${REPO_ROOT}/app/" \
  "${VM_USER}@${VM_HOST}:${REMOTE_DIR}/"

echo "==> [2/4] Ensure buildkitd is running on VM"
ssh "${VM_USER}@${VM_HOST}" '
  if ! systemctl is-active --quiet buildkit; then
    systemctl enable --now buildkit 2>/dev/null || \
      nohup buildkitd >/var/log/buildkitd.log 2>&1 &
    sleep 2
  fi
'

echo "==> [3/4] Build ${IMAGE} on VM into containerd k8s.io namespace"
ssh "${VM_USER}@${VM_HOST}" "
  cd ${REMOTE_DIR} && \
  nerdctl --namespace=k8s.io build \
    --build-arg APP_VERSION=${TAG} \
    -t ${IMAGE} \
    .
"

echo "==> [4/4] Verify image is visible to kubelet"
ssh "${VM_USER}@${VM_HOST}" "nerdctl --namespace=k8s.io images | grep business-fastapi"

echo
echo "Image ${IMAGE} built and loaded. Bump tag in charts/business/values.yaml,"
echo "commit, and push — ArgoCD will roll the Deployment with maxUnavailable=0."
