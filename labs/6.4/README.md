# Lab 6.4 - Horizontal Pod Autoscaler

## Objective
Learn how to configure a Horizontal Pod Autoscaler (HPA) to automatically scale a Deployment based on CPU utilization. Observe scaling behavior under load.

## Prerequisites
- cluster provisioned with `provision.sh`
- Metrics Server installed and working (`kubectl top nodes` should return data)
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Create the Deployment with resource requests

```bash
kubectl apply -f deployment.yaml
```

Resource requests are **required** for CPU-based HPA to work.

### 2. Create a Service for the Deployment (needed for load testing)

```bash
kubectl expose deployment hpa-nginx -n training --port=80 --name=hpa-nginx-svc
```

### 3. Verify the Deployment and Service

```bash
kubectl get deployment hpa-nginx -n training
kubectl get svc hpa-nginx-svc -n training
```

### 4. Check current resource usage

```bash
kubectl top pods -n training
```

### 5. Create the HPA

```bash
kubectl apply -f hpa.yaml
```

### 6. Verify HPA status

```bash
kubectl get hpa -n training
```

Wait a minute for metrics to populate. The TARGETS column should show actual CPU usage vs the 50% target.

### 7. Watch HPA in real-time

Open a separate terminal and run:

```bash
timeout 30s kubectl get hpa -n training -w || true
```

### 8. Generate load

In another terminal:

```bash
kubectl apply -f load-generator.yaml
```

### 9. Observe scaling

Watch the HPA terminal. Within 1-2 minutes, you should see:
- CPU utilization climbing above 50%
- REPLICAS count increasing
- New pods being created

```bash
timeout 90s kubectl get pods -n training -l app=hpa-nginx -w || true
```

**If CPU stalls at 45-54%**, you're in the HPA **tolerance band** (±10% of target). HPA deliberately ignores recommendations within that window to prevent flapping - so CPU must exceed **~55%** for the scale-up to trigger. This is realistic production behavior, not a bug.

### 10. Force scale-up for demo purposes (optional)

If the default load generator doesn't push CPU past the tolerance band, or you want to see the full scaling curve, patch the HPA target downward. The scaling formula is:

```
desiredReplicas = ceil(currentReplicas × currentUtil / targetUtil)
```

**Stage 1 - drop target to 20%** (demonstrates intermediate scale-up, typically `2 → 5-6`):

```bash
kubectl patch hpa hpa-nginx -n training --type=merge \
  -p '{"spec":{"metrics":[{"type":"Resource","resource":{"name":"cpu","target":{"type":"Utilization","averageUtilization":20}}}]}}'
```

**Stage 2 - drop target to 5%** (forces scale to `maxReplicas=10`):

```bash
kubectl patch hpa hpa-nginx -n training --type=merge \
  -p '{"spec":{"metrics":[{"type":"Resource","resource":{"name":"cpu","target":{"type":"Utilization","averageUtilization":5}}}]}}'
```

**Why 5% and not 10%?** After the first scale-up, load is distributed across more pods so `currentUtil` drops. Target must be low enough that `ceil(currentReplicas × currentUtil / target) ≥ maxReplicas`. With ~18% CPU after Stage 1, a 5% target gives a 3.6× ratio - more than enough to cap at 10.

### 11. Stop the load

```bash
kubectl delete pod load-generator -n training --force --grace-period=0
```

### 12. Observe scale-down

After ~5 minutes of reduced load, the HPA will scale back down to `minReplicas` (2). Watch:

```bash
timeout 60s kubectl get hpa -n training -w || true
```

The watch stops automatically after 60 seconds - re-run the command (or `kubectl get hpa -n training`) to keep checking until it reaches `minReplicas`.

### 13. HPA with imperative command (alternative)

```bash
kubectl autoscale deployment hpa-nginx -n training --min=2 --max=10 --cpu-percent=50 --dry-run=client -o yaml
```

## Verification

```bash
# Confirm HPA exists and shows metrics
kubectl get hpa hpa-nginx -n training

# Confirm deployment has resource requests
kubectl get deployment hpa-nginx -n training -o jsonpath='{.spec.template.spec.containers[0].resources.requests}'

# Check HPA events
kubectl describe hpa hpa-nginx -n training
```

## Cleanup

```bash
kubectl delete -f load-generator.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f hpa.yaml --ignore-not-found --force --grace-period=0
kubectl delete svc hpa-nginx-svc -n training --ignore-not-found --force --grace-period=0
kubectl delete -f deployment.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) - concept + task
- [HPA Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/) - official tutorial
- [`kubectl autoscale`](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#autoscale) - command reference
