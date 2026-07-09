# Exercise 4.1 - Solutions

Reference manifests are in `solution/`. Namespace `net41` is assumed to exist (see the exercise Setup).

## Task 1 - Deployment + ClusterIP

```bash
kubectl apply -f solution/deployment.yaml
kubectl apply -f solution/service-clusterip.yaml
kubectl rollout status deployment/hello -n net41 --timeout=60s
```

Curl the ClusterIP from a throwaway pod (a ClusterIP is only reachable from inside the cluster):

```bash
CIP=$(kubectl get svc hello-cip -n net41 -o jsonpath='{.spec.clusterIP}')
kubectl run tmp --image=busybox:1.36 -n net41 --restart=Never -i --rm -- wget -qO- http://$CIP
```

Expected (illustrative - the ClusterIP is env-specific):

```
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```

See what wires the Service to its pods:

```bash
kubectl get endpointslices -n net41 -l kubernetes.io/service-name=hello-cip
```

Expected (pod IPs are illustrative):

```
NAME              ADDRESSTYPE   PORTS   ENDPOINTS                             AGE
hello-cip-abcde   IPv4          80      10.244.1.5,10.244.1.6,10.244.1.7      20s
```

**Answer to the reflective question:** the Service's `spec.selector` (`app: hello`) is matched against
pod labels; the endpoints controller keeps an **EndpointSlice** (the modern successor to the legacy
`Endpoints` object) populated with the IPs of every Ready pod that matches. `kube-proxy` programs the
node's dataplane from that slice. The Service never targets pods by name - it targets whatever the
selector matches, which is why scaling or replacing pods just works.

## Task 2 - NodePort

```bash
kubectl apply -f solution/service-nodeport.yaml
```

Discover the node IP by role label (not by name - node names differ between clusters):

```bash
NODE_IP=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
# the NodePort takes a moment to be programmed on the node - retry until it answers
for i in $(seq 1 20); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://$NODE_IP:30411)
  [ "$code" = 200 ] && break
  sleep 2
done
curl -s -o /dev/null -w '%{http_code}\n' http://$NODE_IP:30411
```

Expected:

```
200
```

**Answer to the reflective question:** a NodePort Service opens the same port (`30411`) on **every
node's** external network interface and forwards it to the Service (and on to a backing pod). That
port is reachable from outside the cluster. A ClusterIP lives only on the internal cluster network
(the virtual service CIDR programmed into each node by `kube-proxy`), so nothing outside the cluster
can route to it. NodePort is a superset: it *is* a ClusterIP plus the per-node port.

## Task 3 - LoadBalancer stays Pending

```bash
kubectl apply -f solution/service-loadbalancer.yaml
kubectl get svc hello-lb -n net41
```

Expected - `EXTERNAL-IP` is `<pending>`:

```
NAME       TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
hello-lb   LoadBalancer   10.96.71.10    <pending>     80:31207/TCP   10s
```

Confirm all three Services front the same pods:

```bash
kubectl get endpointslices -n net41
```

**Answer to the reflective question:** `type: LoadBalancer` asks an **external load-balancer
controller** (a cloud provider's, or MetalLB on bare metal) to provision a real external IP. This
cluster has no such controller, so nothing fulfils the request and `EXTERNAL-IP` stays `<pending>`
indefinitely - that is expected, not a failure. A LoadBalancer Service is a NodePort underneath (note
the auto-assigned `31207` above), so the pods are still reachable **right now** via `NODE_IP:<that
nodePort>` - exactly the path an external load balancer would forward to.

## Cleanup

```bash
kubectl delete ns net41 --ignore-not-found
```
