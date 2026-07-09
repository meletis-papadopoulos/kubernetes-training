# Lab 7.6 - Certificate Inspection

## Objective
Learn how to inspect certificates and keys with OpenSSL in a Kubernetes context. Decode TLS secrets, check expiry, verify certificate chains, and inspect the API server certificate.

## Prerequisites
- cluster provisioned with `provision.sh` (cert-manager installed with `selfsigned-issuer` ClusterIssuer)
- Namespace `training` created: `kubectl create namespace training`

## Steps

### Part A: Create a TLS Certificate

### 1. Create a Certificate using cert-manager

```bash
kubectl apply -f certificate.yaml
```

### 2. Wait for the certificate to be ready

```bash
kubectl wait --for=condition=Ready certificate/lab-cert -n training --timeout=60s
```

### 3. Verify the TLS secret was created

```bash
kubectl get secret lab-cert-tls -n training
```

The type should be `kubernetes.io/tls`.

### Part B: Inspect the Certificate

### 4. Decode and view the full certificate

```bash
kubectl get secret lab-cert-tls -n training -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

Key fields to note:
- **Issuer**: who signed the certificate
- **Subject**: who the certificate is for
- **Not Before / Not After**: validity window
- **Subject Alternative Names (SANs)**: DNS names the cert covers

### 5. Check just the expiry date

```bash
kubectl get secret lab-cert-tls -n training -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -enddate -noout
```

### 6. Check the subject and issuer

```bash
kubectl get secret lab-cert-tls -n training -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -subject -issuer -noout
```

### 7. Check the SANs (Subject Alternative Names)

```bash
kubectl get secret lab-cert-tls -n training -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -ext subjectAltName
```

You should see `lab.example.com` and `*.lab.example.com`.

### Part C: Verify Key Matches Certificate

cert-manager's self-signed issuer generates **RSA 2048** keys by default (confirmed by the cert's `rsaEncryption` public key algorithm from Part B). You can specify `spec.privateKey.algorithm: ECDSA` in the Certificate to get EC keys instead. Use `openssl pkey` for the pubkey-hash comparison below - it handles both RSA and EC cleanly, whereas the classic `openssl rsa -modulus` trick only works for RSA.

### 8. Extract the public key from the certificate

```bash
kubectl get secret lab-cert-tls -n training -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -pubkey | openssl md5
```

### 9. Extract the public key from the private key

```bash
kubectl get secret lab-cert-tls -n training -o jsonpath='{.data.tls\.key}' | base64 -d | openssl pkey -pubout 2>/dev/null | openssl md5
```

### 10. Compare the hashes

The MD5 hashes from steps 8 and 9 must match. If they don't, the key and certificate are mismatched. This method works for both RSA and EC keys.

### Part D: Inspect the Private Key

### 11. Check the private key

```bash
kubectl get secret lab-cert-tls -n training -o jsonpath='{.data.tls\.key}' | base64 -d | openssl pkey -check -noout 2>&1
```

Should output `Key is valid`.

### 12. View key details

```bash
kubectl get secret lab-cert-tls -n training -o jsonpath='{.data.tls\.key}' | base64 -d | openssl pkey -text -noout 2>/dev/null | head -5
```

### Part E: Inspect the API Server Certificate

### 13. Get the API server endpoint

```bash
kubectl cluster-info | grep "control plane"
```

### 14. Inspect the API server certificate from inside the cluster

```bash
echo | openssl s_client -connect localhost:6443 2>/dev/null | openssl x509 -text -noout | head -30
```

### 15. Check the API server certificate expiry

```bash
echo | openssl s_client -connect localhost:6443 2>/dev/null | openssl x509 -enddate -noout
```

### 16. Check the API server SANs

```bash
echo | openssl s_client -connect localhost:6443 2>/dev/null | openssl x509 -noout -ext subjectAltName
```

### Part F: Inspect Cluster Component Certificates (kubeadm)

### 17. List the certificates on the control plane

```bash
ls /etc/kubernetes/pki/
```

### 18. View the CA certificate

```bash
openssl x509 -in /etc/kubernetes/pki/ca.crt -text -noout | head -20
```

### 19. Check all certificate expiry dates

```bash
for cert in /etc/kubernetes/pki/*.crt; do echo "--- $cert ---"; openssl x509 -in $cert -enddate -subject -noout; echo; done
```

### 20. Verify the API server cert is signed by the cluster CA

```bash
openssl verify -CAfile /etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/apiserver.crt
```

Should output `OK`.

### 21. Check if key matches cert for the API server

```bash
openssl x509 -noout -modulus -in /etc/kubernetes/pki/apiserver.crt | openssl md5; openssl rsa -noout -modulus -in /etc/kubernetes/pki/apiserver.key | openssl md5
```

Both MD5 hashes must match.

### Part G: Create and Inspect a CSR

### 22. Generate a private key and CSR inside the cluster

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout /tmp/test.key -out /tmp/test.csr -subj "/CN=test-user/O=dev-team"
```

### 23. Inspect the CSR

```bash
openssl req -in /tmp/test.csr -text -noout
```

Note the **Subject** (`CN=test-user, O=dev-team`) and the **Public Key** details.

### 24. Sign the CSR with the cluster CA

```bash
openssl x509 -req -in /tmp/test.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out /tmp/test.crt -days 30
```

### 25. Verify the signed certificate

```bash
openssl verify -CAfile /etc/kubernetes/pki/ca.crt /tmp/test.crt
openssl x509 -in /tmp/test.crt -subject -issuer -enddate -noout
```

## Verification

```bash
# cert-manager certificate is ready
kubectl get certificate lab-cert -n training -o jsonpath='{.status.conditions[0].status}'
# Should output: True

# TLS secret exists with correct type
kubectl get secret lab-cert-tls -n training -o jsonpath='{.type}'
# Should output: kubernetes.io/tls

# Key matches certificate (hashes should be identical)
CERT_HASH=$(kubectl get secret lab-cert-tls -n training -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -pubkey | openssl md5)
KEY_HASH=$(kubectl get secret lab-cert-tls -n training -o jsonpath='{.data.tls\.key}' | base64 -d | openssl pkey -pubout 2>/dev/null | openssl md5)
echo "Cert: $CERT_HASH"
echo "Key:  $KEY_HASH"

# API server cert is valid
openssl verify -CAfile /etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/apiserver.crt
```

## Cleanup

```bash
kubectl delete -f certificate.yaml --ignore-not-found --force --grace-period=0
kubectl delete secret lab-cert-tls -n training --ignore-not-found --force --grace-period=0
rm -f /tmp/test.key /tmp/test.csr /tmp/test.crt /etc/kubernetes/pki/ca.srl
```

## Further reading
- [Manage TLS Certificates in a Cluster](https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/) - task walkthrough
- [PKI Certificates and Requirements](https://kubernetes.io/docs/setup/best-practices/certificates/) - reference
- [cert-manager documentation](https://cert-manager.io/docs/) - official docs
