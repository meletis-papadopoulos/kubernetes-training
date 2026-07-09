# Lab 9.2 - Image Pull Problems

## Objective
Diagnose and fix one of the most common pod startup failures: the image cannot be pulled. Practice reading `kubectl describe` events to distinguish DNS failures, missing tags, and missing/broken `imagePullSecrets`.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Background

When a pod is stuck in `ErrImagePull` or `ImagePullBackOff`, the root cause is almost always one of:

1. The registry hostname does not resolve (DNS / typo)
2. The image:tag does not exist at that registry
3. The image is private and the pod has no valid `imagePullSecret`

The diagnostic flow is the same in all cases - `kubectl describe pod` and read the **Events** section. The exact wording tells you which of the three you are looking at.

## Steps

### Problem 1: Invalid registry hostname

### 1. Deploy the pod with an unresolvable registry

```bash
kubectl apply -f pod-bad-registry.yaml
```

### 2. Observe the status

```bash
sleep 15
kubectl get pod bad-registry-pod -n training
```

Status: `ErrImagePull` or `ImagePullBackOff`.

### 3. Diagnose

```bash
kubectl describe pod bad-registry-pod -n training | tail -20
```

Look at the **Events** section. You should see something like:

```
Failed to pull image "registry.invalid.example.com/nginx:1.25":
  ... lookup registry.invalid.example.com: no such host
```

The phrase **"no such host"** is the smoking gun for a DNS / hostname problem - typo in the registry, a private registry the cluster cannot reach, or a misconfigured DNS.

### 4. Fix: correct the registry

You cannot mutate `image:` in place; delete and recreate.

```bash
kubectl delete pod bad-registry-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: bad-registry-pod
  namespace: training
spec:
  containers:
    - name: app
      image: nginx:1.25
EOF
kubectl wait --for=condition=Ready pod/bad-registry-pod -n training --timeout=60s
```

---

### Problem 2: Image tag does not exist

### 5. Deploy the pod with a non-existent tag

```bash
kubectl apply -f pod-bad-tag.yaml
```

### 6. Observe the status

```bash
sleep 15
kubectl get pod bad-tag-pod -n training
```

Status: `ImagePullBackOff`.

### 7. Diagnose

```bash
kubectl describe pod bad-tag-pod -n training | tail -20
```

Events show something like:

```
Failed to pull image "nginx:9.99-this-tag-does-not-exist":
  ... manifest for nginx:9.99-this-tag-does-not-exist not found: manifest unknown
```

The phrase **"manifest unknown"** (or "not found") means the registry was reachable and authenticated successfully, but the specific tag does not exist. Typo in the tag, image was deleted, or you're chasing a tag that was never pushed.

### 8. Fix: use a valid tag

```bash
kubectl delete pod bad-tag-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: bad-tag-pod
  namespace: training
spec:
  containers:
    - name: app
      image: nginx:1.25
EOF
kubectl wait --for=condition=Ready pod/bad-tag-pod -n training --timeout=60s
```

---

### Problem 3: Missing imagePullSecret (private registry)

This is a common scenario with private registries: the pod references an image in a private registry, and the `imagePullSecret` referenced by the pod either does not exist as a Secret object or has bad credentials.

### 9. Deploy the pod that references a non-existent pull secret

```bash
kubectl apply -f pod-missing-pullsecret.yaml
```

### 10. Observe the status

```bash
sleep 15
kubectl get pod missing-pullsecret-pod -n training
```

Status: `ImagePullBackOff`.

### 11. Diagnose

```bash
kubectl describe pod missing-pullsecret-pod -n training | tail -20
```

Two distinct events appear:

```
Warning  FailedToRetrieveImagePullSecret  ... secret "nonexistent-registry-secret" not found
Warning  Failed                            Failed to pull image "ghcr.io/private-org/private-image:1.0":
                                            ... denied / unauthorized
```

The first event is the explicit clue. **Always look for `FailedToRetrieveImagePullSecret`** - it tells you the pod is referencing a Secret that does not exist in the namespace.

In the real world, the fix is one of:

- The Secret exists but in a different namespace → recreate it in this namespace (Secrets are namespaced)
- The Secret name is mistyped in the pod spec → fix the spec
- The Secret exists but the credentials are wrong/expired → recreate the docker-registry secret

### 12. Fix: create a valid docker-registry Secret and update the pod to use a public image

For this lab we'll create a placeholder secret and point the pod at a public image to demonstrate the resolution flow. In a real private-registry setup you would generate the Secret with real registry credentials.

```bash
kubectl create secret docker-registry registry-pull-secret \
  --docker-server=fake.registry.example.com \
  --docker-username=placeholder \
  --docker-password=placeholder \
  --docker-email=none@example.com \
  -n training

kubectl delete pod missing-pullsecret-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: missing-pullsecret-pod
  namespace: training
spec:
  imagePullSecrets:
    - name: registry-pull-secret
  containers:
    - name: app
      image: nginx:1.25
EOF
kubectl wait --for=condition=Ready pod/missing-pullsecret-pod -n training --timeout=60s
```

Pod is now Running. The `imagePullSecrets` reference resolves (the Secret exists), and the public image pulls without needing the credentials.

---

## Diagnostic Cheat Sheet

| Event message snippet | Root cause | Where to look |
|---|---|---|
| `lookup ...: no such host` | DNS / bad hostname | Registry URL typo, network egress |
| `manifest unknown`, `not found` | Image:tag doesn't exist | Tag typo, image deleted |
| `FailedToRetrieveImagePullSecret` | Secret missing | Secret name, secret namespace |
| `denied`, `unauthorized` | Auth failure | Secret credentials, registry permissions |
| `pull access denied` | Repo permissions | RBAC on registry side |
| `i/o timeout`, `connection refused` | Network egress blocked | Firewall rules, network policy, DNS routing |

## Verification

```bash
# All three pods Running
kubectl get pods -n training -l '!app'
kubectl get pod bad-registry-pod bad-tag-pod missing-pullsecret-pod -n training
```

## Cleanup

```bash
kubectl delete pod bad-registry-pod bad-tag-pod missing-pullsecret-pod -n training --ignore-not-found --force --grace-period=0
kubectl delete secret registry-pull-secret -n training --ignore-not-found
```

## Further reading
- [Pull an Image from a Private Registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)
