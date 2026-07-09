# Exercise 6.3 - ResourceQuota scopes & LimitRange min/max

*Domain: Workloads & Scheduling. Target: ~12 min. Do not open `solution/` until you have tried.*

This goes deeper than Exercise 6.2 (which capped compute totals): here you practise **object-count**
quotas and a LimitRange with **min/max** bounds - not just defaults.

## Setup

```bash
kubectl create namespace q63
```

## Tasks

1. In the namespace `q63`, create a ResourceQuota named `object-counts` that caps object **counts**
   (not compute): at most `count/deployments.apps=2`, `count/services=2`, and `count/configmaps=2`.
   Render its used-vs-hard figures - note that `configmaps` already reads `1` used, because every
   namespace is seeded with the auto-created `kube-root-ca.crt` ConfigMap. Now create two Deployments
   named `web1` and `web2` (both image `nginx:1.27.1`), then attempt a third Deployment `web3`. Is
   `web3` admitted? At which layer is it rejected - the Deployment object itself, or its Pods - and
   why does that distinction matter?

2. Still in `q63`, create a LimitRange named `container-limits` (type `Container`) with `min` of CPU
   `50m` / memory `64Mi`, `max` of CPU `500m` / memory `512Mi`, a `default` (limit) of CPU `200m` /
   memory `256Mi`, and a `defaultRequest` of CPU `100m` / memory `128Mi`. First create a Pod named
   `mutated` (image `nginx:1.27.1`) that declares **no** resources, and confirm the injected values.
   Then apply a Pod named `oversized` (image `nginx:1.27.1`) whose container sets `limits.cpu: "2"`
   and confirm it is **rejected**. Reflective: how do a LimitRange's defaults interact with a compute
   ResourceQuota (like the one in 6.2) that *requires* `limits.*` to be set on every Pod?

## Acceptance criteria

- `object-counts` exists in `q63`; `web1`/`web2` are created, `web3` is **rejected** with an
  "exceeded quota: object-counts" error on `count/deployments.apps`.
- `container-limits` exists in `q63`; `mutated` runs with the injected `100m`/`128Mi` requests and
  `200m`/`256Mi` limits; `oversized` is **rejected** ("maximum cpu usage per Container is 500m").

## Docs you may reference

- [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Limit Ranges](https://kubernetes.io/docs/concepts/policy/limit-range/)
