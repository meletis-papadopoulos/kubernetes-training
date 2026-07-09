# Exercise 5.4 - PVCs in Deployments & StatefulSets

*Domain: Storage. Target: ~14 min. Do not open `solution/` until you have tried.*

## Prerequisites

A **default StorageClass** with dynamic provisioning must exist (on this cluster it is `local-path`):

```bash
kubectl get storageclass
kubectl create namespace wl-demo
```

## Tasks

1. In the namespace `wl-demo`, create a PersistentVolumeClaim named `shared-pvc` (`1Gi`,
   `ReadWriteOnce`, default class) and a Deployment named `shared-web` with `1` replica, image
   `nginx:1.27.1`, that mounts `shared-pvc` at `/usr/share/nginx/html`. Once the rollout is complete,
   write `<h1>from the deployment</h1>` into `/usr/share/nginx/html/index.html` in the running Pod,
   delete that Pod, and after the Deployment recreates it, read the file back. Did the content survive
   the Pod being replaced, and where does the single PVC "live" relative to the Deployment's Pods?

2. In `wl-demo`, create a **headless** Service named `sts` (`clusterIP: None`, selector `app=sts`,
   port `80`) and a StatefulSet named `sts-web` with `2` replicas, image `nginx:1.27.1`, `serviceName:
   sts`, and a `volumeClaimTemplates` entry named `data` (`1Gi`, `ReadWriteOnce`) mounted at
   `/usr/share/nginx/html`. After the rollout, list the PVCs in the namespace. How many PVCs did the
   StatefulSet create, and what is their naming pattern?

3. Write a **different** file into each StatefulSet Pod (`echo 'pod 0' ...` into `sts-web-0`, `echo
   'pod 1' ...` into `sts-web-1`), then delete `sts-web-0`. Once it is rescheduled, read its file back.
   Did `sts-web-0` come back with **its own** data intact? Given how the Deployment in Task 1 shared one
   PVC across its Pods, why can a Deployment **not** hand each replica a private volume the way a
   StatefulSet does?

## Acceptance criteria

- `shared-pvc` is `Bound`; after deleting the `shared-web` Pod the replacement serves
  `<h1>from the deployment</h1>` - the one PVC outlived the Pod and is re-mounted by the new Pod.
- The StatefulSet created **one PVC per replica**, named `data-sts-web-0` and `data-sts-web-1`.
- After deleting `sts-web-0` it returns bound to `data-sts-web-0` and still reads `pod 0` - each
  ordinal keeps its own volume.

## Docs you may reference

- [Claims As Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#claims-as-volumes)
- [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
