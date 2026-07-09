# Exercise 7.1 - Solutions

Reference manifests are in `solution/`. Everything is created from scratch by the tasks.

## Task 1 - Two namespaces and a namespaced Pod

```bash
kubectl apply -f solution/namespaces.yaml
kubectl apply -f solution/web-pod.yaml
```

`solution/namespaces.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-alpha
  labels:
    team: alpha
---
apiVersion: v1
kind: Namespace
metadata:
  name: team-beta
```

`solution/web-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: team-alpha
spec:
  containers:
  - name: web
    image: nginx:1.27.1
```

Verify the Pod is in `team-alpha` and not visible from `default`:

```bash
kubectl get ns team-alpha --show-labels
kubectl get pod web -n team-alpha
kubectl get pod web -n default
```

Expected:

```
NAME         STATUS   AGE   LABELS
team-alpha   Active   5s    team=alpha
NAME   READY   STATUS    RESTARTS   AGE
web    1/1     Running   0          5s
Error from server (NotFound): pods "web" not found
```

**Answer to the reflective question:** a Pod is a **namespaced** object - its full identity is
`(namespace, name)`, so `web` in `team-alpha` and a hypothetical `web` in `default` would be two
different objects. `kubectl get pod web -n default` looks only inside `default`, finds nothing, and
returns `NotFound`. The namespace is a hard partition of the object namespace, not a display filter.

## Task 2 - Pin the context namespace, then list cluster-wide

```bash
kubectl config set-context --current --namespace=team-alpha
kubectl get pods
```

Expected - `web` shows with no `-n` flag:

```
NAME   READY   STATUS    RESTARTS   AGE
web    1/1     Running   0          30s
```

List every Pod in every namespace with one command:

```bash
kubectl get pods -A
```

Expected (abridged - system pods vary by cluster):

```
NAMESPACE     NAME                               READY   STATUS    RESTARTS   AGE
kube-system   coredns-...                        1/1     Running   0          20m
team-alpha    web                                1/1     Running   0          40s
...
```

Restore the default namespace on the context:

```bash
kubectl config set-context --current --namespace=default
```

**Answer to the reflective question:** the pinned namespace is a property of the **kubeconfig
context**, not the shell session. `set-context --current --namespace=...` writes
`contexts[].context.namespace` into `~/.kube/config`, so it persists across new shells and terminals
until you change it again. It is not an environment variable.

## Task 3 - Cascading namespace deletion

```bash
kubectl delete namespace team-beta
kubectl delete namespace team-alpha
```

Watch the namespace and its contents disappear together:

```bash
kubectl get ns team-alpha team-beta
kubectl get pod web -n team-alpha
```

Expected:

```
Error from server (NotFound): namespaces "team-alpha" not found
Error from server (NotFound): pods "web" not found
```

(`team-beta` is likewise `NotFound`; a namespace may sit in `Terminating` for a few seconds while its
contents drain - re-run the `get` and it clears.)

**Answer to the reflective question:** no - **not** all resources are namespaced. Deleting a
namespace cascades to every namespaced object inside it (Pods, Services, ConfigMaps, Deployments,
ServiceAccounts, ...), which is why `web` went with `team-alpha`. But **cluster-scoped** kinds live
outside any namespace and are unaffected: two examples are **Nodes** and **PersistentVolumes** (others
include **Namespaces** themselves, **ClusterRoles**, and **StorageClasses**). Confirm the split with
`kubectl api-resources --namespaced=false`.

## Cleanup

```bash
kubectl delete ns team-alpha team-beta --ignore-not-found --force --grace-period=0
kubectl config set-context --current --namespace=default
```
