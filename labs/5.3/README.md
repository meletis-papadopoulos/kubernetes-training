# Lab 5.3 - StorageClasses & Dynamic Provisioning

## Objective
Understand StorageClasses and dynamic volume provisioning. Learn how the default StorageClass automatically creates PVs when PVCs are created.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. List available StorageClasses

```bash
kubectl get storageclass
```

You should see the default StorageClass marked with `(default)`.

### 2. Inspect the default StorageClass

```bash
kubectl describe storageclass $(kubectl get sc -o jsonpath='{.items[0].metadata.name}')
```

Note:
- **Provisioner**: the storage backend
- **ReclaimPolicy**: Delete or Retain
- **VolumeBindingMode**: Immediate or WaitForFirstConsumer

### 3. Create a PVC without specifying storageClassName

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc-default
  namespace: training
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
EOF
```

### 4. Check PVC status

```bash
kubectl get pvc dynamic-pvc-default -n training
```

With `WaitForFirstConsumer`, the PVC stays `Pending` until a pod uses it. This is normal.

### 5. Create a pod to trigger provisioning

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: dynamic-pod-default
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo 'Dynamic provisioning works!' > /data/test.txt && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: dynamic-pvc-default
EOF
kubectl wait --for=condition=Ready pod/dynamic-pod-default -n training --timeout=120s
```

### 6. Verify dynamic provisioning

```bash
kubectl get pvc dynamic-pvc-default -n training
kubectl get pv
```

A PV was automatically created and bound to the PVC. You never had to create the PV manually.

### 7. Create a PVC with explicit storageClassName

```bash
DEFAULT_SC=$(kubectl get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc-explicit
  namespace: training
spec:
  storageClassName: ${DEFAULT_SC}
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 250Mi
EOF
```

### 8. Create a pod to bind it

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: dynamic-pod-explicit
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo 'Explicit SC works!' > /data/test.txt && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: dynamic-pvc-explicit
EOF
kubectl wait --for=condition=Ready pod/dynamic-pod-explicit -n training --timeout=120s
```

### 9. Compare PVCs

```bash
kubectl get pvc -n training
```

Both PVCs should be `Bound`, each with a dynamically provisioned PV.

### 10. Create a PVC with storageClassName: "" (no dynamic provisioning)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: static-pvc
  namespace: training
spec:
  storageClassName: ""
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
EOF
```

### 11. Check the static PVC

```bash
kubectl get pvc static-pvc -n training
```

This PVC will stay `Pending` forever because `storageClassName: ""` disables dynamic provisioning and there is no pre-created PV to bind to.

### 12. Understand VolumeBindingMode

- **Immediate**: PV is provisioned as soon as PVC is created
- **WaitForFirstConsumer**: PV is provisioned only when a pod using the PVC is scheduled (default for local-path)

`WaitForFirstConsumer` is better for topology-aware storage because it provisions on the same node as the pod.

## Verification

```bash
# StorageClass exists
kubectl get sc

# Dynamic PVCs are bound
kubectl get pvc -n training

# PVs were auto-created
kubectl get pv

# Data is accessible
kubectl exec dynamic-pod-default -n training -- cat /data/test.txt
```

## Cleanup

```bash
kubectl delete pod dynamic-pod-default dynamic-pod-explicit -n training --ignore-not-found --force --grace-period=0
kubectl delete pvc dynamic-pvc-default dynamic-pvc-explicit static-pvc -n training --ignore-not-found --force --grace-period=0
```

## Further reading
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/) - concept reference
- [Dynamic Volume Provisioning](https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/) - concept reference
