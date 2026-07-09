# Lab 9.1 - Pod Failures

## Objective
Learn to diagnose and fix common pod failures: CrashLoopBackOff, ImagePullBackOff, Pending, and CreateContainerConfigError. Practice using kubectl describe, logs, and events.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### Problem 1: CrashLoopBackOff

### 1. Deploy the crashing pod

```bash
kubectl apply -f pod-crashloop.yaml
```

### 2. Observe the status

```bash
sleep 30
kubectl get pod crashloop-pod -n training
```

By this point the pod will be `CrashLoopBackOff` (after cycling `Running` → `Error` → `CrashLoopBackOff`).

### 3. Diagnose

```bash
kubectl describe pod crashloop-pod -n training
```

Look at the **Events** section and **Last State** (shows exit code).

```bash
kubectl logs crashloop-pod -n training
```

Shows: `Starting...` -- the container ran but exited with code 1.

### 4. Fix: change the command to not exit with error

```bash
kubectl delete pod crashloop-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: crashloop-pod
  namespace: training
spec:
  containers:
    - name: fixed
      image: busybox:1.36
      command: ["sh", "-c", "echo 'Running OK' && sleep 3600"]
EOF
```

---

### Problem 2: ImagePullBackOff

### 5. Deploy the bad image pod

```bash
kubectl apply -f pod-imagepull.yaml
```

### 6. Observe the status

```bash
sleep 15
kubectl get pod imagepull-pod -n training
```

Status shows `ErrImagePull` or `ImagePullBackOff`.

### 7. Diagnose

```bash
kubectl describe pod imagepull-pod -n training
```

Events show: `Failed to pull image "nginx:doesnotexist": ... not found`

### 8. Fix: use a valid image tag

```bash
kubectl delete pod imagepull-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: imagepull-pod
  namespace: training
spec:
  containers:
    - name: nginx
      image: nginx:1.25
EOF
```

---

### Problem 3: Pending (insufficient resources)

### 9. Deploy the greedy pod

```bash
kubectl apply -f pod-pending.yaml
```

### 10. Observe the status

```bash
kubectl get pod pending-pod -n training
```

Status stays `Pending`.

### 11. Diagnose

```bash
kubectl describe pod pending-pod -n training
```

Events show: `FailedScheduling ... Insufficient cpu`

The pod requests 100 CPUs -- no node has that capacity.

### 12. Fix: reduce the resource request

```bash
kubectl delete pod pending-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pending-pod
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
EOF
```

---

### Problem 4: CreateContainerConfigError

### 13. Deploy the config error pod

```bash
kubectl apply -f pod-config-error.yaml
```

### 14. Observe the status

```bash
sleep 15
kubectl get pod config-error-pod -n training
```

Status shows `CreateContainerConfigError`.

### 15. Diagnose

```bash
kubectl describe pod config-error-pod -n training
```

Events show: `configmap "nonexistent-config" not found`

### 16. Fix: create the missing ConfigMap

```bash
kubectl create configmap nonexistent-config --from-literal=KEY=value -n training
```

Kubelet retries automatically (you'll see `Error: configmap "nonexistent-config" not found (x2 over 9s)` in the events) but the retry interval grows. Delete+recreate for an immediate fix:

```bash
kubectl delete pod config-error-pod -n training --force --grace-period=0
kubectl apply -f pod-config-error.yaml
```

---

### Problem 5: Init container failure (main container never starts)

When an init container fails, the main container never gets a chance to start. The pod's `STATUS` shows the init phase, not the main app - easy to misread.

### 17. Deploy the pod with a failing init container

```bash
kubectl apply -f pod-init-fail.yaml
```

### 18. Observe the status

```bash
sleep 20
kubectl get pod init-fail-pod -n training
```

Status: `Init:CrashLoopBackOff` or `Init:Error`. The `READY` column shows `0/1` and **the main `app` container has not been created at all** - `kubectl describe` will list the init container with restart counts but show the main container's state as `Waiting: PodInitializing`.

### 19. Diagnose

```bash
kubectl describe pod init-fail-pod -n training | grep -A 5 "Init Containers" | head -15
```

The init container's `Last State` shows `Terminated: Error, Exit Code: 1`.

The most important command for init failures is `kubectl logs -c <init-name>`:

```bash
kubectl logs init-fail-pod -n training -c prepare-data
```

Output:

```
Fetching config from secret store...
Config service unreachable
```

In the real world this surfaces as a missing Secret/ConfigMap, an unreachable downstream service the init container tries to bootstrap from, or a permission error on a `chown`/`chmod` script.

### 20. Fix: make the init container succeed

```bash
kubectl delete pod init-fail-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: init-fail-pod
  namespace: training
spec:
  initContainers:
    - name: prepare-data
      image: busybox:1.36
      command:
        - /bin/sh
        - -c
        - "echo 'Fetching config from secret store...'; sleep 2; echo 'Config OK'; exit 0"
  containers:
    - name: app
      image: nginx:1.25
EOF
kubectl wait --for=condition=Ready pod/init-fail-pod -n training --timeout=60s
```

Pod is now Running. The init container exited cleanly, then the main container started.

## Troubleshooting Cheat Sheet

| Status | Common Causes | Diagnostic Commands |
|--------|--------------|-------------------|
| CrashLoopBackOff | App crashes, bad command, missing deps | `kubectl describe pod` (Last State exit code), `kubectl logs` |
| ImagePullBackOff | Wrong image name/tag, registry auth | `kubectl describe pod` (events) |
| Pending | Resource constraints, no matching nodes | `kubectl describe pod` (events), `kubectl get nodes` |
| CreateContainerConfigError | Missing ConfigMap/Secret | `kubectl describe pod` (events) |
| Init:CrashLoopBackOff / Init:Error | Init container exits non-zero | `kubectl logs -c <init-name>`, `kubectl describe pod` |

## Verification

```bash
# All fixed pods should be Running
kubectl get pods -n training
```

## Cleanup

```bash
kubectl delete pod crashloop-pod imagepull-pod pending-pod config-error-pod init-fail-pod -n training --ignore-not-found --force --grace-period=0
kubectl delete configmap nonexistent-config -n training --ignore-not-found --force --grace-period=0
```

## Further reading
- [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/) - task walkthrough
- [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/) - task walkthrough
