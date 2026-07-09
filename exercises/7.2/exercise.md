# Exercise 7.2 - RBAC

*Domain: Multi-tenancy & Security. Target: ~10 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace rbac-ex
```

## Tasks

1. In the namespace `rbac-ex`, create a ServiceAccount named `pod-reader`. Then create a **Role**
   named `pod-viewer` (in `rbac-ex`) that grants only `get`, `list`, and `watch` on the `pods`
   resource in the core (`""`) API group. Bind that Role to the ServiceAccount with a **RoleBinding**
   named `pod-reader-binding`. Prove the grant works: run
   `kubectl auth can-i list pods -n rbac-ex --as=system:serviceaccount:rbac-ex:pod-reader` and confirm
   it prints `yes`.

2. Now probe the edges of that grant with `kubectl auth can-i ... --as=system:serviceaccount:rbac-ex:pod-reader`.
   Confirm each of these returns **`no`**: `delete pods -n rbac-ex` (verb not granted),
   `list pods -n default` (wrong namespace - the RoleBinding is namespaced to `rbac-ex`), and
   `list deployments -n rbac-ex` (resource not granted). For any single denied check, why does the
   RoleBinding in `rbac-ex` grant nothing in `default`?

3. Attempt to grant the same subject a cluster-scoped read by checking
   `kubectl auth can-i list nodes --as=system:serviceaccount:rbac-ex:pod-reader` - it returns `no`,
   because Nodes are cluster-scoped and a namespaced Role/RoleBinding can never reach them. Explain,
   for this subject, the difference between **Role vs ClusterRole** and between
   **RoleBinding vs ClusterRoleBinding**.

## Acceptance criteria

- ServiceAccount `pod-reader`, Role `pod-viewer`, and RoleBinding `pod-reader-binding` all exist in
  `rbac-ex`.
- `can-i list pods -n rbac-ex --as=system:serviceaccount:rbac-ex:pod-reader` -> `yes`.
- `can-i delete pods -n rbac-ex`, `can-i list pods -n default`, `can-i list deployments -n rbac-ex`,
  and `can-i list nodes` (all `--as=` the same SA) -> `no`.

## Docs you may reference

- [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
