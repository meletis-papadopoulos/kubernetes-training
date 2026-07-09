# Exercise 9.10 - Fix Pods That Won't Schedule (Cordoned Nodes)

*Domain: Troubleshooting. Target: ~8 min. Do not open `solution/` until you have tried.*

This is a **fix-it** exercise: the fault is at the **node** level. `setup.yaml` ships a workload; the
Setup block below puts the nodes into the broken state. Diagnose from the cluster, then apply the
minimal fix.

## Setup

```bash
kubectl create namespace ts910
# Put every schedulable node into the "broken" state for this exercise:
kubectl cordon -l kubernetes.io/os=linux
kubectl apply -f setup.yaml
```

## Tasks

1. The `batch` Deployment in namespace `ts910` requests 4 replicas, but every Pod is stuck `Pending`.
   Wait ~10s (`kubectl get pods -n ts910 -l app=batch`). Diagnose at the cluster level, not the Pod
   spec: `kubectl describe pod -n ts910 -l app=batch` (Events -> `FailedScheduling`), then
   `kubectl get nodes` and `kubectl describe node <node>` (look at the `Unschedulable` /
   `SchedulingDisabled` state). The Pods request only `25m` CPU each, so this is **not** an
   insufficient-resources problem. Restore scheduling so all 4 `batch` Pods reach `Running`, using the
   correct node command (find the affected nodes by label selector, not by hard-coded name).

2. Reflective: what is the difference between a `FailedScheduling` caused by `node(s) were
   unschedulable` (this exercise) versus `Insufficient cpu` (a resource shortage) versus `untolerated
   taint`? Cordoning did **not** evict the existing system Pods on those nodes - why does `cordon`
   only affect *new* scheduling, and what extra step would `kubectl drain` have added?

## Acceptance criteria

- All 4 `batch` Pods in `ts910` are `Running`; `kubectl get nodes` shows every node `Ready` with no
  `SchedulingDisabled`.
- You identify the fault as **cordoned nodes** (`spec.unschedulable: true`), surfaced as
  `FailedScheduling ... node(s) were unschedulable`, and fix it with `kubectl uncordon` (not by
  lowering requests or editing the Deployment).
- You explain that `cordon` marks nodes unschedulable for *new* Pods only (existing Pods stay), while
  `drain` additionally *evicts* the running Pods.

## Docs you may reference

- [Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)
- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
