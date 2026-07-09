# Exercise 4.3 - Solutions

Reference manifests are in `solution/`. Namespaces `net43a` and `net43b` are assumed to exist
(see the exercise Setup).

## Task 1 - reach a pod by IP across namespaces

```bash
kubectl apply -f solution/server.yaml
kubectl apply -f solution/client.yaml
kubectl rollout status deployment/server -n net43a --timeout=60s
kubectl wait --for=condition=Ready pod/client -n net43b --timeout=60s
```

Grab one pod IP and curl it directly from the client in the *other* namespace:

```bash
POD_IP=$(kubectl get pods -n net43a -l app=server -o jsonpath='{.items[0].status.podIP}')
kubectl exec client -n net43b -- wget -qO- http://$POD_IP | head -4
```

Expected:

```
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

**Answer to the reflective question:** it succeeds with **no special routing**. The Kubernetes network
model requires every pod to reach every other pod's IP directly, without NAT, regardless of node or
namespace - namespaces are an API/RBAC boundary, not a network boundary (that is what NetworkPolicy in
Exercise 4.7 adds). The CNI plugin provides this flat, routable pod network.

## Task 2 - reach it through the Service (survives pod replacement)

```bash
kubectl exec client -n net43b -- \
  wget -qO- http://server-svc.net43a.svc.cluster.local | head -4
```

Replace a pod, then call again:

```bash
VICTIM=$(kubectl get pods -n net43a -l app=server -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod "$VICTIM" -n net43a --force --grace-period=0
kubectl rollout status deployment/server -n net43a --timeout=60s
kubectl exec client -n net43b -- \
  wget -qO- http://server-svc.net43a.svc.cluster.local | head -4
```

Expected (both calls): the nginx welcome page.

**Answer to the reflective question:** the pod IP you used in Task 1 belongs to a single pod and is
gone the moment that pod is replaced - the replacement gets a **new** IP. The Service is a stable name
and ClusterIP whose backing EndpointSlice is continuously reconciled by the endpoints controller, so it
always points at the current Ready pods. Prefer the Service: pod IPs are ephemeral, Service identity is
durable.

## Task 3 - observe load-balancing

```bash
for i in $(seq 1 12); do
  kubectl exec client -n net43b -- \
    wget -qO- http://server-svc.net43a.svc.cluster.local >/dev/null
done
kubectl logs -n net43a -l app=server --prefix --tail=20 | grep 'GET / '
```

Expected - the GET lines carry more than one pod prefix (pod names/counts illustrative):

```
[pod/server-6c...-abcde/nginx] 10.244.2.9 - - [..] "GET / HTTP/1.1" 200 ...
[pod/server-6c...-fghij/nginx] 10.244.1.4 - - [..] "GET / HTTP/1.1" 200 ...
[pod/server-6c...-klmno/nginx] 10.244.2.3 - - [..] "GET / HTTP/1.1" 200 ...
```

**Answer to the reflective question:** `kube-proxy` (via the iptables/IPVS or eBPF dataplane it
programs from the Service's EndpointSlice) distributes new connections across the Ready endpoints. The
Service object itself is just declarative intent; `kube-proxy` on each node is what actually spreads
the traffic.

## Cleanup

```bash
kubectl delete ns net43a net43b --ignore-not-found
```
