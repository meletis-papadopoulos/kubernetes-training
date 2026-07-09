# Lab 5.5 - Access Modes & Reclaim Policies

## Objective
Understand PersistentVolume access modes (RWO, ROX, RWX) and reclaim policies (Retain, Delete). Learn which access mode to use for different workload types.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Create the ReadWriteOnce PV

```bash
kubectl apply -f pv-rwo.yaml
```

### 2. Create the ReadOnlyMany PV

```bash
kubectl apply -f pv-rox.yaml
```

### 3. Inspect both PVs

```bash
kubectl get pv
```

Note the ACCESS MODES and RECLAIM POLICY columns:
- `pv-rwo`: RWO, Retain
- `pv-rox`: ROX, Delete

### 4. Create PVCs

```bash
kubectl apply -f pvc-rwo.yaml
kubectl apply -f pvc-rox.yaml
```

### 5. Verify bindings

```bash
kubectl get pvc -n training
kubectl get pv
```

Both PVCs should be `Bound`.

### 6. Understand access modes

| Mode | Abbreviation | Meaning |
|------|-------------|---------|
| ReadWriteOnce | RWO | Volume can be mounted read-write by a single node |
| ReadOnlyMany | ROX | Volume can be mounted read-only by many nodes |
| ReadWriteMany | RWX | Volume can be mounted read-write by many nodes |
| ReadWriteOncePod | RWOP | Volume can be mounted read-write by a single pod |

**Important**: Access modes are about how many *nodes* can mount the volume, not how many *pods*. Multiple pods on the same node can use an RWO volume.

### 7. Test ReadWriteOnce

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: rwo-writer
  namespace: training
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "echo 'RWO data' > /data/test.txt && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: pvc-rwo
EOF
kubectl wait --for=condition=Ready pod/rwo-writer -n training --timeout=60s
```

### 8. Verify write access

```bash
kubectl exec rwo-writer -n training -- cat /data/test.txt
```

### 9. Demonstrate Retain reclaim policy

Delete the PVC for the RWO PV:

```bash
kubectl delete pod rwo-writer -n training --force --grace-period=0
kubectl delete pvc pvc-rwo -n training --force --grace-period=0
kubectl get pv pv-rwo
```

STATUS becomes `Released`. The PV still exists and retains its data. It cannot be reused until the `claimRef` is cleared.

### 10. Demonstrate Delete reclaim policy

```bash
kubectl delete pvc pvc-rox -n training --force --grace-period=0
kubectl get pv pv-rox
```

With the Delete policy, the PV may be automatically removed. Check:

```bash
kubectl get pv | grep pv-rox
```

Note: for hostPath volumes, the PV resource may be deleted but the host directory may remain.

### 11. Summary of reclaim policies

| Policy | What Happens | Use Case |
|--------|-------------|----------|
| Retain | PV stays, data preserved, manual cleanup needed | Production data you must not lose |
| Delete | PV and backing storage deleted | Temporary/disposable data |
| Recycle | (Deprecated) rm -rf and make available again | Legacy only |

## Verification

```bash
# Check PV statuses
kubectl get pv

# Understand the difference
kubectl get pv -o custom-columns=NAME:.metadata.name,CAPACITY:.spec.capacity.storage,ACCESS:.spec.accessModes,RECLAIM:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase
```

## Cleanup

```bash
kubectl delete pod rwo-writer -n training --ignore-not-found --force --grace-period=0
kubectl delete pvc pvc-rwo pvc-rox -n training --ignore-not-found --force --grace-period=0
kubectl delete pv pv-rwo pv-rox --ignore-not-found --force --grace-period=0
```

## Further reading
- [Access Modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes) - concept reference
- [Reclaim Policy](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming) - concept reference
