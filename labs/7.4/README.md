# Lab 7.4 - Kubeconfig & Contexts

## Objective
Understand the kubeconfig file as the client-side glue between you and one or more clusters. Read its three sections (`clusters`, `users`, `contexts`), pin a namespace to a context, build a second context from a ServiceAccount token, switch identities mid-session, and merge multiple kubeconfig files with `KUBECONFIG`.

## Prerequisites
- cluster provisioned with `provision.sh`
- Default kubeconfig at `~/.kube/config` with the kubeadm context `kubernetes-admin@kubernetes`

## Steps

### Step 1 - Locate and view your kubeconfig

```bash
ls -la ~/.kube/config
```

```bash
echo $KUBECONFIG
```

`$KUBECONFIG` is empty by default - kubectl falls back to `~/.kube/config`.

```bash
kubectl config view
```

Cert and key data are redacted (`DATA+OMITTED`). Use `--raw` to see them.

```bash
kubectl config view --raw
```

### Step 2 - The three sections + current context

A kubeconfig has three top-level lists: `clusters` (where to talk), `users` (how to authenticate), `contexts` (which `(cluster, user, namespace)` triple is active).

```bash
kubectl config get-clusters
```

```bash
kubectl config get-users
```

```bash
kubectl config get-contexts
```

```bash
kubectl config current-context
```

```bash
kubectl config view --minify
```

`--minify` strips everything except the current context's cluster + user.

### Step 3 - Confirm your identity from the kubeconfig

```bash
kubectl auth whoami
```

You should see `Username: kubernetes-admin` and `Groups: [kubeadm:cluster-admins system:authenticated]` (older kubeadm shows `system:masters` instead - kubeadm v1.29+ moved away from it for security). The username comes from the client cert's `Subject.CN`; groups come from `Subject.O` (Organization).

### Step 4 - Pin a namespace to a context (the daily-use command)

The single most useful `kubectl config` command in normal work - stop typing `-n <ns>` everywhere.

```bash
kubectl config set-context --current --namespace=kube-system
```

```bash
kubectl get pods
```

You're now looking at `kube-system` without `-n`. The namespace is part of the context, not a session variable.

```bash
kubectl config set-context --current --namespace=default
```

### Step 5 - Build a second context from scratch (proves what a context IS)

Create a low-privilege ServiceAccount, mint a token, and wire up a context that uses it. Switching to that context proves a context fully determines who you are. First we deploy a small workload so the viewer has something interesting to look at - and not look at.

```bash
kubectl create deployment nginx-demo --image=nginx --replicas=3
```

```bash
kubectl rollout status deployment/nginx-demo --timeout=60s
```

```bash
kubectl create serviceaccount viewer
```

```bash
kubectl create clusterrolebinding viewer-binding --clusterrole=view --serviceaccount=default:viewer
```

```bash
TOKEN=$(kubectl create token viewer --duration=24h)
```

```bash
kubectl config set-credentials viewer-user --token=$TOKEN
```

```bash
kubectl config set-context viewer-ctx --cluster=kubernetes --user=viewer-user --namespace=default
```

```bash
kubectl config get-contexts
```

```bash
kubectl config use-context viewer-ctx
```

```bash
kubectl auth whoami
```

Username is now `system:serviceaccount:default:viewer` - a different identity, same kubectl, same cluster.

```bash
kubectl get pods
```

Works - the `view` ClusterRole permits reads. You see the 3 `nginx-demo-*` pods.

```bash
kubectl get deployment
```

Also works - `view` covers Deployments too.

```bash
kubectl get secrets
```

**Forbidden** - the standard `view` ClusterRole deliberately omits `secrets` to prevent token leakage. So "view" is not "read everything", it's "read everything except credentials".

```bash
kubectl create deployment nginx --image=nginx
```

**Forbidden** - `view` does not permit creates. The `get pods` above showed you can *see* the workloads; this proves you can't *touch* them. The switch changed your identity, not just a label.

```bash
kubectl config use-context kubernetes-admin@kubernetes
```

### Step 6 - Rename, delete, and the "delete all three" gotcha

