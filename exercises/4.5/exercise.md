# Exercise 4.5 - Ingress

*Domain: Networking. Target: ~15 min. Do not open `solution/` until you have tried.*

## Setup

The cluster must already have the **ingress-nginx** controller (provisioned by `provision.sh`; it
listens on NodePort `30080` for HTTP). Check it:

```bash
kubectl get svc -n ingress-nginx
kubectl create namespace net45
```

## Tasks

1. In the namespace `net45`, create two backends, each with a ClusterIP Service: `app-a` (image
   `nginx:1.27.1`, Service `app-a-svc`) and `app-b` (image `httpd:2.4.62`, Service `app-b-svc`), both
   `2` replicas on port `80`. Confirm both Deployments are Ready and both Services have endpoints
   before you touch Ingress.

2. Create an Ingress named `shop-ingress` with `ingressClassName: nginx` and the annotation
   `nginx.ingress.kubernetes.io/rewrite-target: /`, serving host `shop.local`: path `/a` (Prefix)
   routes to `app-a-svc:80` and path `/b` (Prefix) routes to `app-b-svc:80`. Describe it and read back
   the two rules.

3. Discover the ingress controller's HTTP NodePort and a node InternalIP, then curl **both** paths with
   `Host: shop.local`, gating on an HTTP `200` from each backend before trusting the body (the pods can
   be Ready a beat before the controller has synced their endpoints). `/a` should serve the nginx page
   and `/b` should serve httpd's `It works!`. What component actually reads the Ingress object and
   makes this routing happen - the API server, or something else?

## Acceptance criteria

- `app-a` and `app-b` are both `2/2` in `net45`; both Services have endpoints.
- `shop-ingress` exists with class `nginx` and both `/a` and `/b` rules.
- Curling `http://NODE_IP:30080/a` and `.../b` with `Host: shop.local` both return HTTP `200`; `/a`
  serves the nginx welcome page and `/b` serves `It works!`.

## Docs you may reference

- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Ingress Controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
