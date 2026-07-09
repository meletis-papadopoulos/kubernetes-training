# Lab 9.9 - Resource & HPA Problems

## Objective
Diagnose and fix pod failures caused by resource requests/limits, then diagnose HorizontalPodAutoscaler (HPA) failures that build on the very same concepts. Covers four resource-level failure modes - `OOMKilled` (memory over limit), CPU throttling (limit reached without a crash), and two flavors of scheduling `Pending` (untolerated taint, nodeSelector mismatch) - plus two HPA failure modes: `scaleTargetRef` pointing at the wrong deployment, and `<unknown>` HPA targets caused by missing CPU requests. Each surfaces differently, but the underlying fixes all trace back to `requests`, `limits`, and a working metrics pipeline.

## Prerequisites
- Cluster provisioned with `provision.sh` (metrics-server is installed)
- Namespace `training` created: `kubectl create namespace training`
- Verify metrics-server works: `kubectl top nodes` should return data, not "Metrics API not available"
- Detect the worker node name (used in Problem 3): `WORKER=$(kubectl get node -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')`

## Background

A pod (or a controller built on top of pods, like the HPA) can fail for several fundamentally different reasons:

| Class | When it happens | Where to look |
|---|---|---|
| **Runtime (OOMKilled)** | Container started fine, then exceeded its memory `limit` | `kubectl describe pod` → **Last State** → `Reason: OOMKilled`, `Exit Code: 137` |
| **Runtime (CPU throttled)** | Container's CPU demand exceeds its `limit` | No restart, no event - `kubectl top pod` usage pinned at the limit; cgroup `cpu.stat` shows `nr_throttled > 0` |
| **Scheduling (Pending)** | Pod was accepted by the API but the scheduler can't place it | `kubectl describe pod` → **Events** → `FailedScheduling` |
| **HPA (`<unknown>` targets)** | HPA controller can't compute `current/target` utilization | `kubectl describe hpa` → **Conditions** → `FailedGetScale` / `FailedGetResourceMetric` |

Lab 9.1 already covered the simplest scheduling failure (a resource request larger than any node has free). This lab covers two more nuanced scheduling failures - **taint mismatch** and **nodeSelector mismatch** - the two ways a container can misbehave under its own resource limits (**OOMKilled** and **CPU throttling**), and two HPA failures that are really the same underlying problem wearing a different symptom: **the HPA depends on the exact same `requests` values and the same `metrics-server` pipeline that `kubectl top` uses - it's just a different controller consuming them.**

## Steps

### Problem 1: OOMKilled - container exceeds memory limit

### 1. Deploy the memory-hungry pod

```bash
kubectl apply -f pod-oomkilled.yaml
```

The pod has `limits.memory: 64Mi` but tries to allocate 150M with `stress`.

### 2. Wait for the OOMKill cycle

```bash
sleep 30
kubectl get pod oom-pod -n training
```

Status will eventually be `CrashLoopBackOff` (the OOMKill triggers a restart, which OOMKills again).

### 3. Diagnose

```bash
kubectl describe pod oom-pod -n training | grep -A 5 "Last State"
```

Output:

```
Last State:    Terminated
  Reason:      OOMKilled
  Exit Code:   137
```

**Exit code 137** = process killed by SIGKILL = kernel OOM killer. Combined with `Reason: OOMKilled`, this is unambiguous: the container's working set exceeded its `limits.memory`.

The container logs are usually unhelpful here - the kernel SIGKILLs the process before it can log anything. Rely on `Last State` from `kubectl describe pod` instead.

### 4. Fix: raise the memory limit (or fix the leak)

In a real app you'd either fix the memory leak or right-size the limit. Here we'll right-size:

```bash
kubectl delete pod oom-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: oom-pod
  namespace: training
spec:
  containers:
    - name: memory-hog
      image: polinux/stress
      resources:
        requests:
          memory: 32Mi
          cpu: 50m
        limits:
          memory: 256Mi
          cpu: 100m
      command: ["stress"]
      args: ["--vm", "1", "--vm-bytes", "150M", "--vm-hang", "1"]
  restartPolicy: Always
EOF
kubectl wait --for=condition=Ready pod/oom-pod -n training --timeout=60s
```

