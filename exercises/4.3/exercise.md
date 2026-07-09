# Exercise 4.3 - Pod-to-Pod Connectivity

*Domain: Networking. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace net43a
kubectl create namespace net43b
```

## Tasks

1. In the namespace `net43a`, create a Deployment named `server` (`3` replicas, image `nginx:1.27.1`,
   label `app=server`, port `80`) and a ClusterIP Service named `server-svc` on port `80`. In the
   namespace `net43b`, create a single Pod named `client` running `busybox:1.36` with
   `command: ["sleep","3600"]`. Pick one `server` pod's IP and, from `client` (a *different*
   namespace), `wget` that pod IP directly. Does the request succeed across namespaces, and did you
   have to do anything special to route to another namespace's pod network?

2. From `client`, reach the same workload through the Service instead - by its cross-namespace FQDN
   `server-svc.net43a.svc.cluster.local`. Now delete one `server` pod, let the Deployment replace it,
   and repeat the Service call. Why does the Service call keep working while the pod-IP call from
   Task 1 would now be stale?

3. Demonstrate load-balancing: from `client`, `wget` the Service `12` times, then read the nginx
   access logs across the three `server` pods and confirm the requests were spread over more than one
   pod. Which component actually distributes those connections across the endpoints?

## Acceptance criteria

- `server` is `3/3` in `net43a`; `client` is `Running` in `net43b`.
- A direct `wget` to a `server` pod IP from `client` returns the nginx page (cross-namespace pod
  traffic is not NAT'd on a flat cluster network).
- The Service FQDN call from `client` returns the nginx page and still works after a pod is replaced;
  the 12 requests land on at least two different `server` pods (visible in their access logs).

## Docs you may reference

- [Cluster Networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
