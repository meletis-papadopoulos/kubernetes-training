# Exercise 9.4 - Fix a Service with No Endpoints

*Domain: Troubleshooting. Target: ~8 min. Do not open `solution/` until you have tried.*

This is a **fix-it** exercise: `setup.yaml` ships a healthy Deployment plus a broken Service.
Diagnose the fault from the cluster, then apply the minimal fix.

## Setup

```bash
kubectl create namespace ts94
kubectl apply -f setup.yaml
kubectl rollout status deployment/payments -n ts94 --timeout=60s
```

## Tasks

1. Three `payments` Pods are `Running` in namespace `ts94`, but a request to the `payments` Service
   times out. From a throwaway client, confirm the failure:
   ```bash
   SVC_IP=$(kubectl get svc payments -n ts94 -o jsonpath='{.spec.clusterIP}')
   kubectl run curl-check --image=curlimages/curl:8.10.1 -n ts94 -i --rm --restart=Never -- \
     curl -s --max-time 5 -o /dev/null -w "code=%{http_code}\n" "http://$SVC_IP" || echo "FAILED"
   ```
   Diagnose why: inspect the Service's backing endpoints with
   `kubectl get endpointslices -n ts94 -l kubernetes.io/service-name=payments` and compare the
   Service's `spec.selector` against the Pods' actual labels. Fix the Service so it has 3 endpoints
   and the curl returns HTTP `200`.

2. Reflective: the Pods were healthy the whole time - `kubectl get pods` showed `Running` and the
   Deployment was fully rolled out. Which single object was misconfigured, and what is the fastest
   one-command signal that a Service selector doesn't match any Pods (versus a port mismatch, where
   endpoints **do** appear but traffic still fails)?

## Acceptance criteria

- The `payments` Service in `ts94` lists **3** endpoint IPs, and the curl check returns `code=200`.
- You identify the fault as a **selector mismatch**: Service selects `app=payment`, Pods are labelled
  `app=payments`.
- You name `kubectl get endpointslices` showing an **empty** `ENDPOINTS` column as the fingerprint of
  a selector mismatch.

## Docs you may reference

- [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)
- [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
