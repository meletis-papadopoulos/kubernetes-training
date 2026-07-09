# Exercise 4.5 - Solutions

Reference manifests are in `solution/`. Namespace `net45` is assumed to exist and the ingress-nginx
controller is assumed installed (NodePort `30080` for HTTP) - see the exercise Setup.

## Task 1 - two backends + Services

```bash
kubectl apply -f solution/app-a.yaml
kubectl apply -f solution/app-b.yaml
kubectl rollout status deployment/app-a -n net45 --timeout=60s
kubectl rollout status deployment/app-b -n net45 --timeout=60s
kubectl get endpointslices -n net45
```

Expected - both Services have 2 endpoint IPs each (illustrative):

```
NAME              ADDRESSTYPE   PORTS   ENDPOINTS                     AGE
app-a-svc-xxxxx   IPv4          80      10.244.1.20,10.244.2.11       15s
app-b-svc-yyyyy   IPv4          80      10.244.1.21,10.244.2.12       15s
```

## Task 2 - the Ingress

```bash
kubectl apply -f solution/ingress.yaml
kubectl describe ingress shop-ingress -n net45
```

Expected - the two path rules under host `shop.local`:

```
Rules:
  Host        Path  Backends
  ----        ----  --------
  shop.local
              /a    app-a-svc:80 (10.244.1.20:80,10.244.2.11:80)
              /b    app-b-svc:80 (10.244.1.21:80,10.244.2.12:80)
```

## Task 3 - curl both paths, gated on HTTP 200

Discover the controller's HTTP NodePort and a node IP (by label, not name):

```bash
NP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
NODE_IP=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "ingress at $NODE_IP:$NP"
```

Poll until BOTH backends return 200 (a brief `503`/`404` before the controller syncs endpoints is
normal):

```bash
for i in $(seq 1 20); do
  a=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: shop.local' http://$NODE_IP:$NP/a)
  b=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: shop.local' http://$NODE_IP:$NP/b)
  [ "$a" = "200" ] && [ "$b" = "200" ] && break
  echo "waiting for ingress backends (a=$a b=$b)..."; sleep 3
done
echo "final: a=$a b=$b"
```

Expected:

```
final: a=200 b=200
```

Now read each body:

```bash
curl -s -H 'Host: shop.local' http://$NODE_IP:$NP/a | head -4
curl -s -H 'Host: shop.local' http://$NODE_IP:$NP/b
```

Expected - `/a` is nginx, `/b` is httpd:

```
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

```
<html><body><h1>It works!</h1></body></html>
```

**Answer to the reflective question:** the API server only *stores* the Ingress object - it does
nothing to traffic. An **Ingress controller** (here ingress-nginx, running in `ingress-nginx`) watches
Ingress resources and reconfigures its own proxy (an nginx dataplane) to implement the host/path rules,
resolving each backend to the Service's endpoints. No controller running an Ingress class = an Ingress
that does nothing. The `rewrite-target: /` annotation strips the matched prefix (`/a`, `/b`) so the
backend receives `/`, which is why nginx/httpd serve their root page rather than a 404.

## Cleanup

```bash
kubectl delete ns net45 --ignore-not-found
```
