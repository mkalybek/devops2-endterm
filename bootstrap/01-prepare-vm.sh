#!/usr/bin/env bash
# Step 1/6 — Prepare the VM for Kubespray.
#
# Runs an Ansible playbook (ansible/prepare-vm.yml) over SSH against the host
# defined in ansible/inventory.ini. Idempotent — safe to rerun.
#
# Prereqs on Mac: ansible, ansible-galaxy, ssh access to root@<vm>.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Installing Ansible collections"
ansible-galaxy collection install -r ansible/requirements.yml >/dev/null 2>&1 || \
  ansible-galaxy collection install community.general ansible.posix --upgrade

echo "==> Probing SSH"
ansible -i ansible/inventory.ini vm -m ping

echo "==> Running prepare-vm.yml"
ansible-playbook -i ansible/inventory.ini ansible/prepare-vm.yml -v "$@"

echo
echo "VM is ready for Kubespray. Next: bash bootstrap/02-run-kubespray.sh"
