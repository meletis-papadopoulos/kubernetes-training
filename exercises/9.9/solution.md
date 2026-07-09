# Exercise 9.9 - Solutions

Reference manifests are in `solution/`. Namespace `ts99` with the `web` Deployment, `web` Service, and
the `web-hpa` HorizontalPodAutoscaler are assumed applied (see the exercise Setup).

## Task 1 - diagnose and fix the `<unknown>` HPA

### Diagnose

```bash
sleep 30
kubectl get hpa -n ts99
kubectl describe hpa web-hpa -n ts99 | grep -A 6 "Conditions"
kubectl get deployment web -n ts99 -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
kubectl top pods -n ts99
```

Expected (values illustrative):

```
NAME      REFERENCE          TARGETS         MINPODS   MAXPODS   REPLICAS
web-hpa   Deployment/web     <unknown>/50%   1         5         1
```

```
Conditions:
  Type            Status  Reason                   Message
  ----            ------  ------                   -------
  AbleToScale     True    SucceededGetScale        ...
  ScalingActive   False   FailedGetResourceMetric  failed to get cpu utilization: missing request
                                                    for cpu in container nginx of Pod web-...
```

```
{}
```

`kubectl top pods -n ts99` **does** return usage for the `web` Pod - so metrics-server is healthy.

**Root cause:** the Deployment's container declares **no `resources.requests.cpu`** (the resources
block is `{}`). A CPU-utilization HPA computes `currentUsage / requests.cpu` - with no request there
is no denominator, so the controller cannot compute utilization and reports `<unknown>`
(`FailedGetResourceMetric` / `missing request for cpu`). The metrics pipeline is fine; the workload
spec is incomplete.

### Fix

Add CPU (and memory) requests to the Deployment. Re-apply the fixed manifest or patch:

```bash
kubectl apply -f solution/web-deploy.yaml
# or:
# kubectl patch deployment web -n ts99 --type=strategic -p '
# spec:
#   template:
#     spec:
#       containers:
#         - name: nginx
#           resources:
#             requests: {cpu: 100m, memory: 64Mi}
#             limits: {cpu: 200m, memory: 128Mi}'
kubectl rollout status deployment/web -n ts99 --timeout=90s
```

### Verify

```bash
sleep 60
kubectl get hpa -n ts99
kubectl describe hpa web-hpa -n ts99 | grep -A 4 "Conditions"
```

Expected (values illustrative):

```
NAME      REFERENCE          TARGETS       MINPODS   MAXPODS   REPLICAS
web-hpa   Deployment/web     cpu: 0%/50%   1         5         1
```

```
  ScalingActive   True    ValidMetricFound   the HPA was able to successfully calculate ...
```

`<unknown>` is gone; the HPA now reads a real percentage against the `100m` request.

## Task 2 - reflective answer

The HPA target `50%` means "50% of each Pod's `requests.cpu`". Utilization is defined **relative to
the request**, so `requests.cpu` is the mandatory baseline - without it, "50% of nothing" is undefined
and the controller returns `<unknown>` rather than guessing. Because `kubectl top pods -n ts99`
returned data the whole time, the metrics pipeline (kubelet -> metrics-server -> metrics API) was
never the problem; the fault was purely the missing request on the Pod spec. `<unknown>` is a signal,
not a wait state - always read the `ScalingActive` condition's message to see which of the two
(missing request vs. absent metrics) applies.

## Cleanup

```bash
kubectl delete ns ts99 --ignore-not-found
```
