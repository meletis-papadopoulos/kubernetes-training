# Exercise 5.3 - Solutions

Reference manifests are in `solution/`. Namespace `dyn-demo` is assumed to exist (see the exercise
Prerequisites).

## Task 1 - inspect the default StorageClass

```bash
kubectl get storageclass
DEFAULT_SC=$(kubectl get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
echo "default: $DEFAULT_SC"
kubectl describe storageclass "$DEFAULT_SC"
```

Expected (the `(default)` marker is the giveaway):

```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  30d
```

**Answer to the reflective question:** the default class is `local-path`, backed by the
`rancher.io/local-path` provisioner. `VolumeBindingMode: WaitForFirstConsumer` means the provisioner does
**not** create a PV the moment the PVC appears - it waits until a Pod that mounts the PVC is scheduled,
then provisions the volume on the node where that Pod landed. This keeps node-local storage on the same
node as its consumer.

## Task 2 - a PVC using the default class

```bash
kubectl apply -f solution/dynamic-pvc.yaml
kubectl get pvc dynamic-pvc -n dyn-demo
```

`solution/dynamic-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc
  namespace: dyn-demo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Expected - `Pending`, not yet bound:

```
NAME          STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
dynamic-pvc   Pending                                      local-path     3s
```

**Answer to the reflective question:** the PVC is `Pending` because the default class uses
`WaitForFirstConsumer`. There is no Pod consuming it yet, so the provisioner deliberately holds off. This
is expected behaviour, not an error - contrast with an `Immediate` class, which would provision at once.

## Task 3 - the Pod triggers dynamic provisioning

```bash
kubectl apply -f solution/dynamic-pod.yaml
kubectl wait --for=condition=Ready pod/dynamic-pod -n dyn-demo --timeout=120s
kubectl get pvc dynamic-pvc -n dyn-demo
kubectl get pv
```

`solution/dynamic-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dynamic-pod
  namespace: dyn-demo
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "echo 'dynamic!' > /data/test.txt && sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: dynamic-pvc
```

Expected - the PVC is now `Bound` and a PV was created for you (name and age are illustrative):

```
NAME          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
dynamic-pvc   Bound    pvc-8f2a1c34-6b0e-4d9a-9f11-2c5e7a0b3d44   1Gi        RWO            local-path     20s
```
```
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                     STORAGECLASS   AGE
pvc-8f2a1c34-6b0e-4d9a-9f11-2c5e7a0b3d44   1Gi        RWO            Delete           Bound    dyn-demo/dynamic-pvc      local-path     18s
```

Confirm the data is on the provisioned volume:

```bash
kubectl exec dynamic-pod -n dyn-demo -- cat /data/test.txt
```

Expected:

```
dynamic!
```

**Answer to the reflective question:** in exercise 5.2 you had to author and apply a PersistentVolume by
hand (choosing its size, path, access mode, reclaim policy) *before* any claim could bind. Here the
StorageClass' provisioner did all of that automatically the instant a Pod consumed the PVC - it created
the PV (`pvc-<uuid>`), sized it to the request, and bound it. You declare *what* storage you need; the
StorageClass decides *how* to make it exist.

## Cleanup

```bash
kubectl delete ns dyn-demo --ignore-not-found
# The default class reclaim policy is Delete, so the auto-created PV is removed with its PVC.
```
