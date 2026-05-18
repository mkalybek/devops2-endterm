# Networking

## Stack
| Layer | Component | Notes |
|---|---|---|
| CNI | **Calico** | implements `NetworkPolicy`; Flannel/Weave can't do egress policies |
| kube-proxy | iptables | (ipvs is default but iptables keeps debug simpler) |
| Service VIPs | 10.233.0.0/18 | cluster-local CIDR set in kubespray overrides |
| Pod CIDR | 10.233.64.0/18 | per-node `/24` slice (`kube_network_node_prefix: 24`) |
| DNS | CoreDNS + nodelocaldns | per-node cache, less load on kube-system |
| Ingress | ingress-nginx | NodePort 30080 (no LB on single-node) |
| LB | none | no external LB — port-forward / SSH tunnel for Mac→cluster |

## NetworkPolicy posture (default-deny + explicit allow)

`charts/business/templates/networkpolicies.yaml` ships **7 NetworkPolicies** for the `business` namespace:

| # | Name | Type | Effect |
|---|---|---|---|
| 1 | `default-deny-all` | both | denies ALL ingress + egress in the ns |
| 2 | `allow-fastapi-from-ingress` | ingress | only `ns=ingress-nginx` may reach `fastapi:8000` |
| 3 | `allow-postgres-from-fastapi` | ingress | only pods with `app=fastapi` OR `app=postgres-backup` may reach `postgres:5432` |
| 3b | `allow-backup-egress` | egress | backup pod may talk to DNS + postgres only |
| 4 | `allow-fastapi-egress` | egress | fastapi may talk to kube-system (DNS) and postgres only |
| 5 | `allow-postgres-egress` | egress | postgres may talk to kube-system (DNS) only |
| 6 | `allow-fastapi-from-monitoring` | ingress | Prometheus may scrape `/metrics` on fastapi |

Anything not on this list is silently dropped.

## Demo (proves NetworkPolicy works)

`scripts/demo-netpol.sh` runs 3 probes:
1. busybox in `default` ns → `postgres.business:5432` → **DENIED** (rule 1 wins)
2. busybox in `default` ns → `fastapi.business:80` → **DENIED** (only ingress-nginx allowed)
3. busybox in `business` ns with label `app=fastapi` → `postgres.business:5432` → **ALLOWED** (rule 3 matches)

Without policies, all three would succeed. The demo IS the proof.

## Live verification
```bash
kubectl get networkpolicy -A
kubectl -n business describe networkpolicy default-deny-all
kubectl get svc -A
kubectl get ingress -A
kubectl -n ingress-nginx get svc ingress-nginx-controller   # NodePort 30080/30443
```
