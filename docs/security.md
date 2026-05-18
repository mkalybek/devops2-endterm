# Workload security

## Layered controls

### Pod-level: SecurityContext
Every business container runs:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000              # never root
  readOnlyRootFilesystem: true # /tmp is mounted as emptyDir for write
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
  seccompProfile:
    type: RuntimeDefault
```
This denies privilege escalation, all Linux capabilities, root-FS writes, and pins the container to the runtime's default seccomp filter. An RCE in FastAPI can't `chmod` system binaries, can't drop a payload onto disk, can't `setuid`.

Postgres needs `fsGroup: 999` to chown its data dir on first init but otherwise drops all caps.

### Namespace-level: ResourceQuota + LimitRange
`charts/business/templates/resourcequota.yaml`:
```yaml
hard:
  requests.cpu: "2"
  requests.memory: 2Gi
  limits.cpu: "4"
  limits.memory: 4Gi
  pods: "20"
  persistentvolumeclaims: "5"
```
Even if the FastAPI Deployment goes haywire and tries to scale to 100 replicas, the namespace caps it at 20 pods and 4 CPU. The cluster cannot be DoS'd from inside this namespace.

`LimitRange` enforces sensible per-container defaults so a developer who forgets `resources:` in a manifest still gets requests/limits applied.

### Cluster-level: Pod Security Admission
- `kube-system` is set to the `privileged` profile (kubespray internals need it).
- `business` is labeled `restricted` (the strictest profile) by `charts/business/templates/namespace.yaml`. All workloads in the chart already comply (`runAsNonRoot`, `seccompProfile=RuntimeDefault`, drop ALL caps, no `hostPath`).
- Other namespaces inherit `baseline` enforcement via the post-cluster Ansible play.

### Admission policy: Kyverno
Five `ClusterPolicy` resources in `extras/kyverno-policies/`:
| Policy | Mode | Effect |
|---|---|---|
| `disallow-latest-tag` | Enforce | Blocks `:latest` or untagged images in business/monitoring/logging |
| `require-resources` | Enforce | Blocks Pods without CPU+memory requests AND limits |
| `require-non-root` | Enforce | Blocks Pods without `runAsNonRoot=true` |
| `disallow-host-namespaces` | Enforce | Blocks `hostPID/hostIPC/hostNetwork` |
| `restrict-image-registries` | Audit | Surfaces images from non-approved registries |

PSA enforces broad strokes; Kyverno catches the specifics PSA doesn't model.

### Transport: cert-manager + cluster CA
- `cert-manager` minted a 10y self-signed root CA (`extras/cluster-issuer/selfsigned.yaml`).
- Every Ingress in the cluster (`business`, `argocd-server`, `grafana`) carries a `cert-manager.io/cluster-issuer: cluster-ca-issuer` annotation, so each gets an automatically-rotated TLS cert with `nginx.ingress.kubernetes.io/ssl-redirect: "true"`.
- Plain HTTP is closed at the ingress.

### Image-level
- `imagePullPolicy: Never` for our FastAPI image — kubelet uses the locally-built containerd image and can't be tricked into pulling something else.
- Multi-stage Dockerfile drops dev tooling from the final image.

### Credentials: Sealed Secrets
- `db-secret` never appears in git as plaintext.
- `bitnami-labs/sealed-secrets` controller's private key never leaves the cluster — only the public key is used at seal time on dev's laptop.

### Supply chain: Trivy in CI
`.github/workflows/security-scan.yml` runs on every PR + push to main:
- `trivy image` against the FastAPI build — fails the job on HIGH/CRITICAL.
- `trivy config` against the whole repo — surfaces IaC misconfigurations.
- `kyverno validate` — proves policies parse and apply.
- `helm lint` — proves the chart renders cleanly.

Findings upload to GitHub Security tab via SARIF.

### Backup/DR
`charts/business/templates/backup.yaml` ships a `CronJob` that runs `pg_dump` nightly at 03:00 UTC, gzips the output to a dedicated `postgres-backup` PVC, retains the last 7 dumps. Locked down with the same `securityContext` as the app (non-root, read-only FS, drop caps, seccomp) and a dedicated NetworkPolicy.

## Live verification
```bash
kubectl -n business get pods -o jsonpath='{.items[*].spec.containers[*].securityContext}' | jq
kubectl get resourcequota -A
kubectl get limitrange -A
kubectl get poddisruptionbudget -A
kubectl -n business get sealedsecret
kubectl get networkpolicy -A    # see networking.md
kubectl get clusterpolicy       # Kyverno
kubectl get certificate -A      # cert-manager-minted TLS
kubectl get ns -L pod-security.kubernetes.io/enforce
kubectl -n business get cronjob postgres-backup
```
