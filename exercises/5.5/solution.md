# Exercise 5.5 - Solutions

Reference manifests are in `solution/`. Namespace `reclaim-demo` is assumed to exist (see the exercise
Setup).

## Task 1 - two PVs with different access modes and reclaim policies

```bash
kubectl apply -f solution/pv-retain.yaml
kubectl apply -f solution/pv-rox.yaml
kubectl get pv -o custom-columns=\
NAME:.metadata.name,\
CAPACITY:.spec.capacity.storage,\
ACCESS:.spec.accessModes,\
RECLAIM:.spec.persistentVolumeReclaimPolicy,\
STATUS:.status.phase
```

`solution/pv-retain.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-retain
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: /tmp/ex55-retain
    type: DirectoryOrCreate
```

`solution/pv-rox.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-rox
spec:
  capacity:
    storage: 500Mi
  accessModes:
    - ReadOnlyMany
  persistentVolumeReclaimPolicy: Delete
  storageClassName: ""
  hostPath:
    path: /tmp/ex55-rox
    type: DirectoryOrCreate
```

Expected:

```
NAME        CAPACITY   ACCESS            RECLAIM   STATUS
pv-retain   1Gi        [ReadWriteOnce]   Retain    Available
pv-rox      500Mi      [ReadOnlyMany]    Delete    Available
```

**Answer to the reflective question:** `ReadWriteOnce` (RWO) allows the volume to be mounted read-write by
a single **node**; `ReadOnlyMany` (ROX) allows it to be mounted read-only by **many** nodes at once. The
constraint is expressed per node, not per pod - multiple pods on the *same* node can share an RWO volume,
but no second node may mount it read-write. (`ReadWriteMany` would allow read-write from many nodes, and
`ReadWriteOncePod` restricts to a single pod.)

## Task 2 - claims bind to the matching access mode

```bash
kubectl apply -f solution/pvc-retain.yaml
kubectl apply -f solution/pvc-rox.yaml
kubectl get pvc -n reclaim-demo
kubectl get pv
```

`solution/pvc-retain.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-retain
  namespace: reclaim-demo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: ""
```

`solution/pvc-rox.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-rox
  namespace: reclaim-demo
spec:
  accessModes:
    - ReadOnlyMany
  resources:
    requests:
      storage: 500Mi
  storageClassName: ""
```

Expected - each claim bound to the PV with the matching mode:

```
NAME         STATUS   VOLUME      CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc-retain   Bound    pv-retain   1Gi        RWO            ""             5s
pvc-rox      Bound    pv-rox      500Mi      ROX            ""             5s
```

**Answer to the reflective question:** `pvc-retain` (RWO, 1Gi) bound to `pv-retain`, and `pvc-rox` (ROX,
500Mi) bound to `pv-rox`. `pvc-rox` could **not** bind to `pv-retain` because access modes must be
compatible - `pv-retain` offers only `ReadWriteOnce`, which does not satisfy a `ReadOnlyMany` request -
and its `1Gi` size and RWO mode were a mismatch besides. Binding requires StorageClass, access mode, and
capacity all to be satisfied.

## Task 3 - deleting a Retain-bound PVC leaves the PV Released

```bash
kubectl delete pvc pvc-retain -n reclaim-demo --force --grace-period=0
kubectl get pv pv-retain
```

Expected - `Released`, not `Available` (and note the stale claim reference remains):

```
NAME        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM                      STORAGECLASS   AGE
pv-retain   1Gi        RWO            Retain           Released   reclaim-demo/pvc-retain    ""             4m
```

A new claim will **not** bind to it while it is `Released` - the PV still carries a `claimRef` pointing at
the deleted PVC. Confirm and then clear it to make the volume reusable:

```bash
kubectl patch pv pv-retain --type json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
kubectl get pv pv-retain
```

Expected - it returns to `Available`:

```
NAME        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   AGE
pv-retain   1Gi        RWO            Retain           Available           ""             5m
```

**Answer to the reflective question:** with `Retain`, deleting the PVC does **not** delete the PV or its
data - the PV goes to `Released` and holds a dangling `claimRef`, so Kubernetes will not auto-rebind it
(that would risk exposing the old tenant's data to a new claim). To reuse it, an operator must manually
(a) decide what to do with the retained data on the backend, then (b) clear the `claimRef` (the `kubectl
patch` above) or delete and re-create the PV, returning it to `Available`. By contrast the `Delete` policy
on `pv-rox` is automatic: deleting `pvc-rox` would have had Kubernetes remove the PV (and, for a real
dynamic backend, the underlying storage) with no manual step - convenient for disposable data, dangerous
for anything you must not lose.

## Cleanup

```bash
kubectl delete ns reclaim-demo --ignore-not-found
kubectl delete pv pv-retain pv-rox --ignore-not-found
# hostPath data remains on the node's disk at /tmp/ex55-retain and /tmp/ex55-rox until removed manually.
```
