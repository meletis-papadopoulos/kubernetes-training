# Exercise 2.4 - Rollouts & Rollbacks

*Domain: Core Workloads. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace core
```

## Tasks

1. In the namespace `core`, create a Deployment named `rollme` with `3` replicas, pod label
   `app=rollme`, container `nginx` from image `nginx:1.27.0` on `containerPort: 80`. Once it is rolled
   out, perform a rolling update to `nginx:1.27.1` and attach a **recorded change-cause**
   (`kubectl annotate deployment/rollme -n core kubernetes.io/change-cause="upgrade to nginx 1.27.1"`).
   Watch the rollout to completion with `kubectl rollout status`, confirm the live image is now
   `1.27.1`, and view `kubectl rollout history`. How many revisions do you see, and which one carries
   your change-cause message?

2. Roll the Deployment **back to the previous revision** with `kubectl rollout undo` and wait for the
   rollout. Confirm the live container image is `nginx:1.27.0` again. List the ReplicaSets under
   `app=rollme` and note that the one running `1.27.0` now has `3` current replicas while the `1.27.1`
   one has `0`. Why is the number of the new "rolled-back" revision higher than the revision you rolled
   back to?

3. Set a **deliberately broken** image, `nginx:1.27.1-doesnotexist`, and observe the rollout get stuck:
   run `kubectl rollout status deployment/rollme -n core --timeout=30s` (it returns non-zero when the
   deadline passes) and inspect the new pods - they will be `ImagePullBackOff`/`ErrImagePull` while the
   old pods keep serving. Confirm your app never went down (old replicas still `Running`), then recover
   with `kubectl rollout undo`. Why did the bad rollout **not** take down the healthy `1.27.0` pods, and
   which Deployment field governs that safety?

## Acceptance criteria

- `rollme` in `core` rolls from `nginx:1.27.0` to `nginx:1.27.1`; `rollout history` shows the revision
  with `CHANGE-CAUSE` = `upgrade to nginx 1.27.1`.
- After `rollout undo`, the live image is `nginx:1.27.0` again and the `1.27.0` ReplicaSet holds all
  `3` replicas (the `1.27.1` ReplicaSet drops to `0` but is retained).
- Setting `nginx:1.27.1-doesnotexist` produces stuck `ImagePullBackOff` pods while the old pods keep
  running (no downtime); `rollout undo` restores a healthy `Running` state.

## Docs you may reference

- [Updating a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)
- [Rolling Back a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
