# Exercise 2.3 - Deployments & ReplicaSets

*Domain: Core Workloads. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace core
```

## Tasks

1. In the namespace `core`, create a Deployment named `web` with `3` replicas, pod label `app=web`, a
   single container `nginx` from image `nginx:1.27.1` exposing `containerPort: 80`. Apply it, wait for
   the rollout to finish, then list the Deployment, the ReplicaSet it created, and the three pods.
   Follow the ownership chain: read the `ownerReferences` of one pod to find its ReplicaSet, and the
   `ownerReferences` of that ReplicaSet to find the Deployment. Which object directly owns the pods -
   the Deployment or the ReplicaSet?

2. Scale `web` to `5` replicas and wait for the rollout, then scale it back to `3`. While it is at `3`,
   pick one running pod and delete it with `kubectl delete pod <name> -n core`, then immediately list
   the pods again. A replacement appears almost instantly with a new name - which controller noticed
   the pod was missing and recreated it, and how did it know the desired count was `3`?

## Acceptance criteria

- Deployment `web` in `core` reaches `3/3` ready from image `nginx:1.27.1`; exactly one ReplicaSet
  owns the three pods, and that ReplicaSet is owned by the Deployment.
- After deleting a pod at replicas `3`, the ReplicaSet recreates a replacement and the count returns
  to `3`.

## Docs you may reference

- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
