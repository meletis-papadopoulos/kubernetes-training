# Lab 2.3 - Deployments & ReplicaSets

## Objective
Learn how to create, inspect, and scale Kubernetes Deployments. Understand how Deployments manage ReplicaSets and Pods.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Create the Deployment

```bash
kubectl apply -f deployment.yaml
```

### 2. Verify the Deployment was created

```bash
kubectl get deployments -n training
```

You should see `web-deployment` with 3/3 replicas ready.

### 3. Inspect the Deployment details

```bash
kubectl describe deployment web-deployment -n training
```

Note the following in the output:
- **Replicas:** 3 desired, 3 updated, 3 available
- **Selector:** app=web
- **Pod Template:** shows the nginx container spec
- **Events:** shows the ReplicaSet creation

### 4. List Pods created by the Deployment

```bash
kubectl get pods -n training -l app=web
```

All 3 pods should be in `Running` state. Each pod name starts with `web-deployment-` followed by the ReplicaSet hash and a unique suffix.

### 5. Check the ReplicaSet

```bash
kubectl get replicasets -n training
```

The Deployment created a ReplicaSet to manage the pods.

### 6. Scale the Deployment to 5 replicas

```bash
kubectl scale deployment web-deployment --replicas=5 -n training
```

### 7. Verify scaling

```bash
kubectl get deployment web-deployment -n training
kubectl get pods -n training -l app=web
```

You should see 5 pods running.

### 8. Scale back to 3 replicas

```bash
kubectl scale deployment web-deployment --replicas=3 -n training
```

### 9. Verify scale-down

```bash
kubectl get pods -n training -l app=web
```

Two pods should be terminating or already gone, leaving 3.

### 10. Explore imperative creation (alternative)

You can also create deployments imperatively:

```bash
kubectl create deployment test-deploy --image=nginx --replicas=2 -n training --dry-run=client -o yaml
```

This shows the YAML that would be generated without actually creating it.

## Verification

```bash
# Confirm deployment exists with 3 replicas
kubectl get deployment web-deployment -n training -o jsonpath='{.spec.replicas}'
# Should output: 3

# Confirm all pods are running
kubectl get pods -n training -l app=web --no-headers | wc -l
# Should output: 3

# Confirm all pods are Ready
kubectl get pods -n training -l app=web -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}'
# Should output: Running (3 times)
```

## Cleanup

```bash
kubectl delete -f deployment.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) - concept reference
- [Run a stateless application](https://kubernetes.io/docs/tasks/run-application/run-stateless-application-deployment/) - task walkthrough
- [`kubectl scale`](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#scale) - command reference
