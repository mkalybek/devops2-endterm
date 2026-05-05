#!/usr/bin/env bash
# Live demo: bump fastapi image tag, watch RollingUpdate (maxUnavailable=0)
# happen with ZERO 5xx in a parallel curl loop. Q8 on defense.
#
# Prereq: image business-fastapi:<NEW_TAG> already built on VM
#         (run scripts/build-image.sh <NEW_TAG> first)

set -uo pipefail

NEW_TAG="${1:?usage: $0 <new_tag>   e.g. 2.0.0}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"

VALUES="${REPO_ROOT}/charts/business/values.yaml"

bold() { printf "\n\033[1m== %s ==\033[0m\n" "$*"; }

bold "[1/4] Open port-forward to ingress"
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80 >/dev/null 2>&1 &
PF=$!
trap "kill $PF 2>/dev/null || true" EXIT
sleep 2

bold "[2/4] Start background curl loop (200 = good, anything else = bad)"
(
  while true; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: business.local" \
      http://127.0.0.1:8080/version)
    ts=$(date '+%H:%M:%S')
    case "$code" in
      200) printf "[%s] \033[32m%s\033[0m " "$ts" "$code" ;;
      *)   printf "[%s] \033[31m%s\033[0m " "$ts" "$code" ;;
    esac
    sleep 0.2
  done
) &
LOOP=$!
trap "kill $LOOP $PF 2>/dev/null || true" EXIT
sleep 3
echo

bold "[3/4] Bump tag to ${NEW_TAG} in values.yaml"
sed -i.bak "s/^\(  image:\s*\)\?$/\\1/" "$VALUES" >/dev/null 2>&1 || true
# Targeted update: under fastapi.image.tag
python3 - "$VALUES" "$NEW_TAG" <<'PY'
import sys, re
path, tag = sys.argv[1], sys.argv[2]
with open(path) as f: src = f.read()
new = re.sub(r'(fastapi:\n(?:[^\n]*\n)*?\s+image:\n(?:[^\n]*\n)*?\s+tag:\s*)"[^"]*"',
             rf'\1"{tag}"', src, count=1)
with open(path, 'w') as f: f.write(new)
print(f"updated tag → {tag}")
PY

git -C "$REPO_ROOT" diff --no-color -- charts/business/values.yaml | head -30
echo
read -r -p "Commit and push to trigger ArgoCD sync? [y/N] " ans
if [[ "$ans" =~ ^[Yy] ]]; then
  git -C "$REPO_ROOT" add charts/business/values.yaml
  git -C "$REPO_ROOT" commit -m "chore: bump fastapi to ${NEW_TAG}"
  git -C "$REPO_ROOT" push
fi

bold "[4/4] Watch rollout"
kubectl -n business rollout status deploy/fastapi --timeout=120s

echo
echo "Curl-loop output above should show ALL 200s during the rollout."
echo "Press Ctrl-C to stop."
wait