---

### Problem 2: CPU throttling - limit reached without a crash

Memory is an *incompressible* resource - exceed the limit and the kernel has no choice but to kill the container. CPU is *compressible* - exceed `limits.cpu` and the kernel's CFS quota just throttles the process instead. There's no `OOMKilled`, no restart, no `Warning` event - the only signature is CPU usage pinned at the limit while the app quietly gets slower.

### 5. Deploy a CPU-bound pod with a tight limit

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cpu-throttle-pod
  namespace: training
spec:
  containers:
    - name: cpu-hog
      image: polinux/stress
      resources:
        requests:
          cpu: 50m
          memory: 32Mi
        limits:
          cpu: 100m
          memory: 64Mi
      command: ["stress"]
      args: ["--cpu", "1"]
  restartPolicy: Always
EOF
kubectl wait --for=condition=Ready pod/cpu-throttle-pod -n training --timeout=60s
```

### 6. Observe: usage pinned at the limit, not the demand

```bash
sleep 30
kubectl top pod cpu-throttle-pod -n training
```

`stress --cpu 1` tries to peg an entire core, but `kubectl top` reports usage capped at roughly `100m` - the container's `limits.cpu` - no matter how long you let it run. Compare that against `kubectl get pod cpu-throttle-pod -n training`: `Running`, zero restarts, no events. A flat CPU line sitting exactly at the limit, with an app that "feels" slow, is the signature of throttling - there's no error to grep for.

### 7. Confirm with the cgroup throttle counter (optional, the definitive signal)

```bash
kubectl exec cpu-throttle-pod -n training -- sh -c "cat /sys/fs/cgroup/cpu.stat 2>/dev/null || cat /sys/fs/cgroup/cpu/cpu.stat"
```

`nr_throttled` (a count > 0) and a climbing `throttled_usec` / `throttled_time` prove the container has actually been paused by the CFS quota - `kubectl top` alone can't tell you whether a pod is "genuinely busy at the limit" from "being throttled at the limit"; the cgroup counter can.

### 8. Fix: raise the CPU limit (or reduce the work)

```bash
kubectl delete pod cpu-throttle-pod -n training --force --grace-period=0
```

In production you'd raise `limits.cpu`, add more replicas (an HPA can do this automatically - see Problem 5+ below), or optimize the code path burning the cycles.

---

### Problem 3: FailedScheduling - taint without toleration

### 9. Apply the taint to every node (so the pod has nowhere to land)

```bash
WORKER=$(kubectl get node -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
echo "Worker node: $WORKER"
kubectl taint nodes "$WORKER" workload=gpu:NoSchedule
kubectl taint nodes controlplane workload=gpu:NoSchedule
```

Tainting nodes to reserve them for a specific kind of workload (GPU, memory-heavy, or other specialized hardware) is a common pattern - pods that don't carry a matching toleration simply won't be scheduled there. This lab's cluster only has one worker, and `provision.sh` already removed the default control-plane taint, so we taint both nodes here to make sure the untolerated pod truly has nowhere to go and the diagnostic actually fires.

### 10. Deploy a pod without the matching toleration

```bash
kubectl apply -f pod-taint-pending.yaml
```

### 11. Observe and diagnose

```bash
sleep 10
kubectl get pod taint-pending-pod -n training
```

Status: `Pending`.

```bash
kubectl describe pod taint-pending-pod -n training | grep -A 5 "Events:"
```

Events show:

```
Warning  FailedScheduling  ...  0/2 nodes are available:
  2 node(s) had untolerated taint(s).
  preemption: 0/2 nodes are available: 2 Preemption is not helpful for scheduling.
```

The phrase **"untolerated taint(s)"** is the signature of this failure. To see *which* taint, run `kubectl describe node <node-name>` and look at the `Taints:` line. The fix is either:

- **Add a toleration** to the pod (correct fix - the pod knows it should run on the reserved node)
- **Remove the taint** (wrong fix in production - defeats the purpose of reserving the node)

### 12. Fix: add the matching toleration

```bash
kubectl delete pod taint-pending-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: taint-pending-pod
  namespace: training
spec:
  tolerations:
    - key: workload
      operator: Equal
      value: gpu
      effect: NoSchedule
  containers:
    - name: app
      image: nginx:1.25
      resources:
        requests:
          memory: 32Mi
          cpu: 50m
EOF
kubectl wait --for=condition=Ready pod/taint-pending-pod -n training --timeout=60s
```

Pod is now Running on the tainted node.

### 13. Remove the taints (cleanup before next problem)

```bash
kubectl taint nodes "$WORKER" workload=gpu:NoSchedule-
kubectl taint nodes controlplane workload=gpu:NoSchedule-
```

The trailing `-` removes the taint.

---

### Problem 4: FailedScheduling - nodeSelector matches no nodes

### 14. Deploy a pod that requires a non-existent label

```bash
kubectl apply -f pod-nodeselector-pending.yaml
```

The pod requires `disktype: nvme-fast` - no node has this label.

### 15. Observe and diagnose

```bash
sleep 10
kubectl get pod nodeselector-pending-pod -n training
kubectl describe pod nodeselector-pending-pod -n training | grep -A 5 "Events:"
```

Events show:

```
Warning  FailedScheduling  ...  0/2 nodes are available:
  2 node(s) didn't match Pod's node affinity/selector.
```

The phrase **"didn't match Pod's node affinity/selector"** points at the label selector, not a taint.

```bash
kubectl get nodes --show-labels
```

Confirms no node has `disktype=nvme-fast`.

### 16. Fix - two valid options

**Option A - relax the selector** (use an existing label):

```bash
kubectl delete pod nodeselector-pending-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nodeselector-pending-pod
  namespace: training
spec:
  nodeSelector:
    kubernetes.io/os: linux
  containers:
    - name: app
      image: nginx:1.25
      resources:
        requests:
          memory: 32Mi
          cpu: 50m
EOF
kubectl wait --for=condition=Ready pod/nodeselector-pending-pod -n training --timeout=60s
```

**Option B - label a node to match** (correct fix in production when you do want to dedicate a node):

```bash
# (Demonstration only - don't run if you already used Option A)
# WORKER=$(kubectl get node -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
# kubectl label node "$WORKER" disktype=nvme-fast
```

---

Everything so far has been about a **single pod's** resources. The HPA is a controller that reads the exact same signals - `requests.cpu` and live usage from `metrics-server` - to decide how many pods to run. Get either of those wrong and the HPA fails in ways that look completely different from a `Pending` pod, but trace back to the same root causes.

### Problem 5: HPA shows `<unknown>` - wrong scaleTargetRef

### 17. Deploy the target app (intentionally without resource requests)

```bash
kubectl apply -f deployment-no-requests.yaml
kubectl rollout status deployment/php-apache -n training --timeout=60s
```

### 18. Create an HPA pointing at a nonexistent deployment name

```bash
kubectl apply -f hpa-wrong-target.yaml
```

Note: `scaleTargetRef.name` is `php-apache-typo`, but the deployment is `php-apache`.

### 19. Observe - symptom #1: target not found

```bash
sleep 15
kubectl get hpa -n training
```

Output:

```
NAME             REFERENCE                       TARGETS              MINPODS   MAXPODS   REPLICAS
php-apache-hpa   Deployment/php-apache-typo      <unknown>/50%        1         5         0
```

`REPLICAS: 0` and `TARGETS: <unknown>` - the HPA isn't scaling anything because it can't find the deployment.

### 20. Diagnose

```bash
kubectl describe hpa php-apache-hpa -n training | grep -A 5 "Conditions"
```

Look for:

```
Conditions:
  Type           Status  Reason                Message
  ----           ------  ------                -------
  AbleToScale    False   FailedGetScale        the HPA controller was unable to get the target's current scale: deployments.apps "php-apache-typo" not found
  ScalingActive  False   FailedGetScale        ...
```

The phrase **`deployments.apps "..." not found`** confirms the `scaleTargetRef.name` does not match an existing deployment in the same namespace.

### 21. Fix #1: correct the scaleTargetRef

```bash
kubectl apply -f hpa-correct.yaml
sleep 15
kubectl get hpa -n training
```

Output now:

```
NAME             REFERENCE                  TARGETS              MINPODS   MAXPODS   REPLICAS
php-apache-hpa   Deployment/php-apache      <unknown>/50%        1         5         1
```

`REPLICAS: 1` (HPA found the deployment) but `TARGETS` still shows `<unknown>`. We've fixed problem #1 and uncovered problem #2.

---

### Problem 6: HPA shows `<unknown>` - missing CPU requests

For a CPU-utilization HPA to compute `current / target`, it needs a baseline to compute utilization *against* - that baseline is `resources.requests.cpu` on the container. With no request, "50% of nothing" is undefined.

### 22. Diagnose - symptom #2: HPA cannot compute utilization

```bash
kubectl describe hpa php-apache-hpa -n training | grep -A 8 "Conditions"
```

The signature you're looking for is the **combination** `ScalingActive: False` + `Reason: FailedGetResourceMetric` - the HPA controller could not obtain or could not use a metric value. The exact `Message:` text varies with timing; either of these phrasings is the same underlying problem:

```
ScalingActive  False   FailedGetResourceMetric   failed to get cpu utilization: missing request for cpu in container php-apache of Pod ...
```

```
ScalingActive  False   FailedGetResourceMetric   failed to get cpu utilization: did not receive metrics for targeted pods (pods might be unready)
```

- `missing request for cpu in container <name>` - metrics-server returned a value but the container has no `requests.cpu` for the controller to compute "% of request" against.
- `did not receive metrics for targeted pods (pods might be unready)` - metrics-server has no data for this pod yet; without a CPU request set, the kubelet never reports usable metrics for it.

**Don't anchor on the exact string** - anchor on the condition name and reason, then read whatever message is present. Both messages here point at the same fix: add `resources.requests.cpu` to the deployment. Confirm what's currently set:

```bash
kubectl get deployment php-apache -n training -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

Returns `{}` - confirms no requests/limits set.

### 23. Fix #2: add CPU resource requests to the deployment

```bash
kubectl patch deployment php-apache -n training --type=strategic -p '
spec:
  template:
    spec:
      containers:
        - name: php-apache
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
'
kubectl rollout status deployment/php-apache -n training --timeout=60s
```

### 24. Verify HPA is now active - and diagnose if it isn't

```bash
sleep 60
kubectl get hpa -n training
kubectl describe hpa php-apache-hpa -n training | grep -A 5 "Conditions"
```

`TARGETS` should now show a real percentage:

```
NAME             REFERENCE                  TARGETS         MINPODS   MAXPODS   REPLICAS
php-apache-hpa   Deployment/php-apache      cpu: 1%/50%     1         5         1
```

`<unknown>` is **not** a wait state - it's a signal that the HPA controller could not obtain a metric value. The reason is always in the `ScalingActive` condition's `Message:`:

| Message snippet | What it means | What to do |
|---|---|---|
| `missing request for cpu` | The deployment patch didn't take, or container name mismatch | Re-check the deployment has `resources.requests.cpu` set on the right container |
| `no metrics returned`, `unable to get metrics for resource cpu` | metrics-server has no fresh data for the post-rollout pods (transient, 1-2 of its 15s poll cycles) | Verify `kubectl top pods -n training` returns data; if yes, retry in ~30s; if no, troubleshoot metrics-server itself |
| Anything else | Read the message - it names the failure | Address what the message says |

HPA is healthy once `TARGETS` shows a real percentage and `ScalingActive: True`.

### 25. Drive load and observe HPA scale up

Run the load generator as a background pod (no interactive terminal needed - we delete it explicitly later):

```bash
kubectl run load-gen --image=busybox:1.36 --restart=Never -n training -- \
  /bin/sh -c "while true; do wget -q -O- http://php-apache.training.svc.cluster.local; done"
```

Wait ~90s for metrics to flow and HPA to react, then check:

```bash
sleep 90
kubectl get hpa -n training
kubectl get pods -n training -l app=php-apache
```

`REPLICAS` should climb to ≥ 2, often hitting `MAXPODS=5` if the load is sustained. The `TARGETS` column should be at or near `cpu: 50%/50%` (the HPA target). Multiple `php-apache` pods confirm scale-up.

Stop the load generator:

```bash
kubectl delete pod load-gen -n training --force --grace-period=0
```

Within ~5 minutes (the default downscale stabilization window), `REPLICAS` would return to 1. We won't wait for downscale in this walkthrough - proceed straight to cleanup.

## Troubleshooting Cheat Sheet

| Symptom | Event / state / condition snippet | Root cause | Fix |
|---|---|---|---|
| `CrashLoopBackOff` + `Exit Code: 137` | `Reason: OOMKilled` | Memory limit too low (or app leak) | Raise `limits.memory` or fix the leak |
| `Running`, usage pinned at the limit, no restarts | `kubectl top` flat at `limits.cpu`; cgroup `nr_throttled > 0` | CPU limit too low for the workload | Raise `limits.cpu`, add replicas, or optimize |
| `Pending` | `untolerated taint {key=...}` | Pod missing a toleration | Add the matching toleration (or remove the taint if it shouldn't exist) |
| `Pending` | `didn't match Pod's node affinity/selector` | `nodeSelector` / `nodeAffinity` mismatch | Relax the selector or label the target node |
| `Pending` | `Insufficient cpu` / `Insufficient memory` | Request larger than any node has free (covered in 9.1) | Lower the request or add capacity |
| `Pending` | `node(s) had volume node affinity conflict` | PV bound to a different node (covered in 9.7) | See Lab 9.7 |
| HPA `<unknown>/X%`, `REPLICAS=0` | `AbleToScale: False`, `deployments.apps "..." not found` | `scaleTargetRef.name` typo / wrong namespace | Fix the target ref |
| HPA `<unknown>/X%`, `REPLICAS=N` | `ScalingActive: False`, `missing request for cpu` | Container has no `resources.requests.cpu` | Add requests to the deployment |
| HPA `<unknown>/X%` | `Metrics API not available` | metrics-server not running / not ready | `kubectl get pods -n kube-system -l k8s-app=metrics-server` |
| HPA `cpu: 0%/X%` (always 0) | `ScalingActive: True` | Workload is genuinely idle | Drive load to verify; check `kubectl top pods` |
| HPA stuck at `MINPODS` during heavy load | `ScalingLimited: True` | `behavior.scaleUp` is throttling replica growth | Tune `scaleUp` policies or raise `maxReplicas` |

## Additional notes

- **Memory units**: `64Mi` (mebibytes, 1024-based) ≠ `64M` (megabytes, 1000-based). Mix-ups cause limits that are subtly tighter than expected.
- **CPU units**: `100m` = 100 millicores = 0.1 of a CPU core. `1` and `1000m` are the same thing.
- **The through-line**: every failure in this lab except the two taint/nodeSelector scheduling cases traces back to the same two ingredients - a correctly-set `requests`/`limits` block, and a working `metrics-server`. If `kubectl top nodes`/`kubectl top pods` isn't returning data, both the CPU-throttling diagnostics and every HPA symptom in Problems 5-6 become unreliable - fix metrics-server first.

## Verification

```bash
kubectl get pods -n training
# oom-pod, taint-pending-pod, nodeselector-pending-pod should all be Running

kubectl get hpa -n training
# REFERENCE = Deployment/php-apache, TARGETS shows a real value (cpu: N%/50%), no <unknown>
```

## Cleanup

```bash
WORKER=$(kubectl get node -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
kubectl taint nodes "$WORKER" workload=gpu:NoSchedule- 2>/dev/null || true
kubectl taint nodes controlplane workload=gpu:NoSchedule- 2>/dev/null || true
kubectl delete pod oom-pod cpu-throttle-pod taint-pending-pod nodeselector-pending-pod load-gen -n training --ignore-not-found --force --grace-period=0
kubectl delete hpa php-apache-hpa -n training --ignore-not-found
kubectl delete deployment php-apache -n training --ignore-not-found
kubectl delete service php-apache -n training --ignore-not-found
```

## Further reading
- [Assign Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Pod Lifecycle - Container states](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-states)
- [Managing Resources for Containers (requests, limits, CPU throttling)](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Horizontal Pod Autoscaler Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
- [HPA - Algorithm Details](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#algorithm-details)
