# Lab 9.4 - Service Problems

## Objective
Learn to diagnose and fix service connectivity issues. Two distinct failures look similar from the outside (no traffic gets through) but have different fingerprints in `kubectl get endpointslices`: **selector mismatch** (no endpoints at all) and **port mismatch** (endpoints exist, but targetPort doesn't match the pod's listening port).

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### Part A: Selector mismatch (no endpoints)

### 1. Deploy the backend

```bash
kubectl apply -f deployment.yaml
kubectl rollout status deployment/svc-debug-web -n training --timeout=60s
```

### 2. Verify pods are running

```bash
kubectl get pods -n training -l app=web
```

All 3 pods should be `Running` with label `app=web`.

### 3. Deploy the BROKEN service

```bash
kubectl apply -f service-broken.yaml
sleep 10
```

The `sleep` lets the EndpointSlice controller reconcile - without it, a curl right after `apply` may still hit cached endpoints from a prior selector and succeed misleadingly.

### 4. Try to access the service

```bash
curl -s --max-time 3 $(kubectl get svc svc-debug -n training -o jsonpath='{.spec.clusterIP}') || echo "CONNECTION FAILED"
```

The connection fails or times out.

### 5. Diagnose: check endpoints

```bash
kubectl get endpointslices -n training -l kubernetes.io/service-name=svc-debug
```

The `ENDPOINTS` column is **empty** (no IPs). This means the service selector does not match any pods.

### 6. Compare the selector

```bash
# Service selector
kubectl get svc svc-debug -n training -o jsonpath='{.spec.selector}'
# Shows: {"app":"wrong"}

# Pod labels
kubectl get pods -n training --show-labels | grep svc-debug-web
# Shows: app=web
```

The service selects `app=wrong` but pods have `app=web`. This is the mismatch.

### 7. Fix the service

```bash
kubectl apply -f service-fixed.yaml
```

### 8. Verify endpoints now exist

```bash
kubectl get endpointslices -n training -l kubernetes.io/service-name=svc-debug
```

Should show 3 IPs in the `ENDPOINTS` column (one per pod).

### 9. Test the fixed service

```bash
curl -s $(kubectl get svc svc-debug -n training -o jsonpath='{.spec.clusterIP}')
```

You should see the nginx welcome page.

### 10. Additional service debugging techniques

```bash
# Check service details
kubectl describe svc svc-debug -n training

# Check if targetPort matches the container port
kubectl get svc svc-debug -n training -o jsonpath='{.spec.ports[0].targetPort}'
kubectl get pods -n training -l app=web -o jsonpath='{.items[0].spec.containers[0].ports[0].containerPort}'

# DNS resolution
kubectl run dns-check --image=busybox:1.36 -n training --rm -it --restart=Never -- nslookup svc-debug.training.svc.cluster.local
```

---

### Part B: Port mismatch (endpoints exist, traffic still fails)

This is the trickier failure mode. `kubectl get endpointslices` shows the pod IPs, the service looks healthy at first glance, but connections still fail.

### 11. Apply a service whose targetPort does not match the pod's containerPort

```bash
kubectl apply -f service-port-mismatch.yaml
```

The pods listen on port 80, but `targetPort: 8080`.

### 12. Confirm - endpoints exist this time

```bash
kubectl get endpointslices -n training -l kubernetes.io/service-name=svc-port-mismatch
```

Output:

```
NAME                        ADDRESSTYPE   PORTS   ENDPOINTS
svc-port-mismatch-x7k2p     IPv4          8080    10.244.x.x,10.244.x.x,10.244.x.x
```

Three endpoints - selector matched. So why doesn't the service work?

### 13. Test it - connection fails

```bash
SVC_IP=$(kubectl get svc svc-port-mismatch -n training -o jsonpath='{.spec.clusterIP}')
kubectl run curl-check --image=curlimages/curl:8.10.1 -n training --rm -it --restart=Never -- \
  curl -s --max-time 5 -o /dev/null -w "exit=%{http_code}\n" "http://$SVC_IP"
```

You'll see `exit=000` (timeout / connection refused) - even though endpoints are present.

### 14. Diagnose - compare service targetPort vs container's listening port

```bash
kubectl get svc svc-port-mismatch -n training -o jsonpath='targetPort={.spec.ports[0].targetPort}{"\n"}'
kubectl get pods -n training -l app=web -o jsonpath='containerPort={.items[0].spec.containers[0].ports[0].containerPort}{"\n"}'
```

Output:

```
targetPort=8080
containerPort=80
```

The service forwards to port 8080 on each pod, but the pod's nginx is listening on port 80. kube-proxy / Cilium dutifully forwards the packet - the pod just RSTs because nothing is on 8080.

The `PORTS` column the EndpointSlice publishes (`8080`) is the giveaway - it inherits the service's `targetPort`, not the pod's actual listening port. If you compare that port with what the pod actually listens on, the mismatch is obvious.

### 15. Fix: align targetPort with the pod's containerPort

```bash
kubectl patch svc svc-port-mismatch -n training --type=json -p='[
  {"op": "replace", "path": "/spec/ports/0/targetPort", "value": 80}
]'
```

Re-test:

```bash
kubectl run curl-check --image=curlimages/curl:8.10.1 -n training --rm -it --restart=Never -- \
  curl -s --max-time 5 -o /dev/null -w "exit=%{http_code}\n" "http://$SVC_IP"
```

You should now see `exit=200`.

---

### 16. Common service problems checklist

| Symptom | Likely cause | Diagnostic |
|---|---|---|
| `get endpointslices` shows empty `ENDPOINTS` | Selector / pod labels mismatch | Compare `svc.spec.selector` to `pod.metadata.labels` |
| Endpoints present, connection refused | targetPort vs containerPort mismatch | Compare endpoint port to pod's listening port |
| Endpoints present, intermittent failures | Some pods not Ready (readiness probe failing) | `kubectl get pod` `READY` column |
| Service in wrong namespace | Cross-namespace name resolution | Use FQDN: `svc.namespace.svc.cluster.local` |
| No DNS resolution | CoreDNS not running / wrong nameserver | `kubectl run debug --image busybox:1.36 -- nslookup svc.namespace` |

## Verification

```bash
# Service has endpoints
kubectl get endpointslices -n training -l kubernetes.io/service-name=svc-debug

# Service is accessible
curl -s -o /dev/null -w '%{http_code}' $(kubectl get svc svc-debug -n training -o jsonpath='{.spec.clusterIP}')
# Should return: 200
```

## Cleanup

```bash
kubectl delete -f service-fixed.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f service-port-mismatch.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f deployment.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/) - task walkthrough
- [Service](https://kubernetes.io/docs/concepts/services-networking/service/) - concept reference (selectors/endpoints)
