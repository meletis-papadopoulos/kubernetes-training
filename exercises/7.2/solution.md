# Exercise 7.2 - Solutions

Reference manifests are in `solution/`. Namespace `rbac-ex` is assumed to exist (see Setup).

## Task 1 - ServiceAccount, Role, RoleBinding

```bash
kubectl apply -f solution/serviceaccount.yaml
kubectl apply -f solution/pod-viewer-role.yaml
kubectl apply -f solution/pod-reader-binding.yaml
```

`solution/pod-viewer-role.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-viewer
  namespace: rbac-ex
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
```

`solution/pod-reader-binding.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: rbac-ex
subjects:
- kind: ServiceAccount
  name: pod-reader
  namespace: rbac-ex
roleRef:
  kind: Role
  name: pod-viewer
  apiGroup: rbac.authorization.k8s.io
```

Verify the grant:

```bash
kubectl auth can-i list pods -n rbac-ex --as=system:serviceaccount:rbac-ex:pod-reader
```

Expected:

```
yes
```

**Answer to the reflective question:** the RoleBinding binds the `pod-viewer` Role to the
`pod-reader` ServiceAccount **within `rbac-ex`**, so the SA can now `get`/`list`/`watch` Pods there.
`kubectl auth can-i --as=` impersonates the subject and asks the authorizer the exact question the API
server would answer at request time - a zero-cost way to test RBAC without switching identities.

## Task 2 - Probe the edges (denied verbs / scope / resource)

```bash
kubectl auth can-i delete pods      -n rbac-ex --as=system:serviceaccount:rbac-ex:pod-reader
kubectl auth can-i list   pods      -n default --as=system:serviceaccount:rbac-ex:pod-reader
kubectl auth can-i list   deployments -n rbac-ex --as=system:serviceaccount:rbac-ex:pod-reader
```

Expected - every one denied:

```
no
no
no
```

**Answer to the reflective question:** the RoleBinding lives **in** `rbac-ex` and can only bind
permissions **inside** `rbac-ex`. Authorization in `default` consults only the Roles/RoleBindings (and
any ClusterRoleBindings) that apply to `default`; nothing there references `pod-reader`, so
`list pods -n default` is denied. The other two denials are because the Role never granted the
`delete` verb, nor the `deployments` resource - RBAC is additive and default-deny, so anything not
explicitly granted is refused.

## Task 3 - Cluster-scoped resource is unreachable

```bash
kubectl auth can-i list nodes --as=system:serviceaccount:rbac-ex:pod-reader
```

Expected:

```
no
```

Optionally list everything the subject *can* do in the namespace:

```bash
kubectl auth can-i --list -n rbac-ex --as=system:serviceaccount:rbac-ex:pod-reader
```

Expected (abridged) - only the pod verbs plus the self-review defaults:

```
Resources   Non-Resource URLs   Resource Names   Verbs
pods        []                  []               [get list watch]
...
```

**Answer to the reflective question:**
- **Role vs ClusterRole:** a `Role` is namespaced - its rules only ever apply inside its own
  namespace and can only name namespaced resources (like Pods). A `ClusterRole` is cluster-scoped and
  is the *only* way to grant access to cluster-scoped resources such as **Nodes**, and it can also be
  reused across namespaces. `pod-viewer` is a Role, so it can never authorize `list nodes` no matter
  how it is bound.
- **RoleBinding vs ClusterRoleBinding:** a `RoleBinding` grants its referenced Role/ClusterRole
  **only within one namespace**; a `ClusterRoleBinding` grants a ClusterRole **cluster-wide** (all
  namespaces + cluster-scoped resources). To let `pod-reader` read Nodes you would need a ClusterRole
  with a `nodes` rule bound by a **ClusterRoleBinding**.

## Cleanup

```bash
kubectl delete ns rbac-ex --ignore-not-found --force --grace-period=0
```
