# Exercise 4.1 - Services (ClusterIP / NodePort / LoadBalancer)

*Domain: Networking. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace net41
```

## Tasks

1. In the namespace `net41`, create a Deployment named `hello` with `3` replicas running the image
   `nginx:1.27.1`, pod label `app=hello`, container port `80`. Expose it with a **ClusterIP** Service
   named `hello-cip` on port `80` targeting `80`. From a throwaway `busybox:1.36` pod, curl the
   Service's ClusterIP and confirm you get the nginx welcome page. Which object - and which field on
   it - is what actually lets the Service find its three backing pods?

2. Add a second Service named `hello-np` of type **NodePort**, same selector, port `80`, with a fixed
   `nodePort: 30411`. Discover the node's InternalIP and curl `NODE_IP:30411`. Why is this path
   reachable from outside the cluster while the ClusterIP from Task 1 is not?

3. Add a third Service named `hello-lb` of type **LoadBalancer**, same selector, port `80`. Inspect
   its `EXTERNAL-IP`. What value does it show on this bare cluster, and why does it never resolve?
   Given that, how could you still reach the pods externally right now?

## Acceptance criteria

- `hello` is `3/3` in `net41`; `hello-cip` returns the nginx page when curled by ClusterIP from an
  in-cluster pod.
- `hello-np` (NodePort `30411`) returns the nginx page when curled at `NODE_IP:30411`.
- `hello-lb` exists with `type: LoadBalancer` and its `EXTERNAL-IP` stays `<pending>`; the same three
  pod IPs appear as endpoints for all three Services.

## Docs you may reference

- [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Connecting Applications with Services](https://kubernetes.io/docs/tutorials/services/connect-applications-service/)
