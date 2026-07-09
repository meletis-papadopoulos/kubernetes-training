# Scenario 3 - Enforcement Actions: deny vs warn vs dryrun

## What You Will Learn
- The three Gatekeeper enforcement actions and when to use each
- How `warn` lets the resource through but returns a warning to the user
- How `dryrun` silently records violations in the constraint status (audit only)
- How to use `dryrun` to evaluate policy impact before enforcing

## Context
When rolling out a new policy in production, you don't start with `deny`. You start with `dryrun` to measure how many existing resources would violate, switch to `warn` to notify teams, then finally `deny` once teams have remediated. This scenario walks through that progression.

---

## Create

### 1. Ensure the lab namespace exists and apply the ConstraintTemplate (if not already present)

```bash
kubectl apply -f namespace.yaml
kubectl apply -f template-required-labels.yaml
kubectl wait --for=create crd/k8srequiredlabels.constraints.gatekeeper.sh --timeout=60s
kubectl wait --for=condition=Established crd/k8srequiredlabels.constraints.gatekeeper.sh --timeout=60s
```

### Part A: dryrun (audit only)

### 2. Apply the dryrun constraint

```bash
kubectl apply -f constraint-required-labels-dryrun.yaml
```

### 3. Deploy a pod without required labels

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: dryrun-test
  namespace: gatekeeper-lab
  labels:
    env: staging
spec:
  containers:
    - name: nginx
      image: docker.io/library/nginx:1.25
EOF
```

The pod is **created** - dryrun never blocks.

### 4. Check the audit violations

Wait 1-2 minutes for the audit controller to run, then:

```bash
kubectl describe k8srequiredlabels audit-pod-labels
```

Look at `status.violations` - the pod should be listed there even though it was allowed through.

```bash
kubectl get k8srequiredlabels audit-pod-labels -o jsonpath='{.status.totalViolations}'
```

### 5. Clean up the dryrun constraint

```bash
kubectl delete pod dryrun-test -n gatekeeper-lab --ignore-not-found --force --grace-period=0
kubectl delete -f constraint-required-labels-dryrun.yaml --force --grace-period=0
```

### Part B: warn (allow + warning)

### 6. Apply the warn constraint

```bash
kubectl apply -f constraint-required-labels-warn.yaml
```

### 7. Deploy a pod without required labels

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: warn-test
  namespace: gatekeeper-lab
  labels:
    env: staging
spec:
  containers:
    - name: nginx
      image: docker.io/library/nginx:1.25
EOF
```

The pod is **created**, but you should see a warning message in the output: "Warning: pods should have labels of owner and appName."

### 8. Verify the pod exists despite the warning

```bash
kubectl get pod warn-test -n gatekeeper-lab
```

### 9. Clean up the warn constraint

```bash
kubectl delete pod warn-test -n gatekeeper-lab --ignore-not-found --force --grace-period=0
kubectl delete -f constraint-required-labels-warn.yaml --force --grace-period=0
```

### Part C: deny (block)

### 10. Apply the deny constraint

```bash
kubectl apply -f constraint-required-labels.yaml
```

### 11. Deploy the same pod

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: deny-test
  namespace: gatekeeper-lab
  labels:
    env: staging
spec:
  containers:
    - name: nginx
      image: docker.io/library/nginx:1.25
EOF
```

The pod is **rejected**. It does not exist.

### 12. Compare the three actions

| Action | Pod created? | User notified? | Violations recorded? | Use case |
|--------|-------------|----------------|---------------------|----------|
| `dryrun` | Yes | No | Yes (audit only) | Impact assessment before rollout |
| `warn` | Yes | Yes (warning) | Yes | Notify teams, give time to remediate |
| `deny` | No | Yes (error) | Yes | Enforce in production |

---

## Verify

```bash
# No test pods should remain
kubectl get pods -n gatekeeper-lab -l env=staging 2>&1

# The deny constraint should be active
kubectl get constraints
```

---

## Destroy

```bash
kubectl delete pod dryrun-test warn-test deny-test -n gatekeeper-lab --ignore-not-found --force --grace-period=0
kubectl delete -f constraint-required-labels.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f constraint-required-labels-warn.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f constraint-required-labels-dryrun.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f template-required-labels.yaml --ignore-not-found --force --grace-period=0
```
