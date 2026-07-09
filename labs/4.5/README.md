# Lab 4.5 - Ingress

## Objective
Learn how to expose multiple services through a single Ingress resource using path-based routing with the nginx ingress controller.

## Prerequisites
- cluster provisioned with `provision.sh` (check ingress IP with `kubectl get svc -n ingress-nginx`)
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Deploy both applications

```bash
kubectl apply -f deployment-app1.yaml
kubectl apply -f deployment-app2.yaml
```

### 2. Create services for both apps

```bash
kubectl apply -f service-app1.yaml
kubectl apply -f service-app2.yaml
```

### 3. Verify deployments and services

```bash
kubectl get deployments,svc -n training
```

### 4. Create the Ingress resource

```bash
kubectl apply -f ingress.yaml
```

### 5. Inspect the Ingress

```bash
kubectl get ingress -n training
kubectl describe ingress training-ingress -n training
```

Note the rules: `/app1` routes to `app1-svc:80`, `/app2` routes to `app2-svc:80`.

### 6. Test path-based routing for app1

```bash
kubectl rollout status deployment/app1 -n training --timeout=60s
kubectl rollout status deployment/app2 -n training --timeout=60s
NODE_IP=$(kubectl get node controlplane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

# The pods are Ready, but ingress-nginx needs a moment to sync the new Service
# endpoints into its config - until it does you'll get 503. httpd (app2) often syncs a
# beat after nginx (app1), so poll until BOTH backends return 200:
for i in $(seq 1 20); do
  c1=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: training.local' http://$NODE_IP:30080/app1)
  c2=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: training.local' http://$NODE_IP:30080/app2)
  [ "$c1" = "200" ] && [ "$c2" = "200" ] && break
  echo "waiting for ingress backends to sync (app1=$c1 app2=$c2)..."; sleep 3
done

curl -s -H 'Host: training.local' http://$NODE_IP:30080/app1
```

You should see the nginx welcome page (app1 is nginx). **A brief `503` before this is normal** - it means the Ingress object exists but the controller hasn't wired the Service's endpoints into its backend yet (watch for it in the controller logs in step 9).

### 7. Test path-based routing for app2

```bash
curl -s -H 'Host: training.local' http://$NODE_IP:30080/app2
```

You should see "It works!" (app2 is httpd).

### 8. Test without the Host header

```bash
curl -s http://$NODE_IP:30080/app1
```

This may return a 404 because the Ingress requires the Host header `training.local`.

### 9. Check ingress controller logs

```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=20
```

### 10. Understand the rewrite annotation

The annotation `nginx.ingress.kubernetes.io/rewrite-target: /` rewrites the URL path. When a request hits `/app1`, the ingress controller forwards it to the backend as `/` (stripping `/app1`). Without this, nginx would try to serve `/app1` which does not exist.

## Verification

```bash
# Ingress exists and has address
kubectl get ingress training-ingress -n training

# Both paths work
NODE_IP=$(kubectl get node controlplane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
curl -s -o /dev/null -w '%{http_code}' -H 'Host: training.local' http://$NODE_IP:30080/app1
# Should return: 200

curl -s -o /dev/null -w '%{http_code}' -H 'Host: training.local' http://$NODE_IP:30080/app2
# Should return: 200
```

## Cleanup

```bash
kubectl delete -f ingress.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f service-app1.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f service-app2.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f deployment-app1.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f deployment-app2.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) - concept reference
- [Ingress Controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/) - concept reference
- [ingress-nginx documentation](https://kubernetes.github.io/ingress-nginx/) - official controller docs
