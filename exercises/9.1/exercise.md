# Exercise 9.1 - Fix a CrashLoopBackOff Pod

*Domain: Troubleshooting. Target: ~8 min. Do not open `solution/` until you have tried.*

This is a **fix-it** exercise: `setup.yaml` ships a broken Pod. Diagnose the fault from the
cluster, then apply the minimal fix.

## Setup

```bash
kubectl create namespace ts91
kubectl apply -f setup.yaml
```

## Tasks

1. The Pod `checkout` in namespace `ts91` will not stay up. Wait ~30s, then confirm its state with
   `kubectl get pod checkout -n ts91`. Diagnose **why** it is failing: use `kubectl describe pod` to
   read the container's **Last State** (exit code) and `kubectl logs checkout -n ts91 --previous` to
   read what the container printed on its **last terminated** instance. Quote the exit code and the
   fatal log line. Then fix the Pod so it reaches `Running` and stays there (`RESTARTS` stops
   climbing). The container should still run `busybox:1.36`.

2. Reflective: `kubectl logs checkout -n ts91` (without `--previous`) often shows nothing on a
   crash-looping Pod, while `--previous` shows the error. Explain why - and state which **class** of
   failure this is (an application-level crash exiting non-zero, versus a Kubernetes scheduling or
   config error). Which of `describe`, `logs`, or `logs --previous` was the load-bearing command?

## Acceptance criteria

- `checkout` in `ts91` is `Running` with a stable, non-climbing `RESTARTS` count.
- You can name the exit code (`1`) and the fatal message the crashed container logged.
- You correctly classify this as an application exit-non-zero crash (not an image, scheduling, or
  config-object fault) and identify `logs --previous` as the command that revealed the cause.

## Docs you may reference

- [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
