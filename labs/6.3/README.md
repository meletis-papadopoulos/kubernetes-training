# Lab 6.3 - ResourceQuota & LimitRange

## Objective
Learn how to cap total resource consumption in a namespace with a ResourceQuota, and enforce per-container defaults/minimums/maximums with a LimitRange. This builds on the per-container `requests`/`limits` from Lab 6.2 by adding namespace-wide guardrails on top of them.

## Prerequisites
- cluster provisioned with `provision.sh`

## Steps

### 1. Create the namespace

```bash
kubectl apply -f namespace.yaml
```

### 2. Apply the ResourceQuota

```bash
kubectl apply -f resourcequota.yaml
```

### 3. Inspect the quota

```bash
kubectl describe resourcequota namespace-quota -n quota-lab
```

Note the "Used" vs "Hard" columns -- all zeros initially.

### 4. Apply the LimitRange

```bash
kubectl apply -f limitrange.yaml
```

### 5. Inspect the LimitRange

```bash
kubectl describe limitrange default-limits -n quota-lab
```

This sets default requests/limits for containers that don't specify them.

### 6. Create a pod with explicit resource requests and limits

```bash
kubectl apply -f pod-resources.yaml
```

### 7. Check the quota usage

```bash
kubectl describe resourcequota namespace-quota -n quota-lab
```

The "Used" column should now show the resources consumed by the pod.

### 8. Create a pod WITHOUT specifying resources

```bash
kubectl run no-resources -n quota-lab --image=busybox:1.36 --command -- sleep 3600
```

Note the `-n quota-lab` must come **before** `--`. Anything after `--` with `--command` becomes the container command, so if `-n quota-lab` lands there it gets passed as an argument to `sleep` (and the pod ends up in the `default` namespace).

### 9. Inspect the auto-applied defaults

```bash
kubectl get pod no-resources -n quota-lab -o jsonpath='{.spec.containers[0].resources}' | python -m json.tool 2>/dev/null || kubectl get pod no-resources -n quota-lab -o jsonpath='{.spec.containers[0].resources}'
```

The pod was created with no `resources` block at all, yet it now has requests and limits - the LimitRange's `defaultRequest`/`default` filled them in at admission time. Without the LimitRange, a resourceless pod would count as `0` against the ResourceQuota's `requests.cpu`/`requests.memory`, which would defeat the point of the quota.

### 10. Try to exceed the quota

Try creating many pods to exceed the 10-pod limit:

```bash
for i in $(seq 1 12); do
  kubectl run quota-test-$i -n quota-lab --image=busybox:1.36 --command -- sleep 3600 2>&1
done
```

After 10 pods (including the 2 already running), new pods will be rejected with a "forbidden: exceeded quota" error. Note: ResourceQuota's internal count is eventually consistent, so you may see a momentary race where a pod beyond your "expected" cap succeeds while another gets rejected - the final count still lands at exactly 10.

### 11. Try to exceed resource constraints (quota and LimitRange together)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cpu-hog
  namespace: quota-lab
spec:
  containers:
    - name: hog
      image: busybox:1.36
      command: ["sleep", "3600"]
      resources:
        requests:
          cpu: "3"
          memory: 128Mi
        limits:
          cpu: "5"
          memory: 256Mi
EOF
```

This pod violates **two** constraints simultaneously:
- Its `limits.cpu: 5` exceeds the **LimitRange** per-container max of `500m`
- Its `requests.cpu: 3` exceeds the **ResourceQuota** total of `2` CPU

Admission checks fire in order - **LimitRange wins**, so the error you'll see is `maximum cpu usage per Container is 500m, but limit is 5`, not the quota violation. The quota check never runs because the pod was already rejected by an earlier admission plugin. Same pedagogical outcome (pod is rejected), but worth knowing which layer caught it - and that this ordering means a ResourceQuota alone gives no guarantee about per-container sizing without a LimitRange in front of it.

### 12. Try to violate the LimitRange minimum

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: limit-violator
  namespace: quota-lab
spec:
  containers:
    - name: violator
      image: busybox:1.36
      command: ["sleep", "3600"]
      resources:
        requests:
          cpu: 10m
          memory: 32Mi
        limits:
          cpu: 100m
          memory: 64Mi
EOF
```

This should fail because `cpu: 10m` is below the LimitRange minimum of `50m`.

## Verification

```bash
# Check quota status
kubectl describe resourcequota namespace-quota -n quota-lab

# Check LimitRange
kubectl describe limitrange default-limits -n quota-lab

# Verify pod resources
kubectl get pods -n quota-lab -o custom-columns=NAME:.metadata.name,CPU_REQ:.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory
```

## Cleanup

```bash
kubectl delete namespace quota-lab --ignore-not-found --force --grace-period=0
```

## Further reading
- [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/) - concept reference
- [Limit Ranges](https://kubernetes.io/docs/concepts/policy/limit-range/) - concept reference
- Lab 6.2 - Requests & Limits: per-container `requests`/`limits`, `OOMKilled` vs CPU throttling, and `kubectl top` - the building blocks this lab caps at the namespace level
