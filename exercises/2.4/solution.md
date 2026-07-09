# Exercise 2.4 - Solutions

Reference manifest is in `solution/`. Namespace `core` is assumed to exist (see the exercise Setup).

## Task 1 - rolling update with a recorded change-cause

```bash
kubectl apply -f solution/deployment.yaml
kubectl rollout status deployment/rollme -n core
```

`solution/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rollme
  namespace: core
  labels:
    app: rollme
spec:
  replicas: 3
  selector:
    matchLabels:
      app: rollme
  template:
    metadata:
      labels:
        app: rollme
    spec:
      containers:
      - name: nginx
        image: nginx:1.27.0
        ports:
        - containerPort: 80
```

Update the image, record the change-cause, and watch the rollout:

```bash
kubectl set image deployment/rollme nginx=nginx:1.27.1 -n core
kubectl annotate deployment/rollme -n core \
  kubernetes.io/change-cause="upgrade to nginx 1.27.1"
kubectl rollout status deployment/rollme -n core
```

Verify the image and history:

```bash
kubectl get deployment rollme -n core -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl rollout history deployment/rollme -n core
```

Expected:

```
nginx:1.27.1
```

```
REVISION  CHANGE-CAUSE
1         <none>
2         upgrade to nginx 1.27.1
```

**Answer to the reflective question:** two revisions - revision `1` (the initial `1.27.0` rollout,
`<none>` cause) and revision `2`, which carries your `upgrade to nginx 1.27.1` change-cause. The
change-cause is just the `kubernetes.io/change-cause` annotation snapshotted into the revision.

## Task 2 - roll back to the previous revision

```bash
kubectl rollout undo deployment/rollme -n core
kubectl rollout status deployment/rollme -n core
```

Verify the image reverted and inspect the ReplicaSets:

```bash
kubectl get deployment rollme -n core -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl get rs -n core -l app=rollme \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,DESIRED:.spec.replicas,CURRENT:.status.replicas
```

Expected:

```
nginx:1.27.0
```

```
NAME               IMAGE          DESIRED   CURRENT
rollme-<hashA>     nginx:1.27.0   3         3
rollme-<hashB>     nginx:1.27.1   0         0
```

**Answer to the reflective question:** rolling back does not "reuse" the old revision number - it
re-applies that old ReplicaSet's pod template as a **new** revision at the top of the history
(`REVISION 3`). Revision numbers are monotonic and only ever increase; the field records the *order*
of pod-template changes, and a rollback is itself a change. The old ReplicaSet is scaled back up (it
was never deleted), which is what makes the rollback fast.

## Task 3 - a stuck rollout and safe recovery

```bash
kubectl set image deployment/rollme nginx=nginx:1.27.1-doesnotexist -n core
kubectl rollout status deployment/rollme -n core --timeout=30s || echo "rollout did not complete (expected)"
```

Inspect the stuck new pods and confirm the old ones still serve:

```bash
kubectl get pods -n core -l app=rollme
```

Expected - new pods cannot pull the image, but old `1.27.0` pods stay `Running`:

```
NAME               READY   STATUS             RESTARTS   AGE
rollme-<A>-xxxxx   1/1     Running            0          5m
rollme-<A>-yyyyy   1/1     Running            0          5m
rollme-<A>-zzzzz   1/1     Running            0          5m
rollme-<B>-wwwww   0/1     ImagePullBackOff   0          40s
```

Recover:

```bash
kubectl rollout undo deployment/rollme -n core
kubectl rollout status deployment/rollme -n core
kubectl get pods -n core -l app=rollme
```

Expected - all pods `Running` again on `nginx:1.27.0`.

**Answer to the reflective question:** a rolling update replaces pods **gradually**, and it only
deletes an old pod once a new one reports Ready. The broken image never became Ready, so the rollout
stalled with the old pods still up - zero downtime. The safety margin is set by
`spec.strategy.rollingUpdate.maxUnavailable` (default `25%`): it caps how many old pods may be taken
down before enough new ones are Ready, so a failing new revision simply blocks rather than draining the
healthy one. The old ReplicaSet is kept around (scaled to `0`) precisely so `rollout undo` can scale
it straight back up.

## Cleanup

```bash
kubectl delete -f solution/deployment.yaml --ignore-not-found --force --grace-period=0
kubectl delete ns core --ignore-not-found
```
