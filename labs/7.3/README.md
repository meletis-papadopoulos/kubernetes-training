# Lab 7.3 - ServiceAccounts

## Objective
Learn how ServiceAccounts provide identity to pods, how tokens are mounted, and how to use them to access the Kubernetes API from within a pod.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Create the ServiceAccount

```bash
kubectl apply -f serviceaccount.yaml
```

### 2. Create the Role and RoleBinding

```bash
kubectl apply -f role.yaml
kubectl apply -f rolebinding.yaml
```

### 3. Deploy the pod with the ServiceAccount

```bash
kubectl apply -f pod.yaml
kubectl wait --for=condition=Ready pod/api-explorer-pod -n training --timeout=60s
```

### 4. Verify the ServiceAccount is assigned

```bash
kubectl get pod api-explorer-pod -n training -o jsonpath='{.spec.serviceAccountName}'
```

Should output: `api-explorer`

### 5. Inspect the projected token volume

```bash
kubectl get pod api-explorer-pod -n training -o yaml | sed -n '/^  volumes:/,/^  [a-z]/p' | head -30
```

Kubernetes automatically mounts a projected service account token at `/var/run/secrets/kubernetes.io/serviceaccount/`.

### 6. View the mounted token from inside the pod

```bash
kubectl exec api-explorer-pod -n training -- ls /var/run/secrets/kubernetes.io/serviceaccount/
```

You should see: `ca.crt`, `namespace`, `token`

### 7. Read the token

```bash
kubectl exec api-explorer-pod -n training -- cat /var/run/secrets/kubernetes.io/serviceaccount/token
```

This is a JWT token that the pod uses to authenticate with the API server.

### 8. Access the Kubernetes API from within the pod

```bash
kubectl exec api-explorer-pod -n training -- sh -c '
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    -H "Authorization: Bearer $TOKEN" \
    https://kubernetes.default.svc/api/v1/namespaces/training/pods
' | head -20
```

This should return a JSON list of pods in the training namespace (our SA has `get` and `list` permissions on pods).

### 9. Test unauthorized access

```bash
kubectl exec api-explorer-pod -n training -- sh -c '
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    -H "Authorization: Bearer $TOKEN" \
    https://kubernetes.default.svc/api/v1/namespaces/default/pods
'
```

Should return a 403 Forbidden -- the SA only has permissions in the `training` namespace.

### 10. Test with kubectl auth can-i

```bash
kubectl auth can-i list pods -n training --as=system:serviceaccount:training:api-explorer
# yes

kubectl auth can-i create pods -n training --as=system:serviceaccount:training:api-explorer
# no

kubectl auth can-i list deployments -n training --as=system:serviceaccount:training:api-explorer
# yes
```

### 11. Check the default ServiceAccount

Every namespace has a `default` ServiceAccount:

```bash
kubectl get serviceaccount -n training
```

Pods that don't specify a ServiceAccount use `default`. The default SA typically has no extra permissions.

### 12. Opt out of token mounting

You can disable automatic token mounting:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: no-token-pod
  namespace: training
spec:
  automountServiceAccountToken: false
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
EOF
kubectl wait --for=condition=Ready pod/no-token-pod -n training --timeout=60s
kubectl exec no-token-pod -n training -- ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1 \
  || echo "(directory not mounted - expected)"
```

The `ls` fails because no projected volume was created. This is a security best practice for pods that do not need API access.

## Verification

```bash
# SA exists
kubectl get sa api-explorer -n training

# Pod uses correct SA
kubectl get pod api-explorer-pod -n training -o jsonpath='{.spec.serviceAccountName}'

# API access works from within pod
kubectl exec api-explorer-pod -n training -- sh -c '
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    -H "Authorization: Bearer $TOKEN" \
    https://kubernetes.default.svc/api/v1/namespaces/training/pods | grep "\"kind\""
'
```

## Cleanup

```bash
kubectl delete pod no-token-pod -n training --ignore-not-found --force --grace-period=0
kubectl delete -f pod.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f rolebinding.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f role.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f serviceaccount.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts/) - concept reference
- [Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) - task walkthrough
