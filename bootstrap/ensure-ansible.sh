#!/usr/bin/env bash
# Idempotent: ensures kubespray/.venv/bin/ansible-playbook exists, so
# Terraform's local-exec bootstrap can find ansible-playbook on PATH
# regardless of the user's current shell/venv. Reuses the kubespray venv
# (created by ansible/site.yml anyway) to avoid double-provisioning.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="${REPO_ROOT}/kubespray/.venv"

if [ ! -x "${VENV}/bin/ansible-playbook" ]; then
  echo "==> Creating Python venv at ${VENV}"
  python3 -m venv "$VENV"
  "${VENV}/bin/pip" install --quiet --upgrade pip
  "${VENV}/bin/pip" install --quiet 'ansible-core>=2.16,<2.18'
fi

# kubernetes.core.k8s + community.general.modprobe etc. need these libs in
# the venv that ansible-playbook runs in. Idempotent — pip skips if present.
if ! "${VENV}/bin/python3" -c 'import kubernetes' 2>/dev/null; then
  echo "==> Installing kubernetes Python lib into venv"
  "${VENV}/bin/pip" install --quiet kubernetes
fi

# Ansible Galaxy collections (kubernetes.core, community.general, ansible.posix)
if ! "${VENV}/bin/ansible-galaxy" collection list kubernetes.core 2>/dev/null | grep -q kubernetes.core; then
  echo "==> Installing ansible galaxy collections"
  "${VENV}/bin/ansible-galaxy" collection install -r "${REPO_ROOT}/ansible/requirements.yml"
fi

echo "==> Ansible ready: $(${VENV}/bin/ansible-playbook --version | head -1)"
