# Lab 5.4 - PVCs in Deployments & StatefulSets

## Objective
Compare how Deployments and StatefulSets use persistent storage. Deployments share a single PVC; StatefulSets get one PVC per replica via volumeClaimTemplates.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### Part A: Deployment with PVC

### 1. Create the PVC

```bash
kubectl apply -f pvc.yaml
```

### 2. Deploy the Deployment

```bash
kubectl apply -f deployment-pvc.yaml
kubectl rollout status deployment/deploy-with-pvc -n training --timeout=60s
```

### 3. Verify PVC is bound

```bash
kubectl get pvc deploy-pvc -n training
```

### 4. Write data to the volume

```bash
POD=$(kubectl get pod -n training -l app=deploy-pvc -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -n training -- sh -c 'echo "<h1>Persistent Deployment</h1>" > /usr/share/nginx/html/index.html'
```

### 5. Delete the pod (Deployment will recreate it)

```bash
kubectl delete pod $POD -n training --force --grace-period=0
```

### 6. Verify data survives

```bash
kubectl rollout status deployment/deploy-with-pvc -n training --timeout=60s
NEW_POD=$(kubectl get pod -n training -l app=deploy-pvc -o jsonpath='{.items[0].metadata.name}')
kubectl exec $NEW_POD -n training -- cat /usr/share/nginx/html/index.html
```

The data persists because the PVC outlives the pod.

### 7. Note the limitation

A Deployment with RWO PVC and `replicas > 1` will fail if pods land on different nodes, because RWO only allows one node to mount the volume. Try:

```bash
kubectl scale deployment deploy-with-pvc --replicas=2 -n training
kubectl get pods -n training -l app=deploy-pvc
```

One pod may stay `Pending` if it is scheduled on a different node.

```bash
kubectl scale deployment deploy-with-pvc --replicas=1 -n training
```

### Part B: StatefulSet with volumeClaimTemplates

### 8. Deploy the StatefulSet

```bash
kubectl apply -f statefulset.yaml
kubectl rollout status statefulset/web-stateful -n training --timeout=180s
```

### 9. Verify PVCs are created for each replica

```bash
kubectl get pvc -n training
```

You should see:
- `web-data-web-stateful-0`
- `web-data-web-stateful-1`
- `web-data-web-stateful-2`

Each replica gets its own PVC.

### 10. Write unique data to each pod

```bash
kubectl exec web-stateful-0 -n training -- sh -c 'echo "<h1>Pod 0</h1>" > /usr/share/nginx/html/index.html'
kubectl exec web-stateful-1 -n training -- sh -c 'echo "<h1>Pod 1</h1>" > /usr/share/nginx/html/index.html'
kubectl exec web-stateful-2 -n training -- sh -c 'echo "<h1>Pod 2</h1>" > /usr/share/nginx/html/index.html'
```

### 11. Delete a pod and verify data survives

```bash
kubectl delete pod web-stateful-1 -n training --force --grace-period=0
kubectl wait --for=create pod/web-stateful-1 -n training --timeout=60s
kubectl wait --for=condition=Ready pod/web-stateful-1 -n training --timeout=120s
kubectl exec web-stateful-1 -n training -- cat /usr/share/nginx/html/index.html
```

Output: `<h1>Pod 1</h1>` -- the data survived because the PVC was not deleted.

### 12. Compare Deployment vs StatefulSet storage

| Feature | Deployment + PVC | StatefulSet + VCT |
|---------|-----------------|-------------------|
| PVC per pod | No (shared) | Yes (unique) |
| Data isolation | Shared data | Per-pod data |
| Scaling | RWO limits multi-node | Each pod gets own PVC |
| PVC lifecycle | Manual management | Auto-created, manual delete |
| Use case | Shared config/cache | Databases, stateful apps |

## Verification

```bash
# Deployment PVC bound
kubectl get pvc deploy-pvc -n training

# StatefulSet PVCs (one per replica)
kubectl get pvc -n training -l app=web-stateful

# Data persists
kubectl exec web-stateful-0 -n training -- cat /usr/share/nginx/html/index.html
```

## Cleanup

```bash
kubectl delete -f deployment-pvc.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pvc.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f statefulset.yaml --ignore-not-found --force --grace-period=0
# StatefulSet PVCs are not deleted automatically
kubectl delete pvc -n training -l app=web-stateful --ignore-not-found --force --grace-period=0
```

## Further reading
- [Claims as Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#claims-as-volumes) - concept reference
- [StatefulSet Stable Storage](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#stable-storage) - concept reference
- [StatefulSet Basics Tutorial](https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/) - tutorial
