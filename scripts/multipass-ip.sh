#!/usr/bin/env bash
# Wrapper for Terraform's `external` data source.
# Stdin:  {"name": "<multipass-instance>"}
# Stdout: {"ip": "<ipv4-or-empty>"}
#
# Returns the first global IPv4 from `multipass info`, skipping link-local
# and the Kubernetes pod/service CIDRs (10.42.*, 10.233.*) that show up
# once Calico is running. If the instance doesn't exist or has no IP yet,
# returns {"ip":""} — Terraform's precondition turns that into a clear
# "run bootstrap/up-vm.sh first" error.

set -euo pipefail

name=$(jq -r '.name')

ip=""
info=$(multipass info "$name" --format json 2>/dev/null || true)
if [ -n "$info" ]; then
  ip=$(printf '%s' "$info" | jq -r --arg n "$name" '
    (.info[$n].ipv4 // [])
    | map(select(startswith("169.254.") | not))
    | map(select(startswith("10.") or startswith("172.") or startswith("192.168.")))
    | map(select(startswith("10.42.") or startswith("10.233.") | not))
    | .[0] // ""
  ')
fi

jq -n --arg ip "$ip" '{ip: $ip}'
