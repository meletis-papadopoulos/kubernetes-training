# Exercise 5.5 - Access modes & reclaim policies

*Domain: Storage. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace reclaim-demo
```

## Tasks

1. Create two **manually provisioned** PersistentVolumes (cluster-scoped), both `storageClassName: ""`
   and backed by a `hostPath` with `type: DirectoryOrCreate`: `pv-retain` (`1Gi`, access mode
   `ReadWriteOnce`, reclaim policy `Retain`, path `/tmp/ex55-retain`) and `pv-rox` (`500Mi`, access mode
   `ReadOnlyMany`, reclaim policy `Delete`, path `/tmp/ex55-rox`). Apply both and list them with their
   access modes and reclaim policies shown. What is the difference between what `ReadWriteOnce` and
   `ReadOnlyMany` permit - and is the constraint about pods or about nodes?

2. In the namespace `reclaim-demo`, create a PVC `pvc-retain` (`1Gi`, `ReadWriteOnce`,
   `storageClassName: ""`) and a PVC `pvc-rox` (`500Mi`, `ReadOnlyMany`, `storageClassName: ""`). Apply
   them and confirm each binds to the volume with the matching access mode. Which PV did each PVC bind to,
   and why did `pvc-rox` not bind to `pv-retain`?

3. Delete `pvc-retain` (the claim bound to the `Retain` PV) with `--force --grace-period=0`, then inspect
   `pv-retain`. What status is it in now, and can a brand-new PVC bind to it as-is? Describe exactly what
   an operator must do to make this `Retain` volume reusable again, and contrast that with what the
   `Delete` policy on `pv-rox` would have done.

## Acceptance criteria

- `pv-retain` (RWO, Retain) and `pv-rox` (ROX, Delete) both exist and are `Available`, then `Bound`.
- `pvc-retain` binds to `pv-retain` and `pvc-rox` binds to `pv-rox` (access modes match).
- After deleting `pvc-retain`, `pv-retain` is `Released` (not `Available`) and will **not** accept a new
  claim until its `claimRef` is cleared (or the PV is deleted and re-created).

## Docs you may reference

- [Access Modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes)
- [Reclaiming](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming)
