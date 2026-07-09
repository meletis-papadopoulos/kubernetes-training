# Exercise 9.6 - Fix an Ingress Returning 503

*Domain: Troubleshooting. Target: ~10 min. Do not open `solution/` until you have tried.*

This is a **fix-it** exercise: `setup.yaml` ships a healthy app + Service plus a broken Ingress.
Diagnose from the cluster, then apply the minimal fix. Assumes `provision.sh` (ingress-nginx as a
NodePort Service on 30080/HTTP).

## Setup

```bash
kubectl create namespace ts96
kubectl apply -f setup.yaml
kubectl rollout status deployment/shop -n ts96 --timeout=60s
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "Node IP: $NODE_IP"
```

## Tasks

1. First prove the app itself is healthy inside the cluster (eliminate "is the backend even up?"):
   ```bash
   kubectl run curl-check --image=curlimages/curl:8.10.1 -n ts96 -i --rm --restart=Never -- \
     curl -s -o /dev/null -w "%{http_code}\n" http://shop-svc.ts96.svc.cluster.local
   ```
   Expect `200`. Now request it through the Ingress and observe the failure:
   ```bash
   curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://${NODE_IP}:30080/"
   ```
   You get `HTTP 503`. Diagnose why using `kubectl describe ingress shop-ingress -n ts96` and
   `kubectl get svc -n ts96`, and confirm from the ingress-controller logs
   (`kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=20`). Fix the
   Ingress so `curl http://${NODE_IP}:30080/` returns HTTP `200`.

2. Reflective: the app returned `200` internally but the Ingress returned `503`. What does a `503`
   from ingress-nginx specifically mean about the backend it tried to reach, and how does that differ
   from a `404` (which you would get from a path/host that matches no rule)?

## Acceptance criteria

- `curl -s -o /dev/null -w "%{http_code}" http://${NODE_IP}:30080/` returns `200`.
- You identify the fault as an Ingress backend pointing at a **non-existent Service**
  (`shop-svc-typo`; the real Service is `shop-svc`).
- You explain that `503` = the matched backend has no reachable/existing endpoints, whereas `404` =
  no rule matched the request at all.

## Docs you may reference

- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
