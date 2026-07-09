# Exercise 6.2 - Requests, Limits & Quotas

*Domain: Workloads & Scheduling. Target: ~10 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace rq-demo
kubectl create namespace d92
```

## Tasks

1. In the namespace `rq-demo`, create a Pod named `resourced` that runs a single container using the
   image `nginx:1.23.4`. For that container, set a CPU resource request of `250m` and a memory
   resource request of `64Mi`; set a CPU limit of `500m` and a memory limit of `128Mi`. Create the
   Pod and inspect the applied resource block to confirm all four values. On which value did the
   scheduler base its placement decision - the request or the limit?

2. In the same namespace `rq-demo`, create a ResourceQuota named `team-quota` that caps the namespace
   at `requests.cpu=1`, `requests.memory=1Gi`, `limits.cpu=2`, `limits.memory=2Gi`, and a maximum of
   `3` pods. Render the quota's used-vs-hard figures. Now attempt to create a second Pod named
   `no-limits` (image `nginx:1.23.4`) that declares **no** requests or limits at all. Does it get
   admitted? Explain what the API server returns and why.

3. In the namespace `d92`, create a LimitRange named `default-limits` that applies a **default** CPU
   limit of `500m` and memory limit of `256Mi`, and a **default request** of CPU `200m` and memory
   `128Mi`, to any container that omits them. Then create a Pod named `inherits` (image
   `busybox:1.36`, command `sleep 3600`) that specifies no resources of its own. Inspect the running
   Pod's container resources - where did its requests and limits come from?

## Acceptance criteria

- `resourced` in `rq-demo` is `Running` with requests `250m`/`64Mi` and limits `500m`/`128Mi`.
- `team-quota` exists in `rq-demo`; `no-limits` is **rejected** at admission (quota with a
  `requests`/`limits` hard cap forbids pods that do not declare them).
- `default-limits` LimitRange exists in `d92`; `inherits` runs and shows the injected default
  request/limit values on its container despite defining none.

## Docs you may reference

- [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Limit Ranges](https://kubernetes.io/docs/concepts/policy/limit-range/)
