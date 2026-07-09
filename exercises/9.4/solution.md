# Exercise 9.4 - Solutions

Reference manifests are in `solution/`. Namespace `ts94` with the `payments` Deployment (3 Pods) and
the broken Service are assumed applied (see the exercise Setup).

## Task 1 - diagnose and fix the empty Service

### Diagnose

```bash
kubectl get endpointslices -n ts94 -l kubernetes.io/service-name=payments
kubectl get svc payments -n ts94 -o jsonpath='selector={.spec.selector}{"\n"}'
kubectl get pods -n ts94 -l app=payments --show-labels
```

Expected (values illustrative):

```
NAME             ADDRESSTYPE   PORTS   ENDPOINTS
payments-xxxxx   IPv4          <unset> <unset>
```

```
selector={"app":"payment"}
NAME                        READY   STATUS    ...   LABELS
payments-6c...-abcde        1/1     Running   ...   app=payments,pod-template-hash=...
```

**Root cause:** the Service selects `app=payment` but every Pod is labelled `app=payments` (note the
missing `s`). No Pod matches the selector, so the EndpointSlice controller populates **zero**
endpoints - kube-proxy/Cilium has nowhere to forward traffic and the connection times out. The Pods
themselves are perfectly healthy; only the Service is wrong.

### Fix

Correct the selector. Either re-apply the fixed manifest or patch it:

```bash
kubectl apply -f solution/payments-svc.yaml
# or:
# kubectl patch svc payments -n ts94 --type=merge -p '{"spec":{"selector":{"app":"payments"}}}'
sleep 5
```

### Verify

```bash
kubectl get endpointslices -n ts94 -l kubernetes.io/service-name=payments
SVC_IP=$(kubectl get svc payments -n ts94 -o jsonpath='{.spec.clusterIP}')
kubectl run curl-check --image=curlimages/curl:8.10.1 -n ts94 -i --rm --restart=Never -- \
  curl -s -o /dev/null -w "code=%{http_code}\n" "http://$SVC_IP"
```

Expected: 3 endpoint IPs in the `ENDPOINTS` column, and:

```
code=200
```

## Task 2 - reflective answer

Only the **Service** was misconfigured. The fastest signal for a selector mismatch is
`kubectl get endpointslices -l kubernetes.io/service-name=<svc>` showing an **empty** `ENDPOINTS`
column - no Pod matched, so no addresses were published. This is distinct from a **targetPort**
mismatch, where the selector *does* match and endpoints *are* listed, but the published port does not
match the Pod's listening port, so traffic still fails. Empty endpoints => selector/label problem;
populated endpoints + failing traffic => port (or Pod-readiness) problem.

## Cleanup

```bash
kubectl delete ns ts94 --ignore-not-found
```
