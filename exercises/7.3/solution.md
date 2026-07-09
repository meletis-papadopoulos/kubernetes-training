# Exercise 7.3 - Solutions

Reference manifests are in `solution/`. Namespace `sa-ex` is assumed to exist (see Setup).

## Task 1 - ServiceAccount, Pod running as it, projected token

```bash
kubectl apply -f solution/serviceaccount.yaml
kubectl apply -f solution/pod.yaml
kubectl wait --for=condition=Ready pod/api-pod -n sa-ex --timeout=60s
```

`solution/pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api-pod
  namespace: sa-ex
spec:
  serviceAccountName: api-caller
  containers:
  - name: kubectl
    image: alpine/k8s:1.35.1
    command: ["sleep", "3600"]
```

Confirm the assigned SA and list the mounted token directory:

```bash
kubectl get pod api-pod -n sa-ex -o jsonpath='{.spec.serviceAccountName}{"\n"}'
kubectl exec api-pod -n sa-ex -- ls /var/run/secrets/kubernetes.io/serviceaccount/
```

Expected:

```
api-caller
ca.crt
namespace
token
```

**Answer to the reflective question:** the three files are `ca.crt` (the API server's CA bundle, so
the container can verify TLS), `namespace` (the Pod's namespace, `sa-ex`), and `token` - the bearer
token the container presents in an `Authorization: Bearer` header to authenticate as
`api-caller` - the kubelet auto-mounts it for the Pod's ServiceAccount.

## Task 2 - Call the API from inside the Pod (Forbidden, no RBAC yet)

```bash
kubectl exec api-pod -n sa-ex -- kubectl get pods -n sa-ex
```

Expected - Forbidden (the message is illustrative; the identity string is the load-bearing part):

```
Error from server (Forbidden): pods is forbidden: User
"system:serviceaccount:sa-ex:api-caller" cannot list resource "pods" in API group "" in the
namespace "sa-ex"
```

**Answer to the reflective question:** inside the Pod, kubectl finds no `~/.kube/config`, so it falls
back to **in-cluster configuration**: it reads the mounted `token`, `ca.crt`, and the API server
address from the environment. That token belongs to `api-caller`, so the request is authenticated as
`system:serviceaccount:sa-ex:api-caller` - not your admin kubeconfig identity, which never leaves your
workstation and is never mounted into the Pod. The SA has no Role bound yet, hence Forbidden.

## Task 3 - Bind a Role, re-run, succeed

```bash
kubectl apply -f solution/role.yaml
kubectl apply -f solution/rolebinding.yaml
```

`solution/role.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: sa-ex
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
```

`solution/rolebinding.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: api-caller-read
  namespace: sa-ex
subjects:
- kind: ServiceAccount
  name: api-caller
  namespace: sa-ex
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

Re-run the in-pod call:

```bash
kubectl exec api-pod -n sa-ex -- kubectl get pods -n sa-ex
```

Expected - now authorized:

```
NAME      READY   STATUS    RESTARTS   AGE
api-pod   1/1     Running   0          2m
```

**Answer to the reflective question:** binding the Role did **not** change *who* the Pod is - the
in-pod kubectl still authenticates as `system:serviceaccount:sa-ex:api-caller` using the same
auto-mounted token. It only changed **authorization**: the RoleBinding grants `api-caller` the
`get`/`list` on pods it previously lacked, so the identical request flips from Forbidden to allowed.
Authentication (who you are) and authorization (what you may do) are separate steps.

## Cleanup

```bash
kubectl delete ns sa-ex --ignore-not-found --force --grace-period=0
```
