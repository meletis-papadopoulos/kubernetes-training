# Lab 9.10 - Node Operations

## Objective
Learn how to manage node availability: cordon a node to prevent new scheduling, drain a node to evict workloads for maintenance, and uncordon to restore scheduling.

## Prerequisites
- cluster provisioned with `provision.sh` (1 control-plane + 1 worker)
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Check node status

```bash
kubectl get nodes
```

Both nodes should be `Ready`.

### 2. Deploy a workload spread across nodes

```bash
kubectl create deployment drain-test --image=nginx:1.25 --replicas=6 -n training
```

### 3. Check pod distribution

```bash
kubectl get pods -n training -l app=drain-test -o wide
```

Pods should be distributed across the available nodes.

### Part A: Cordon

### 4. Cordon a worker node

```bash
kubectl cordon node01
```

### 5. Verify the node is cordoned

```bash
kubectl get nodes
```

`node01` should show `Ready,SchedulingDisabled`.

### 6. Existing pods are NOT affected

```bash
kubectl get pods -n training -l app=drain-test -o wide
```

Pods on `node01` are still running. Cordon only prevents NEW pods from being scheduled.

### 7. Scale up and observe

```bash
kubectl scale deployment drain-test --replicas=10 -n training
kubectl get pods -n training -l app=drain-test -o wide
```

New pods will only be scheduled on `controlplane` (the uncordoned node, if it allows workloads).

### 8. Scale back down

```bash
kubectl scale deployment drain-test --replicas=6 -n training
```

### Part B: Drain

### 9. Drain the cordoned node

```bash
timeout 30s kubectl drain node01 --ignore-daemonsets --delete-emptydir-data || true
```

- `--ignore-daemonsets`: DaemonSet pods cannot be deleted (they would just restart)
- `--delete-emptydir-data`: allows eviction of pods using emptyDir volumes
- `timeout 30s ... || true`: this drain WILL hang on a PDB violation (see below) - the timeout caps it so the command returns instead of retrying forever. If you're running this by hand, feel free to drop the wrapper and just Ctrl+C once you see the pattern.

**Drain hangs on a PDB violation** (you'll see `Cannot evict pod as it would violate the pod's disruption budget` retrying every 5s) - that's a single-replica Deployment with a PodDisruptionBudget that allows zero unavailable replicas. On this sandbox, `gatekeeper-controller-manager` is the usual offender (provisioned single-replica to save RAM). Bypass with:

```bash
kubectl drain node01 --ignore-daemonsets --delete-emptydir-data --disable-eviction --force
```

`--disable-eviction` uses the DELETE API directly instead of the eviction subresource, ignoring PDBs. Use this only when you know the disruption is acceptable (lab, controlled maintenance window with explicit approval).

### 10. Verify pods were evicted

```bash
kubectl get pods -n training -l app=drain-test -o wide
```

All pods should now be on `controlplane` only. No pods on `node01`.

### 11. Check node status

```bash
kubectl get nodes
```

`node01` is still `SchedulingDisabled` (drain includes cordon).

### Part C: Uncordon

### 12. Uncordon the node

```bash
kubectl uncordon node01
```

### 13. Verify the node is schedulable again

```bash
kubectl get nodes
```

`node01` should show `Ready` (without SchedulingDisabled).

### 14. Note: existing pods do NOT automatically rebalance

```bash
kubectl get pods -n training -l app=drain-test -o wide
```

Pods stay on `controlplane`. Kubernetes does not automatically redistribute pods. To rebalance:

```bash
kubectl rollout restart deployment drain-test -n training
```

Now check:

```bash
kubectl get pods -n training -l app=drain-test -o wide
```

Pods should be spread across both nodes again.

### 15. Drain escape hatches - what `--force` and `--disable-eviction` actually do

The two flags are commonly confused. They solve different problems:

| Flag | What it does | When to use |
|---|---|---|
| `--force` | Allows deletion of **bare pods** (not managed by a controller - no Deployment/StatefulSet/DaemonSet/Job owner). Without it, drain refuses to touch them. | Pods created with `kubectl run --restart=Never` or raw Pod manifests with no owner |
| `--disable-eviction` | Skips the eviction subresource and calls the DELETE API directly, **bypassing PodDisruptionBudgets**. | Single-replica Deployments with `minAvailable: 1` PDBs (or `maxUnavailable: 0`) - eviction would never succeed |

Combined for a "get me through this maintenance window" drain (replace `<node>` with the actual node name - shown as reference only, not run by `lab-walkthrough.sh`):

```text
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force --disable-eviction
```

In production, prefer to fix the root cause (scale the deployment to 2+ replicas, relax the PDB) over `--disable-eviction` - the PDB is there for a reason.

## Verification

```bash
# Both nodes are Ready
kubectl get nodes

# Pods are distributed
kubectl get pods -n training -l app=drain-test -o wide
```

## Cleanup

```bash
kubectl delete deployment drain-test -n training --ignore-not-found --force --grace-period=0
kubectl uncordon node01 2>/dev/null
# the --disable-eviction --force drain above bypasses PDBs and evicts every pod on the
# node regardless of owner, including single-replica platform components (metrics-server,
# cert-manager, ingress-nginx, gatekeeper) if they happened to be scheduled there - wait for
# metrics-server specifically since a later lab depends on `kubectl top` working
kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s
```

## Further reading
- [Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/) - task walkthrough
- [`kubectl drain`](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#drain) - command reference
