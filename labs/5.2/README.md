# Lab 5.2 - PersistentVolumes & PVCs

## Objective
Learn the PersistentVolume (PV) and PersistentVolumeClaim (PVC) abstraction. Create a PV, bind it with a PVC, mount it in a pod, and verify data persistence across pod restarts.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Create the PersistentVolume

```bash
kubectl apply -f pv.yaml
```

PVs are cluster-scoped (no namespace).

### 2. Verify the PV

```bash
kubectl get pv lab-pv
```

STATUS should be `Available`.

### 3. Create the PersistentVolumeClaim

```bash
kubectl apply -f pvc.yaml
```

### 4. Verify binding

```bash
kubectl get pv lab-pv
kubectl get pvc lab-pvc -n training
```

Both should show STATUS `Bound`. The PVC is bound to the PV.

### 5. Deploy a pod using the PVC

```bash
kubectl apply -f pod.yaml
kubectl wait --for=condition=Ready pod/pvc-pod -n training --timeout=60s
```

### 6. Verify the pod is running

```bash
kubectl get pod pvc-pod -n training
```

### 7. Verify data was written

```bash
kubectl exec pvc-pod -n training -- cat /data/output.txt
```

### 8. Test persistence: delete and recreate the pod

```bash
kubectl delete pod pvc-pod -n training --force --grace-period=0
kubectl apply -f pod.yaml
kubectl wait --for=condition=Ready pod/pvc-pod -n training --timeout=60s
```

Wait for the pod to start, then:

```bash
kubectl exec pvc-pod -n training -- cat /data/output.txt
```

You may see two lines if the new pod appended. The key point: the PVC (and underlying PV) retained the data across pod restarts.

### 9. Inspect the PV-PVC relationship

```bash
kubectl describe pv lab-pv
kubectl describe pvc lab-pvc -n training
```

Note the `Claim` field on the PV and the `Volume` field on the PVC.

### 10. Understand reclaim policies

The PV has `persistentVolumeReclaimPolicy: Retain`. When the PVC is deleted:
- **Retain**: PV keeps data, status becomes `Released` (manual cleanup needed)
- **Delete**: PV and backing storage are deleted
- **Recycle**: (deprecated) basic rm -rf on the volume

### 11. Test the Retain policy

```bash
kubectl delete pod pvc-pod -n training --force --grace-period=0
kubectl delete pvc lab-pvc -n training --force --grace-period=0
kubectl get pv lab-pv
```

The PV status should be `Released`, not `Available`. It cannot be rebound to a new PVC until manually cleaned up.

### 12. Clean up and re-create

To make the PV available again, you must remove the claimRef:

```bash
kubectl patch pv lab-pv --type json -p '[{"op": "remove", "path": "/spec/claimRef"}]'
kubectl get pv lab-pv
```

STATUS should return to `Available`.

## Verification

```bash
# PV exists
kubectl get pv lab-pv

# PVC binds to PV
kubectl apply -f pvc.yaml
kubectl get pvc lab-pvc -n training -o jsonpath='{.status.phase}'
# Should output: Bound
```

## Cleanup

```bash
kubectl delete -f pod.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pvc.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pv.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) - concept reference
- [Run a Single-Instance Stateful Application](https://kubernetes.io/docs/tasks/run-application/run-single-instance-stateful-application/) - task walkthrough
