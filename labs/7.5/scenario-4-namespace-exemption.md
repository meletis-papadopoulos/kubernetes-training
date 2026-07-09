# Scenario 4 - Exempt a Namespace from Gatekeeper Policies

## What You Will Learn
- How to scope a constraint cluster-wide and exempt selected namespaces via `match.excludedNamespaces`
- How to exempt a namespace from **all** constraints at once with the cluster-wide `Config` resource
- Why `kube-system` and `gatekeeper-system` should always be excluded
- The difference between `match.namespaces` (allowlist) and `match.excludedNamespaces` (denylist)

## Context
Production policies are usually cluster-wide - you want them enforced everywhere by default, then carve out exceptions for sandboxes, system namespaces, or break-glass workloads. There are two ways to do this:

- **Method A - Per-constraint exemption** (`match.excludedNamespaces` on the constraint). Granular: each policy decides what it exempts. Recommended for most cases.
- **Method B - Cluster-wide exemption** via the `Config` resource (`config.gatekeeper.sh`). One place exempts a namespace from every constraint, including audit. Use for trusted system or sandbox namespaces.

In this scenario you will create a `gatekeeper-demo` namespace, prove a cluster-wide constraint blocks it, then exempt it both ways.

---

## Create

### 1. Apply the ConstraintTemplate (if not already present)

```bash
kubectl apply -f template-required-labels.yaml
kubectl wait --for=create crd/k8srequiredlabels.constraints.gatekeeper.sh --timeout=60s
kubectl wait --for=condition=Established crd/k8srequiredlabels.constraints.gatekeeper.sh --timeout=60s
```

### 2. Create the lab and demo namespaces

```bash
kubectl apply -f namespace.yaml
kubectl apply -f namespace-demo.yaml
```

### 3. Apply the cluster-wide constraint (no exemption yet)

```bash
kubectl apply -f constraint-required-labels-clusterwide.yaml
```

### 4. Inspect the constraint

```bash
kubectl describe k8srequiredlabels require-pod-labels-clusterwide
```

Note:
- **No `match.namespaces`** - the constraint targets every namespace in the cluster
- `enforcementAction: deny`
- Same `owner`/`appName` regex requirement as Scenario 1

---

## Test - without exemption (both namespaces blocked)

### 5. Try to deploy a label-less pod into `gatekeeper-lab`

```bash
kubectl apply -f pod-no-labels-lab.yaml
```

Should be **denied** - pod has only `env: production`, missing `owner` and `appName`.

### 6. Try to deploy a label-less pod into `gatekeeper-demo`

```bash
kubectl apply -f pod-no-labels-demo.yaml
```

Also **denied** - the cluster-wide constraint applies everywhere. The fact that the namespace is named "demo" or labelled `gatekeeper-exempt: "true"` doesn't matter; Gatekeeper has no idea what those labels mean.

---

## Method A - Per-constraint exemption

### 7. Reapply the constraint with `excludedNamespaces`

```bash
kubectl apply -f constraint-required-labels-clusterwide-exempt.yaml
```

This is the same constraint with one addition:

```yaml
match:
  excludedNamespaces:
    - gatekeeper-demo
    - kube-system
    - gatekeeper-system
```

`kubectl apply` updates the existing constraint - no need to delete first.

### 8. Verify the exemption took effect

```bash
kubectl describe k8srequiredlabels require-pod-labels-clusterwide | grep -A4 "Excluded Namespaces"
```

### 9. Re-try the pod in the demo namespace

```bash
kubectl apply -f pod-no-labels-demo.yaml
```

Should now **succeed** - Gatekeeper skips this namespace entirely.

```bash
kubectl get pod pod-no-labels-demo -n gatekeeper-demo
```

### 10. Confirm `gatekeeper-lab` is still enforced

```bash
kubectl apply -f pod-no-labels-lab.yaml
```

Still **denied**. Exemption is namespace-scoped - only `gatekeeper-demo` is exempt; the rest of the cluster (including `gatekeeper-lab`) still enforces the policy.

---

## Method B - Cluster-wide exemption via the `Config` resource

`Config` (`config.gatekeeper.sh/v1alpha1`) sits in `gatekeeper-system` and exempts namespaces from **every** constraint and audit run at once. Use this for system namespaces you never want any policy to touch.

### 11. Inspect the Config YAML

```bash
cat gatekeeper-config-exempt.yaml
```

Note:
- `processes: ["*"]` - exempts from webhook (admission) AND audit AND mutation
- Lives in `gatekeeper-system`, name must be `config` (singleton)
- Affects every constraint without you having to edit them

### 12. Apply the Config

```bash
kubectl apply -f gatekeeper-config-exempt.yaml
```

### 13. Verify

```bash
kubectl get config config -n gatekeeper-system -o yaml
```

With this in place, you could remove the per-constraint `excludedNamespaces` from the constraint above and `gatekeeper-demo` would still be skipped - the Config takes precedence at the webhook layer. This is the pattern most production clusters use for `kube-system`, `kube-public`, and the Gatekeeper namespace itself.

---

## Verify

```bash
# Demo namespace pod is running (exempt)
kubectl get pod pod-no-labels-demo -n gatekeeper-demo

# Lab namespace pod was denied (still enforced)
kubectl get pod pod-no-labels-lab -n gatekeeper-lab 2>&1

# Constraint shows the exemption list
kubectl get k8srequiredlabels require-pod-labels-clusterwide -o jsonpath='{.spec.match.excludedNamespaces}'

# Config exists with the exempt list
kubectl get config config -n gatekeeper-system -o jsonpath='{.spec.match[0].excludedNamespaces}'
```

---

## When to use which

| Method | Scope | Granularity | Use when |
|---|---|---|---|
| `match.namespaces` (allowlist) | Per constraint | Only listed namespaces enforced | New policy rolling out to one tenant |
| `match.excludedNamespaces` (denylist) | Per constraint | All namespaces enforced except listed | Cluster-wide policy with named exceptions |
| `Config` resource | Cluster-wide | Exempt from **all** constraints + audit | System / trusted namespaces (kube-system, gatekeeper-system) |

**Always exclude `kube-system` and `gatekeeper-system`** from cluster-wide policies - Gatekeeper's own pods getting denied = self-DoS, and `kube-system` workloads are managed by the kubelet/control plane, not your policy regime.

---

## Destroy

```bash
kubectl delete pod pod-no-labels-demo -n gatekeeper-demo --ignore-not-found --force --grace-period=0
kubectl delete pod pod-no-labels-lab -n gatekeeper-lab --ignore-not-found --force --grace-period=0
kubectl delete -f gatekeeper-config-exempt.yaml --ignore-not-found
kubectl delete -f constraint-required-labels-clusterwide-exempt.yaml --ignore-not-found
kubectl delete -f template-required-labels.yaml --ignore-not-found
kubectl delete namespace gatekeeper-demo --ignore-not-found --force --grace-period=0
kubectl delete namespace gatekeeper-lab --ignore-not-found --force --grace-period=0
```

This scenario runs last in `lab-walkthrough.sh`'s replay order (README.md's own Cleanup fires *before* the scenarios, not after), so it's the one responsible for the final teardown of both `gatekeeper-lab` and `gatekeeper-demo` - otherwise `pod-no-labels-lab` leaks into every subsequent lab (it once blocked a node drain in Lab 9.9).
