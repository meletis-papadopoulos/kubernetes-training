# Exercise 9.1 - Solutions

Reference manifests are in `solution/`. Namespace `ts91` and the broken Pod are assumed applied
(see the exercise Setup).

## Task 1 - diagnose and fix the crash loop

### Diagnose

```bash
sleep 30
kubectl get pod checkout -n ts91
kubectl describe pod checkout -n ts91 | grep -A 6 "Last State"
kubectl logs checkout -n ts91 --previous
```

Expected (values illustrative):

```
NAME       READY   STATUS             RESTARTS      AGE
checkout   0/1     CrashLoopBackOff   3 (20s ago)   90s
```

```
Last State:     Terminated
  Reason:       Error
  Exit Code:    1
  ...
Warning  BackOff  ...  Back-off restarting failed container app in pod checkout_ts91
```

```
checkout starting
FATAL: could not open /config/settings.conf
```

**Root cause:** the container's own process exits non-zero (`Exit Code: 1`) immediately after start;
the kubelet restarts it, it exits again, and the Pod settles into `CrashLoopBackOff`. This is an
**application-level crash**, not an image pull, scheduling, or missing-config-object fault - the image
pulled and the container ran; it just chose to `exit 1`.

### Fix

The command is the fault. Re-apply the corrected manifest (a bare Pod's `command` cannot be edited in
place - delete and re-create):

```bash
kubectl delete pod checkout -n ts91 --force --grace-period=0
kubectl apply -f solution/checkout-pod.yaml
```

`solution/checkout-pod.yaml` runs the same image but a command that stays up:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: checkout
  namespace: ts91
  labels:
    app: checkout
spec:
  containers:
    - name: app
      image: busybox:1.36
      command:
        - sh
        - -c
        - "echo 'checkout starting'; echo 'settings loaded'; sleep 3600"
  restartPolicy: Always
```

### Verify

```bash
kubectl wait --for=condition=Ready pod/checkout -n ts91 --timeout=60s
kubectl get pod checkout -n ts91
```

Expected:

```
NAME       READY   STATUS    RESTARTS   AGE
checkout   1/1     Running   0          15s
```

## Task 2 - reflective answer

Plain `kubectl logs` streams the **current** container instance. On a crash loop, that instance is
either brand-new (nothing logged yet) or already gone - so the output is usually empty. `--previous`
reads the **last terminated** instance's logs, which is where the `FATAL ...` line and the reason for
the `exit 1` live. The diagnostic path was: `describe` established it was an application crash
(`Reason: Error`, `Exit Code: 1`, not `OOMKilled` / not `ImagePullBackOff` / not `FailedScheduling`),
and `logs --previous` was the load-bearing command that produced the actual error message.

## Cleanup

```bash
kubectl delete ns ts91 --ignore-not-found
```
