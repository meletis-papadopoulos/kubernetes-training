# Exercise 5.2 - PersistentVolumes & PVCs

*Domain: Storage. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace pv-demo
```

## Tasks

1. Create a **manually provisioned** PersistentVolume named `manual-pv` (it is cluster-scoped, no
   namespace) with capacity `1Gi`, access mode `ReadWriteOnce`, reclaim policy `Retain`,
   `storageClassName: ""` (empty - static binding, no dynamic provisioner), backed by a `hostPath` at
   `/tmp/ex52-pv` with `type: DirectoryOrCreate`. Apply it and confirm its status. What status does a PV
   have before any claim binds to it?

2. In the namespace `pv-demo`, create a PersistentVolumeClaim named `app-pvc` requesting `1Gi` with
   access mode `ReadWriteOnce` and `storageClassName: ""` so it binds statically. Apply it and confirm
   **both** the PVC and `manual-pv` become `Bound`. Which properties of the claim had to be satisfied by
   the volume for this binding to happen?

3. In `pv-demo`, create a Pod named `pv-pod` (image `busybox:1.36`) that mounts `app-pvc` at `/data` and
   runs `echo 'persisted data' > /data/output.txt && sleep 3600`. Once Ready, read the file. Then delete
   the Pod (`--force --grace-period=0`), re-create it from the same manifest (it re-runs the same
   command, so append instead: verify the *original* line is still present before the new write). Confirm
   the data written by the first Pod survived into the second. Why did the file survive, when the
   `emptyDir` in exercise 5.1 did not?

## Acceptance criteria

- `manual-pv` exists cluster-wide and is `Available` before the claim, then `Bound` after.
- `app-pvc` in `pv-demo` is `Bound` to `manual-pv` (capacity `1Gi`, RWO, matching empty StorageClass).
- After deleting and re-creating `pv-pod`, `/data/output.txt` still contains the line written by the
  first Pod - the data lived in the PV, not the Pod.

## Docs you may reference

- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Configure a Pod to Use a PersistentVolume for Storage](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)
