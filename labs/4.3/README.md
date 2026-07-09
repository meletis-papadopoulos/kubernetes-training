# Lab 4.3 - Pod-to-Pod Connectivity

## Objective
Understand how pods communicate directly with each other inside a Kubernetes cluster. Deploy two pods, find their IPs, and test connectivity by IP - then see why pod IPs alone aren't a stable way to reach a workload.

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

### 3. Get the web server's IP address

```bash
kubectl get pod web-server -n training -o wide
```

Note the IP address from the IP column.

### 4. Test connectivity from client to server by IP

```bash
kubectl exec test-client -n training -- wget -qO- $(kubectl get pod web-server -n training -o jsonpath='{.status.podIP}')
```

This resolves the web server's pod IP inline and curls it directly. You should see the nginx welcome page HTML.

### 5. Get both pod IPs for comparison

```bash
kubectl get pods -n training -o wide
```

Both pods have unique IPs from the cluster's pod network, and every pod can reach every other pod's IP directly - no NAT, regardless of which node they landed on. That flat, routable network model is a core Kubernetes networking requirement, provided by the cluster's CNI plugin.

### 6. Observe that pod IPs are ephemeral

Delete and recreate the web server pod:

```bash
kubectl delete pod web-server -n training --force --grace-period=0
kubectl apply -f pod-a.yaml
kubectl wait --for=condition=Ready pod/web-server -n training --timeout=60s
kubectl get pod web-server -n training -o wide
```

Compare this IP to the one you noted in Step 3 - it has changed. A pod's IP is only stable for the pod's lifetime; recreating a pod (even from the exact same manifest) gets it a new IP. Never hardcode a pod IP in application config.

### 7. Confirm connectivity still works via the new IP

```bash
kubectl exec test-client -n training -- wget -qO- $(kubectl get pod web-server -n training -o jsonpath='{.status.podIP}')
```

Direct IP connectivity still works - but you had to look the new IP up again. This is exactly the problem Services solve: a stable name and address in front of pods whose IPs keep changing.

## Verification

```bash
# Both pods running
kubectl get pods -n training -o wide

# Direct IP connectivity works
WEB_IP=$(kubectl get pod web-server -n training -o jsonpath='{.status.podIP}')
kubectl exec test-client -n training -- wget -qO- $WEB_IP
```

## Cleanup

```bash
kubectl delete -f pod-a.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pod-b.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Cluster Networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/) - concept reference
- [The Kubernetes Network Model](https://kubernetes.io/docs/concepts/services-networking/#the-kubernetes-network-model) - concept reference
- [Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) - concept reference
