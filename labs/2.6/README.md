# Lab 2.6 - StatefulSets Basics

## Objective
Learn what makes a StatefulSet different from a Deployment: stable, predictable pod names, ordered creation and deletion, stable per-pod network identity, and a dedicated PersistentVolumeClaim (PVC) for each pod.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Create the headless Service first

StatefulSets need a headless Service (a Service with `clusterIP: None`) to provide each pod its own stable DNS name, and it must exist before the StatefulSet is created:

```bash
kubectl apply -f headless-service.yaml
```

### 2. Create the StatefulSet

```bash
kubectl apply -f statefulset.yaml
kubectl rollout status statefulset/nginx-stateful -n training --timeout=180s
```

Note the `volumeClaimTemplates` section in `statefulset.yaml` - Kubernetes creates a dedicated PVC for each pod automatically. Lab 5.4 covers PVCs and volumeClaimTemplates in more depth.

### 3. Watch pods being created in order

```bash
timeout 15s kubectl get pods -n training -l app=nginx-stateful -w || true
```

Notice pods are created **sequentially**: `nginx-stateful-0`, then `nginx-stateful-1`, then `nginx-stateful-2`. Each must be Running before the next is created.

### 4. Verify stable pod names

```bash
kubectl get pods -n training -l app=nginx-stateful
```

Pod names follow the pattern `<statefulset-name>-<ordinal>` and are predictable. A Deployment's pods get random suffixes instead.

### 5. Verify stable network identity

Apply the throwaway `dns-test.yaml` — a one-shot busybox pod that resolves both the headless Service and each pod's stable per-pod name — then read its output and delete it:

```bash
kubectl apply -f dns-test.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/dns-test -n training --timeout=60s
kubectl logs dns-test -n training
kubectl delete -f dns-test.yaml
```

The headless Service name (`nginx-headless.training.svc.cluster.local`) returns **all** pod IPs — generic headless-Service behavior. The StatefulSet-specific feature is that **each pod also gets its own stable DNS name**, `nginx-stateful-<ordinal>.nginx-headless.training.svc.cluster.local`, each resolving to that one pod — a stable address that survives restarts. A Deployment's pods get random names and no per-pod DNS.

### 6. Verify PersistentVolumeClaims

```bash
kubectl get pvc -n training
```

Each pod has its own PVC: `www-nginx-stateful-0`, `www-nginx-stateful-1`, `www-nginx-stateful-2`.

### 7. Write data to prove persistence

```bash
kubectl exec nginx-stateful-0 -n training -- sh -c 'echo "Hello from pod-0" > /usr/share/nginx/html/index.html'
kubectl exec nginx-stateful-1 -n training -- sh -c 'echo "Hello from pod-1" > /usr/share/nginx/html/index.html'
```

### 8. Delete a pod and verify data survives

```bash
kubectl delete pod nginx-stateful-0 -n training --force --grace-period=0
```

Wait for it to restart (same name!):

```bash
timeout 30s kubectl get pods -n training -l app=nginx-stateful -w || true
```

Verify data persisted:

```bash
kubectl wait --for=condition=Ready pod/nginx-stateful-0 -n training --timeout=60s
kubectl exec nginx-stateful-0 -n training -- cat /usr/share/nginx/html/index.html
# Output: Hello from pod-0
```

The data survives because the pod's PVC is not deleted along with the pod.

### 9. Compare deletion behavior

StatefulSets delete pods in reverse order (2, 1, 0). Scale down to observe:

```bash
kubectl scale statefulset nginx-stateful --replicas=1 -n training
timeout 20s kubectl get pods -n training -l app=nginx-stateful -w || true
```

Scale back up:

```bash
kubectl scale statefulset nginx-stateful --replicas=3 -n training
```

## Verification

```bash
# StatefulSet has ordered pod names
kubectl get pods -n training -l app=nginx-stateful --sort-by=.metadata.name

# PVCs exist for each StatefulSet pod
kubectl get pvc -n training
```

## Cleanup

```bash
kubectl delete -f statefulset.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f headless-service.yaml --ignore-not-found --force --grace-period=0
# PVCs are not deleted automatically - clean them up manually
kubectl delete pvc -n training -l app=nginx-stateful --ignore-not-found --force --grace-period=0
```

## Further reading
- [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) - concept reference
- [StatefulSet Basics](https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/) - tutorial
