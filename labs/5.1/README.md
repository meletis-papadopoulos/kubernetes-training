# Lab 5.1 - Volumes

## Objective
Learn how to use emptyDir volumes for sharing data between containers in a pod, and hostPath volumes for accessing host filesystem. Understand the lifecycle and risks of each volume type.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### Part A: emptyDir Volume

### 1. Deploy the emptyDir pod

```bash
kubectl apply -f pod-emptydir.yaml
kubectl wait --for=condition=Ready pod/emptydir-pod -n training --timeout=60s
```

This pod has two containers sharing an emptyDir volume:
- **writer**: appends a timestamped message every 5 seconds
- **reader**: tails the log file

### 2. Verify both containers are running

```bash
kubectl get pod emptydir-pod -n training
```

Should show `2/2` in the READY column.

### 3. View the reader's output

```bash
kubectl logs emptydir-pod -n training -c reader --tail=5
```

You should see timestamped log entries written by the writer container.

### 4. Verify the shared file from the writer side

```bash
kubectl exec emptydir-pod -n training -c writer -- cat /data/log.txt
```

### 5. Understand emptyDir lifecycle

The emptyDir volume:
- Is created when the pod is assigned to a node
- Exists as long as the pod runs on that node
- Is **deleted permanently** when the pod is removed

Delete and recreate the pod:

```bash
kubectl delete pod emptydir-pod -n training --force --grace-period=0
kubectl apply -f pod-emptydir.yaml
kubectl wait --for=condition=Ready pod/emptydir-pod -n training --timeout=60s
kubectl exec emptydir-pod -n training -c writer -- cat /data/log.txt
```

The old data is gone. The file only has new entries.

### Part B: hostPath Volume

### 6. Deploy the hostPath pod

```bash
kubectl apply -f pod-hostpath.yaml
kubectl wait --for=condition=Ready pod/hostpath-pod -n training --timeout=60s
```

### 7. Verify the file was written

```bash
kubectl exec hostpath-pod -n training -- cat /host-data/test.txt
```

### 8. Verify the file exists on the host node

```bash
NODE=$(kubectl get pod hostpath-pod -n training -o jsonpath='{.spec.nodeName}')
ssh $NODE cat /tmp/k8s-lab-data/test.txt
```

The file exists on the host filesystem, outside the container.

### 9. Delete the pod and verify data persists on the host

```bash
kubectl delete pod hostpath-pod -n training --force --grace-period=0
ssh $NODE cat /tmp/k8s-lab-data/test.txt
```

The data survives pod deletion because it lives on the host.

### 10. Understand hostPath risks

**hostPath volumes are dangerous because:**
- Data is tied to a specific node (no portability)
- Pods can read/write arbitrary host files (security risk)
- If the pod is rescheduled to a different node, data is lost
- In production, use PersistentVolumes with proper storage backends instead

## Verification

```bash
# emptyDir: both containers see the same data
kubectl apply -f pod-emptydir.yaml
kubectl wait --for=condition=Ready pod/emptydir-pod -n training --timeout=60s
kubectl exec emptydir-pod -n training -c reader -- head -3 /data/log.txt

# hostPath: data written to host filesystem
kubectl apply -f pod-hostpath.yaml
kubectl wait --for=condition=Ready pod/hostpath-pod -n training --timeout=60s
NODE=$(kubectl get pod hostpath-pod -n training -o jsonpath='{.spec.nodeName}')
ssh $NODE cat /tmp/k8s-lab-data/test.txt
```

## Cleanup

```bash
kubectl delete -f pod-emptydir.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pod-hostpath.yaml --ignore-not-found --force --grace-period=0
# Clean up host directory on both nodes (the hostPath pod may have run on either)
for NODE in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  ssh $NODE rm -rf /tmp/k8s-lab-data
done
```

## Further reading
- [Volumes](https://kubernetes.io/docs/concepts/storage/volumes/) - concept reference
- [emptyDir](https://kubernetes.io/docs/concepts/storage/volumes/#emptydir) - concept reference
- [hostPath](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath) - concept reference
