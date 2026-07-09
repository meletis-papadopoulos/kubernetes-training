# Exercise 7.4 - Kubeconfig (contexts, SA-token context, merging)

*Domain: Multi-tenancy & Security. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

No setup beyond your working kubeconfig (`~/.kube/config`, with a current context that can create
ServiceAccounts and ClusterRoleBindings). This exercise edits **only your client-side kubeconfig** and
one ServiceAccount - it never changes cluster workloads.

## Tasks

1. Inspect where you are: print the current context name, then `kubectl config view --minify` to see
   the `(cluster, user, namespace)` your requests currently resolve to. Now create a **new context**
   named `dev-ctx` that reuses your existing cluster and user but pins its default namespace to
   `kube-system` (`kubectl config set-context dev-ctx --cluster=<c> --user=<u> --namespace=kube-system`).
   Switch to it with `use-context`, run `kubectl get pods` (no `-n`) to confirm you now see
   `kube-system` Pods, then switch back to your original context. What three things does a context
   bind together?

2. Build a second identity from a ServiceAccount token and wire it into a context. Create a
   ServiceAccount `viewer` in `default` bound to a custom read-only ClusterRole `pod-viewer`
   (get/list/watch on pods; manifest provided),
   mint a token with `kubectl create token viewer --duration=1h`, register it as a kubeconfig user
   with `kubectl config set-credentials viewer-user --token=<token>`, then create context `viewer-ctx`
   (same cluster, user `viewer-user`, namespace `default`) and `use-context` it. Run
   `kubectl auth whoami` and confirm the username is now `system:serviceaccount:default:viewer`, then
   switch back to your admin context. Same kubectl, same cluster - what made you a different user?

3. Demonstrate `KUBECONFIG` merging. Copy `~/.kube/config` to `/tmp/second.config`, rename the context
   inside that copy to `second`, then run
   `KUBECONFIG=~/.kube/config:/tmp/second.config kubectl config get-contexts` and confirm contexts
   from **both** files appear in one merged view. Produce a single self-contained file with
   `kubectl config view --flatten`. Reflective: when the same cluster/user name appears in both files,
   which file's entry wins?

## Acceptance criteria

- Context `dev-ctx` exists pinned to `kube-system`; switching to it makes `kubectl get pods` (no `-n`)
  show `kube-system` Pods; you returned to your original context afterwards.
- ServiceAccount `viewer` (bound to ClusterRole `pod-viewer`) exists; user `viewer-user` and context `viewer-ctx` are in
  the kubeconfig; under `viewer-ctx`, `kubectl auth whoami` reports
  `system:serviceaccount:default:viewer`.
- `KUBECONFIG=~/.kube/config:/tmp/second.config kubectl config get-contexts` lists contexts from both
  files; `--flatten` produces one merged kubeconfig.

## Docs you may reference

- [Organizing Cluster Access Using kubeconfig Files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)
- [Configure Access to Multiple Clusters](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/)
