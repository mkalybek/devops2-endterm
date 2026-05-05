# Q2 — Cluster deployment process

## Tooling
- **Distro**: Kubernetes upstream (not k3s, not k0s) installed via **Kubespray v2.27**.
- **Kubespray** is itself an Ansible suite, so the entire cluster bring-up is declarative IaC (which also satisfies the final-Target "infrastructure preparations made on Ansible/Terraform/Puppet" criterion).
- A small **custom Ansible playbook** (`ansible/prepare-vm.yml`) runs first to handle OS-level prereqs that Kubespray doesn't touch in detail (apt deps, kernel modules, sysctl, swap-off, buildkit for image builds).

## Six bootstrap steps
| # | Script | Purpose |
|---|---|---|
| 1 | `bootstrap/01-prepare-vm.sh` | runs the custom Ansible playbook against the VM |
| 2 | `bootstrap/02-run-kubespray.sh` | clones Kubespray v2.27, copies our single-node inventory in, runs `cluster.yml` |
| 3 | `bootstrap/03-fetch-kubeconfig.sh` | scp's `/etc/kubernetes/admin.conf`, rewrites `127.0.0.1` → VM IP |
| 4 | `bootstrap/04-untaint-master.sh` | removes `node-role.kubernetes.io/control-plane:NoSchedule` so single-node workloads schedule |
| 5 | `bootstrap/05-install-argocd.sh` | installs ArgoCD, applies `argocd/root-app.yaml` (app-of-apps) |
| 6 | `bootstrap/06-create-sealed-secrets.sh` | seals DB credentials → commits `SealedSecret` to git |

## Inventory shape
```ini
[kube_control_plane]
node1 ansible_host=192.168.10.12 ansible_user=root

[etcd]
node1

[kube_node]
node1            ; same node also serves as worker
```

## Why this split
- Custom Ansible for OS prep keeps Kubespray output deterministic — it expects sane prereqs and our playbook ensures them.
- Kubespray for cluster install gives us audited upstream patterns: certificates, etcd backups, kubelet config, all out-of-the-box.
- After cluster-up, **everything else is GitOps** — we never `kubectl apply` workloads ourselves.
