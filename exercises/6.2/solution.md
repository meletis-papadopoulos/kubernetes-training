# Exercise 6.2 - Solutions

Reference manifests are in `solution/`. Namespaces `rq-demo` and `d92` are assumed to exist
(see the exercise Setup).

## Task 1 - Pod with requests and limits

You cannot set resource requests/limits with a pure `kubectl run` flag combination cleanly, so
generate a skeleton and edit, or apply the manifest directly:

```bash
kubectl apply -f solution/resourced-pod.yaml
```

`solution/resourced-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: resourced
  namespace: rq-demo
spec:
  containers:
  - name: web
    image: nginx:1.23.4
    resources:
      requests:
        cpu: 250m
        memory: 64Mi
      limits:
        cpu: 500m
        memory: 128Mi
```

Verify the applied block:

```bash
kubectl get pod resourced -n rq-demo \
  -o custom-columns=NAME:.metadata.name,\
CPU_REQ:.spec.containers[0].resources.requests.cpu,\
MEM_REQ:.spec.containers[0].resources.requests.memory,\
CPU_LIM:.spec.containers[0].resources.limits.cpu,\
MEM_LIM:.spec.containers[0].resources.limits.memory
```

Expected:

```
NAME        CPU_REQ   MEM_REQ   CPU_LIM   MEM_LIM
resourced   250m      64Mi      500m      128Mi
```

**Answer to the reflective question:** the scheduler placed the Pod based on the **requests**
(`250m` / `64Mi`) - that is what it counts against a node's schedulable capacity. The limits are the
runtime ceiling enforced by the kubelet via cgroups; they play no part in scheduling.

## Task 2 - ResourceQuota and a rejected Pod

```bash
kubectl apply -f solution/team-quota.yaml
```

`solution/team-quota.yaml`:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: rq-demo
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 1Gi
    limits.cpu: "2"
    limits.memory: 2Gi
    pods: "3"
```

Render used vs hard:

```bash
kubectl describe resourcequota team-quota -n rq-demo
```

Expected (values reflect `resourced` from Task 1 already counted):

```
Name:            team-quota
Namespace:       rq-demo
Resource         Used   Hard
--------         ----   ----
limits.cpu       500m   2
limits.memory    128Mi  2Gi
pods             1      3
requests.cpu     250m   1
requests.memory  64Mi   1Gi
```

Now try the pod with no resources:

```bash
kubectl run no-limits --image=nginx:1.23.4 -n rq-demo
```

Expected - it is **rejected at admission**:

```
Error from server (Forbidden): pods "no-limits" is forbidden: failed quota: team-quota:
must specify limits.cpu for: no-limits; limits.memory for: no-limits;
requests.cpu for: no-limits; requests.memory for: no-limits
```

**Why:** once a ResourceQuota constrains `requests.*` / `limits.*` in a namespace, every new Pod
**must** declare those values so the quota can account for them. A Pod that omits them cannot be
measured against the quota, so the quota admission controller forbids it. (A LimitRange with defaults
- Task 3 - is the standard way to let such Pods through: it injects values *before* the quota check.)

## Task 3 - LimitRange defaults

```bash
kubectl apply -f solution/default-limits.yaml
```

`solution/default-limits.yaml`:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: d92
spec:
  limits:
  - type: Container
    default:
      cpu: 500m
      memory: 256Mi
    defaultRequest:
      cpu: 200m
      memory: 128Mi
```

Create a Pod that sets no resources of its own:

```bash
kubectl run inherits --image=busybox:1.36 -n d92 --command -- sleep 3600
```

Verify the injected values:

```bash
kubectl get pod inherits -n d92 \
  -o jsonpath='{.spec.containers[0].resources}{"\n"}'
```

Expected:

```
{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"200m","memory":"128Mi"}}
```

**Answer to the reflective question:** the Pod declared no resources, so the LimitRange admission
controller in `d92` injected the `default` values as its limits and the `defaultRequest` values as
its requests. This is why `inherits` (in `d92`) is admitted while `no-limits` (in `rq-demo`, which has
a quota but no LimitRange) was rejected.

**LimitRange vs ResourceQuota - the one-line distinction:**
- **LimitRange** answers *"what may a single container/Pod ask for in this namespace?"* - per-object
  `min`/`max` bounds and `default`/`defaultRequest` values, applied to **each** container at admission.
- **ResourceQuota** answers *"what is the total CPU/memory all Pods together may request/consume in this
  namespace?"* - one **namespace-wide** ceiling on the sum of every Pod's `requests.*`/`limits.*` (plus
  object counts).

## Cleanup

```bash
kubectl delete ns rq-demo d92 --ignore-not-found
```
