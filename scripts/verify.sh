#!/usr/bin/env bash
# Health snapshot for the cluster.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"

bold() { printf "\n\033[1m== %s ==\033[0m\n" "$*"; }

bold "Cluster"
kubectl get nodes -o wide
kubectl version --short 2>/dev/null || kubectl version

bold "All namespaces"
kubectl get ns

bold "Pods (all namespaces, non-Running highlighted)"
kubectl get pods -A | awk 'NR==1 || $4!="Running" {print "\033[33m"$0"\033[0m"; next} {print}'

bold "ArgoCD apps"
kubectl -n argocd get app -o wide 2>/dev/null || echo "(argocd not installed yet)"

bold "Storage"
kubectl get sc
kubectl get pv 2>/dev/null
kubectl get pvc -A

bold "Networking"
kubectl get svc -A | grep -v 'kube-system'
kubectl get ingress -A
kubectl get networkpolicy -A

bold "Security guardrails"
kubectl get resourcequota -A
kubectl get limitrange -A
kubectl get poddisruptionbudget -A
kubectl -n kube-system get deploy sealed-secrets 2>/dev/null

bold "Monitoring CRDs"
kubectl get crd | grep -E 'monitoring|sealed' || echo "(none)"

bold "ServiceMonitors (Prometheus targets)"
kubectl get servicemonitor -A 2>/dev/null

bold "Business app HTTP probe"
if kubectl -n business get pods -l app=fastapi 2>/dev/null | grep -q Running; then
  kubectl -n business port-forward svc/fastapi 18000:80 >/dev/null 2>&1 &
  PF=$!
  sleep 2
  curl -s --max-time 3 http://127.0.0.1:18000/health || echo "  (probe failed)"
  echo
  curl -s --max-time 3 http://127.0.0.1:18000/version || echo "  (version probe failed)"
  echo
  kill $PF 2>/dev/null || true
else
  echo "(business app not running)"
fi

bold "Done"
