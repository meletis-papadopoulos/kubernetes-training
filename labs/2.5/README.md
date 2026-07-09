# Lab 2.5 - Probes

## Objective
Learn how Kubernetes health probes work: liveness probes restart unhealthy containers, readiness probes control traffic routing, and startup probes protect slow-starting applications.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### Part A: Liveness Probe

### 1. Deploy the liveness probe pod

```bash
kubectl apply -f pod-liveness.yaml
kubectl wait --for=condition=Ready pod/liveness-http -n training --timeout=60s
```

### 2. Verify the probe is working

```bash
kubectl describe pod liveness-http -n training
```

Look for the "Liveness" section in the container spec and check Events for successful probes.

### 3. Simulate a liveness failure

Exec into the pod and remove the default page:

```bash
kubectl exec liveness-http -n training -- rm /usr/share/nginx/html/index.html
```

### 4. Watch the pod restart

```bash
timeout 35s kubectl get pod liveness-http -n training -w || true
```

After 3 failed probes (about 30 seconds), Kubernetes will restart the container. The RESTARTS column will increment. The watch stops automatically after 35 seconds.

### 5. Check events

```bash
kubectl describe pod liveness-http -n training | tail -20
```

You should see "Liveness probe failed" events followed by a container restart.

### Part B: Readiness Probe

### 6. Deploy the readiness probe pod

```bash
kubectl apply -f pod-readiness.yaml
kubectl wait --for=condition=Ready pod/readiness-test -n training --timeout=60s
```

### 7. Watch the pod status

```bash
timeout 35s kubectl get pod readiness-test -n training -w || true
```

The pod will show `0/1 READY` for about 30 seconds (until `/tmp/ready` is created), then transition to `1/1 READY`. The watch stops automatically after 35 seconds.

### 8. Understand the difference from liveness

- **Liveness probe failure**: container is restarted
- **Readiness probe failure**: pod is removed from Service endpoints (no traffic sent to it)
- The readiness-test pod starts but is NOT ready for 30 seconds. It would not receive traffic from a Service during that time.

### 9. Simulate readiness failure

```bash
kubectl exec readiness-test -n training -- rm /tmp/ready
```

Watch the pod become unready:

```bash
timeout 15s kubectl get pod readiness-test -n training -w || true
```

The READY column changes to `0/1`. The pod is still running but would not receive Service traffic.

### 10. Restore readiness

```bash
kubectl exec readiness-test -n training -- touch /tmp/ready
```

The pod becomes ready again.

### Part C: Startup Probe

### 11. Deploy the startup probe pod

```bash
kubectl apply -f pod-startup.yaml
```

### 12. Watch the pod

```bash
timeout 55s kubectl get pod startup-test -n training -w || true
```

The startup probe gives the slow app time to start (up to 50 seconds: 5 initial + 5 period x 10 failures). Once the startup probe succeeds, the liveness probe takes over. The watch stops automatically after 55 seconds.

### 13. Understand startup probes

Without a startup probe, a slow-starting app would be killed by the liveness probe before it finishes starting. The startup probe disables liveness/readiness probes until it succeeds.

### 14. Check probe configuration

```bash
kubectl get pod startup-test -n training -o jsonpath='{.spec.containers[0].startupProbe}' | python3 -m json.tool 2>/dev/null
kubectl get pod startup-test -n training -o jsonpath='{.spec.containers[0].livenessProbe}' | python3 -m json.tool 2>/dev/null
```

## Verification

```bash
# Liveness pod should have restarted at least once (if you deleted index.html)
kubectl get pod liveness-http -n training -o jsonpath='{.status.containerStatuses[0].restartCount}'

# Readiness pod should be Ready
kubectl get pod readiness-test -n training -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# Startup pod should be Running
kubectl get pod startup-test -n training
```

## Cleanup

```bash
kubectl delete -f pod-liveness.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pod-readiness.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pod-startup.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) - task walkthrough
- [Container probes](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes) - concept reference
