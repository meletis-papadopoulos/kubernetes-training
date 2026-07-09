# Exercise 4.4 - Solutions

Reference manifests are in `solution/`. Namespace `net44` is assumed to exist (see the exercise Setup).
`busybox:1.28` is used for DNS lookups (its `nslookup` prints all A records cleanly).

## Task 1 - headless Service returns per-pod A records

```bash
kubectl apply -f solution/deployment.yaml
kubectl apply -f solution/headless-service.yaml
kubectl rollout status deployment/hnode -n net44 --timeout=60s
```

```bash
kubectl run dnstmp --image=busybox:1.28 -n net44 --restart=Never -i --rm -- \
  nslookup hnode-headless.net44.svc.cluster.local
```

Expected - **three** addresses, one per pod (IPs illustrative):

```
Name:      hnode-headless.net44.svc.cluster.local
Address 1: 10.244.1.11
Address 2: 10.244.2.7
Address 3: 10.244.1.12
```

**Answer to the reflective question:** a headless Service (`clusterIP: None`) has no VIP, so CoreDNS
returns the **A records of every Ready backing pod directly** - here, 3 addresses. A normal ClusterIP
Service returns a *single* address (its ClusterIP) and lets `kube-proxy` load-balance. Headless hands
the full pod list to the client, which is how StatefulSets give each pod a stable, individually
addressable name.

## Task 2 - inspect the EndpointSlice

```bash
kubectl get endpointslices -n net44 -l kubernetes.io/service-name=hnode-headless \
  -o custom-columns=NAME:.metadata.name,ADDRESSES:.endpoints[*].addresses
kubectl get pods -n net44 -l app=hnode -o wide
```

Expected - the slice's addresses match the three pod IPs:

```
NAME                   ADDRESSES
hnode-headless-x9k2p   [10.244.1.11 10.244.2.7 10.244.1.12]

NAME                     READY   STATUS    IP            NODE
hnode-6f...-aaaaa        1/1     Running   10.244.1.11   worker
hnode-6f...-bbbbb        1/1     Running   10.244.2.7    worker
hnode-6f...-ccccc        1/1     Running   10.244.1.12   controlplane
```

**Answer to the reflective question:** the EndpointSlice is the source of truth CoreDNS reads to build
those per-pod A records; each listed address is exactly one Ready pod matched by the Service selector.

## Task 3 - break the selector (silent failure)

```bash
kubectl apply -f solution/headless-service-broken.yaml
kubectl get svc hnode-headless -n net44
kubectl get endpointslices -n net44 -l kubernetes.io/service-name=hnode-headless \
  -o custom-columns=NAME:.metadata.name,ADDRESSES:.endpoints[*].addresses
kubectl run dnstmp --image=busybox:1.28 -n net44 --restart=Never -i --rm -- \
  nslookup hnode-headless.net44.svc.cluster.local
```

Expected - the Service still lists fine, but endpoints are empty and DNS no longer resolves to pods:

```
NAME             TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
hnode-headless   ClusterIP   None         <none>        80/TCP    3m

NAME                   ADDRESSES
hnode-headless-x9k2p   <none>

*** Can't find hnode-headless.net44.svc.cluster.local: No answer
```

**Answer to the reflective question:** changing the selector to `app=hnode-typo` (which no pod carries)
leaves the Service object healthy-looking but its EndpointSlice drops to **zero addresses**, so DNS
returns no pod records and every client silently gets "connection refused" / no route. Detect it by
checking endpoints, not the Service: `kubectl get endpointslices -l kubernetes.io/service-name=<svc>`
showing `<none>` (or `kubectl describe svc <svc>` showing `Endpoints: <none>`) is the tell. Cross-check
`kubectl get svc <svc> -o jsonpath='{.spec.selector}'` against the actual pod labels
(`kubectl get pods --show-labels`).

## Cleanup

```bash
kubectl delete ns net44 --ignore-not-found
```
