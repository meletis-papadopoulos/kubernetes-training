# Exercise 9.2 - Fix an ImagePullBackOff Pod

*Domain: Troubleshooting. Target: ~7 min. Do not open `solution/` until you have tried.*

This is a **fix-it** exercise: `setup.yaml` ships a broken Pod. Diagnose the fault from the
cluster, then apply the minimal fix.

## Setup

```bash
kubectl create namespace ts92
kubectl apply -f setup.yaml
```

## Tasks

1. The Pod `catalog` in namespace `ts92` never reaches `Running`. Wait ~15s, then confirm its state
   with `kubectl get pod catalog -n ts92`. Diagnose the cause by reading the **Events** section of
   `kubectl describe pod catalog -n ts92` - do **not** guess. Quote the exact event line the kubelet
   recorded and identify which of the three classic pull failures it is: unresolvable registry
   (`no such host`), non-existent tag (`manifest unknown` / `not found`), or missing/invalid
   `imagePullSecret` (`unauthorized` / `FailedToRetrieveImagePullSecret`). Then fix the Pod so it
   pulls and reaches `Running`, using the valid image `nginx:1.27.1`.

2. Reflective: the `STATUS` column cycles `ErrImagePull` -> `ImagePullBackOff`. What is the
   difference between those two, and why does `kubectl logs catalog -n ts92` give you nothing useful
   here (compare against how you diagnosed the CrashLoopBackOff in 9.1)?

## Acceptance criteria

- `catalog` in `ts92` is `Running` and `1/1` Ready on image `nginx:1.27.1`.
- You quote the `describe` Events line and correctly classify it as a **non-existent tag**
  (`manifest ... not found` / `manifest unknown`), not a registry-DNS or pull-secret failure.
- You explain that `logs` is useless pre-pull (no container ever started) and that `describe` Events
  is the diagnostic surface for image problems.

## Docs you may reference

- [Images](https://kubernetes.io/docs/concepts/containers/images/)
- [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
