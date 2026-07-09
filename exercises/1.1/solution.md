# Exercise 1.1 - Solutions

Reference manifests are in `solution/`. Namespace `kdemo` is assumed to exist (see the exercise Setup).

## Task 1 - three objects, imperatively

```bash
kubectl run web --image=nginx:1.27.1 --port=80 -n kdemo
kubectl create deployment api --image=httpd:2.4.62 --replicas=2 -n kdemo
kubectl expose deployment api --name=api --port=80 --target-port=80 -n kdemo
```

Verify all three:

```bash
kubectl get pods,deploy,svc -n kdemo
```

Expected (`AGE`/`CLUSTER-IP` are illustrative):

```
NAME                       READY   STATUS    RESTARTS   AGE
pod/web                    1/1     Running   0          20s
pod/api-6c9f8b7d5f-abcde   1/1     Running   0          18s
pod/api-6c9f8b7d5f-fghij   1/1     Running   0          18s

NAME                   READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/api    2/2     2            2           18s

NAME          TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/api   ClusterIP   10.96.14.201   <none>        80/TCP    10s
```

**Answer:** all three are imperative *create* verbs, so re-running any of them fails with
`Error from server (AlreadyExists)` - the object already exists and `run`/`create`/`expose` do not
reconcile, they only create. This "already exists" friction is exactly what `kubectl apply`
(declarative) removes.

## Task 2 - declarative via scaffolded YAML + diff

Scaffold the manifest without touching the cluster, then apply it:

```bash
kubectl create deployment cache --image=nginx:1.27.1 --replicas=1 -n kdemo \
  --dry-run=client -o yaml > cache.yaml
kubectl apply -f cache.yaml
```

`solution/cache-deploy.yaml` is the reference manifest (already at the final `3` replicas):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache
  namespace: kdemo
  labels:
    app: cache
spec:
  replicas: 3
  selector:
    matchLabels:
      app: cache
  template:
    metadata:
      labels:
        app: cache
    spec:
      containers:
      - name: nginx
        image: nginx:1.27.1
        ports:
        - containerPort: 80
```

Bump the replicas and preview the change before applying:

```bash
sed -i 's/replicas: 1/replicas: 3/' cache.yaml
kubectl diff -f cache.yaml
kubectl apply -f cache.yaml
```

Expected `kubectl diff` (illustrative - shows only the changed field):

```
--- .../cache (before)
+++ .../cache (after)
@@ -...
-  replicas: 1
+  replicas: 3
```

Confirm 3 ready replicas:

```bash
kubectl rollout status deployment cache -n kdemo
kubectl get deployment cache -n kdemo -o jsonpath='{.status.readyReplicas}{"\n"}'
```

Expected:

```
deployment "cache" successfully rolled out
3
```

**Answer:** `kubectl apply` computes the difference between the file (desired state) and the live
object and reconciles it, so re-running is idempotent - the second apply is a no-op or a minimal
patch, never an error. `kubectl create` only ever tries to add a new object, so a repeat fails with
`AlreadyExists`. Declarative wins whenever you want a reviewable, version-controlled source of truth,
repeatable applies (CI/CD and GitOps), and safe incremental edits previewed with `diff` - i.e.
anything beyond a throwaway one-off.

## Task 3 - explain, label, annotate, delete

Discover the field and its default:

```bash
kubectl explain pod.spec.restartPolicy
```

Expected:

```
KIND:       Pod
VERSION:    v1

FIELD: restartPolicy <string>

DESCRIPTION:
    Restart policy for all containers within the pod. One of Always, OnFailure,
    Never. ... Default to Always.
```

Label and annotate the `web` Pod, then filter by the label:

```bash
kubectl label pod web tier=frontend -n kdemo
kubectl annotate pod web owner=team-a -n kdemo
kubectl get pods -n kdemo -l tier=frontend
```

Expected - the selector returns exactly `web`:

```
NAME   READY   STATUS    RESTARTS   AGE
web    1/1     Running   0          3m
```

Delete the four objects imperatively:

```bash
kubectl delete pod web -n kdemo --force --grace-period=0
kubectl delete deployment api cache -n kdemo
kubectl delete service api -n kdemo
```

**Answer:** a label selector can match `tier=frontend` but **not** `owner=team-a`. Labels are the
identifying, queryable metadata that selectors (and Services, ReplicaSets, etc.) index on;
annotations are free-form, non-identifying metadata (tooling hints, contact info) that are never
selectable. Same `key=value` shape, completely different purpose.

## Cleanup

```bash
kubectl delete ns kdemo --ignore-not-found
rm -f cache.yaml
```
