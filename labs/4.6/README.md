# Lab 4.6 - TLS Ingress

## Objective
Learn how to secure an Ingress with TLS using cert-manager to automatically provision certificates from a self-signed ClusterIssuer.

## Prerequisites
- cluster provisioned with `provision.sh` (check ingress IP with `kubectl get svc -n ingress-nginx`)
- cert-manager installed with a ClusterIssuer named `selfsigned-issuer`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Deploy the application

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl rollout status deployment/tls-web -n training --timeout=60s
```

### 2. Create the Certificate resource

```bash
kubectl apply -f certificate.yaml
```

### 3. Verify the certificate was issued

```bash
kubectl wait --for=condition=Ready certificate/training-tls-cert -n training --timeout=60s
kubectl get certificate training-tls-cert -n training
```

The READY column should show `True`. The `wait` blocks until cert-manager has issued the certificate and written the TLS secret, so the next steps won't race ahead of the operator. If it does not become ready, check:

```bash
kubectl describe certificate training-tls-cert -n training
```

### 4. Verify the TLS secret was created

```bash
kubectl get secret training-tls-secret -n training
```

The secret type should be `kubernetes.io/tls` with `tls.crt` and `tls.key` data keys.

### 5. Inspect the certificate details

```bash
kubectl get secret training-tls-secret -n training -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text 2>/dev/null | head -20
```

### 6. Create the TLS Ingress

```bash
kubectl apply -f ingress-tls.yaml
```

### 7. Verify the Ingress

```bash
kubectl get ingress tls-ingress -n training
kubectl describe ingress tls-ingress -n training
```

Note the TLS section showing the secret name and host.

### 8. Test HTTPS access

```bash
NODE_IP=$(kubectl get node controlplane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
curl -k --resolve training-tls.local:30443:$NODE_IP https://training-tls.local:30443
```

The `-k` flag is needed because the certificate is self-signed. You should see the nginx welcome page.

### 9. Test HTTP to HTTPS redirect

```bash
curl -s -o /dev/null -w '%{http_code}' --resolve training-tls.local:30080:$NODE_IP http://training-tls.local:30080
```

Should return `308` (permanent redirect to HTTPS) because `ssl-redirect` is enabled.

### 10. View the certificate chain

```bash
echo | openssl s_client -connect $NODE_IP:30443 -servername training-tls.local 2>/dev/null | openssl x509 -noout -subject -issuer
```

## Verification

```bash
# Certificate is ready
kubectl get certificate training-tls-cert -n training -o jsonpath='{.status.conditions[0].status}'
# Should output: True

# TLS secret exists
kubectl get secret training-tls-secret -n training -o jsonpath='{.type}'
# Should output: kubernetes.io/tls

# HTTPS works
NODE_IP=$(kubectl get node controlplane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
curl -k -s -o /dev/null -w '%{http_code}' --resolve training-tls.local:30443:$NODE_IP https://training-tls.local:30443
# Should output: 200
```

## Cleanup

```bash
kubectl delete -f ingress-tls.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f certificate.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f service.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f deployment.yaml --ignore-not-found --force --grace-period=0
kubectl delete secret training-tls-secret -n training --ignore-not-found --force --grace-period=0
```

## Further reading
- [TLS in Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls) - concept reference
- [cert-manager documentation](https://cert-manager.io/docs/) - official docs
- [Securing nginx-ingress](https://cert-manager.io/docs/tutorials/acme/nginx-ingress/) - cert-manager tutorial
