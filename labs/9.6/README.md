# Lab 9.6 - Ingress Problems

## Objective
Diagnose three of the most common ingress failures: a wrong backend service name (503), a path that doesn't match the rule (404), and a TLS Secret that doesn't exist (HTTPS handshake fails). Learn to use ingress-controller logs as the primary diagnostic tool when ingress behavior doesn't match expectations.

## Prerequisites
- cluster provisioned with `provision.sh` (ingress-nginx + cert-manager)
- Namespace `training` created: `kubectl create namespace training`
- Get the node IP (ingress-nginx is a NodePort Service - 30080/HTTP, 30443/HTTPS): `NODE_IP=$(kubectl get node controlplane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'); echo "$NODE_IP"`

## Background

When an ingress isn't routing the way you expect, the diagnosis happens at three layers:

| Layer | What to check | Command |
|---|---|---|
| **K8s API** | Ingress object exists, rules look right, backend service exists | `kubectl describe ingress` |
| **Ingress controller** | Did nginx see the Ingress? Did it find the backend? Did it wire up TLS? | `kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx` |
| **HTTP layer** | What status code does the request get? `curl -v` to see headers | `curl -v http://NODE_IP:30080/...` |

The HTTP status code narrows it down fast: **503** = backend not reachable; **404** = no rule matched; **TLS handshake errors** = certificate / secret problem.

## Setup - deploy the backend app

```bash
kubectl apply -f app.yaml
kubectl rollout status deployment/webapp -n training --timeout=60s
NODE_IP=$(kubectl get node controlplane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
echo "Node IP (ingress NodePort 30080/30443): $NODE_IP"
```

Sanity check the service is reachable from inside the cluster (eliminates "is the app even up?" as a variable):

```bash
kubectl run curl-check --image=curlimages/curl:8.10.1 -n training --rm -it --restart=Never -- \
  curl -s -o /dev/null -w "%{http_code}\n" http://webapp-svc.training.svc.cluster.local
```

Expect `200`.

## Steps

### Problem 1: Wrong backend service name → 503

### 1. Apply the ingress with a typo'd backend

```bash
kubectl apply -f ingress-bad-backend.yaml
sleep 5
```

### 2. Test from outside

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://${NODE_IP}:30080/"
```

Result: `HTTP 503`.

### 3. Diagnose

The ingress object itself looks valid:

```bash
kubectl describe ingress webapp-ingress -n training
```

But the **Backend** column may show `<error: ... not found>`, or the rules section references `webapp-typo-svc:80` - a service that doesn't exist:

```bash
kubectl get svc -n training
```

No `webapp-typo-svc` in the list. The ingress controller can see the Ingress object, but when a request comes in it tries to forward to a service with no endpoints (because the service doesn't exist) and returns 503.

Confirm via the ingress-nginx logs:

```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=20 | grep -i "webapp\|503"
```

You should see lines like `service "training/webapp-typo-svc" does not exist` or 503 access-log entries.

### 4. Fix: correct the backend service name

```bash
kubectl patch ingress webapp-ingress -n training --type=json -p='[
  {"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "webapp-svc"}
]'
sleep 3
curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://${NODE_IP}:30080/"
```

Expect `HTTP 200`.

---

### Problem 2: Path mismatch → 404

### 5. Apply an ingress that only routes `/api`

```bash
kubectl apply -f ingress-path-only-api.yaml
sleep 3
```

### 6. Test the wrong path

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://${NODE_IP}:30080/"
```

Result: `HTTP 404`.

### 7. Test the path the rule names

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://${NODE_IP}:30080/api"
```

Result: `HTTP 404` - but a **different** 404 from Step 6. The webapp container is plain `nginx:1.25`, which only serves `/`; any other path returns the app's own 404. So `/api` actually reached the pod (rule matched, request was forwarded), but the app doesn't have an `/api` route. Two 404s, two different sources. Step 8 shows you how to tell them apart - that's the lesson of this problem.

### 8. Diagnose - distinguish default-backend 404 from app-side 404

Look at the ingress rules to see what paths are actually defined:

```bash
kubectl get ingress webapp-ingress -n training -o jsonpath='{range .spec.rules[*].http.paths[*]}{.path}{" → "}{.backend.service.name}{":"}{.backend.service.port.number}{"\n"}{end}'
```

Output:

```
/api → webapp-svc:80
```

Only `/api` is wired up. Now exercise both 404s and compare the `Server:` header:

```bash
echo "--- body for / (no rule matches) ---"
curl -s "http://${NODE_IP}:30080/"
echo
echo "--- body for /api (rule matches, app says 404) ---"
curl -s "http://${NODE_IP}:30080/api"
```

Both bodies are HTML pages - the distinguishing line is the footer:

```
--- body for / (no rule matches) ---
<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx</center>                 ← bare "nginx" (no version) - ingress-nginx default backend
</body>
</html>

