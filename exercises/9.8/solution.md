# Exercise 9.8 - Solutions

Reference manifests are in `solution/`. Namespace `ts98` with the `frontend` Deployment and
`frontend-svc` Service are assumed applied (see the exercise Setup).

## Task 1 - diagnose and fix the readiness probe

### Diagnose

```bash
sleep 20
kubectl get pods -n ts98 -l app=frontend
kubectl get endpoints frontend-svc -n ts98
kubectl describe pod -n ts98 -l app=frontend | grep -A 2 "Readiness probe failed" | head -3
```

Expected (values illustrative):

```
NAME                        READY   STATUS    RESTARTS   AGE
frontend-6c...-aaaaa        0/1     Running   0          25s
frontend-6c...-bbbbb        0/1     Running   0          25s

NAME           ENDPOINTS   AGE
frontend-svc   <none>      25s

Warning  Unhealthy  ...  Readiness probe failed: HTTP probe failed with statuscode: 404
```

**Root cause:** the readiness probe does `httpGet /healthz` on port 80, but the nginx image serves
`/` and returns `404` for `/healthz`. Readiness keeps failing, so the kubelet marks every Pod
NotReady and the endpoints controller keeps them **out** of `frontend-svc` - the Service has zero
endpoints. The containers are healthy and never restart (that would be a *liveness* failure); they are
simply deemed not ready for traffic.

### Fix

Point the readiness probe at a path the app actually serves. Re-apply the fixed manifest or patch:

```bash
kubectl apply -f solution/frontend-deploy.yaml
# or:
# kubectl patch deployment frontend -n ts98 --type=strategic -p '
# spec:
#   template:
#     spec:
#       containers:
#         - name: nginx
#           readinessProbe:
#             httpGet:
#               path: /
#               port: 80'
kubectl rollout status deployment/frontend -n ts98 --timeout=90s
```

### Verify

```bash
kubectl get pods -n ts98 -l app=frontend
kubectl get endpoints frontend-svc -n ts98
```

Expected: both Pods `1/1 Running`, and the Service lists 2 endpoint IPs (not `<none>`).

## Task 2 - reflective answer

A **readiness** probe answers "should this Pod receive traffic?" When it fails, the kubelet removes the
Pod from its Services' endpoints but leaves the container running - no restart. That is exactly the
observed symptom: `Running`, `RESTARTS: 0`, but `0/N Ready` and empty endpoints. A **liveness** failure
would instead kill and restart the container (climbing `RESTARTS`, eventually `CrashLoopBackOff`). The
readiness fingerprint (`Running` Pods + empty endpoints) differs from the 9.4 selector mismatch, where
the Pods are fully `Ready` but the Service's label selector never matched them - there the endpoints
are empty because no Pod was *selected*, not because the selected Pods are *not ready*. Check the
`READY` column to tell them apart: `0/N` => readiness; `1/1` but still no endpoints => selector.

## Cleanup

```bash
kubectl delete ns ts98 --ignore-not-found
```
