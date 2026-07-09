# Lab 3.1 - ConfigMaps

## Objective
Learn how to create ConfigMaps from literals and files, and consume them in Pods as environment variables and mounted volumes.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Create a ConfigMap from literals (declarative)

```bash
kubectl apply -f configmap-literal.yaml
```

### 2. Verify the ConfigMap

```bash
kubectl get configmap app-config-literal -n training
kubectl describe configmap app-config-literal -n training
```

### 3. Create a ConfigMap from literals (imperative alternative)

```bash
kubectl create configmap app-config-imperative \
  --from-literal=APP_ENV=training \
  --from-literal=LOG_LEVEL=debug \
  -n training --dry-run=client -o yaml
```

This shows what the YAML would look like without creating the resource.

### 4. Create a ConfigMap from a file (declarative)

```bash
kubectl apply -f configmap-file.yaml
```

### 5. Create a ConfigMap from a file (imperative alternative)

```bash
kubectl create configmap app-config-from-file \
  --from-file=app-config.properties \
  -n training --dry-run=client -o yaml
```

### 6. Deploy a Pod that uses ConfigMap as environment variables

```bash
kubectl apply -f pod-env.yaml
kubectl wait --for=condition=Ready pod/pod-configmap-env -n training --timeout=60s
```

### 7. Verify the environment variables are set

```bash
kubectl logs pod-configmap-env -n training
```

Expected output: `APP_ENV=training LOG_LEVEL=debug`

You can also exec into the pod:

```bash
kubectl exec pod-configmap-env -n training -- env | grep -E "APP_ENV|LOG_LEVEL"
```

### 8. Deploy a Pod that mounts ConfigMap as a volume

```bash
kubectl apply -f pod-volume.yaml
kubectl wait --for=condition=Ready pod/pod-configmap-volume -n training --timeout=60s
```

### 9. Verify the mounted file

```bash
kubectl logs pod-configmap-volume -n training
```

You should see the contents of `app-config.properties`.

Also verify via exec:

```bash
kubectl exec pod-configmap-volume -n training -- ls /etc/config/
kubectl exec pod-configmap-volume -n training -- cat /etc/config/app-config.properties
```

### 10. Update a ConfigMap and observe behavior

Edit the ConfigMap:

```bash
kubectl edit configmap app-config-file -n training
```

Change a value (e.g., `database.port=3306`), save, and wait about 60 seconds. Then check:

```bash
kubectl exec pod-configmap-volume -n training -- cat /etc/config/app-config.properties
```

Volume-mounted ConfigMaps update automatically (with a delay). Environment variables do NOT update without restarting the pod.

## Verification

```bash
# Confirm ConfigMaps exist
kubectl get configmaps -n training

# Confirm pods are running
kubectl get pods -n training -l '!app'

# Confirm env vars are set
kubectl exec pod-configmap-env -n training -- env | grep APP_ENV

# Confirm volume is mounted
kubectl exec pod-configmap-volume -n training -- cat /etc/config/app-config.properties
```

## Cleanup

```bash
kubectl delete -f pod-env.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pod-volume.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f configmap-literal.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f configmap-file.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) - concept reference
- [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) - task walkthrough
- [`kubectl create configmap`](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#-em-configmap-em-) - command reference
