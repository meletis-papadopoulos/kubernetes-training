# Lab 6.2 - Requests & Limits

## Objective
Learn how to set resource requests and limits on Pod containers, understand the difference between what the scheduler reserves and the hard ceiling enforced at runtime, and observe the two failure modes of exceeding a limit: `OOMKilled` (memory) and CPU throttling.

## Prerequisites
- cluster provisioned with `provision.sh` (Metrics Server installed)
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Create a pod with explicit resource requests and limits

```bash
kubectl apply -f pod-resources.yaml
```

### 2. Inspect the applied requests and limits

```bash
kubectl get pod resource-pod -n training -o jsonpath='{.spec.containers[0].resources}' | python -m json.tool 2>/dev/null || kubectl get pod resource-pod -n training -o jsonpath='{.spec.containers[0].resources}'
```

### 3. Requests vs limits - what each one actually does

- **`requests`**: what the scheduler reserves. The scheduler only places a pod on a node that has this much *unallocated* CPU/memory. It is a soft floor, not enforced once the pod is running.
- **`limits`**: the hard ceiling enforced by the kubelet/container runtime via cgroups. A container can burst above its CPU request but never above its CPU limit, and it is never allowed to hold more memory than its memory limit.

### 4. See the request reservation on the node

```bash
kubectl describe nodes | grep -A 5 "Allocated resources"
```

The "Requests" column reflects `resource-pod`'s `requests.cpu`/`requests.memory` - this is what the scheduler counted against the node's capacity, not the (higher) limits.

### 5. Deploy a pod that exceeds its memory limit

```bash
kubectl apply -f pod-mem-limit.yaml
```

The container has `limits.memory: 64Mi` but tries to allocate 150M with `stress`.

### 6. Wait for the OOMKill cycle

```bash
sleep 30
kubectl get pod mem-limit-demo -n training
```

Status will eventually be `CrashLoopBackOff` (the OOMKill triggers a restart, which OOMKills again).

### 7. Diagnose the OOMKill

```bash
kubectl describe pod mem-limit-demo -n training | grep -A 5 "Last State"
```

Output:

```
Last State:    Terminated
  Reason:      OOMKilled
  Exit Code:   137
```

**Exit code 137** = process killed by SIGKILL = kernel OOM killer. Memory has no "burst then throttle" option - going over `limits.memory` gets the container killed outright.

### 8. Deploy a pod that exceeds its CPU limit

```bash
kubectl apply -f pod-cpu-limit.yaml
```

The container has `limits.cpu: 200m` but `stress --cpu 2` tries to spin two CPU-bound workers, each demanding a full core.

### 9. Observe CPU throttling with `kubectl top`

Metrics Server's scrape interval is 60s by default:

```bash
sleep 60
kubectl top pod cpu-limit-demo -n training
kubectl get pod cpu-limit-demo -n training
```

CPU usage will read at (or just under) `200m` - the cgroup CFS quota caps it there - while the pod stays `Running`. Unlike memory, exceeding a CPU limit does not kill the container: the kernel just slices the CPU time it is given thinner and thinner (throttling), so the process runs slower rather than getting terminated.

### 10. Compare the two failure modes

| Resource | Exceed the limit | Container survives? |
|---|---|---|
| Memory | `OOMKilled`, Exit Code 137 | No - killed and restarted |
| CPU | Throttled (CFS quota) | Yes - just runs slower |

## Verification

```bash
# Requests/limits applied to resource-pod
kubectl get pod resource-pod -n training -o custom-columns=NAME:.metadata.name,CPU_REQ:.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory,CPU_LIM:.spec.containers[0].resources.limits.cpu,MEM_LIM:.spec.containers[0].resources.limits.memory

# mem-limit-demo shows OOMKilled in its last state
kubectl describe pod mem-limit-demo -n training | grep -A 5 "Last State"

# cpu-limit-demo is still Running, capped near its CPU limit
kubectl top pod cpu-limit-demo -n training
```

## Cleanup

```bash
kubectl delete pod resource-pod mem-limit-demo cpu-limit-demo -n training --ignore-not-found --force --grace-period=0
```

## Further reading
- [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) - concept reference
- [Assign Memory Resources to Containers and Pods](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/) - task walkthrough
- [Assign CPU Resources to Containers and Pods](https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-resource/) - task walkthrough
- [Resource Metrics Pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/) - `kubectl top` / Metrics Server
- Lab 6.3 - ResourceQuota & LimitRange: namespace-wide caps and defaults built on top of these per-container requests/limits
