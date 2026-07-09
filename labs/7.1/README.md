# Lab 7.1 - Namespaces

## Objective
Learn how namespaces provide logical isolation in a Kubernetes cluster. Create a namespace with labels, apply resource constraints, deploy workloads, and understand namespace isolation.

## Prerequisites
- cluster provisioned with `provision.sh`

## Steps

### 1. List existing namespaces

```bash
kubectl get namespaces
```

Default namespaces:
- `default`: for resources with no specified namespace
- `kube-system`: for Kubernetes system components
- `kube-public`: readable by all, used for cluster info
- `kube-node-lease`: for node heartbeat leases

### 2. Create the namespace with labels

```bash
kubectl apply -f namespace.yaml
```

### 3. Verify namespace labels

```bash
kubectl get namespace ns-lab --show-labels
```

### 4. Apply resource constraints

```bash
kubectl apply -f resourcequota.yaml
kubectl apply -f limitrange.yaml
```

### 5. Verify constraints

```bash
kubectl describe namespace ns-lab
```

This shows the quota and limit range applied to the namespace.

### 6. Deploy a workload

```bash
kubectl apply -f deployment.yaml
```

### 7. Verify the deployment

```bash
kubectl get all -n ns-lab
```

### 8. Check resource usage against quota

```bash
kubectl describe resourcequota ns-quota -n ns-lab
```

The "Used" column shows resources consumed by the deployment.

### 9. Check that LimitRange applied default resources

```bash
kubectl get pods -n ns-lab -o jsonpath='{range .items[*]}{.metadata.name}{": cpu="}{.spec.containers[0].resources.requests.cpu}{", mem="}{.spec.containers[0].resources.requests.memory}{"\n"}{end}'
```

Even though the deployment did not specify resources, the LimitRange applied defaults.

### 10. Test namespace isolation

Resources in different namespaces are isolated by default:

```bash
# This pod is in ns-lab
kubectl get pods -n ns-lab

# Cannot see it from the default namespace
kubectl get pods -n default
```

### 11. Cross-namespace communication

While resources are logically isolated, network traffic can still flow between namespaces (unless NetworkPolicies block it). Verify cross-namespace DNS resolution from a pod in `ns-lab` to the `kubernetes` Service in `default`:

```bash
kubectl run cross-ns-test --image=busybox:1.36 -n ns-lab --rm -i --restart=Never -- nslookup kubernetes.default.svc.cluster.local
```

You'll see the Service's ClusterIP resolved from within `ns-lab`. (Actually connecting would require HTTPS on port 443 - busybox wget's TLS support is unreliable; DNS resolution alone proves the namespace boundary isn't a network boundary.)

### 12. Switch default namespace context

```bash
kubectl config set-context --current --namespace=ns-lab
kubectl get pods
# Shows pods in ns-lab without -n flag

# Switch back
kubectl config set-context --current --namespace=default
```

### 13. List resources across all namespaces

```bash
kubectl get pods --all-namespaces
# or shorter:
kubectl get pods -A
```

### 14. Understand namespace-scoped vs cluster-scoped resources

```bash
# Namespace-scoped resources
kubectl api-resources --namespaced=true | head -20

# Cluster-scoped resources
kubectl api-resources --namespaced=false
```

Cluster-scoped resources (Nodes, PVs, ClusterRoles, Namespaces) are NOT inside any namespace.

## Verification

```bash
# Namespace exists with labels
kubectl get ns ns-lab --show-labels

# Quota is enforced
kubectl describe resourcequota ns-quota -n ns-lab

# Deployment is running
kubectl get deployment ns-web -n ns-lab
```

## Cleanup

```bash
kubectl delete namespace ns-lab --ignore-not-found --force --grace-period=0
```

## Further reading
- [Namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) - concept reference
- [Share a Cluster with Namespaces](https://kubernetes.io/docs/tasks/administer-cluster/namespaces-walkthrough/) - task walkthrough
