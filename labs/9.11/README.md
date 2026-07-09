# Lab 9.11 - Logs, Events & Metrics

## Objective
Learn the three tools you'll reach for constantly in the rest of this course when something looks wrong: **logs** (what did the app say - single container, multi-container, or a container that already crashed), **events** (what did Kubernetes do - scheduling, image pulls, failures), and **metrics** (how much CPU/memory is actually being used vs. requested).

## Prerequisites
- cluster provisioned with `provision.sh` (includes Metrics Server)
- Namespace `training` created: `kubectl create namespace training`
- `kubectl top nodes` should return data - confirms Metrics Server is running (Part C needs it)

## Steps

### Part A: Logs

### 1. Deploy the single-container pod

```bash
kubectl apply -f pod-single.yaml
kubectl wait --for=condition=Ready pod/log-single -n training --timeout=60s
```

### 2. View logs

```bash
kubectl logs log-single -n training
```

Nginx may not have any logs yet. Generate some traffic and check again:

```bash
kubectl exec log-single -n training -- curl -s localhost > /dev/null
kubectl logs log-single -n training
```

### 3. Common log flags: tail, since, timestamps

```bash
kubectl logs log-single -n training --tail=5
kubectl logs log-single -n training --since=5m
kubectl logs log-single -n training --timestamps
```

### 4. Follow logs in real time

```bash
timeout 10s kubectl logs log-single -n training -f || true
```

The follow stops automatically after 10 seconds (in an interactive session, press Ctrl+C instead). In another terminal you could generate traffic with the `curl` command from step 2 and watch it appear live.

### 5. Deploy the multi-container pod

```bash
kubectl apply -f pod-multi.yaml
kubectl wait --for=condition=Ready pod/log-multi -n training --timeout=60s
```

### 6. View logs without specifying a container

```bash
kubectl logs log-multi -n training
```

Modern kubectl (1.20+) does **not** fail - it prints `Defaulted container "nginx" out of: nginx, sidecar` and shows logs from the **first container defined** in the pod spec. Explicit `-c <name>` is still the right habit for multi-container pods - relying on "first container" is fragile.

### 7. View logs for a specific container

```bash
kubectl logs log-multi -n training -c nginx
kubectl logs log-multi -n training -c sidecar
```

### 8. Generate traffic and view sidecar logs

```bash
kubectl exec log-multi -n training -c nginx -- curl -s localhost > /dev/null
kubectl exec log-multi -n training -c nginx -- curl -s localhost > /dev/null
kubectl logs log-multi -n training -c sidecar --tail=5
```

The sidecar tails the nginx access log file from a shared volume - or view every container in the pod at once:

```bash
kubectl logs log-multi -n training --all-containers
```

### 9. View logs from all pods matching a label

```bash
kubectl logs -n training -l app=log-single --tail=3 --prefix
kubectl logs -n training -l 'app in (log-single,log-multi)' --tail=2 --prefix --all-containers
```

`--prefix` shows `[pod/<name>/<container>]` in front of each line so you can tell which pod emitted what.

### 10. Logs from a crashed container: `--previous`

```bash
kubectl apply -f pod-crash.yaml
kubectl wait --for=condition=Ready=false pod/log-crash -n training --timeout=30s || true
sleep 15
kubectl get pod log-crash -n training
```

The container exits every few seconds, so the pod cycles into `CrashLoopBackOff` with a restart count > 0. Plain `kubectl logs` only shows the **current** (post-restart) container instance, which may have no output yet:

```bash
kubectl logs log-crash -n training
```

`--previous` (or `-p`) shows the logs from the **last terminated instance** - essential for seeing why a container crashed before it restarted:

```bash
kubectl logs log-crash -n training --previous
```

### Part B: Events

### 11. Deploy a broken pod

```bash
kubectl apply -f pod-broken.yaml
```

The image tag doesn't exist, so this pod will never reach `Running`.

### 12. View and sort events

```bash
kubectl get events -n training
kubectl get events -n training --sort-by=.metadata.creationTimestamp
```

The most recent events appear at the bottom.

