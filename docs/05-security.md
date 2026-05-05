# Q5 — Workload security

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
- Other namespaces inherit the default `baseline` enforcement — no host paths, no host networking, no privileged containers.

### Image-level
- `imagePullPolicy: Never` for our FastAPI image — kubelet uses the locally-built containerd image and can't be tricked into pulling something else.
- Multi-stage Dockerfile drops dev tooling from the final image.

### Credentials: Sealed Secrets
- `db-secret` never appears in git as plaintext.
- `bitnami-labs/sealed-secrets` controller's private key never leaves the cluster — only the public key is used at seal time on dev's laptop.

## Live verification
```bash
kubectl -n business get pods -o jsonpath='{.items[*].spec.containers[*].securityContext}' | jq
kubectl get resourcequota -A
kubectl get limitrange -A
kubectl get poddisruptionbudget -A
kubectl -n business get sealedsecret
kubectl get networkpolicy -A    # see Q6
```
