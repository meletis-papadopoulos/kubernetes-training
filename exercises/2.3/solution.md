# Exercise 2.3 - Solutions

Reference manifest is in `solution/`. Namespace `core` is assumed to exist (see the exercise Setup).

## Task 1 - Deployment, its ReplicaSet, and the ownership chain

```bash
kubectl apply -f solution/deployment.yaml
kubectl rollout status deployment/web -n core
```

`solution/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: core
  labels:
    app: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.27.1
        ports:
        - containerPort: 80
```

List the three object layers and walk the ownership chain:

```bash
kubectl get deploy,rs,pods -n core -l app=web
POD=$(kubectl get pods -n core -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl get pod "$POD" -n core -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
RS=$(kubectl get rs -n core -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl get rs "$RS" -n core -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
```

Expected (ReplicaSet hash illustrative):

```
NAME                  READY   UP-TO-DATE   AVAILABLE
deployment.apps/web   3/3     3            3

NAME                             DESIRED   CURRENT   READY
replicaset.apps/web-6f9c8d7b5c   3         3         3
...three web-6f9c8d7b5c-xxxxx pods...

ReplicaSet/web-6f9c8d7b5c
Deployment/web
```

**Answer to the reflective question:** the **ReplicaSet** directly owns the pods (each pod's
`ownerReferences` points at the ReplicaSet). The Deployment owns the ReplicaSet, not the pods - it
manages pods only *through* the ReplicaSet it creates for each pod-template revision.

## Task 2 - self-healing at the ReplicaSet level

```bash
kubectl scale deployment web -n core --replicas=5
kubectl rollout status deployment/web -n core
kubectl scale deployment web -n core --replicas=3
kubectl rollout status deployment/web -n core

VICTIM=$(kubectl get pods -n core -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod "$VICTIM" -n core
kubectl get pods -n core -l app=web
```

Verify the count returned to 3:

```bash
kubectl get deployment web -n core -o jsonpath='{.status.availableReplicas}{"\n"}'
```

Expected - the deleted pod is gone, a new-named replacement is present, and the total is back to `3`:

```
3
```

**Answer to the reflective question:** the **ReplicaSet** controller noticed the pod count dropped
below its `spec.replicas` (`3`) and created a replacement to close the gap. It knows the desired count
because scaling the Deployment updates the active ReplicaSet's `replicas` field; the ReplicaSet's only
job is to keep exactly that many pods matching its selector alive.

## Cleanup

```bash
kubectl delete -f solution/deployment.yaml --ignore-not-found --force --grace-period=0
kubectl delete ns core --ignore-not-found
```
