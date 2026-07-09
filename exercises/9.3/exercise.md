# Exercise 9.3 - Fix a CreateContainerConfigError Pod

*Domain: Troubleshooting. Target: ~8 min. Do not open `solution/` until you have tried.*

This is a **fix-it** exercise: `setup.yaml` ships a broken Pod plus the ConfigMap and Secret it
consumes. Diagnose the fault from the cluster, then apply the minimal fix.

## Setup

```bash
kubectl create namespace ts93
kubectl apply -f setup.yaml
```

## Tasks

1. The Pod `api` in namespace `ts93` will not start. Wait ~15s, then check `kubectl get pod api -n
   ts93` - note it is **not** `CrashLoopBackOff` or `ImagePullBackOff`. Diagnose from the **Events**
   of `kubectl describe pod api -n ts93` and quote the exact error. The Pod reads two values: `DB_HOST`
   from ConfigMap `db-config`, and `DB_PASSWORD` from Secret `db-creds`. One of the two references
   names a key that does not exist on its object. Compare the keys the Pod requests against the keys
   the objects actually hold (`kubectl get configmap db-config -n ts93 -o yaml`,
   `kubectl get secret db-creds -n ts93 -o jsonpath='{.data}'`), find the mismatch, and fix the Pod
   so it reaches `Running`.

2. Reflective: this status is `CreateContainerConfigError`, not `CrashLoopBackOff`. At what point in
   the container lifecycle does this failure occur, and why does that mean the container never even
   starts? If the offending reference had been marked `optional: true`, what would have happened
   instead - and why is that arguably worse?

## Acceptance criteria

- `api` in `ts93` is `Running`; `kubectl logs api -n ts93` prints `DB_HOST=db.internal PW_SET=yes`.
- You identify the fault as a **wrong key name** in the Secret reference (`passwd`, real key is
  `password`), surfaced as `couldn't find key passwd in Secret ts93/db-creds`.
- You explain that config resolution happens **before** the container is created, so an unresolved
  required key blocks start entirely; and that `optional: true` would let the Pod run with the value
  silently unset - hiding the typo.

## Docs you may reference

- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
