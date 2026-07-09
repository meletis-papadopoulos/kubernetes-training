# Exercise 6.3 - Solutions

Reference manifests are in `solution/`. Namespace `q63` is assumed to exist
(see the exercise Setup).

## Task 1 - object-count ResourceQuota

```bash
kubectl apply -f solution/object-counts.yaml
```

`solution/object-counts.yaml`:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: object-counts
  namespace: q63
spec:
  hard:
    count/deployments.apps: "2"
    count/services: "2"
    count/configmaps: "2"
```

Render used vs hard:

```bash
kubectl describe resourcequota object-counts -n q63
```

Expected (note `configmaps` is already `1`):

```
Name:                   object-counts
Namespace:              q63
Resource                Used  Hard
--------                ----  ----
count/configmaps        1     2
count/deployments.apps  0     2
count/services          0     2
```

Create two Deployments, then a third:

```bash
kubectl create deployment web1 --image=nginx:1.27.1 -n q63
kubectl create deployment web2 --image=nginx:1.27.1 -n q63
kubectl create deployment web3 --image=nginx:1.27.1 -n q63
```

Expected - `web3` is **rejected**:

```
error: failed to create deployment: deployments.apps "web3" is forbidden: exceeded quota:
object-counts, requested: count/deployments.apps=1, used: count/deployments.apps=2,
limited: count/deployments.apps=2
```

**Answer to the reflective question:** the rejection happens on the **Deployment object itself** at
admission - not on its Pods. An object-count quota (`count/<resource>`) limits how many API objects of
a kind may exist in the namespace, regardless of whether they consume any compute. That is different
from 6.2's compute quota (`requests.cpu` etc.), which counts Pod resource demand. The distinction
matters because a compute quota would happily allow one Deployment scaled to 50 replicas, while
`count/deployments.apps` caps the number of *controllers* you can create.

## Task 2 - LimitRange min/max + defaults

```bash
kubectl apply -f solution/container-limits.yaml
```

`solution/container-limits.yaml`:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: container-limits
  namespace: q63
spec:
  limits:
  - type: Container
    min:
      cpu: 50m
      memory: 64Mi
    max:
      cpu: 500m
      memory: 512Mi
    default:
      cpu: 200m
      memory: 256Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
```

Create a Pod that declares no resources of its own:

```bash
kubectl run mutated --image=nginx:1.27.1 -n q63
```

Confirm the injected values:

```bash
kubectl get pod mutated -n q63 \
  -o jsonpath='{.spec.containers[0].resources}{"\n"}'
```

Expected:

```
{"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}
```

Now the over-max Pod:

```bash
kubectl apply -f solution/oversized-pod.yaml
```

`solution/oversized-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: oversized
  namespace: q63
spec:
  containers:
  - name: web
    image: nginx:1.27.1
    resources:
      limits:
        cpu: "2"
      requests:
        cpu: 100m
```

Expected - **rejected** by the LimitRange:

```
Error from server (Forbidden): error when creating "solution/oversized-pod.yaml": pods "oversized"
is forbidden: maximum cpu usage per Container is 500m, but limit is 2
```

**Answer to the reflective question:** a LimitRange runs at admission **before** the ResourceQuota
accounting. So when a compute quota requires every Pod to declare `limits.*` (as in 6.2), a Pod that
omits them is *not* rejected - the LimitRange first injects its `default`/`defaultRequest` values,
and the now-complete Pod satisfies the quota. In short: the LimitRange is what lets resourceless Pods
pass a quota that would otherwise forbid them, while `max`/`min` independently reject Pods whose
explicit values fall outside the allowed band.

## Cleanup

```bash
kubectl delete ns q63 --ignore-not-found
```
