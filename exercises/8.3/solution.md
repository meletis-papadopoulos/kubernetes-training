# Exercise 8.3 - Solutions

Reference manifest is in `solution/`. Namespace `crd-demo` is assumed to exist (see Setup). The cluster
already has cert-manager's CRDs and the `selfsigned-issuer` ClusterIssuer (installed by `provision.sh`).

## Task 1 - explore the installed CRDs

```bash
kubectl get crd | grep cert-manager
kubectl describe crd certificates.cert-manager.io | head -40
kubectl get crd certificates.cert-manager.io -o jsonpath='group={.spec.group}{"\n"}scope={.spec.scope}{"\n"}kind={.spec.names.kind}{"\n"}short={.spec.names.shortNames}{"\n"}versions={range .spec.versions[*]}{.name}{" "}{end}{"\n"}'
```

Expected (illustrative):

```
certificates.cert-manager.io
certificaterequests.cert-manager.io
clusterissuers.cert-manager.io
issuers.cert-manager.io
...
group=cert-manager.io
scope=Namespaced
kind=Certificate
short=["cert","certs"]
versions=v1
```

**Answer to the reflective question:** installing cert-manager registered a set of
**CustomResourceDefinitions** (`certificates`, `issuers`, `clusterissuers`, ...). Each CRD teaches the
API server a brand-new kind, so on this cluster `Certificate` is now a first-class, namespaced API
object with its own group (`cert-manager.io`), version (`v1`), and short names - none of which exist on
a bare cluster. CRDs are how you extend the Kubernetes API without recompiling it.

## Task 2 - drive a CRD with a custom resource

```bash
kubectl api-resources | grep cert-manager
kubectl apply -f solution/certificate.yaml
kubectl wait --for=condition=Ready certificate/demo-cert -n crd-demo --timeout=90s
kubectl get certificate demo-cert -n crd-demo
```

`solution/certificate.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: demo-cert
  namespace: crd-demo
spec:
  secretName: demo-cert-tls
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
    - demo.example.com
  duration: 2160h
  renewBefore: 360h
```

Expected - the Certificate becomes Ready:

```
NAME        READY   SECRET          AGE
demo-cert   True    demo-cert-tls   3s
```

**Answer to the reflective question:** the **cert-manager controller** watches `Certificate` objects.
When you created `demo-cert`, the controller reconciled it - generated a key, issued a self-signed
certificate via `selfsigned-issuer`, and wrote the result into a Secret. You only declared the desired
state; the operator did the work. Your kubeconfig identity created the object, but cert-manager (not
you) fulfilled it.

## Task 3 - confirm the operator produced real state

```bash
kubectl get secret demo-cert-tls -n crd-demo
kubectl get secret demo-cert-tls -n crd-demo -o jsonpath='{.type}{"\n"}'
```

Expected:

```
NAME            TYPE                DATA   AGE
demo-cert-tls   kubernetes.io/tls   3      5s
kubernetes.io/tls
```

**Answer to the reflective question:** a plain ConfigMap of the same fields would just be **inert
data** - nothing would read `dnsNames` and mint a certificate. The Certificate CRD gives the fields a
**schema** the API server validates and, crucially, a **controller** that acts on them: this is the
operator pattern - a custom kind plus a reconciler. And it keeps reconciling: cert-manager watches
`demo-cert` for its whole life and re-issues/renews the Secret before expiry (`renewBefore`), so the
object is not "done" after the first issue - it is continuously driven toward its declared state.

## Cleanup

```bash
kubectl delete certificate demo-cert -n crd-demo --ignore-not-found
kubectl delete secret demo-cert-tls -n crd-demo --ignore-not-found
kubectl delete ns crd-demo --ignore-not-found
```
