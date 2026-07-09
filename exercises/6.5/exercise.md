# Exercise 6.5 - DaemonSets

*Domain: Workloads & Scheduling. Target: ~10 min. Do not open `solution/` until you have tried.*
*Authored in-house (not derived from a study guide); grounded in the official docs linked below.*

## Setup

```bash
kubectl create namespace logging
kubectl get nodes    # note the node count - a DaemonSet runs one pod per eligible node
```

## Tasks

1. In the namespace `logging`, create a DaemonSet named `node-logger` whose pod runs the image
   `busybox:1.36` with the command `sleep 3600`, labelled `app=node-logger`. The pod must mount the
   host path `/var/log` **read-only** at `/host/var/log` (a typical node-log-collector pattern). Apply
   it and confirm exactly **one** pod is scheduled per eligible node. On a standard 2-node cluster
   (one control-plane, one worker), how many pods do you get, and why not two?

2. Make `node-logger` also run on the control-plane node by adding a toleration for the control-plane
   `NoSchedule` taint (key `node-role.kubernetes.io/control-plane`, operator `Exists`, effect
   `NoSchedule`). Re-apply and confirm the pod count now equals the **total** node count.

3. Trigger a rolling update by changing the container command to `sleep 7200` and confirm the
   DaemonSet replaces its pods node-by-node under the default `RollingUpdate` strategy. Which field
   reports how many pods are up to date?

## Acceptance criteria

- `node-logger` DaemonSet exists in `logging`; after Task 1, `DESIRED` == number of **worker/eligible**
  nodes (1 on a standard 2-node cluster - the control-plane taint repels it).
- After Task 2, `DESIRED`/`READY` == **total** node count (2 on a standard cluster).
- After Task 3, `kubectl rollout status ds/node-logger -n logging` reports the rollout complete and
  `UP-TO-DATE` equals `DESIRED`.

## Docs you may reference

- [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Perform a Rolling Update on a DaemonSet](https://kubernetes.io/docs/tasks/manage-daemon/update-daemon-set/)
