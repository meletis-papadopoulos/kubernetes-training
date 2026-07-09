# Exercise 6.1 - Scheduling (nodeSelector / affinity / taints & tolerations)

*Domain: Workloads & Scheduling. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

This exercise needs a cluster with at least one schedulable **worker** node (a node without the
control-plane role). Capture the worker node's name into `$WORKER` - do not grep by name, since node
names differ between sandboxes:

```bash
WORKER=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' \
  -o jsonpath='{.items[0].metadata.name}')
echo "worker = $WORKER"
kubectl create namespace sched
```

## Tasks

1. Label the worker node `$WORKER` with `disktype=ssd`. In the namespace `sched`, create a Pod named
   `ssd-pod` using image `nginx:1.27.1` that, via a **nodeSelector**, is only ever scheduled onto a
   node carrying the label `disktype=ssd`. Create the Pod and confirm which node it landed on.

2. Add a taint to the worker node `$WORKER`: key `dedicated`, value `team-a`, effect `NoSchedule`.
   In `sched`, create a Pod named `plain-web` (image `nginx:1.27.1`) with **no** toleration, and a
   second Pod named `tolerant-web` (image `nginx:1.27.1`) that **tolerates** that taint (operator
   `Equal`, effect `NoSchedule`). If the worker is your only schedulable node, which of the two Pods
   ends up `Running`, and which stays `Pending`? Explain what `kubectl describe` reports for the
   Pending one.

3. Still in `sched`, create a Pod named `prefers-ssd` (image `nginx:1.27.1`) that uses **preferred**
   (soft) node affinity - `preferredDuringSchedulingIgnoredDuringExecution`, weight `1` - for the
   label `disktype=ssd`, and also tolerates the `dedicated=team-a:NoSchedule` taint from Task 2.
   Would this Pod still schedule if **no** node had `disktype=ssd`? Why - and how does that differ
   from the `nodeSelector` in Task 1?

## Cleanup note

Task 2 taints your only worker. Run the `Cleanup` block in `solution.md` when done so later
exercises are not left with a `NoSchedule` worker.

## Acceptance criteria

- Node `$WORKER` carries `disktype=ssd`; `ssd-pod` is `Running` on `$WORKER`.
- Node `$WORKER` carries taint `dedicated=team-a:NoSchedule`; `tolerant-web` is `Running`,
  `plain-web` is `Pending` with a "node(s) had untolerated taint" scheduling event.
- `prefers-ssd` is `Running` (soft affinity does not block scheduling when unmet).

## Docs you may reference

- [Assigning Pods to Nodes (nodeSelector / affinity)](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Labels and Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
