# Exercise 7.5 - Image policy & OPA Gatekeeper

*Domain: Multi-tenancy & Security. Target: ~12 min. Do not open `solution/` until you have tried.*
*Authored in-house (not derived from a study guide); grounded in the official docs linked below.*

## Prerequisites

OPA Gatekeeper must be installed (`provision.sh` installs it):

```bash
kubectl get pods -n gatekeeper-system     # controller-manager + audit should be Running
```

Two **ConstraintTemplates** are provided for you in `setup/` (writing Rego is out of scope here -
you author the Constraints that use them). Apply them:

```bash
kubectl apply -f setup/template-requiredlabels.yaml
kubectl apply -f setup/template-allowedrepos.yaml
kubectl create namespace secure
```

Wait until the generated Constraint CRDs are registered:

```bash
kubectl get crd | grep gatekeeper
```

## Tasks

1. Create a Constraint of kind `K8sRequiredLabels` named `pods-must-have-owner` that applies **only**
   to `Pod` resources in the `secure` namespace and requires the label key `owner`. Use the default
   enforcement (`deny`). Then prove it works: try to create a Pod named `bad` (image `nginx:1.27.1`)
   in `secure` with **no** `owner` label - it must be rejected - and a Pod named `good` (image
   `nginx:1.27.1`) **with** `owner=team-a` - it must be admitted. Quote the rejection message.

2. Create a Constraint of kind `K8sAllowedRepos` named `allowed-image-repos` that applies to `Pod`
   resources in the `secure` namespace and only permits container images whose repo starts with
   `docker.io/library/`. Verify that a Pod using `quay.io/prometheus/busybox` (plus the `owner` label,
   so it passes Constraint 1) is rejected by the repo policy, while `docker.io/library/nginx:1.27.1`
   is allowed.

3. Inspect the audit results Gatekeeper records for pre-existing violations:
   `kubectl get k8srequiredlabels pods-must-have-owner -o yaml` - which `status` field lists the
   objects already violating the constraint, and how does that differ from the admission-time deny
   you saw in Task 1?

## Acceptance criteria

- Constraint `pods-must-have-owner` exists; Pod `bad` is **denied** with a message naming the missing
  `owner` label; Pod `good` is created.
- Constraint `allowed-image-repos` exists; the `quay.io/...` Pod is **denied** with an
  "invalid image repo" message; the `docker.io/library/nginx` Pod is created.
- `status.violations` (populated by the audit controller) enumerates existing offenders, whereas
  admission enforcement blocks *new* offenders at `kubectl apply` time.

## Docs you may reference

- [OPA Gatekeeper docs](https://open-policy-agent.github.io/gatekeeper/website/docs/) *(OPA project - not kubernetes.io)*
- [Gatekeeper - How to use constraints](https://open-policy-agent.github.io/gatekeeper/website/docs/howto)
- [Dynamic Admission Control](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/)
