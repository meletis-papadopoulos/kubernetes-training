# Exercise 8.3 - CRDs

*Domain: Packaging & Extensibility. Target: ~12 min. Do not open `solution/` until you have tried.*

The cluster already has CRDs installed by **cert-manager** (via `provision.sh`), plus the
`selfsigned-issuer` ClusterIssuer. You will explore those CRDs and drive one with a custom resource -
you do **not** author a CRD here.

## Setup

```bash
kubectl create namespace crd-demo
```

## Tasks

1. List all CRDs in the cluster, then filter the cert-manager ones. Pick
   `certificates.cert-manager.io` and inspect it (`kubectl describe crd ...`, and/or
   `kubectl get crd ... -o yaml`). Identify its **group**, its **names** (kind, plural, singular,
   short names), the served **version(s)**, and its **scope** (Namespaced or Cluster). What did
   installing cert-manager add to the cluster's API surface that was not there on a bare cluster?

2. Confirm the custom kinds are now first-class API resources with `kubectl api-resources | grep
   cert-manager`. Then create a **Certificate** custom resource named `demo-cert` in `crd-demo` that
   references the pre-existing `selfsigned-issuer` ClusterIssuer, with `dnsNames: [demo.example.com]`
   and `secretName: demo-cert-tls`. Wait for the Certificate to report `Ready`. Which component noticed
   your new object and acted on it?

3. Confirm cert-manager fulfilled the request by creating the backing TLS Secret
   (`kubectl get secret demo-cert-tls -n crd-demo`, type `kubernetes.io/tls`). Reflective: this is the
   **operator pattern** - a controller watching a CRD kind and reconciling real state. What does the
   Certificate CRD + cert-manager controller give you that a plain ConfigMap of the same fields could
   not, and does anything keep reconciling the `demo-cert` object after the Secret exists?

## Acceptance criteria

- `kubectl get crd | grep cert-manager` lists several CRDs; `certificates.cert-manager.io` shows group
  `cert-manager.io`, kind `Certificate` (short names `cert`/`certs`), and scope `Namespaced`.
- `Certificate` appears in `kubectl api-resources` under group `cert-manager.io`.
- `demo-cert` in `crd-demo` reaches `Ready=True`, and Secret `demo-cert-tls` (type
  `kubernetes.io/tls`) is created by cert-manager.

## Docs you may reference

- [Custom Resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)
- [CustomResourceDefinitions](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/)