```bash
kubectl config rename-context kubernetes-admin@kubernetes admin
```

```bash
kubectl config use-context admin
```

```bash
kubectl config delete-context viewer-ctx
```

```bash
kubectl config get-users
```

`viewer-user` is still listed - `delete-context` only removes the context entry. Cluster and user entries are orphaned, not garbage-collected. To fully prune you delete all three (`delete-context`, `delete-user`, `delete-cluster`).

```bash
kubectl config delete-user viewer-user
```

```bash
kubectl config rename-context admin kubernetes-admin@kubernetes
```

### Step 7 - `KUBECONFIG` env var + merging multiple files

`KUBECONFIG` accepts a colon-separated list of paths (semicolon on Windows). kubectl loads them all and merges.

```bash
cp ~/.kube/config /tmp/secondary.config
```

```bash
kubectl --kubeconfig=/tmp/secondary.config config rename-context kubernetes-admin@kubernetes secondary
```

```bash
KUBECONFIG=~/.kube/config:/tmp/secondary.config kubectl config get-contexts
```

Both contexts show - same cluster, same user, two context names.

```bash
KUBECONFIG=~/.kube/config:/tmp/secondary.config kubectl config view --flatten > /tmp/merged.config
```

`--flatten` resolves the merge into a single self-contained file. On name collision the first file wins, so cluster and user entries dedupe.

```bash
wc -l ~/.kube/config /tmp/secondary.config /tmp/merged.config
```

Merged is roughly the size of one file plus the extra context - clusters and users are deduped.

```bash
rm /tmp/secondary.config /tmp/merged.config
```

### Step 8 - Cleanup hygiene + cleanup verification

```bash
kubectl delete deployment nginx-demo
```

```bash
kubectl delete clusterrolebinding viewer-binding
```

```bash
kubectl delete serviceaccount viewer
```

```bash
kubectl config current-context
```

Should print `kubernetes-admin@kubernetes`.

```bash
kubectl get pods
```

Back to admin in the `default` namespace. Any `nginx-demo` pods still showing `Terminating` will clear in a few seconds - `kubectl delete deployment` returns as soon as the Deployment object is gone, but the underlying pods drain asynchronously. Re-run `kubectl get pods` and the namespace is empty.

## Verification

```bash
# Single context, named as expected
kubectl config current-context
# Should output: kubernetes-admin@kubernetes

# Default namespace pinned (or unset, which also resolves to 'default')
kubectl config view --minify -o jsonpath='{..namespace}{"\n"}'

# No leftover viewer artefacts
kubectl get serviceaccount viewer 2>&1 | grep -q "NotFound" && echo "viewer SA gone"
kubectl get clusterrolebinding viewer-binding 2>&1 | grep -q "NotFound" && echo "viewer-binding gone"
kubectl config get-users | grep -q viewer-user && echo "ORPHAN viewer-user" || echo "viewer-user gone"
kubectl config get-contexts -o name | grep -q viewer-ctx && echo "ORPHAN viewer-ctx" || echo "viewer-ctx gone"

# /tmp scratch files removed
ls /tmp/secondary.config /tmp/merged.config 2>&1 | grep -q "No such" && echo "tmp files gone"
```

## Cleanup

The lab self-cleans in Step 8. If you exited mid-lab, run:

```bash
kubectl delete deployment nginx-demo --ignore-not-found --force --grace-period=0
kubectl delete clusterrolebinding viewer-binding --ignore-not-found --force --grace-period=0
kubectl delete serviceaccount viewer --ignore-not-found --force --grace-period=0
kubectl config delete-context viewer-ctx 2>/dev/null || true
kubectl config delete-user viewer-user 2>/dev/null || true
kubectl config use-context kubernetes-admin@kubernetes 2>/dev/null || true
kubectl config set-context --current --namespace=default 2>/dev/null || true
rm -f /tmp/secondary.config /tmp/merged.config
```

## Further reading
- [Organizing Cluster Access Using kubeconfig Files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/) - concept page
- [Configure Access to Multiple Clusters](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/) - task walkthrough
- [`kubectl config` reference](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#config) - full subcommand list
