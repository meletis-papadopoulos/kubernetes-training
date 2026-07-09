# Exercise 7.6 - Certificate inspection (OpenSSL)

*Domain: Multi-tenancy & Security. Target: ~10 min. Do not open the solution until you have tried.*
*Authored in-house (not derived from a study guide); grounded in the official docs linked below.*

## Prerequisites

`openssl` must be available on the node (it is, on a standard sandbox):

```bash
openssl version
kubectl create namespace certs
```

## Tasks

1. Using `openssl` only, generate a self-signed certificate and its private key for the common name
   `demo.example.com`, valid for `365` days, with a Subject Alternative Name of
   `DNS:demo.example.com`. Then create a Kubernetes **TLS** Secret named `demo-tls` in the `certs`
   namespace from that certificate/key pair. Confirm the Secret's type is `kubernetes.io/tls`.

2. Without trusting what you *think* you created, read the certificate **back out of the Secret**,
   decode it, and use `openssl x509` to print (a) its Subject, (b) its Subject Alternative Names, and
   (c) its expiry date (`notAfter`). Do the Subject CN and SAN match what you set in Task 1?

3. Inspect the **live Kubernetes API server** serving certificate. Discover the API server URL from
   your kubeconfig, connect to it with `openssl s_client`, and print the certificate's Subject,
   Issuer, and validity window. Who issued the API server's certificate, and what is its `notAfter`?

## Acceptance criteria

- Secret `certs/demo-tls` exists with type `kubernetes.io/tls` and keys `tls.crt` / `tls.key`.
- The decoded certificate shows `Subject: CN=demo.example.com` and
  `X509v3 Subject Alternative Name: DNS:demo.example.com`.
- `openssl s_client` against the API server returns a certificate whose Issuer names the cluster CA
  (e.g. `kubernetes` / `kubernetes-ca`) and a readable `notAfter` date.

## Docs you may reference

- [Certificates and Certificate Signing Requests](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)
- [Manage TLS Certificates in a Cluster](https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/)
- [TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)
