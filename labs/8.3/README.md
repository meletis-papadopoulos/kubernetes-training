# Lab 8.3 - CRDs

## Objective
Understand Custom Resource Definitions (CRDs) and the operator pattern. Explore the CRDs installed by cert-manager as a real-world example.

## Prerequisites
- cluster provisioned with `provision.sh` (cert-manager installed)

## Steps

### 1. List all CRDs in the cluster

```bash
kubectl get crd
```

You should see CRDs from cert-manager (certificates, issuers, etc.).

### 2. Filter cert-manager CRDs

```bash
kubectl get crd | grep cert-manager
```

Expected CRDs:
- `certificates.cert-manager.io`
- `certificaterequests.cert-manager.io`
- `clusterissuers.cert-manager.io`
- `issuers.cert-manager.io`
- `orders.acme.cert-manager.io`
- `challenges.acme.cert-manager.io`

### 3. Describe a CRD

```bash
kubectl describe crd certificates.cert-manager.io | head -60
```

Note:
- **Group**: `cert-manager.io`
- **Names**: kind, singular, plural, shortNames
- **Versions**: which API versions are supported
- **Scope**: Namespaced or Cluster

### 4. View the CRD spec

```bash
kubectl get crd certificates.cert-manager.io -o yaml | sed -n '/^  names:/,/^  [a-z]/p' | head -20
```

### 5. List cert-manager Certificates

```bash
kubectl get certificates --all-namespaces
```

### 6. List ClusterIssuers

```bash
kubectl get clusterissuers
```

You should see `selfsigned-issuer`.

### 7. Describe the ClusterIssuer

```bash
kubectl describe clusterissuer selfsigned-issuer
```

### 8. Create a Certificate using the CRD

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: training
spec:
  secretName: test-cert-tls
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
    - test.example.com
  duration: 2160h
  renewBefore: 360h
EOF
```

### 9. Verify the Certificate

```bash
kubectl wait --for=condition=Ready certificate/test-cert -n training --timeout=60s
kubectl get certificate test-cert -n training
kubectl describe certificate test-cert -n training
```

The READY column should show `True`. The `wait` blocks until cert-manager has issued the certificate and written the backing Secret, so the next step won't race ahead of the operator.

### 10. Check the generated Secret

```bash
kubectl get secret test-cert-tls -n training
```

### 11. Understand the operator pattern

The cert-manager operator:
1. **Watches** for Certificate CRD objects
2. **Processes** the certificate request
3. **Creates** the TLS secret with the certificate
4. **Renews** certificates before they expire

This is the **operator pattern**: a controller that watches CRDs and takes action.

### 12. View API resources including custom ones

```bash
kubectl api-resources | grep cert-manager
```

CRDs extend the Kubernetes API. After installing cert-manager, `certificates`, `issuers`, etc. become first-class API resources.

## Verification

```bash
# CRDs exist
kubectl get crd | grep cert-manager | wc -l
# Should show several CRDs

# Certificate was created and is ready
kubectl get certificate test-cert -n training -o jsonpath='{.status.conditions[0].status}'
# Should output: True

# Secret was generated
kubectl get secret test-cert-tls -n training -o jsonpath='{.type}'
# Should output: kubernetes.io/tls
```

## Cleanup

```bash
kubectl delete certificate test-cert -n training --ignore-not-found --force --grace-period=0
kubectl delete secret test-cert-tls -n training --ignore-not-found --force --grace-period=0
```

## Further reading
- [Custom Resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) - concept reference
- [CustomResourceDefinitions](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/) - task walkthrough
