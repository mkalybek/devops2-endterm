# Q1 — Cluster topology

## What
- **1 VM**: `192.168.10.12`, Ubuntu 25.10 (Questing Quokka), aarch64, 4 vCPU, 7.2 Gi RAM, 32 Gi disk.
- **1 node** acting as both control-plane and worker (single-node "all-in-one"). The control-plane `NoSchedule` taint is removed by `bootstrap/04-untaint-master.sh` so workloads can land on the only node we have.
- **CRI**: containerd (kubespray default for k8s 1.31).
- **CNI**: Calico — chosen over Flannel because it implements `NetworkPolicy` (required for Q5/Q6).
- **DNS**: CoreDNS (cluster default), with `nodelocaldns` enabled so per-node DNS lookups don't hit kube-system every time.
- **kube-proxy**: iptables mode.

## Why single-node
The endterm spec calls for "Simple Kubernetes cluster (1 node)" as the EDGE-level topology. Adding a second worker would only demonstrate scheduling we can already prove with `affinity` and `topologySpreadConstraints` against zero-downtime rolling updates on this one node.

## Live verification
```bash
kubectl get nodes -o wide
kubectl get nodes -o jsonpath='{.items[0].spec.taints}'   # → empty
kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}'  # containerd://...
kubectl -n kube-system get pods -l k8s-app=calico-node
kubectl -n kube-system get pods -l k8s-app=kube-dns
```