--- body for /api (rule matches, app says 404) ---
<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx/1.25.x</center>          ← versioned - the webapp pod's own nginx 404 page
</body>
</html>
```

Same status code, two different responders - distinguished by the version string in the `<hr><center>...</center>` footer. The bare `nginx` is ingress-nginx's default backend (it scrubs the version); the versioned `nginx/1.25.x` came from the upstream pod. Modern ingress-nginx versions also strip the `Server:` response header by default, so don't rely on header inspection alone; the body is the more reliable tell. The access log confirms this from the other side: a default-backend 404 has no upstream column populated; an app-side 404 logs the upstream service it forwarded to.

```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=20 | grep -E '"GET /(api)? HTTP'
```

### 9. Fix: add a rule for `/` (or change `/api` to `/`)

```bash
kubectl patch ingress webapp-ingress -n training --type=json -p='[
  {"op": "replace", "path": "/spec/rules/0/http/paths/0/path", "value": "/"}
]'
sleep 3
curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://${NODE_IP}:30080/"
```

Expect `HTTP 200`.

---

### Problem 3: TLS Secret missing → handshake fails

### 10. Apply an ingress with TLS, but don't create the secret yet

```bash
kubectl apply -f ingress-tls-missing-secret.yaml
sleep 5
```

### 11. Test HTTPS

```bash
curl -sv -k --resolve "webapp.training.local:30443:${NODE_IP}" "https://webapp.training.local:30443/" 2>&1 | head -25
```

The TLS handshake either fails outright or completes with the **ingress-nginx fake/default certificate** (CN=Kubernetes Ingress Controller Fake Certificate). In a browser this would show a "not secure" warning.

### 12. Diagnose

Confirm the secret is missing:

```bash
kubectl get secret webapp-tls-secret -n training
```

Output: `Error from server (NotFound): secrets "webapp-tls-secret" not found`.

Check the ingress controller logs:

```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50 | grep -i "tls\|secret\|webapp"
```

Look for messages like `error obtaining X.509 certificate ... secret training/webapp-tls-secret was not found`. ingress-nginx falls back to its default cert, which is why you see the "fake certificate" name.

### 13. Fix: create the Secret via cert-manager

```bash
kubectl apply -f certificate.yaml
kubectl wait --for=condition=Ready certificate/webapp-tls -n training --timeout=60s
kubectl get secret webapp-tls-secret -n training
```

The Secret now exists. Re-test:

```bash
sleep 5
curl -sv -k --resolve "webapp.training.local:30443:${NODE_IP}" "https://webapp.training.local:30443/" 2>&1 | grep -E "subject:|issuer:|HTTP/"
```

You should now see `subject: CN=webapp.training.local` and `HTTP/1.1 200 OK` (or `HTTP/2 200`). The fake-certificate fallback is gone.

---

## Diagnostic Cheat Sheet

| HTTP status | curl flag | Meaning | First check |
|---|---|---|---|
| `503 Service Unavailable` | - | Backend has no endpoints | `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` for the backend service |
| `404 Not Found` from ingress-nginx default | response body is small "404" | No rule matched the path/host | `kubectl get ingress -o yaml` rules |
| `404 Not Found` from your app | response body is your app's 404 | Rule matched, but app doesn't have that route | App-side routing |
| TLS "fake certificate" | `curl -v` shows fake CN | Secret named in `tls:` block missing/wrong | `kubectl get secret <name>` |
| `502 Bad Gateway` | - | Backend connected but returned malformed response, or terminated mid-request | Pod logs, health check |
| `504 Gateway Timeout` | - | Backend accepted connection, didn't respond in time | Pod CPU, slow query, deadlock |

## Additional notes

- **Private cluster + private DNS**: a misnamed host in the Ingress rule paired with a missing private DNS record produces the exact same 404 as a typo - verify DNS first.

## Verification

Each `kubectl apply -f ingress-*.yaml` in this lab **replaces** the prior `webapp-ingress` definition (same name, same namespace) - fixes don't accumulate across problems. By the end, the live ingress is the one from Problem 3: host `webapp.training.local`, path `/`, TLS via the cert-manager-issued secret. So the end-state verification is host-based HTTPS:

```bash
curl -sv -k --resolve "webapp.training.local:30443:${NODE_IP}" "https://webapp.training.local:30443/" 2>&1 | grep -E "subject:|HTTP/" | head -3
# subject: CN=webapp.training.local      ← real cert, not the fake fallback
# HTTP/1.1 200 OK   (or HTTP/2 200)      ← Problem 3 fixed end-to-end
```

A plain `curl http://${NODE_IP}:30080/` at this point will return `HTTP 404` from the default backend - that's expected, the live ingress only serves `webapp.training.local`. To exercise the same host on plain HTTP, supply the Host header (and accept that ingress-nginx may issue an HTTP→HTTPS 308 redirect since TLS is configured):

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" -H "Host: webapp.training.local" "http://${NODE_IP}:30080/"
# HTTP 308 (redirect to HTTPS) - also acceptable; means routing reached the right rule
```

## Cleanup

```bash
kubectl delete certificate webapp-tls -n training --ignore-not-found
kubectl delete secret webapp-tls-secret -n training --ignore-not-found
kubectl delete ingress webapp-ingress -n training --ignore-not-found
kubectl delete service webapp-svc -n training --ignore-not-found
kubectl delete deployment webapp -n training --ignore-not-found
```

## Further reading
- [Ingress - concepts](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [ingress-nginx - debugging](https://kubernetes.github.io/ingress-nginx/troubleshooting/)
- [cert-manager - Certificate troubleshooting](https://cert-manager.io/docs/troubleshooting/)
