# Lab 4.2 - CoreDNS & Service Discovery

## Objective
Understand how pods discover and reach each other by name instead of by IP. Expose a pod via a Service, then resolve and call it through CoreDNS - by FQDN, by short name, and across namespaces.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Deploy the web server pod

```bash
kubectl apply -f pod-a.yaml
kubectl wait --for=condition=Ready pod/web-server -n training --timeout=60s
```

### 2. Deploy the test client pod

```bash
kubectl apply -f pod-b.yaml
kubectl wait --for=condition=Ready pod/test-client -n training --timeout=60s
```

### 3. Expose the web server via a Service

Pod IPs change every time a pod is recreated, so pods discover each other through a stable Service name resolved by CoreDNS instead:

```bash
kubectl expose pod web-server -n training --port=80 --name=web-svc
```

### 4. Test DNS resolution from the client

```bash
kubectl exec test-client -n training -- nslookup web-svc.training.svc.cluster.local
```

CoreDNS resolves the Service's fully-qualified domain name (FQDN) to its stable ClusterIP.

### 5. Access via DNS name

```bash
kubectl exec test-client -n training -- wget -qO- http://web-svc.training.svc.cluster.local
```

### 6. Test short DNS names

Within the same namespace, you can use short names:

```bash
kubectl exec test-client -n training -- wget -qO- http://web-svc
```

### 7. Inspect the pod's DNS configuration

```bash
kubectl exec test-client -n training -- cat /etc/resolv.conf
```

Notice:
- `nameserver`: points to CoreDNS ClusterIP
- `search`: includes `training.svc.cluster.local`, `svc.cluster.local`, `cluster.local`

The `search` list is what makes the short name in Step 6 work: the resolver tries each suffix in order until one resolves.

### 8. Test cross-namespace DNS resolution

Short names only work within the same namespace; reaching a Service in another namespace needs at least `<service>.<namespace>`. First prove DNS resolves across namespaces:

```bash
kubectl exec test-client -n training -- nslookup kubernetes.default.svc.cluster.local
kubectl exec test-client -n training -- nslookup ingress-nginx-controller.ingress-nginx.svc.cluster.local
```

Then do an actual HTTP round-trip. **Not** against the `kubernetes` Service - that only exposes port 443:

```bash
kubectl get svc kubernetes -n default   # PORT(S) is 443/TCP - no port 80
```

Use `ingress-nginx-controller.ingress-nginx` instead (it listens on port 80):

```bash
kubectl exec test-client -n training -- wget -qO- --timeout=5 \
  http://ingress-nginx-controller.ingress-nginx.svc.cluster.local
```

Expect `HTTP/1.1 404 Not Found` - **that's the success signal**. You reached the ingress controller in a different namespace by name and got an HTTP response; the 404 is because no Ingress rule matches the bare request.

## Verification

```bash
# Both pods running
kubectl get pods -n training -o wide

# Service exists
kubectl get svc web-svc -n training

# DNS resolution works
kubectl exec test-client -n training -- nslookup web-svc.training.svc.cluster.local

# HTTP via DNS name works
kubectl exec test-client -n training -- wget -qO- http://web-svc.training.svc.cluster.local
```

## Cleanup

```bash
kubectl delete -f pod-a.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pod-b.yaml --ignore-not-found --force --grace-period=0
kubectl delete svc web-svc -n training --ignore-not-found --force --grace-period=0
```

## Further reading
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) - concept reference
- [Debugging DNS Resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/) - task walkthrough
- [Customizing DNS Service](https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/) - task walkthrough