### 13. Trace the failure with `describe`

```bash
kubectl describe pod event-debug-pod -n training
```

The Events section at the bottom shows the timeline for this specific pod. You should see:
- `Scheduled` - pod assigned to a node
- `Pulling` - attempting to pull the image
- `Failed` - image pull failed (bad tag)

This is the same pattern used to trace a scheduling failure (`FailedScheduling` instead of `Pulling`/`Failed`) - `describe pod` → Events is always the first place to look.

### 14. Filter events by type and reason

```bash
kubectl get events -n training --field-selector type=Warning
kubectl get events -n training --field-selector reason=Failed
```

`kubectl get events -A --field-selector type=Warning --sort-by=.metadata.creationTimestamp` widens this to the whole cluster - the fastest way to find "what's broken right now" when you don't yet know which namespace to look in.

### Part C: Metrics

### 15. Deploy the monitored application

```bash
kubectl apply -f deployment.yaml
```

### 16. Check node and pod resource usage

```bash
kubectl top nodes
kubectl top pods -n training
```

Wait a minute if pod metrics aren't available yet - Metrics Server needs time to collect data. `kubectl top nodes` shows CPU/memory usage and percentage of allocatable resources per node.

### 17. Sort and drill into per-container usage

```bash
kubectl top pods -n training --sort-by=cpu
kubectl top pods -n training --sort-by=memory
kubectl top pods -n training --containers
```

### 18. Compare actual usage against requests and limits

```bash
# Actual usage
kubectl top pods -n training

# Requested / limited resources
kubectl get pods -n training -o custom-columns=NAME:.metadata.name,CPU_REQ:.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory,CPU_LIM:.spec.containers[0].resources.limits.cpu,MEM_LIM:.spec.containers[0].resources.limits.memory
```

If actual usage is far below **requests**, the workload is over-provisioned. If it approaches **limits**, expect CPU throttling or an OOMKill.

## Quick Reference

| Command | Purpose |
|---------|---------|
| `kubectl logs <pod> -c <container>` | Logs from one container in a multi-container pod |
| `kubectl logs <pod> --previous` | Logs from the last terminated (crashed) instance |
| `kubectl logs -l app=foo --prefix` | Logs from every pod matching a label |
| `kubectl get events --sort-by=.metadata.creationTimestamp` | Events oldest-to-newest |
| `kubectl describe pod <pod>` | Events section for one specific object |
| `kubectl get events --field-selector type=Warning` | Only the events worth worrying about |
| `kubectl top nodes` / `kubectl top pods` | Actual CPU/memory usage right now |

| Common Warning reason | Meaning |
|---|---|
| `FailedScheduling` | No suitable node found |
| `Failed` (pull) | Image pull failed - check name/tag/registry access |
| `BackOff` | Container keeps crashing - check `describe pod` Last State and `logs --previous` |
| `Unhealthy` | Probe failed |
| `FailedMount` | Volume mount failed - check PV/PVC/StorageClass |

## Verification

```bash
# Logs: current and previous instance both reachable
kubectl logs log-single -n training --tail=1
kubectl logs log-multi -n training -c sidecar --tail=1
kubectl logs log-crash -n training --previous | grep -q "crash attempt" && echo "previous logs OK"

# Events: the broken pod produced a Warning event
kubectl get events -n training --field-selector involvedObject.name=event-debug-pod,type=Warning --no-headers | wc -l
# Should be > 0

# Metrics: Metrics Server is working
kubectl top nodes
kubectl top pods -n training
```

## Cleanup

```bash
kubectl delete -f pod-single.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pod-multi.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pod-crash.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pod-broken.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f deployment.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Logging Architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/) - concept reference
- [`kubectl logs`](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#logs) - command reference
- [Application Introspection and Debugging](https://kubernetes.io/docs/tasks/debug/debug-application/) - task walkthrough
- [`kubectl events`](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#events) - command reference
- [Resource Metrics Pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/) - concept + task
- [metrics-server](https://github.com/kubernetes-sigs/metrics-server) - project repo
