# Scenario 1 - Enforce Required Labels

## What You Will Learn
- How a ConstraintTemplate defines reusable policy logic in Rego
- How a Constraint applies that logic with specific parameters
- How `get_message` provides custom violation messages
- How `allowedRegex` validates label values (not just presence)

## Context
This scenario mimics a real production policy that requires all pods to carry `owner` and `appName` labels. Labels with invalid characters (spaces, special chars) are rejected via regex.

---

## Create

### 1. Ensure the lab namespace exists and apply the ConstraintTemplate

```bash
kubectl apply -f namespace.yaml
kubectl apply -f template-required-labels.yaml
kubectl wait --for=create crd/k8srequiredlabels.constraints.gatekeeper.sh --timeout=60s
kubectl wait --for=condition=Established crd/k8srequiredlabels.constraints.gatekeeper.sh --timeout=60s
```

The wait matters if this ConstraintTemplate was just deleted (e.g. re-running the lab) - deleting it tears down the backing CRD, and creating a Constraint before the CRD finishes re-establishing fails with `create not allowed while custom resource definition is terminating`.

### 2. Inspect the template

```bash
kubectl describe constrainttemplate k8srequiredlabels
```

Note the Rego policy has two violation rules:
- **First rule**: checks for missing labels (set difference: `required - provided`)
- **Second rule**: checks label values against `allowedRegex`

### 3. Apply the Constraint

```bash
kubectl apply -f constraint-required-labels.yaml
```

### 4. Inspect the constraint

```bash
kubectl describe k8srequiredlabels require-pod-labels
```

Note:
- `enforcementAction: deny` - blocks non-compliant pods
- `match.namespaces: ["gatekeeper-lab"]` - scoped to our lab namespace
- `parameters.labels` - requires `owner` and `appName` with regex `^[a-z][a-z0-9-]*$` (lowercase-only, must start with a letter - stricter than Kubernetes's own label validation so Gatekeeper's regex actually gets exercised)
- No custom `parameters.message` - so the default Rego messages are returned, which tell you which rule fired (missing labels vs regex fail)

---

## Test

### 5. Deploy a compliant pod

```bash
kubectl apply -f pod-labels-allowed.yaml
```

This pod has both `appName: nginx-web` and `owner: training-team`. Should succeed.

```bash
kubectl get pod pod-labels-allowed -n gatekeeper-lab
```

### 6. Deploy a pod with missing labels

```bash
kubectl apply -f pod-labels-disallowed.yaml
```

This pod only has `env: production` - missing both required labels. Should be **denied** with the default message: `you must provide labels: {"appName", "owner"}`.

### 7. Deploy a pod with labels that fail regex

```bash
kubectl apply -f pod-labels-bad-regex.yaml
```

This pod has `appName: NginxWeb` and `owner: Training-Team`. These values are **valid Kubernetes label values** (K8s accepts mixed case) but they fail the Gatekeeper regex `^[a-z][a-z0-9-]*$` which requires lowercase-only. Should be **denied by Gatekeeper** with a message like `Label <owner: Training-Team> does not satisfy allowed regex: ^[a-z][a-z0-9-]*$`. This is the key pedagogical moment - it's Gatekeeper's regex triggering, not K8s's native label validation.

### 8. Check constraint violations

```bash
kubectl describe k8srequiredlabels require-pod-labels
```

Look at the `status.violations` section. Gatekeeper's audit controller records violations even for resources that existed before the constraint.

---

## Verify

```bash
# Compliant pod is running
kubectl get pod pod-labels-allowed -n gatekeeper-lab

# Missing-labels pod does not exist
kubectl get pod pod-labels-disallowed -n gatekeeper-lab 2>&1

# Bad-regex pod does not exist
kubectl get pod pod-labels-bad-regex -n gatekeeper-lab 2>&1

# Check total violations
kubectl get k8srequiredlabels require-pod-labels -o jsonpath='{.status.totalViolations}'
```

---

## Destroy

```bash
kubectl delete pod pod-labels-allowed -n gatekeeper-lab --ignore-not-found --force --grace-period=0
kubectl delete -f constraint-required-labels.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f template-required-labels.yaml --ignore-not-found --force --grace-period=0
```
