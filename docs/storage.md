# Storage

## Stack
- **CSI**: `local-path-provisioner` (Rancher) — a tiny dynamic provisioner that satisfies PVC requests by carving out subdirectories under `/opt/local-path-provisioner` on the node.
- **StorageClass**: `local-path` (set as default), `reclaimPolicy: Delete`, `volumeBindingMode: WaitForFirstConsumer`.
- **PV/PVC binding**: when a `PVC` is created, the provisioner waits for a Pod to be scheduled (so the PV can be on the right node), then creates a `PersistentVolume` of type `local`.

## Why local-path
- Single-node — no need for replicated block storage (longhorn would be overkill).
- Real CSI driver (not just `hostPath`) — supports volume cleanup, ownership, and reclaim semantics.
- Dynamic — chart writers ask for a PVC, the provisioner makes a PV; no manual `kubectl create pv`.

## Volumes in this cluster
| PVC | Owner | Size | Purpose |
|---|---|---|---|
| `data-postgres-0` | StatefulSet `postgres` | 1 Gi | application data |
| `prometheus-monitoring-prometheus-db-prometheus-monitoring-prometheus-0` | Prometheus operator | 5 Gi | metrics tsdb |
| `alertmanager-monitoring-alertmanager-db-alertmanager-monitoring-alertmanager-0` | AM operator | 1 Gi | silence/alert state |
| `monitoring-grafana` | Grafana | 2 Gi | dashboards, users, plugins |
| `storage-loki-0` | Loki | 5 Gi | log chunks |

## Backup / snapshot
- For the live demo: `pg_dump` via `kubectl exec` produces a portable SQL dump:
  ```bash
  kubectl -n business exec -it postgres-0 -- pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > backup.sql
  ```
- Restore:
  ```bash
  kubectl -n business exec -i postgres-0 -- psql -U "$POSTGRES_USER" "$POSTGRES_DB" < backup.sql
  ```
- **Snapshot** support requires CSI snapshot driver — `local-path` doesn't ship one. Out of scope for endterm; in production we'd swap to Longhorn (lab10 pattern) for proper volume snapshots.

## Live verification
```bash
kubectl get sc                    # local-path is default
kubectl get pv                    # bound to PVCs
kubectl get pvc -A                # all Bound
kubectl get sc local-path -o yaml | grep reclaimPolicy
ssh root@172.20.10.4 ls /opt/local-path-provisioner   # actual data on disk
```
