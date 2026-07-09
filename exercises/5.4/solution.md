# Exercise 5.4 - Solutions

Reference manifests are in `solution/`. Namespace `wl-demo` is assumed to exist (see the exercise
Prerequisites).

## Task 1 - a Deployment shares one PVC

```bash
kubectl apply -f solution/shared-pvc.yaml
kubectl apply -f solution/shared-web.yaml
kubectl rollout status deployment/shared-web -n wl-demo --timeout=120s
```

`solution/shared-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-pvc
  namespace: wl-demo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

`solution/shared-web.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shared-web
  namespace: wl-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: shared-web
  template:
    metadata:
      labels:
        app: shared-web
    spec:
      containers:
      - name: nginx
        image: nginx:1.27.1
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        persistentVolumeClaim:
          claimName: shared-pvc
```

Write a file, delete the Pod, and read it back from the replacement:

```bash
POD=$(kubectl get pod -n wl-demo -l app=shared-web -o jsonpath='{.items[0].metadata.name}')
kubectl exec "$POD" -n wl-demo -- sh -c 'echo "<h1>from the deployment</h1>" > /usr/share/nginx/html/index.html'
kubectl delete pod "$POD" -n wl-demo --force --grace-period=0
kubectl rollout status deployment/shared-web -n wl-demo --timeout=120s
NEW=$(kubectl get pod -n wl-demo -l app=shared-web -o jsonpath='{.items[0].metadata.name}')
kubectl exec "$NEW" -n wl-demo -- cat /usr/share/nginx/html/index.html
```

Expected - the content survived into the new Pod:

```
<h1>from the deployment</h1>
```

**Answer to the reflective question:** the file survived because `shared-pvc` is a standalone object that
outlives the Pod; the Deployment's Pod template just references it **by name**. Every replica of a
Deployment uses the *same* Pod template, so they all mount that one PVC - the volume is shared, not
per-Pod. (With `ReadWriteOnce` and more than one replica, only Pods on the same node as the volume can
mount it, which is why sharing a single PVC across many Deployment replicas is limited.)

## Task 2 - a StatefulSet creates one PVC per replica

```bash
kubectl apply -f solution/sts-web.yaml
kubectl rollout status statefulset/sts-web -n wl-demo --timeout=180s
kubectl get pvc -n wl-demo
```

`solution/sts-web.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: sts
  namespace: wl-demo
spec:
  clusterIP: None
  selector:
    app: sts
  ports:
  - port: 80
    name: web
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: sts-web
  namespace: wl-demo
spec:
  serviceName: sts
  replicas: 2
  selector:
    matchLabels:
      app: sts
  template:
    metadata:
      labels:
        app: sts
    spec:
      containers:
      - name: nginx
        image: nginx:1.27.1
        ports:
        - containerPort: 80
          name: web
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
```

Expected - one PVC per replica, `<template>-<statefulset>-<ordinal>`:

```
NAME             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
data-sts-web-0   Bound    pvc-...                                    1Gi        RWO            local-path     40s
data-sts-web-1   Bound    pvc-...                                    1Gi        RWO            local-path     25s
shared-pvc       Bound    pvc-...                                    1Gi        RWO            local-path     3m
```

**Answer to the reflective question:** the StatefulSet created **two** PVCs, `data-sts-web-0` and
`data-sts-web-1` - one per replica, named from the `volumeClaimTemplates` entry plus the Pod's ordinal.
The `volumeClaimTemplates` block is a *template*: the controller stamps out a fresh PVC for each ordinal.

## Task 3 - each ordinal keeps its own volume

```bash
kubectl exec sts-web-0 -n wl-demo -- sh -c 'echo "pod 0" > /usr/share/nginx/html/index.html'
kubectl exec sts-web-1 -n wl-demo -- sh -c 'echo "pod 1" > /usr/share/nginx/html/index.html'
kubectl delete pod sts-web-0 -n wl-demo --force --grace-period=0
kubectl wait --for=condition=Ready pod/sts-web-0 -n wl-demo --timeout=120s
kubectl exec sts-web-0 -n wl-demo -- cat /usr/share/nginx/html/index.html
```

Expected - `sts-web-0` came back with its own data:

```
pod 0
```

**Answer to the reflective question:** `sts-web-0` was re-bound to `data-sts-web-0`, the same PVC it had
before, so it reads `pod 0` and not `pod 1`. A Deployment cannot do this because all its replicas share a
single Pod template that names one PVC - there is no mechanism to give ordinal-0 a different claim from
ordinal-1, and Deployment Pods have no stable identity (random suffixes, interchangeable). Only a
StatefulSet couples a **stable ordinal identity** to a **per-ordinal PVC** via `volumeClaimTemplates`,
which is why databases and other stateful apps run as StatefulSets.

## Cleanup

```bash
kubectl delete ns wl-demo --ignore-not-found
# StatefulSet PVCs are not deleted with the StatefulSet; the namespace delete removes them here.
```
