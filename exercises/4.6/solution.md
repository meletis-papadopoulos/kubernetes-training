# Exercise 4.6 - Solutions

Reference manifests are in `solution/`. Namespace `net46` is assumed to exist; ingress-nginx (HTTPS
NodePort `30443`) and cert-manager are assumed installed - see the exercise Setup.

## Task 1 - Issuer + Certificate -> TLS Secret

```bash
kubectl apply -f solution/deployment.yaml
kubectl apply -f solution/issuer.yaml
kubectl apply -f solution/certificate.yaml
kubectl rollout status deployment/secure -n net46 --timeout=60s
```

Wait for issuance (this is the step that must not be raced):

```bash
kubectl wait --for=condition=Ready certificate/secure-cert -n net46 --timeout=90s
kubectl get certificate secure-cert -n net46
kubectl get secret secure-tls -n net46 -o jsonpath='{.type}{"\n"}'
```

Expected:

```
NAME          READY   SECRET       AGE
secure-cert   True    secure-tls   8s

kubernetes.io/tls
```

**Answer to the reflective question:** **cert-manager** created the Secret. Its controller watches
Certificate objects; seeing `secure-cert`, it used the referenced `selfsigned` Issuer to generate a key
pair and a self-signed certificate, then wrote them into a new Secret `secure-tls` of type
`kubernetes.io/tls` (keys `tls.crt` / `tls.key`). You declared *intent* (the Certificate); the operator
produced the material. Deleting the Secret would make cert-manager re-issue it.

## Task 2 - TLS Ingress

```bash
kubectl apply -f solution/ingress-tls.yaml
kubectl describe ingress secure-ingress -n net46
```

Expected - a TLS section binding the host to the Secret:

```
TLS:
  secure-tls terminates secure.local
Rules:
  Host          Path  Backends
  ----          ----  --------
  secure.local
                /     secure-svc:80 (10.244.1.30:80,10.244.2.15:80)
```

## Task 3 - HTTPS via NodePort, gated on 200

Discover the HTTPS NodePort and a node IP:

```bash
HTTPS_NP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
HTTP_NP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
NODE_IP=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "https at $NODE_IP:$HTTPS_NP"
```

Poll HTTPS until 200 (`-k` trusts the self-signed cert; `--resolve` maps the host to the node IP):

```bash
for i in $(seq 1 20); do
  code=$(curl -k -s -o /dev/null -w '%{http_code}' \
    --resolve secure.local:$HTTPS_NP:$NODE_IP https://secure.local:$HTTPS_NP/)
  [ "$code" = "200" ] && break
  echo "waiting for TLS backend (code=$code)..."; sleep 3
done
echo "https code: $code"
curl -k -s --resolve secure.local:$HTTPS_NP:$NODE_IP https://secure.local:$HTTPS_NP/ | head -4
```

Expected:

```
https code: 200
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

Confirm plain HTTP is redirected to HTTPS (`ssl-redirect`):

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  --resolve secure.local:$HTTP_NP:$NODE_IP http://secure.local:$HTTP_NP/
```

Expected:

```
308
```

Optionally inspect the served certificate (dates are illustrative):

```bash
echo | openssl s_client -connect $NODE_IP:$HTTPS_NP -servername secure.local 2>/dev/null \
  | openssl x509 -noout -subject -issuer
```

**Answer to the reflective question:** ingress-nginx terminates TLS using the `secure-tls` Secret named
in the Ingress `tls` block - the Secret that cert-manager produced in Task 1. The `-k` is needed only
because the issuer is self-signed (untrusted by the system CA bundle), not because anything is wrong;
`308` proves `ssl-redirect` bounced the HTTP request up to HTTPS.

## Cleanup

```bash
kubectl delete ns net46 --ignore-not-found
```
