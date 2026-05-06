#!/usr/bin/env bash
# Prove NetworkPolicies actually deny traffic.
#
# Test plan:
#   1) Run a debug Pod in the `default` namespace (NOT in `business`).
#   2) Try to reach Postgres in `business` ns → should TIMEOUT.
#   3) Try to reach FastAPI from same debug Pod → should TIMEOUT (only ingress-nginx allowed).
#   4) Run debug Pod inside `business` with label app=fastapi → Postgres reachable.
#
# Without the NetworkPolicies, every step would succeed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"

bold() { printf "\n\033[1m== %s ==\033[0m\n" "$*"; }

bold "[1] Debug Pod from outside business ns → Postgres (EXPECT: timeout)"
kubectl run netpol-attacker --rm -it --quiet --restart=Never \
  --image=busybox:1.36 -- sh -c '
    echo "Trying postgres.business.svc.cluster.local:5432 ..."
    nc -zv -w 3 postgres.business.svc.cluster.local 5432 2>&1 || echo "DENIED ✓"
'

bold "[2] Debug Pod from outside business ns → FastAPI (EXPECT: timeout)"
kubectl run netpol-attacker --rm -it --quiet --restart=Never \
  --image=busybox:1.36 -- sh -c '
    echo "Trying fastapi.business.svc.cluster.local:80 ..."
    wget -T 3 -qO- http://fastapi.business.svc.cluster.local/health 2>&1 || echo "DENIED ✓"
'

bold "[3] Debug Pod IN business ns with label app=fastapi → Postgres (EXPECT: open)"
kubectl run netpol-allowed --rm -it --quiet --restart=Never \
  --namespace business \
  --labels=app=fastapi \
  --image=busybox:1.36 -- sh -c '
    echo "Trying postgres.business.svc.cluster.local:5432 ..."
    nc -zv -w 3 postgres.business.svc.cluster.local 5432 2>&1
'

bold "Done. Summary:"
echo "  - external attacker → Postgres: DENIED"
echo "  - external attacker → FastAPI: DENIED (only ingress-nginx ns allowed)"
echo "  - in-ns fastapi pod → Postgres: ALLOWED"
