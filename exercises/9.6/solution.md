# Exercise 9.6 - Solutions

Reference manifests are in `solution/`. Namespace `ts96` with the `shop` Deployment, `shop-svc`
Service, and the broken `shop-ingress` Ingress are assumed applied (see the exercise Setup).

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
```

## Task 1 - diagnose and fix the 503

### Diagnose

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://${NODE_IP}:30080/"
kubectl describe ingress shop-ingress -n ts96
kubectl get svc -n ts96
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=20 | grep -i "shop\|503"
```

Expected (values illustrative):

```
HTTP 503
```

`describe ingress` shows the rule forwarding to `shop-svc-typo:80`, and `get svc` lists only
`shop-svc` (no `shop-svc-typo`). The controller logs show:

```
service "ts96/shop-svc-typo" does not exist
```

**Root cause:** the Ingress rule's backend names Service `shop-svc-typo`, which does not exist. The
controller has a valid Ingress object but no backend to route to, so it answers `503 Service
Unavailable`. The real Service (`shop-svc`) is healthy - proven by the internal `200`.

### Fix

Point the backend at the correct Service - re-apply the fixed manifest or patch it:

```bash
kubectl apply -f solution/shop-ingress.yaml
# or:
# kubectl patch ingress shop-ingress -n ts96 --type=json \
#   -p='[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/name","value":"shop-svc"}]'
sleep 5
```

### Verify

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://${NODE_IP}:30080/"
```

Expected:

```
HTTP 200
```

## Task 2 - reflective answer

A `503` from ingress-nginx means the request **matched a rule**, but the backend that rule points at
has no reachable endpoints - here because the Service named in the rule does not exist at all (a
missing/mis-selected Service, or a Service with zero ready endpoints, produces the same code). A `404`
is the opposite failure: the request reached the controller but **no rule matched** the path/host, so
it fell through to the default backend. `503` => "I know where to send this but there's nothing there";
`404` => "I don't have a rule for this request".

## Cleanup

```bash
kubectl delete ns ts96 --ignore-not-found
```
