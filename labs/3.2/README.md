# Lab 3.2 - Secrets

## Objective
Learn how to create Kubernetes Secrets, decode their values, and consume them in Pods as environment variables and mounted volumes.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Understand base64 encoding

Secrets store values as base64-encoded strings. Encode values:

```bash
echo -n "admin" | base64
# Output: YWRtaW4=

echo -n "S3cr3tP@ssword" | base64
# Output: UzNjcjN0UEBzc3dvcmQ=
```

### 2. Create the Secret (declarative)

```bash
kubectl apply -f secret.yaml
```

### 3. Verify the Secret

```bash
kubectl get secret app-secret -n training
kubectl describe secret app-secret -n training
```

Note: `describe` shows the keys but hides the values (shows byte count).

### 4. Decode the Secret values

```bash
kubectl get secret app-secret -n training -o jsonpath='{.data.username}' | base64 -d
# Output: admin

kubectl get secret app-secret -n training -o jsonpath='{.data.password}' | base64 -d
# Output: S3cr3tP@ssword
```

### 5. Create a Secret imperatively (alternative)

```bash
kubectl create secret generic app-secret-imperative \
  --from-literal=username=admin \
  --from-literal=password='S3cr3tP@ssword' \
  -n training --dry-run=client -o yaml
```

Note: the imperative command handles base64 encoding automatically.

### 6. Deploy a Pod using Secret as environment variables

```bash
kubectl apply -f pod-secret-env.yaml
kubectl wait --for=condition=Ready pod/pod-secret-env -n training --timeout=60s
```

### 7. Verify environment variables

```bash
kubectl logs pod-secret-env -n training
```

Expected output: `Username=admin Password=S3cr3tP@ssword`

```bash
kubectl exec pod-secret-env -n training -- env | grep DB_
```

### 8. Deploy a Pod mounting Secret as a volume

```bash
kubectl apply -f pod-secret-volume.yaml
kubectl wait --for=condition=Ready pod/pod-secret-volume -n training --timeout=60s
```

### 9. Verify the mounted files

```bash
kubectl logs pod-secret-volume -n training
```

Expected output:
```
admin
S3cr3tP@ssword
```

Verify file permissions (Secrets are mounted read-only by default):

```bash
kubectl exec pod-secret-volume -n training -- ls -la /etc/secrets/
```

### 10. Important Security Notes

- Secrets are base64-encoded, NOT encrypted (by default)
- Anyone with API access can decode them
- In production, enable encryption at rest for etcd
- Use RBAC to restrict access to Secrets
- Prefer volume mounts over env vars (env vars can leak in logs/crash dumps)

## Verification

```bash
# Confirm secret exists
kubectl get secret app-secret -n training

# Confirm pods are running
kubectl get pods -n training pod-secret-env pod-secret-volume

# Verify decoded values
kubectl get secret app-secret -n training -o jsonpath='{.data.username}' | base64 -d && echo
kubectl get secret app-secret -n training -o jsonpath='{.data.password}' | base64 -d && echo
```

## Cleanup

```bash
kubectl delete -f pod-secret-env.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pod-secret-volume.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f secret.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) - concept reference
- [Distribute Credentials Securely Using Secrets](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/) - task walkthrough
- [Managing Secrets using kubectl](https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kubectl/) - task walkthrough
