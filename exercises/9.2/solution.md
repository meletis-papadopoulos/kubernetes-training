# Exercise 9.2 - Solutions

Reference manifests are in `solution/`. Namespace `ts92` and the broken Pod are assumed applied
(see the exercise Setup).

## Task 1 - diagnose and fix the pull failure

### Diagnose

```bash
sleep 15
kubectl get pod catalog -n ts92
kubectl describe pod catalog -n ts92 | tail -12
```

Expected (values illustrative):

```
NAME      READY   STATUS             RESTARTS   AGE
catalog   0/1     ImagePullBackOff   0          20s
```

```
Warning  Failed   ...  Failed to pull image "nginx:1.99-doesnotexist":
   ... manifest for docker.io/library/nginx:1.99-doesnotexist not found: manifest unknown
Warning  Failed   ...  Error: ErrImagePull
Normal   BackOff  ...  Back-off pulling image "nginx:1.99-doesnotexist"
```

**Root cause:** the registry (`docker.io`) resolved and answered, but the **tag** `1.99-doesnotexist`
does not exist - `manifest unknown` / `not found`. This is a bad-tag failure, not a DNS/registry
failure (which would say `no such host`) and not an auth/pull-secret failure (which would say
`unauthorized` or `FailedToRetrieveImagePullSecret`).

### Fix

`image:` is immutable on a running Pod - delete and re-create with a real tag:

```bash
kubectl delete pod catalog -n ts92 --force --grace-period=0
kubectl apply -f solution/catalog-pod.yaml
```

### Verify

```bash
kubectl wait --for=condition=Ready pod/catalog -n ts92 --timeout=90s
kubectl get pod catalog -n ts92
```

Expected:

```
NAME      READY   STATUS    RESTARTS   AGE
catalog   1/1     Running   0          10s
```

## Task 2 - reflective answer

`ErrImagePull` is the **first** failed pull attempt; after repeated failures the kubelet applies an
exponential back-off and the status becomes `ImagePullBackOff` (it is waiting before trying again -
not a new error, just rate-limiting the retries). `kubectl logs` is empty because **no container was
ever created** - the failure happens before the container runtime can start anything, so there are no
application logs to read. Unlike the 9.1 crash loop (where the container ran and `logs --previous`
held the answer), image problems live entirely in `kubectl describe pod` -> **Events**.

## Cleanup

```bash
kubectl delete ns ts92 --ignore-not-found
```
