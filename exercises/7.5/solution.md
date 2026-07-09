# Exercise 7.5 - Solutions

Reference manifests are in `solution/`. The two ConstraintTemplates from `setup/` and the `secure`
namespace are assumed applied (see Prerequisites).

## Task 1 - required-label Constraint

```bash
kubectl apply -f solution/require-owner.yaml
```

`solution/require-owner.yaml`:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: pods-must-have-owner
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    namespaces: ["secure"]
  parameters:
    labels: ["owner"]
```

Test the deny path (give the webhook a moment to start enforcing the new Constraint):

```bash
sleep 5
kubectl apply -f solution/bad-pod.yaml
```

Expected - rejected at admission:

```
Error from server (Forbidden): error when creating "solution/bad-pod.yaml": admission webhook
"validation.gatekeeper.sh" denied the request: [pods-must-have-owner] you must provide labels:
{"owner"}
```

Test the allow path:

```bash
kubectl apply -f solution/good-pod.yaml
kubectl get pod good -n secure
```

Expected: `good` is created and `Running`.

> Note: Gatekeeper's webhook can take a few seconds after the Constraint is applied before it starts
> enforcing. If `bad` is admitted immediately after `kubectl apply` of the Constraint, delete it and
> retry after ~5s.

## Task 2 - allowed-repos Constraint

```bash
kubectl apply -f solution/allowed-repos.yaml
```

`solution/allowed-repos.yaml`:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: allowed-image-repos
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    namespaces: ["secure"]
  parameters:
    repos:
    - "docker.io/library/"
```

Test denial (this pod has the `owner` label so it clears Constraint 1, and is blocked only by the
repo policy):

```bash
kubectl apply -f solution/bad-repo-pod.yaml
```

Expected:

```
Error from server (Forbidden): ... denied the request: [allowed-image-repos] container <app> has an
invalid image repo <quay.io/prometheus/busybox>, allowed repos are ["docker.io/library/"]
```

The `good` Pod from Task 1 uses `nginx:1.27.1`; if your cluster records that as
`docker.io/library/nginx:1.27.1` it satisfies the policy. Verify existing pods are not retroactively
deleted - enforcement is at admission only.

## Task 3 - audit vs admission

```bash
kubectl get k8srequiredlabels pods-must-have-owner -o yaml
```

Look at the bottom:

```yaml
status:
  auditTimestamp: "..."
  totalViolations: 1
  violations:
  - enforcementAction: deny
    kind: Pod
    message: 'you must provide labels: {"owner"}'
    name: <some-preexisting-pod>
    namespace: secure
```

**Answer:** `status.violations` is populated by Gatekeeper's **audit** controller, which periodically
scans objects **already in the cluster** and reports those that break the constraint (it does not
delete them). That is distinct from **admission** enforcement, which rejects *new* non-compliant
objects synchronously at `kubectl apply` time (Task 1). Audit = detect existing drift; admission =
prevent new drift.

## Cleanup

```bash
kubectl delete k8srequiredlabels pods-must-have-owner --ignore-not-found
kubectl delete k8sallowedrepos allowed-image-repos --ignore-not-found
kubectl delete ns secure --ignore-not-found
kubectl delete constrainttemplate k8srequiredlabels k8sallowedrepos --ignore-not-found
```
