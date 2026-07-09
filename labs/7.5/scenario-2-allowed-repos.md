# Scenario 2 - Restrict Image Repos to Approved Registries

## What You Will Learn
- How the `validRepo` Rego function validates image prefixes and subdomain patterns
- How constraints can match multiple resource kinds (Pod, Deployment, StatefulSet, etc.)
- How the `template.spec.containers` rule catches images inside Deployment/StatefulSet specs
- The difference between a pod-level denial and a workload-level denial

## Context
This scenario mimics a real production policy that restricts all container images to an approved registry. Only images from `docker.io` are allowed. Public images without a registry prefix (like `nginx:1.25`) are also covered since they resolve to `docker.io/library/`.

---

## Create

### 1. Ensure the lab namespace exists and apply the ConstraintTemplate

```bash
kubectl apply -f namespace.yaml
kubectl apply -f template-allowed-repos.yaml
kubectl wait --for=create crd/k8sallowedrepos.constraints.gatekeeper.sh --timeout=60s
kubectl wait --for=condition=Established crd/k8sallowedrepos.constraints.gatekeeper.sh --timeout=60s
```

### 2. Inspect the Rego logic

```bash
kubectl describe constrainttemplate k8sallowedrepos
```

The Rego has three violation rules covering different resource shapes:
- `spec.containers[_]` - catches Pods
- `spec.initContainers[_]` - catches init containers
- `spec.template.spec.containers[_]` - catches Deployments, StatefulSets, DaemonSets

The `validRepo` function has two paths:
- **Direct prefix match**: `startswith(image, repo)` - e.g., `docker.io/library/nginx:1.25`
- **Subdomain pattern**: regex `[a-zA-Z0-9]+.repo/.*` - catches `subdomain.docker.io/...`

### 3. Apply the Constraint

```bash
kubectl apply -f constraint-allowed-repos.yaml
```

### 4. Inspect the constraint

```bash
kubectl describe k8sallowedrepos allow-only-approved-repos
```

Note:
- Matches Pods AND Deployments/ReplicaSets/DaemonSets/StatefulSets
- Scoped to `gatekeeper-lab` namespace
- Only `docker.io` is in the approved list (images must literally start with `docker.io/...` or match the subdomain pattern)

---

## Test

### 5. Deploy a pod with an approved image

```bash
kubectl apply -f pod-repo-allowed.yaml
```

Uses `docker.io/library/nginx:1.25`. Should succeed.

```bash
kubectl get pod pod-repo-allowed -n gatekeeper-lab
```

### 6. Deploy a pod with an unapproved image

```bash
kubectl apply -f pod-repo-disallowed.yaml
```

Uses `registry.k8s.io/pause:3.9` - from a different registry. Should be **denied** with message: "container <nginx> has an invalid image repo, allowed repos are..."

### 7. Deploy a Deployment with an unapproved image

```bash
kubectl apply -f deployment-repo-disallowed.yaml
```

Uses `quay.io/prometheus/busybox:latest` in the Deployment's `template.spec.containers`. Should be **denied** - the third violation rule catches images inside workload templates, not just bare pods.

### 8. Check violations

```bash
kubectl describe k8sallowedrepos allow-only-approved-repos
```

---

## Verify

```bash
# Approved pod is running
kubectl get pod pod-repo-allowed -n gatekeeper-lab

# Unapproved image pod does not exist
kubectl get pod pod-repo-disallowed -n gatekeeper-lab 2>&1

# Unapproved image deployment does not exist
kubectl get deployment deployment-repo-disallowed -n gatekeeper-lab 2>&1

# Total violations
kubectl get k8sallowedrepos allow-only-approved-repos -o jsonpath='{.status.totalViolations}'
```

---

## Destroy

```bash
kubectl delete pod pod-repo-allowed -n gatekeeper-lab --ignore-not-found --force --grace-period=0
kubectl delete deployment deployment-repo-disallowed -n gatekeeper-lab --ignore-not-found --force --grace-period=0
kubectl delete -f constraint-allowed-repos.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f template-allowed-repos.yaml --ignore-not-found --force --grace-period=0
```
