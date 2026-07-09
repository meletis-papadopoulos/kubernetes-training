# Lab 7.2 - RBAC

## Objective
Learn how to configure RBAC with Roles, RoleBindings, ClusterRoles, and ClusterRoleBindings. Test permissions using `kubectl auth can-i` and by running kubectl from within a pod with a specific ServiceAccount.

## Prerequisites
- cluster provisioned with `provision.sh`

## Steps

### 1. Create the namespace

```bash
kubectl apply -f namespace.yaml
```

### 2. Create the ServiceAccount

```bash
kubectl apply -f serviceaccount.yaml
```

### 3. Create the Role (namespace-scoped)

```bash
kubectl apply -f role.yaml
```

### 4. Inspect the Role

```bash
kubectl describe role pod-reader-role -n rbac-lab
```

This Role only allows `get`, `list`, `watch` on `pods` in the `rbac-lab` namespace.

### 5. Create the RoleBinding

```bash
kubectl apply -f rolebinding.yaml
```

### 6. Test permissions with kubectl auth can-i

```bash
# Can the SA list pods in rbac-lab? (should be yes)
kubectl auth can-i list pods -n rbac-lab --as=system:serviceaccount:rbac-lab:pod-reader

# Can the SA delete pods? (should be no)
kubectl auth can-i delete pods -n rbac-lab --as=system:serviceaccount:rbac-lab:pod-reader

# Can the SA list pods in a different namespace? (should be no)
kubectl auth can-i list pods -n default --as=system:serviceaccount:rbac-lab:pod-reader

# Can the SA list deployments? (should be no)
kubectl auth can-i list deployments -n rbac-lab --as=system:serviceaccount:rbac-lab:pod-reader
```

### 7. Create the ClusterRole

```bash
kubectl apply -f clusterrole.yaml
```

### 8. Create the ClusterRoleBinding

```bash
kubectl apply -f clusterrolebinding.yaml
```

### 9. Test cluster-wide permissions

```bash
# Can the SA list nodes? (should be yes - ClusterRole)
kubectl auth can-i list nodes --as=system:serviceaccount:rbac-lab:pod-reader

# Can the SA delete nodes? (should be no)
kubectl auth can-i delete nodes --as=system:serviceaccount:rbac-lab:pod-reader
```

### 10. Test from inside a pod

Deploy a pod with the ServiceAccount:

```bash
kubectl apply -f pod-sa.yaml
kubectl wait --for=condition=Ready pod/rbac-test-pod -n rbac-lab --timeout=60s
```

Test from inside:

```bash
# List pods in rbac-lab (should work)
kubectl exec rbac-test-pod -n rbac-lab -- kubectl get pods -n rbac-lab

# List pods in default namespace (should fail)
kubectl exec rbac-test-pod -n rbac-lab -- kubectl get pods -n default

# List nodes (should work - ClusterRole)
kubectl exec rbac-test-pod -n rbac-lab -- kubectl get nodes

# Try to delete a pod (should fail)
kubectl exec rbac-test-pod -n rbac-lab -- kubectl delete pod rbac-test-pod -n rbac-lab --force --grace-period=0
```

### 11. List all permissions for the SA

```bash
kubectl auth can-i --list --as=system:serviceaccount:rbac-lab:pod-reader -n rbac-lab
```

### 12. Understand Role vs ClusterRole

| Resource | Scope | Use Case |
|----------|-------|----------|
| Role | Namespace | Grant access within a specific namespace |
| ClusterRole | Cluster | Grant access to cluster-scoped resources (nodes, PVs) or across all namespaces |
| RoleBinding | Namespace | Bind Role or ClusterRole within a namespace |
| ClusterRoleBinding | Cluster | Bind ClusterRole cluster-wide |

## Verification

```bash
# Role exists
kubectl get role pod-reader-role -n rbac-lab

# RoleBinding exists
kubectl get rolebinding pod-reader-binding -n rbac-lab

# ClusterRole exists
kubectl get clusterrole node-viewer

# Pod can list pods
kubectl exec rbac-test-pod -n rbac-lab -- kubectl get pods -n rbac-lab

# Pod cannot delete pods
kubectl exec rbac-test-pod -n rbac-lab -- kubectl delete pod rbac-test-pod -n rbac-lab 2>&1 | grep -i forbidden
```

## Cleanup

```bash
kubectl delete -f pod-sa.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f clusterrolebinding.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f clusterrole.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f rolebinding.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f role.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f serviceaccount.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f namespace.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) - concept + reference
- [Checking API Access](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access) - task reference
