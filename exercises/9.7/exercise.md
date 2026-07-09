# Exercise 9.7 - Fix a Pod Pending on an Unbound PVC

*Domain: Troubleshooting. Target: ~9 min. Do not open `solution/` until you have tried.*

This is a **fix-it** exercise: `setup.yaml` ships a PVC and a Pod that consumes it. Diagnose from the
cluster, then apply the minimal fix. Assumes `provision.sh` (default StorageClass `local-path`).

## Setup

```bash
kubectl create namespace ts97
kubectl apply -f setup.yaml
```

## Tasks

1. The Pod `writer` in namespace `ts97` is stuck `Pending`, and the PVC `data` it mounts never binds.
   Wait ~10s, then diagnose from the **storage layer down**, not the Pod: `kubectl get pvc data -n
   ts97` shows `Pending` with no `VOLUME`; `kubectl describe pvc data -n ts97` shows the reason in its
   Events; `kubectl get storageclass` shows what the cluster actually offers. Quote the PVC event.
   Then fix it so the PVC binds and `writer` reaches `Running`, using the cluster's real default
   StorageClass. (`storageClassName` is immutable on an existing PVC.)

2. Reflective: after your fix, the PVC may briefly report `Pending` with a `WaitForFirstConsumer`
   event before it binds. Why is that `Pending` **not** a bug - and how does its event differ from the
   `Pending` you started with? Which layer of the PVC binding flow was actually broken here (PVC ->
   StorageClass, PVC <-> PV, or Pod -> PVC)?

## Acceptance criteria

- PVC `data` in `ts97` is `Bound` and Pod `writer` is `Running`.
- You identify the fault as a **non-existent StorageClass** (`fast-ssd`), surfaced as
  `storageclass.storage.k8s.io "fast-ssd" not found`.
- You explain that `WaitForFirstConsumer` `Pending` is expected (binding deferred until a consumer is
  scheduled), distinct from the original `ProvisioningFailed`, and that the broken layer was
  PVC -> StorageClass.

## Docs you may reference

- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
