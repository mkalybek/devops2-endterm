#!/usr/bin/env bash
# Bring up (or resume) the single-node Kubernetes VM under Multipass.
#
# Why Multipass instead of "some IP on the LAN":
#   - The VM lives on the Mac, on Multipass' internal NAT — its IP only
#     changes when the instance is destroyed. WiFi/hotspot changes no longer
#     break the cluster.
#   - IP discovery is automated (`multipass info --format json`), so nothing
#     in this repo hardcodes the address — Terraform pulls it at apply-time.
#
# Idempotent:
#   - First run: launches Ubuntu 24.04, runs cloud-init to inject SSH key
#     and enable root login, prints the assigned IP.
#   - Subsequent runs: starts a stopped instance, otherwise no-op.
#
# Usage:  bash bootstrap/up-vm.sh
# Tunables (env):
#   VM_NAME    default: node1
#   VM_CPUS    default: 4
#   VM_MEM     default: 7G
#   VM_DISK    default: 40G
#   VM_IMAGE   default: 24.04
#   SSH_PUBKEY default: ~/.ssh/id_ed25519.pub

set -euo pipefail

VM_NAME="${VM_NAME:-node1}"
VM_CPUS="${VM_CPUS:-4}"
VM_MEM="${VM_MEM:-7G}"
VM_DISK="${VM_DISK:-40G}"
VM_IMAGE="${VM_IMAGE:-24.04}"
SSH_PUBKEY="${SSH_PUBKEY:-$HOME/.ssh/id_ed25519.pub}"

command -v multipass >/dev/null || { echo "multipass not installed: brew install --cask multipass" >&2; exit 1; }
command -v jq        >/dev/null || { echo "jq not installed: brew install jq" >&2; exit 1; }
[ -r "$SSH_PUBKEY" ]            || { echo "ssh pubkey not readable: $SSH_PUBKEY" >&2; exit 1; }

info=$(multipass info "$VM_NAME" --format json 2>/dev/null || true)
if [ -n "$info" ]; then
  state=$(printf '%s' "$info" | jq -r ".info[\"$VM_NAME\"].state // \"absent\"")
else
  state="absent"
fi

case "$state" in
  Running)
    echo "==> ${VM_NAME} already Running"
    ;;
  Stopped|Suspended)
    echo "==> ${VM_NAME} is ${state}, starting"
    multipass start "$VM_NAME"
    ;;
  absent)
    echo "==> Launching ${VM_NAME} (${VM_CPUS} CPU / ${VM_MEM} RAM / ${VM_DISK} disk, Ubuntu ${VM_IMAGE})"
    # cloud-init: inject the Mac's pubkey for root + ubuntu, enable root SSH.
    cloud_init=$(mktemp)
    trap "rm -f $cloud_init" EXIT
    pubkey="$(cat "$SSH_PUBKEY")"
    cat >"$cloud_init" <<EOF
#cloud-config
users:
  - name: root
    ssh_authorized_keys:
      - ${pubkey}
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${pubkey}
ssh_pwauth: false
runcmd:
  - sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  - systemctl restart ssh
package_update: true
packages:
  - python3
  - python3-apt
EOF
    multipass launch \
      --name "$VM_NAME" \
      --cpus "$VM_CPUS" \
      --memory "$VM_MEM" \
      --disk "$VM_DISK" \
      --cloud-init "$cloud_init" \
      "$VM_IMAGE"
    ;;
  *)
    echo "==> ${VM_NAME} in unexpected state: ${state}" >&2
    exit 1
    ;;
esac

echo "==> Waiting for SSH on root@${VM_NAME}"
for i in $(seq 1 30); do
  ip=$(multipass info "$VM_NAME" --format json | jq -r ".info[\"$VM_NAME\"].ipv4[0] // empty")
  [ -n "$ip" ] && ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o BatchMode=yes "root@${ip}" true 2>/dev/null && break
  sleep 2
done
[ -n "${ip:-}" ] || { echo "could not discover IPv4 for ${VM_NAME}" >&2; exit 1; }

echo
echo "==> ${VM_NAME} ready at root@${ip}"
echo "    Next:  cd terraform && terraform apply -var=run_bootstrap=true"
