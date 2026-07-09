# Exercise 6.1 - Solutions

Reference manifests are in `solution/`. These solutions assume `$WORKER` and the `sched` namespace
from the exercise Setup:

```bash
WORKER=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' \
  -o jsonpath='{.items[0].metadata.name}')
```

## Task 1 - nodeSelector

Label the node imperatively, then create the Pod from the manifest:

```bash
kubectl label node "$WORKER" disktype=ssd --overwrite
kubectl apply -f solution/ssd-pod.yaml
```

`solution/ssd-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ssd-pod
  namespace: sched
spec:
  nodeSelector:
    disktype: ssd
  containers:
  - name: web
    image: nginx:1.27.1
```

Confirm placement:

```bash
kubectl get pod ssd-pod -n sched -o wide
```

Expected (NODE column equals your `$WORKER`):

```
NAME      READY   STATUS    RESTARTS   AGE   IP            NODE     ...
ssd-pod   1/1     Running   0          8s    10.244.1.5    node01   ...
```

**Note:** `nodeSelector` is a hard filter - if no node had `disktype=ssd`, the Pod would stay
`Pending` forever.

## Task 2 - taint + toleration

Taint the worker:

```bash
kubectl taint node "$WORKER" dedicated=team-a:NoSchedule
```

Create both Pods:

```bash
kubectl apply -f solution/plain-web.yaml
kubectl apply -f solution/tolerant-web.yaml
```

`solution/tolerant-web.yaml` (the toleration is the point):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tolerant-web
  namespace: sched
spec:
  tolerations:
  - key: dedicated
    operator: Equal
    value: team-a
    effect: NoSchedule
  containers:
  - name: web
    image: nginx:1.27.1
```

Observe:

```bash
kubectl get pods -n sched -o wide
```

Expected:

```
NAME           READY   STATUS    RESTARTS   AGE   NODE     ...
plain-web      0/1     Pending   0          10s   <none>   ...
tolerant-web   1/1     Running   0          10s   node01   ...
ssd-pod        1/1     Running   0          3m    node01   ...
```

Diagnose the Pending Pod:

```bash
kubectl describe pod plain-web -n sched | grep -A3 Events
```

Expected event:

```
  Warning  FailedScheduling  ...  0/2 nodes are available: 1 node(s) had untolerated taint
  {dedicated: team-a}, 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }.
```

**Answer:** `tolerant-web` runs because its toleration matches the `dedicated=team-a:NoSchedule`
taint. `plain-web` stays `Pending`: the worker repels it (untolerated taint) and the control-plane
node also repels it (its own control-plane `NoSchedule` taint), so no node accepts it. A taint repels
Pods that lack a matching toleration; a toleration does not *attract* a Pod to a node, it only lets it
tolerate the taint.

## Task 3 - soft (preferred) node affinity

```bash
kubectl apply -f solution/prefers-ssd.yaml
```

`solution/prefers-ssd.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: prefers-ssd
  namespace: sched
spec:
  tolerations:
  - key: dedicated
    operator: Equal
    value: team-a
    effect: NoSchedule
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - key: disktype
            operator: In
            values:
            - ssd
  containers:
  - name: web
    image: nginx:1.27.1
```

Verify:

```bash
kubectl get pod prefers-ssd -n sched -o wide
```

Expected: `Running` on `$WORKER`.

**Answer to the reflective question:** yes - `prefers-ssd` would still schedule even if **no** node
had `disktype=ssd`. `preferredDuringScheduling...` is a *soft* preference: the scheduler scores nodes
with the label higher but will still place the Pod on a node that lacks it. That is the key contrast
with Task 1's `nodeSelector` (and with `requiredDuringScheduling...` affinity), which are *hard*
filters that leave the Pod `Pending` when unmet. (The toleration is still required here only because
the sole worker is tainted from Task 2.)

## Cleanup

```bash
kubectl delete ns sched --ignore-not-found
kubectl taint node "$WORKER" dedicated=team-a:NoSchedule- 2>/dev/null
kubectl label node "$WORKER" disktype- 2>/dev/null
```
