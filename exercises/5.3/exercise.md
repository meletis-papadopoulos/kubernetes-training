# Exercise 5.3 - StorageClasses & dynamic provisioning

*Domain: Storage. Target: ~10 min. Do not open `solution/` until you have tried.*

## Prerequisites

A **default StorageClass** with dynamic provisioning must exist (on this cluster it is `local-path`):

```bash
kubectl get storageclass
kubectl create namespace dyn-demo
```

## Tasks

1. Identify the cluster's **default** StorageClass and inspect it. Report its provisioner, its reclaim
   policy, and its volume-binding mode. On this cluster which provisioner is backing the default class,
   and what does `VolumeBindingMode: WaitForFirstConsumer` mean for *when* a volume gets created?

2. In the namespace `dyn-demo`, create a PersistentVolumeClaim named `dynamic-pvc` requesting `1Gi` with
   access mode `ReadWriteOnce` and **no** `storageClassName` field at all (so it uses the default class).
   Apply it and check its status immediately. Is it `Bound` yet? Explain the status you see in terms of
   the binding mode from Task 1.

3. Create a Pod named `dynamic-pod` (image `busybox:1.36`) in `dyn-demo` that mounts `dynamic-pvc` at
   `/data` and runs `echo 'dynamic!' > /data/test.txt && sleep 3600`. Once it is Ready, confirm the PVC
   is now `Bound` and that a PersistentVolume was **created automatically** - list the PVs and note the
   auto-generated name and its provisioner. What manual step did the StorageClass save you from doing,
   compared with exercise 5.2?

## Acceptance criteria

- The default StorageClass is `local-path` with provisioner `rancher.io/local-path` and
  `VolumeBindingMode: WaitForFirstConsumer`.
- `dynamic-pvc` is `Pending` immediately after creation (no consumer yet) and becomes `Bound` once
  `dynamic-pod` is scheduled.
- A PV with an auto-generated name (`pvc-<uuid>`) exists, bound to `dyn-demo/dynamic-pvc`, that **you
  never created by hand**.

## Docs you may reference

- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Dynamic Volume Provisioning](https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/)
