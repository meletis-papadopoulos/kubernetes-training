# Exercise 7.4 - Solutions

The only manifest is `solution/viewer-sa.yaml` (the ServiceAccount + a read-only ClusterRole + its ClusterRoleBinding for Task 2);
everything else is `kubectl config` work on your client-side kubeconfig. Cluster/user/context names
below are **illustrative** - a kubeadm cluster typically has cluster `kubernetes`, user
`kubernetes-admin`, and context `kubernetes-admin@kubernetes`. Discover yours instead of hard-coding:

```bash
CLUSTER=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
USER=$(kubectl config view --minify -o jsonpath='{.users[0].name}')
ORIG=$(kubectl config current-context)
```

## Task 1 - Inspect, then build a namespace-pinned context

```bash
kubectl config current-context
kubectl config view --minify
```

Expected (illustrative):

```
kubernetes-admin@kubernetes
```

```yaml
# ...only the current context's cluster + user + namespace...
contexts:
- context:
    cluster: kubernetes
    namespace: default
    user: kubernetes-admin
  name: kubernetes-admin@kubernetes
current-context: kubernetes-admin@kubernetes
```

Create and switch to the new context:

```bash
kubectl config set-context dev-ctx --cluster="$CLUSTER" --user="$USER" --namespace=kube-system
kubectl config use-context dev-ctx
kubectl get pods
```

Expected - `kube-system` Pods appear with no `-n` flag:

```
NAME                               READY   STATUS    RESTARTS   AGE
coredns-...                        1/1     Running   0          25m
kube-apiserver-...                 1/1     Running   0          25m
...
```

Switch back:

```bash
kubectl config use-context "$ORIG"
```

**Answer to the reflective question:** a context binds exactly **three** things: a **cluster** (the
API server endpoint + CA - *where* to talk), a **user** (the credentials - *how* to authenticate), and
a default **namespace** (*which* namespace unqualified commands target). `dev-ctx` reused the first two
and changed only the namespace.

## Task 2 - A second identity from a ServiceAccount token

```bash
kubectl apply -f solution/viewer-sa.yaml
```

`solution/viewer-sa.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: viewer
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-viewer
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: viewer-binding
subjects:
- kind: ServiceAccount
  name: viewer
  namespace: default
roleRef:
  kind: ClusterRole
  name: pod-viewer
  apiGroup: rbac.authorization.k8s.io
```

Mint a token, register it as a kubeconfig user, wire up and switch to the context:

```bash
TOKEN=$(kubectl create token viewer --duration=1h)
kubectl config set-credentials viewer-user --token="$TOKEN"
kubectl config set-context viewer-ctx --cluster="$CLUSTER" --user=viewer-user --namespace=default
kubectl config use-context viewer-ctx
kubectl auth whoami
```

Expected (the `token`/times are env-specific; the username is the point):

```
ATTRIBUTE   VALUE
Username    system:serviceaccount:default:viewer
Groups      [system:serviceaccounts system:serviceaccounts:default system:authenticated]
```

Confirm the identity really is the low-privilege `viewer` SA (pod reads allowed, creates denied), then
return to admin:

```bash
kubectl get pods
kubectl create deployment nope --image=nginx:1.27.1
kubectl config use-context "$ORIG"
```

Expected: `get pods` succeeds (the `pod-viewer` ClusterRole allows pod reads); `create deployment` is
**Forbidden** for `system:serviceaccount:default:viewer`.

**Answer to the reflective question:** switching to `viewer-ctx` swapped the context's **user** from
your admin credentials to `viewer-user`, whose credential is the `viewer` SA bearer token. The API
server authenticates by that token, so you are now `system:serviceaccount:default:viewer`. Same
kubectl binary and same cluster endpoint - **the user half of the context changed your identity**, and
RBAC then limited you to what `pod-viewer` permits.

## Task 3 - KUBECONFIG merging

```bash
cp ~/.kube/config /tmp/second.config
kubectl --kubeconfig=/tmp/second.config config rename-context "$ORIG" second
KUBECONFIG=~/.kube/config:/tmp/second.config kubectl config get-contexts
```

Expected - contexts from **both** files in one view (`dev-ctx`, `viewer-ctx`, your admin context, and
`second`):

```
CURRENT   NAME                          CLUSTER      AUTHINFO           NAMESPACE
          dev-ctx                       kubernetes   kubernetes-admin   kube-system
*         kubernetes-admin@kubernetes   kubernetes   kubernetes-admin   default
          second                        kubernetes   kubernetes-admin   default
          viewer-ctx                    kubernetes   viewer-user        default
```

Flatten the merge into a single self-contained file:

```bash
KUBECONFIG=~/.kube/config:/tmp/second.config kubectl config view --flatten > /tmp/merged.config
```

**Answer to the reflective question:** `KUBECONFIG` takes a list of files (`:`-separated on
Linux/macOS, `;` on Windows) and merges them. On a **name collision** the **first file in the list
wins** - so the `kubernetes` cluster and `kubernetes-admin` user defined in `~/.kube/config` are kept
once and `/tmp/second.config`'s duplicate copies are dropped, while the uniquely-named `second`
context is added. `--flatten` inlines all cert/token data into one portable file.

## Cleanup

```bash
kubectl config use-context "$ORIG" 2>/dev/null || true
kubectl config delete-context dev-ctx 2>/dev/null || true
kubectl config delete-context viewer-ctx 2>/dev/null || true
kubectl config delete-user viewer-user 2>/dev/null || true
kubectl delete -f solution/viewer-sa.yaml --ignore-not-found --force --grace-period=0
rm -f /tmp/second.config /tmp/merged.config
```
