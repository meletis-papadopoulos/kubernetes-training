# Exercise 5.2 - Solutions

Reference manifests are in `solution/`. Namespace `pv-demo` is assumed to exist (see the exercise Setup).

## Task 1 - a manually provisioned PersistentVolume

```bash
kubectl apply -f solution/manual-pv.yaml
kubectl get pv manual-pv
```

`solution/manual-pv.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: manual-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: /tmp/ex52-pv
    type: DirectoryOrCreate
```

Expected - no claim yet, so it is `Available`:

```
NAME        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   AGE
manual-pv   1Gi        RWO            Retain           Available           ""             5s
```

**Answer to the reflective question:** a freshly created PV with no bound claim is `Available`. It moves
to `Bound` when a matching PVC claims it, and (with `Retain`) to `Released` once that claim is deleted.

## Task 2 - a PVC that binds statically

```bash
kubectl apply -f solution/app-pvc.yaml
kubectl get pvc app-pvc -n pv-demo
kubectl get pv manual-pv
```

`solution/app-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-pvc
  namespace: pv-demo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: ""
```

Expected - both are `Bound` to each other:

```
NAME      STATUS   VOLUME      CAPACITY   ACCESS MODES   STORAGECLASS   AGE
app-pvc   Bound    manual-pv   1Gi        RWO            ""             4s
```
```
NAME        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM             STORAGECLASS   AGE
manual-pv   1Gi        RWO            Retain           Bound    pv-demo/app-pvc   ""             1m
```

**Answer to the reflective question:** the binding controller matched the claim to `manual-pv` because the
volume satisfied every request: **StorageClass** (both `""`), **access mode** (both include
`ReadWriteOnce`), and **capacity** (the PV's `1Gi` is at least the requested `1Gi`). A PV whose capacity
is smaller, whose access modes do not include the requested one, or whose StorageClass differs would not
have been selected. `storageClassName: ""` on both sides is what tells Kubernetes to bind statically
rather than invoke a dynamic provisioner.

## Task 3 - data persists across Pod restarts

```bash
kubectl apply -f solution/pv-pod.yaml
kubectl wait --for=condition=Ready pod/pv-pod -n pv-demo --timeout=60s
kubectl exec pv-pod -n pv-demo -- cat /data/output.txt
```

`solution/pv-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pv-pod
  namespace: pv-demo
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "echo 'persisted data' >> /data/output.txt && sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: app-pvc
```

Delete and re-create the Pod, then read the file again:

```bash
kubectl delete pod pv-pod -n pv-demo --force --grace-period=0
kubectl apply -f solution/pv-pod.yaml
kubectl wait --for=condition=Ready pod/pv-pod -n pv-demo --timeout=60s
kubectl exec pv-pod -n pv-demo -- cat /data/output.txt
```

Expected - the original line survived, and the second Pod appended its own:

```
persisted data
persisted data
```

**Answer to the reflective question:** the file survived because it lives in the PersistentVolume, an
object with a lifecycle **independent of the Pod**. Deleting the Pod releases nothing about the PVC or PV;
the next Pod that claims `app-pvc` mounts the exact same storage. The `emptyDir` in exercise 5.1 was part
of the Pod itself, so it was destroyed with it. (Because `manual-pv` is a `hostPath` volume its data lives
on one node; if the re-created Pod is scheduled to a different node it will see an empty directory - a
`hostPath` limitation, not a PV one. A real StorageClass-backed PV does not have this problem.)

## Cleanup

```bash
kubectl delete ns pv-demo --ignore-not-found
kubectl delete pv manual-pv --ignore-not-found
# hostPath data remains on the node's disk at /tmp/ex52-pv until removed manually.
```
