# Exercise 7.6 - Solutions

This exercise is entirely imperative (openssl + kubectl) - there are no manifests. Namespace `certs`
is assumed to exist.

## Task 1 - generate a cert and store it as a TLS Secret

```bash
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout tls.key -out tls.crt \
  -days 365 \
  -subj "/CN=demo.example.com" \
  -addext "subjectAltName=DNS:demo.example.com"

kubectl create secret tls demo-tls -n certs --cert=tls.crt --key=tls.key
```

Confirm the type:

```bash
kubectl get secret demo-tls -n certs -o jsonpath='{.type}{"\n"}'
```

Expected:

```
kubernetes.io/tls
```

(`kubectl create secret tls` validates that the cert and key match and stores them base64-encoded
under the fixed keys `tls.crt` and `tls.key`.)

## Task 2 - read it back out and inspect

```bash
kubectl get secret demo-tls -n certs -o jsonpath='{.data.tls\.crt}' \
  | base64 -d \
  | openssl x509 -noout -subject -ext subjectAltName -enddate
```

Expected (dates will differ - the SAN/CN must match):

```
subject=CN = demo.example.com
X509v3 Subject Alternative Name:
    DNS:demo.example.com
notAfter=Jul  8 12:00:00 2027 GMT
```

**Answer:** the Subject CN and SAN match what was set in Task 1. Reading the cert *from the Secret*
(rather than the local `tls.crt`) proves the object actually stored what you intended - the usual
real-world check when a TLS Ingress or webhook rejects a certificate.

## Task 3 - inspect the live API server certificate

Discover the API server URL, strip the scheme, and connect:

```bash
APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
HOSTPORT=${APISERVER#https://}
echo "API server: $HOSTPORT"

echo | openssl s_client -connect "$HOSTPORT" -showcerts 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

Expected (values are environment-specific; shape shown):

```
subject=CN = kube-apiserver
issuer=CN = kubernetes
notBefore=...
notAfter=...
```

**Answer:** the API server's serving certificate is issued by the **cluster CA** (Issuer `CN =
kubernetes`, the self-signed root minted at cluster init). Its `notAfter` is typically one year from
the cluster's creation/last cert rotation - which is why kubeadm clusters need `kubeadm certs renew`
before that date. `openssl s_client` is the go-to when a client reports a TLS handshake/expiry error
and you need to see the certificate the server is actually presenting.

## Cleanup

```bash
rm -f tls.crt tls.key
kubectl delete ns certs --ignore-not-found
```
