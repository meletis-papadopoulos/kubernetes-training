# Exercise 4.4 - Endpoints & Headless Services

*Domain: Networking. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace net44
```

## Tasks

1. In the namespace `net44`, create a Deployment named `hnode` (`3` replicas, image `httpd:2.4.62`,
   label `app=hnode`, port `80`) and a **headless** Service named `hnode-headless` (`clusterIP: None`,
   selector `app=hnode`, port `80`). From a throwaway `busybox:1.28` pod, resolve
   `hnode-headless.net44.svc.cluster.local`. How many addresses come back, and how does that differ
   from what a normal ClusterIP Service returns?

2. Inspect the EndpointSlice(s) backing `hnode-headless`. How many endpoint IPs are listed, and how do
   they line up with the pod IPs of the three `hnode` pods? (Confirm with `get pods -o wide`.)

3. Now **break the selector**: re-apply the headless Service with its selector changed to
   `app=hnode-typo` (a label no pod carries). Re-check the EndpointSlice and re-run the DNS lookup.
   The Service still exists and looks healthy in `kubectl get svc` - but what changed for endpoints and
   DNS, and how would you *detect* this silent selector/label mismatch in practice?

## Acceptance criteria

- `hnode` is `3/3`; `hnode-headless` shows `CLUSTER-IP` = `None`.
- The headless DNS name resolves to **3 separate pod A records** (not one ClusterIP); its EndpointSlice
  lists the same 3 pod IPs.
- After the selector is broken, the EndpointSlice for `hnode-headless` lists **no addresses** and the
  DNS name no longer resolves to pod IPs - even though `kubectl get svc` still shows the Service.

## Docs you may reference

- [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)
- [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/)
