# Exercise 9.7 - Solutions

Reference manifests are in `solution/`. Namespace `ts97` with the broken PVC `data` and the `writer`
Pod are assumed applied (see the exercise Setup).

## Task 1 - diagnose and fix the unbound PVC

### Diagnose

```bash
sleep 10
kubectl get pvc data -n ts97
kubectl get pod writer -n ts97
kubectl describe pvc data -n ts97 | tail -8
kubectl get storageclass
```

Expected (values illustrative):

```
NAME   STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
data   Pending                                      fast-ssd       15s

NAME     READY   STATUS    RESTARTS   AGE
writer   0/1     Pending   0          15s
```

```
Warning  ProvisioningFailed  ...  storageclass.storage.k8s.io "fast-ssd" not found
```

```
NAME                   PROVISIONER             ...
local-path (default)   rancher.io/local-path   ...
```

**Root cause:** the PVC requests StorageClass `fast-ssd`, which does not exist in this cluster. With
no StorageClass to delegate to, the provisioner cannot create a PV, the PVC stays `Pending`, and the
Pod that mounts it cannot be scheduled - so `writer` is `Pending` too. The break is at the first
layer: **PVC -> StorageClass**.

### Fix

`storageClassName` is immutable, so delete and re-create the PVC with the real default class
(`local-path`). The Pod already references the claim by name; the scheduler will retry once the claim
can bind:

```bash
kubectl delete pvc data -n ts97
kubectl apply -f solution/data-pvc.yaml
```

### Verify

```bash
kubectl wait --for=condition=Ready pod/writer -n ts97 --timeout=90s
kubectl get pvc data -n ts97
kubectl get pod writer -n ts97
```

Expected:

```
NAME   STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS   AGE
data   Bound    pvc-....     1Gi        RWO            local-path     30s

NAME     READY   STATUS    RESTARTS   AGE
writer   1/1     Running   0          30s
```

## Task 2 - reflective answer

`local-path` uses `volumeBindingMode: WaitForFirstConsumer`: it deliberately holds the PVC `Pending`
until a Pod that mounts it is scheduled, so the volume lands on the right node. That `Pending` carries
a `WaitForFirstConsumer` event (provisioner healthy, just waiting) - fundamentally different from the
original `ProvisioningFailed` (provisioner cannot act because the class is missing). Same `Pending`
word, opposite meaning: read the **event**, not the status column. Once `writer` is scheduled the
volume provisions and the PVC binds. The layer that was broken was PVC -> StorageClass, not PVC <-> PV
sizing or Pod -> PVC naming.

## Cleanup

```bash
kubectl delete ns ts97 --ignore-not-found
```
