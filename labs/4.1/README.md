# Lab 4.1 - Services

## Objective
Learn the three main Service types in Kubernetes: ClusterIP (internal only), NodePort (node port exposure), and LoadBalancer (external IP provisioned by an external load-balancer controller - stays `<pending>` on a bare cluster with no such controller).

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Deploy the backend

```bash
kubectl apply -f deployment.yaml
kubectl rollout status deployment/web-deploy -n training --timeout=60s
```

### 2. Verify pods are running

```bash
kubectl get pods -n training -l app=web -o wide
```

### Part A: ClusterIP Service

### 3. Create the ClusterIP service

```bash
kubectl apply -f service-clusterip.yaml
```

### 4. Inspect the service

```bash
kubectl get svc web-clusterip -n training
kubectl describe svc web-clusterip -n training
```

Note the CLUSTER-IP -- this is only reachable from within the cluster.

### 5. Test ClusterIP from inside the cluster

```bash
curl -s $(kubectl get svc web-clusterip -n training -o jsonpath='{.spec.clusterIP}')
```

### Part B: NodePort Service

### 6. Create the NodePort service

```bash
kubectl apply -f service-nodeport.yaml
```

### 7. Inspect the service

```bash
kubectl get svc web-nodeport -n training
```

Note the NodePort (30090) in the PORT(S) column.

### 8. Test NodePort access

Get a node IP and test:

```bash
NODE_IP=$(kubectl get node controlplane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
curl -s $NODE_IP:30090
```

The service is accessible on port 30090 on ANY node.

### Part C: LoadBalancer Service

### 9. Create the LoadBalancer service

```bash
kubectl apply -f service-loadbalancer.yaml
```

### 10. Check the external IP - it stays `<pending>`

```bash
kubectl get svc web-loadbalancer -n training
```

The EXTERNAL-IP column shows `<pending>` and never resolves. A `type: LoadBalancer` Service asks an **external load-balancer controller** to provision an external IP. On a bare cluster with no such controller running, nothing fulfills the request and the IP stays `<pending>` indefinitely - that's expected here, not a failure.

Where an external load-balancer controller *is* running (e.g. MetalLB on bare metal, or a provider-supplied controller), it watches for LoadBalancer Services and provisions a real external IP, which then appears in EXTERNAL-IP within a minute or two.

### 11. Reach the pods without an external load balancer - use NodePort

A `type: LoadBalancer` Service is a NodePort Service *plus* an external load balancer in front of it, so even while EXTERNAL-IP is `<pending>` the pods are still reachable. On this cluster the working external-access path is the NodePort from Part B:

```bash
NODE_IP=$(kubectl get node controlplane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
curl -s $NODE_IP:30090
```

This is the same access method an external load balancer uses under the hood - it simply forwards external traffic to the node port for you.

### 12. Compare all three service types

```bash
kubectl get svc -n training
```

| Type | Accessible From | Use Case |
|------|----------------|----------|
| ClusterIP | Inside cluster only | Internal microservices |
| NodePort | Node IP + port (30000-32767) | Dev/testing, on-prem external access |
| LoadBalancer | External IP via an external load-balancer controller; `<pending>` without one | Production external access where a load-balancer controller is available |

### 13. Verify endpoints

```bash
kubectl get endpointslices -n training
```

All three services should have the same 3 pod IPs listed in the `ENDPOINTS` column, grouped into per-service `EndpointSlice` objects - proving service type only changes the *access method*, not the routing targets.

**`EndpointSlice` is the modern source of truth** that `kube-proxy` and CoreDNS actually read (better scaling: a large Service's backing IPs are sharded across multiple slices instead of one giant object). The older `v1 Endpoints` API (one object per Service, all IPs in one list) is being phased out (K8s v1.33+) - expect a deprecation warning on it - but it's still populated for legacy tooling:

```bash
kubectl get endpoints -n training   # legacy, still populated
```

## Verification

```bash
# All services exist
kubectl get svc -n training

# ClusterIP accessible internally
curl -s $(kubectl get svc web-clusterip -n training -o jsonpath='{.spec.clusterIP}') | head -5

# LoadBalancer stays <pending> on this cluster (no external load-balancer controller) - EXTERNAL-IP has no address
kubectl get svc web-loadbalancer -n training

# All services have endpoints
kubectl get endpointslices -n training
```

## Cleanup

```bash
kubectl delete -f service-clusterip.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f service-nodeport.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f service-loadbalancer.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f deployment.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Service](https://kubernetes.io/docs/concepts/services-networking/service/) - concept reference
- [Connecting Applications with Services](https://kubernetes.io/docs/tutorials/services/connect-applications-service/) - tutorial
- [`kubectl expose`](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#expose) - command reference
