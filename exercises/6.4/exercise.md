# Exercise 6.4 - Horizontal Pod Autoscaler

*Domain: Workloads & Scheduling. Target: ~15 min. Do not open `solution/` until you have tried.*

This exercise needs a working **Metrics Server** - `kubectl top nodes` must return data.

## Setup

```bash
kubectl create namespace scale
kubectl top nodes    # must return CPU/memory columns, not an error
```

## Tasks

1. In the namespace `scale`, create a Deployment named `web` (image `nginx:1.27.1`, `1` replica,
   container port `80`) whose container declares a CPU **request** of `100m` and limit `200m` (memory
   request `64Mi`, limit `128Mi`). Expose it as a ClusterIP Service named `web-svc` on port `80`. Then
   create an `autoscaling/v2` HorizontalPodAutoscaler named `web` targeting `web`, scaling on **50%**
   average CPU utilization, `minReplicas: 1`, `maxReplicas: 4`. Immediately after creating the HPA,
   inspect it. Why does the `TARGETS`
   column show `<unknown>/50%` (or `0%`) for the first ~30-60 seconds, and what component must be
   running for it to ever populate?

2. Generate CPU load by creating a Pod named `load-generator` (image `busybox:1.36`) that runs
   `while true; do wget -q -O- http://web-svc.scale.svc.cluster.local; done`. Poll the HPA every
   ~15 seconds (do **not** use `-w`) for a minute or two and watch `REPLICAS` climb as CPU crosses the
   target. What is the upper bound the HPA will scale to, and which field sets it?

3. Delete the `load-generator` Pod to remove the load, then poll the HPA again. Confirm `REPLICAS`
   falls back toward `minReplicas` once CPU drops below the target.

## Acceptance criteria

- Deployment `web` runs with a CPU request of `100m`; `web-svc` resolves to its Pods.
- HPA `web` exists (`autoscaling/v2`), min `1` / max `4`, target `50%`; after metrics populate,
  `TARGETS` shows a real percentage (not `<unknown>`).
- Under load, `REPLICAS` rises (up to `4`); after the load Pod is deleted, it returns toward `1`.

## Docs you may reference

- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [HPA Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
- [`kubectl autoscale`](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#autoscale)
