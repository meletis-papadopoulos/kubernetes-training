# Exercise 9.3 - Solutions

Reference manifests are in `solution/`. Namespace `ts93`, the ConfigMap `db-config`, the Secret
`db-creds`, and the broken Pod are assumed applied (see the exercise Setup).

## Task 1 - diagnose and fix the config reference

### Diagnose

```bash
sleep 15
kubectl get pod api -n ts93
kubectl describe pod api -n ts93 | tail -8
```

Expected (values illustrative):

```
NAME   READY   STATUS                       RESTARTS   AGE
api    0/1     CreateContainerConfigError   0          20s
```

```
Warning  Failed   ...  Error: couldn't find key passwd in Secret ts93/db-creds
```

Now compare requested keys against real keys:

```bash
kubectl get configmap db-config -n ts93 -o jsonpath='{.data}{"\n"}'
kubectl get secret db-creds -n ts93 -o jsonpath='{.data}{"\n"}'
```

Expected:

```
{"DB_HOST":"db.internal"}
{"password":"..."}
```

**Root cause:** the Pod's `secretKeyRef` asks for key `passwd`, but the Secret's only key is
`password`. The reference is required (no `optional: true`), so the kubelet cannot assemble the
container's environment and fails **before** creating the container - hence
`CreateContainerConfigError`, not a crash or a pull error. (The `DB_HOST` ConfigMap reference is fine.)

### Fix

Correct the key name and re-apply (delete first - `env` is immutable on a running Pod):

```bash
kubectl delete pod api -n ts93 --force --grace-period=0
kubectl apply -f solution/api-pod.yaml
```

`solution/api-pod.yaml` changes only the Secret key from `passwd` to `password`.

### Verify

```bash
kubectl wait --for=condition=Ready pod/api -n ts93 --timeout=60s
kubectl logs api -n ts93
```

Expected:

```
DB_HOST=db.internal PW_SET=yes
```

## Task 2 - reflective answer

Environment values from `configMapKeyRef` / `secretKeyRef` are resolved by the kubelet **at container
creation time**, before the container process is ever started. A required key that does not resolve
aborts creation, so the container never runs - that is why the status is `CreateContainerConfigError`
and why `kubectl logs` has nothing to show. Had the reference set `optional: true`, the Pod would have
started **Running** with `DB_PASSWORD` simply unset - the app might then fail deep in its own logic
(or connect with no password) far from the real cause. `optional: true` is right for genuinely
optional config, but it converts a loud admission-time failure into a silent runtime one.

## Cleanup

```bash
kubectl delete ns ts93 --ignore-not-found
```
