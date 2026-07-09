# Lab 4.4 - Endpoints & Headless Services

## Objective
Understand how Kubernetes Services use EndpointSlices (the modern successor to the legacy `v1 Endpoints` API) to track backend pods. Compare normal ClusterIP services with headless services and their DNS behavior.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Deploy the backend

```bash
kubectl apply -f deployment.yaml
```

### 2. Create the normal ClusterIP service

```bash
kubectl apply -f service.yaml
```

### 3. Create the headless service

```bash
kubectl apply -f headless-service.yaml
```

### 4. Inspect endpoints of the normal service

```bash
kubectl get endpointslices -n training -l kubernetes.io/service-name=httpd-svc
```

You should see 3 IPs in the `ENDPOINTS` column, one for each pod.

### 5. Inspect endpoints of the headless service

```bash
kubectl get endpointslices -n training -l kubernetes.io/service-name=httpd-headless
```

Same 3 IPs.

### 6. Compare the service IPs

```bash
kubectl get svc -n training
```

- `httpd-svc`: has a ClusterIP assigned
- `httpd-headless`: shows `None` for ClusterIP

### 7. Test DNS for the normal service

```bash
kubectl run dns-test --image=busybox:1.36 -n training --rm -it --restart=Never -- nslookup httpd-svc.training.svc.cluster.local
```

A normal service returns the **single ClusterIP** of the service.

### 8. Test DNS for the headless service

```bash
kubectl run dns-test2 --image=busybox:1.36 -n training --rm -it --restart=Never -- nslookup httpd-headless.training.svc.cluster.local
```

A headless service returns **all pod IPs directly**. Each pod gets its own A record.

### 9. Scale and observe endpoint changes

```bash
kubectl scale deployment httpd-deploy --replicas=5 -n training
kubectl get endpointslices -n training -l kubernetes.io/service-name=httpd-svc
kubectl get endpointslices -n training -l kubernetes.io/service-name=httpd-headless
```

Both EndpointSlices now list 5 IPs.

### 10. Describe endpoints for details

```bash
kubectl describe endpointslices -n training -l kubernetes.io/service-name=httpd-svc
```

Shows which pods are backing the service, grouped by ready/not-ready. (The legacy per-service command still works too: `kubectl describe endpoints httpd-svc -n training` - but `EndpointSlice` is what `kube-proxy` and CoreDNS actually read.)

### 11. Understand when to use headless services

- **Normal Service**: load balancing via ClusterIP, clients see one IP
- **Headless Service**: no load balancing, clients get all pod IPs directly
- **Use cases for headless**: StatefulSets (stable network identity), client-side load balancing, service discovery

## Verification

```bash
# Both services exist
kubectl get svc -n training | grep httpd

# Both have EndpointSlices
kubectl get endpointslices -n training | grep httpd

# DNS returns different results
kubectl run verify-dns --image=busybox:1.36 -n training --rm -it --restart=Never -- sh -c 'nslookup httpd-svc.training.svc.cluster.local && echo "---" && nslookup httpd-headless.training.svc.cluster.local'
```

## Cleanup

```bash
kubectl delete -f service.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f headless-service.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f deployment.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Services without selectors](https://kubernetes.io/docs/concepts/services-networking/service/#services-without-selectors) - concept reference
- [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services) - concept reference
- [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/) - concept reference
