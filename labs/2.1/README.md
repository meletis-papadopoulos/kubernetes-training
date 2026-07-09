# Lab 2.1 - Pods

## Objective
Understand the Pod - the smallest deployable unit in Kubernetes. Create a Pod both imperatively and declaratively, inspect it, read its logs, exec into it, and learn the anatomy of a Pod manifest. Finish by seeing *why* a bare Pod isn't enough - which motivates Deployments in Lab 2.3.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Create a Pod imperatively

The fastest way to get a Pod running is `kubectl run`:

```bash
kubectl run hello-pod --image=nginx:1.25 -n training
```

`kubectl run` builds the Pod spec for you and submits it - no YAML needed.

### 2. List Pods (wide view)

```bash
kubectl get pods -n training -o wide
```

`-o wide` also shows the **node** the Pod landed on and its **Pod IP**. Wait until `STATUS` is `Running` before reading logs or exec-ing - the next command blocks until the container is ready:

```bash
kubectl wait --for=condition=Ready pod/hello-pod -n training --timeout=60s
```

### 3. Inspect the Pod

```bash
kubectl describe pod hello-pod -n training
```

Note in the output:
- **Containers:** the `nginx` container, its image, and state (`Running`)
- **Conditions:** `Ready: True`
- **Events:** `Scheduled` → `Pulled` → `Created` → `Started` (the Pod lifecycle)

### 4. Read the container logs

```bash
kubectl logs hello-pod -n training
```

`kubectl logs` streams the container's stdout/stderr - your first debugging tool.

### 5. Run a command inside the Pod

```bash
kubectl exec hello-pod -n training -- nginx -v
```

`kubectl exec ... -- <cmd>` runs a command in the container. (Add `-it` and use `-- sh` for an interactive shell.)

### 6. See the manifest a Pod is made of

Generate the YAML without creating anything:

```bash
kubectl run web-pod --image=nginx:1.25 -n training --dry-run=client -o yaml
```

This prints the manifest `kubectl` *would* apply - a great way to learn the shape of a Pod.

### 7. Create a Pod declaratively

The provided `pod.yaml` is the same idea, written out and version-controllable:

```bash
kubectl apply -f pod.yaml
```

### 8. Pod manifest anatomy

Open `pod.yaml` and match each part to what it does:
- **`apiVersion: v1` / `kind: Pod`** - what kind of object this is
- **`metadata`** - `name`, `namespace`, and `labels` (labels are how Services/controllers find this Pod later)
- **`spec.containers`** - the container(s): `name`, `image`, `ports`
- **`resources.requests`** - what the scheduler reserves; **`resources.limits`** - the hard ceiling

### 9. View the live object

```bash
kubectl get pod web-pod -n training -o yaml
```

Same manifest you applied, **plus** a `status:` block Kubernetes filled in (Pod IP, phase, container states, conditions).

### 10. Delete a Pod - and see why bare Pods aren't enough

```bash
kubectl delete pod web-pod -n training
kubectl get pods -n training
```

`web-pod` is gone and **nothing recreates it** - a bare Pod has no controller watching it. If the node died, your app would just vanish. That's exactly the problem **Deployments** solve (Lab 2.3): they keep a desired number of Pods running for you.

## Verification

```bash
# hello-pod is Running
kubectl get pod hello-pod -n training -o jsonpath='{.status.phase}'
# Should output: Running

# It runs the expected image
kubectl get pod hello-pod -n training -o jsonpath='{.spec.containers[0].image}'
# Should output: nginx:1.25

# web-pod was deleted and did NOT come back (no controller)
kubectl get pod web-pod -n training --ignore-not-found
# Should output: nothing
```

## Cleanup

```bash
kubectl delete pod hello-pod -n training --force --grace-period=0 --ignore-not-found
kubectl delete -f pod.yaml --force --grace-period=0 --ignore-not-found
```

## Further reading
- [Pods](https://kubernetes.io/docs/concepts/workloads/pods/) - concept reference
- [`kubectl run`](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#run) - command reference
- [Pod lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) - phases and conditions
