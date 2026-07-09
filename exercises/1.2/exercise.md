# Exercise 1.2 - Inspect Your Cluster

*Domain: Foundations. Target: ~10 min. Do not open `solution.md` until you have tried.*

This exercise is **entirely read-only** - you inspect an existing cluster and change nothing. There
are no manifests to apply.

## Prerequisites

Any running cluster you can reach (a vanilla `kubeadm`/training cluster shows the control-plane
components; managed platforms may hide them). Confirm access first:

```bash
kubectl cluster-info
```

## Tasks

1. Enumerate every node with `kubectl get nodes -o wide` and read the columns: `ROLES`, `VERSION`,
   `INTERNAL-IP`, and `CONTAINER-RUNTIME`. Identify which node is the control plane and which are
   workers, and show **all** labels on the control-plane node with `--show-labels`. Then extract just
   that node's kubelet version and container-runtime string with a `-o jsonpath` query. Which single
   label is what `kubectl` reads to print `control-plane` in the `ROLES` column?

2. List the control-plane component Pods in the `kube-system` namespace - `kube-apiserver`, `etcd`,
   `kube-scheduler`, `kube-controller-manager` - with `-o wide`, and note which node they all run on.
   Then locate the cluster's DNS: show the CoreDNS Pods and the `kube-dns` Service
   (`-l k8s-app=kube-dns`), and look for `kube-proxy` (`-l k8s-app=kube-proxy`). How do the
   control-plane components get started, given there is no Deployment or ReplicaSet behind them?

3. Use `kubectl api-resources` to find the API group, short name, and namespaced/cluster scope of
   `deployments`, `nodes`, and `events`. Then `describe` the control-plane node and read its
   `Conditions` and `Capacity` blocks; also pull `Capacity` CPU and memory directly with a
   `-o jsonpath` query. If freshly created Pods are stuck `Pending` and never schedule, which of the
   things you just inspected would you check **first**, and why?

## Acceptance criteria

- You can name the control-plane node and the worker node(s) and state each node's kubelet version
  and container runtime (e.g. `containerd://...`).
- You located the four control-plane components in `kube-system`, the CoreDNS Pods, and the `kube-dns`
  Service ClusterIP, and can explain that the components run as **static Pods** managed by the kubelet.
- You can state the group/scope of `deployments` (`apps`, namespaced), `nodes` (core, cluster-scoped),
  and `events` (core, namespaced), and read a node's `Capacity` CPU/memory and `Ready` condition.

## Docs you may reference

- [kubectl cheat sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Troubleshooting clusters](https://kubernetes.io/docs/tasks/debug/debug-cluster/)
- [Kubernetes components](https://kubernetes.io/docs/concepts/overview/components/)
