# Exercise 9.10 - Solutions

Reference manifest is in `solution/`. Namespace `ts910`, the cordoned nodes, and the `batch`
Deployment are assumed applied (see the exercise Setup). The fault is at the **node** level, so the
fix is a `kubectl` node command, not a manifest edit - `solution/batch-deploy.yaml` is the expected
healthy workload for reference.

## Task 1 - diagnose and fix the scheduling failure

### Diagnose

```bash
sleep 10
kubectl get pods -n ts910 -l app=batch
kubectl describe pod -n ts910 -l app=batch | grep -A 4 "Events:"
kubectl get nodes
```

Expected (values illustrative):

```
NAME                     READY   STATUS    RESTARTS   AGE
batch-6c...-aaaaa        0/1     Pending   0          10s
batch-6c...-bbbbb        0/1     Pending   0          10s
...

Warning  FailedScheduling  ...  0/2 nodes are available:
  2 node(s) were unschedulable.
  preemption: 0/2 nodes are available: 2 Preemption is not helpful for scheduling.

NAME           STATUS                     ROLES           AGE   VERSION
controlplane   Ready,SchedulingDisabled   control-plane   ...   ...
node01         Ready,SchedulingDisabled   <none>          ...   ...
```

**Root cause:** every node is **cordoned** (`Ready,SchedulingDisabled`, i.e. `spec.unschedulable:
true`), so the scheduler has nowhere to place new Pods and reports `node(s) were unschedulable`. This
is not a resource shortage (the requests are tiny, `25m` CPU) and not a taint - it is an operational
state on the nodes. Confirm on a node:

```bash
kubectl describe node -l kubernetes.io/os=linux | grep -E "^Name:|Unschedulable:"
```

Shows `Unschedulable: true`.

### Fix

Uncordon the affected nodes (found by label selector, not name):

```bash
kubectl uncordon -l kubernetes.io/os=linux
```

### Verify

```bash
kubectl get nodes
kubectl rollout status deployment/batch -n ts910 --timeout=90s
kubectl get pods -n ts910 -l app=batch -o wide
```

Expected: every node `Ready` (no `SchedulingDisabled`), and all 4 `batch` Pods `Running`, spread
across the schedulable nodes.

## Task 2 - reflective answer

Three distinct `FailedScheduling` reasons, three different fixes:

- `node(s) were unschedulable` - nodes are cordoned; fix with `uncordon` (operational, nothing wrong
  with the Pod).
- `Insufficient cpu` / `Insufficient memory` - the Pod's requests exceed free capacity on every node;
  fix by lowering requests or adding capacity.
- `untolerated taint {...}` - nodes carry a taint the Pod does not tolerate; fix by adding a matching
  toleration (or removing the taint if it shouldn't be there).

`cordon` only sets `spec.unschedulable: true`, which the scheduler consults when placing **new** Pods;
Pods already running on the node keep running untouched. `kubectl drain` does the cordon **and** then
evicts the existing Pods (respecting PodDisruptionBudgets) so the node can be taken down for
maintenance.

## Cleanup

```bash
kubectl uncordon -l kubernetes.io/os=linux
kubectl delete ns ts910 --ignore-not-found
```
