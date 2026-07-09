# Exercise 4.6 - TLS Ingress (cert-manager)

*Domain: Networking. Target: ~15 min. Do not open `solution/` until you have tried.*
*Uses cert-manager (a third-party operator, docs at cert-manager.io - **not** kubernetes.io).*

## Setup

The cluster must have **ingress-nginx** (HTTPS NodePort `30443`) and **cert-manager** installed
(both provisioned by `provision.sh`). Check them:

```bash
kubectl get pods -n cert-manager
kubectl get svc -n ingress-nginx
kubectl create namespace net46
```

## Tasks

1. In the namespace `net46`, create a Deployment `secure` (`2` replicas, `nginx:1.27.1`, port `80`) and
   a ClusterIP Service `secure-svc`. Create a namespaced **self-signed Issuer** named `selfsigned`
   (`spec.selfSigned: {}`), then a **Certificate** named `secure-cert` with `secretName: secure-tls`,
   `dnsNames: [secure.local]`, issued by `selfsigned` (`kind: Issuer`). Wait for the Certificate to go
   `Ready=True` and confirm the Secret `secure-tls` now exists with type `kubernetes.io/tls`. You never
   ran `openssl` or `kubectl create secret` - so what object created that Secret?

2. Create an Ingress named `secure-ingress` (`ingressClassName: nginx`, annotation
   `nginx.ingress.kubernetes.io/ssl-redirect: "true"`) with a `tls` block referencing host
   `secure.local` and `secretName: secure-tls`, routing `/` to `secure-svc:80`.

3. Discover the ingress controller's HTTPS NodePort and a node InternalIP, then curl
   `https://secure.local` over that NodePort with `-k` (self-signed) and `--resolve`, gating on an
   HTTP `200`. Also confirm plain HTTP is redirected. Because self-signed issuance takes a moment,
   make sure you waited on the Certificate before curling.

## Acceptance criteria

- `secure-cert` reaches `Ready=True`; Secret `secure-tls` exists with type `kubernetes.io/tls` and keys
  `tls.crt` / `tls.key`.
- `secure-ingress` has a `tls` entry for `secure.local` -> `secure-tls`.
- `curl -k https://secure.local:<httpsNodePort>` (via `--resolve` to the node IP) returns HTTP `200`
  and the nginx page; plain HTTP returns a `308` redirect.

## Docs you may reference

- [TLS in Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls)
- [cert-manager documentation](https://cert-manager.io/docs/)
