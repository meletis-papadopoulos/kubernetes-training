# Exercise 9.9 - Fix an HPA Stuck at `<unknown>`

*Domain: Troubleshooting. Target: ~10 min. Do not open `solution/` until you have tried.*

This is a **fix-it** exercise: `setup.yaml` ships a Deployment, Service, and a HorizontalPodAutoscaler
that cannot compute its target. Diagnose from the cluster, then apply the minimal fix. Assumes
`provision.sh` (metrics-server installed; `kubectl top pods -n kube-system` returns data).

## Setup

```bash
kubectl create namespace ts99
kubectl apply -f setup.yaml
kubectl rollout status deployment/web -n ts99 --timeout=60s
```

## Tasks

1. The HPA `web-hpa` in namespace `ts99` targets CPU utilization but its `TARGETS` column is stuck at
   `<unknown>/50%`, so it never scales. Wait ~30s, then diagnose - do **not** assume metrics-server is
   broken. Check `kubectl get hpa -n ts99`, then read the controller's own explanation in
   `kubectl describe hpa web-hpa -n ts99` under **Conditions** (`ScalingActive` / reason
   `FailedGetResourceMetric`). Confirm what the target Deployment declares with
   `kubectl get deployment web -n ts99 -o jsonpath='{.spec.template.spec.containers[0].resources}'`.
   Fix the workload so the HPA computes a real percentage.

2. Reflective: a CPU-utilization HPA reports `50%` of *what* baseline, and why does that baseline make
   `resources.requests.cpu` mandatory for this HPA to work? Verify `kubectl top pods -n ts99` returns
   data even while the HPA reads `<unknown>` - what does that prove about where the fault is (the
   metrics pipeline vs. the workload spec)?

## Acceptance criteria

- `kubectl get hpa -n ts99` shows `TARGETS` as a real percentage (e.g. `cpu: 0%/50%`), not
  `<unknown>`; `describe hpa` shows `ScalingActive: True`.
- You identify the fault as the target Deployment having **no `resources.requests.cpu`**, surfaced as
  `FailedGetResourceMetric` / `missing request for cpu`.
- You explain that utilization is measured as a percentage of `requests.cpu` (undefined with no
  request), and that a working `kubectl top` proves the metrics pipeline is fine - the gap is the
  missing request on the Pod spec.

## Docs you may reference

- [Resource Metrics Pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
