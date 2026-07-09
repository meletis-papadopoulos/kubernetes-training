# Exercise 2.6 - StatefulSets (stable identity, ordered pods, per-pod PVCs)

*Domain: Core Workloads. Target: ~12 min. Do not open `solution/` until you have tried.*
*Authored in-house (not derived from a study guide); grounded in the official docs linked below.*

## Prerequisites

A **default StorageClass** with dynamic provisioning must exist (see lab 5.3):

```bash
kubectl get storageclass
kubectl create namespace stateful
```

## Tasks

1. In the namespace `stateful`, create a **headless** Service named `nginx` (`clusterIP: None`),
   selecting `app=nginx` on port `80`. Then create a StatefulSet named `web` with `3` replicas whose
   `serviceName` is `nginx`, pod label `app=nginx`, container image `nginx:1.27.1` exposing port `80`.
   Give it a `volumeClaimTemplates` entry named `www` that requests `1Gi` with access mode
   `ReadWriteOnce`, mounted at `/usr/share/nginx/html`. Apply it and watch the pods appear - in what
   order are `web-0`, `web-1`, `web-2` created, and are the names stable?

2. Confirm that each pod got its **own** PersistentVolumeClaim (`www-web-0`, `www-web-1`,
   `www-web-2`). Scale the StatefulSet up to `5` replicas, then back down to `2`. After scaling down,
   what happened to the PVCs `www-web-2`, `www-web-3`, `www-web-4` - were they deleted with the pods?
   Verify and explain.

3. Verify stable network identity: from a throwaway `busybox:1.28` pod in the `stateful` namespace,
   resolve the DNS name `web-0.nginx` (the per-pod stable hostname). What fully-qualified name does it
   resolve to?

## Acceptance criteria

- Service `nginx` in `stateful` is headless (`CLUSTER-IP` = `None`); StatefulSet `web` reaches `2/2`
  after the scale-down (was `3/3`, then `5/5`).
- PVCs `www-web-0`..`www-web-4` were all created; after scaling to `2`, `www-web-0` and `www-web-1`
  remain **Bound** and the higher-ordinal PVCs still exist (StatefulSets never delete PVCs on scale-down).
- `web-0.nginx` resolves to `web-0.nginx.stateful.svc.cluster.local`.

## Docs you may reference

- [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [StatefulSet Basics tutorial](https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/)
- [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)
