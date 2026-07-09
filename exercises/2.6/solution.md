# Exercise 2.6 - Solutions

Reference manifests are in `solution/`. Namespace `stateful` is assumed to exist.

## Task 1 - headless Service + StatefulSet

```bash
kubectl apply -f solution/headless-svc.yaml
kubectl apply -f solution/statefulset.yaml
```

`solution/headless-svc.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: stateful
spec:
  clusterIP: None
  selector:
    app: nginx
  ports:
  - port: 80
    name: web
```

`solution/statefulset.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
  namespace: stateful
spec:
  serviceName: nginx
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.27.1
        ports:
        - containerPort: 80
          name: web
        volumeMounts:
        - name: www
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: www
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
```

Wait for the rollout and list the pods:

```bash
kubectl rollout status statefulset web -n stateful
kubectl get pods -n stateful -l app=nginx
```

Expected - pods are created **one at a time, in ordinal order**, each becoming `Running` before the
next starts:

```
NAME    READY   STATUS    RESTARTS   AGE
web-0   1/1     Running   0          20s
web-1   1/1     Running   0          12s
web-2   1/1     Running   0          5s
```

**Answer:** names are stable and ordinal (`web-0`, `web-1`, `web-2`), assigned by the StatefulSet;
a rescheduled pod keeps its name and its bound volume. This is the defining difference from a
Deployment, whose pods get random suffixes and are interchangeable.

## Task 2 - per-pod PVCs survive scale-down

Confirm one PVC per pod:

```bash
kubectl get pvc -n stateful
```

Expected:

```
NAME        STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
www-web-0   Bound    pvc-...  1Gi        RWO            <default>      1m
www-web-1   Bound    pvc-...  1Gi        RWO            <default>      1m
www-web-2   Bound    pvc-...  1Gi        RWO            <default>      50s
```

Scale up then down:

```bash
kubectl scale statefulset web -n stateful --replicas=5
kubectl rollout status statefulset web -n stateful
kubectl scale statefulset web -n stateful --replicas=2
kubectl get pods -n stateful -l app=nginx
kubectl get pvc -n stateful
```

Expected after scaling to 2 - only `web-0`/`web-1` remain as pods, but **all five PVCs still exist**:

```
NAME        STATUS   ...
www-web-0   Bound
www-web-1   Bound
www-web-2   Bound
www-web-3   Bound
www-web-4   Bound
```

**Answer:** StatefulSets **do not** delete PVCs when pods are removed on scale-down (unless you set
`persistentVolumeClaimRetentionPolicy`, which defaults to `Retain`). This preserves data so that
scaling `web-2` back up rebinds it to the same `www-web-2` volume. You must delete leftover PVCs
manually if you want the storage reclaimed.

## Task 3 - stable per-pod DNS

```bash
kubectl run dnstest -n stateful --image=busybox:1.28 --restart=Never -i --rm -- \
  nslookup web-0.nginx
```

Expected:

```
Name:      web-0.nginx.stateful.svc.cluster.local
Address 1: 10.244.1.7 web-0.nginx.stateful.svc.cluster.local
```

**Answer:** the headless Service gives each pod a stable DNS name of the form
`<pod>.<service>.<namespace>.svc.cluster.local`. A client can therefore address `web-0` directly and
reliably - impossible with a normal ClusterIP Service, which load-balances across interchangeable pods.

## Cleanup

```bash
kubectl delete ns stateful --ignore-not-found
# PVCs live in the namespace and are removed with it; if you used a cluster-scoped PV, check:
kubectl get pv | grep stateful || true
```
