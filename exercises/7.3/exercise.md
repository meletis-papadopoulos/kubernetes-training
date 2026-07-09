# Exercise 7.3 - ServiceAccounts

*Domain: Multi-tenancy & Security. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace sa-ex
```

## Tasks

1. In the namespace `sa-ex`, create a ServiceAccount named `api-caller`. Then create a Pod named
   `api-pod` that runs the image `alpine/k8s:1.35.1` (command `sleep 3600`) and runs **as** that
   ServiceAccount (`spec.serviceAccountName: api-caller`). Once the Pod is `Running`, confirm the Pod
   is using `api-caller`, and show the directory where its projected token is mounted:
   `kubectl exec api-pod -n sa-ex -- ls /var/run/secrets/kubernetes.io/serviceaccount/`. Which three
   files appear there, and which one is the bearer token the container presents to the API server?

2. From **inside** the Pod, use the mounted identity to talk to the API server:
   `kubectl exec api-pod -n sa-ex -- kubectl get pods -n sa-ex`. Because `alpine/k8s` runs kubectl
   with the Pod's in-cluster config (the mounted `api-caller` token), this call is authenticated as
   `system:serviceaccount:sa-ex:api-caller` - and it is **Forbidden**, because that SA has no RBAC
   yet. Capture the forbidden message. Why is the container's identity `api-caller` rather than your
   admin identity?

3. Grant the SA read access on pods by creating a Role `pod-reader` (get/list on `pods`) in `sa-ex`
   and a RoleBinding `api-caller-read` binding it to `api-caller` - the same mechanism you used in
   exercise 7.2. Re-run `kubectl exec api-pod -n sa-ex -- kubectl get pods -n sa-ex` and confirm it
   now succeeds. Reflective: did binding the Role change *who* the Pod authenticates as, or only
   *what* it is allowed to do?

## Acceptance criteria

- ServiceAccount `api-caller` and Pod `api-pod` (image `alpine/k8s:1.35.1`, SA `api-caller`) exist in
  `sa-ex`; the projected volume dir contains `ca.crt`, `namespace`, and `token`.
- **Before** the RoleBinding: `kubectl exec api-pod -n sa-ex -- kubectl get pods -n sa-ex` is
  **Forbidden** for `system:serviceaccount:sa-ex:api-caller`.
- **After** Role `pod-reader` + RoleBinding `api-caller-read`: the same in-pod command lists the Pods
  in `sa-ex`.

## Docs you may reference

- [Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
- [Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts/)
