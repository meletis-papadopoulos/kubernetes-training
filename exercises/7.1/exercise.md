# Exercise 7.1 - Namespaces

*Domain: Multi-tenancy & Security. Target: ~8 min. Do not open `solution/` until you have tried.*

## Setup

No setup beyond a running cluster (`provision.sh`). You will create every object in the tasks below.

## Tasks

1. Create two namespaces named `team-alpha` and `team-beta`, and put the label `team=alpha` on
   `team-alpha`. In `team-alpha`, create a Pod named `web` running the image `nginx:1.27.1`. Confirm
   the Pod is `Running` **in `team-alpha`** and that the same `kubectl get pod web` returns nothing in
   the `default` namespace. Why does the Pod exist from one namespace's point of view but not the
   other's?

2. Pin your kubectl context's default namespace to `team-alpha` with
   `kubectl config set-context --current --namespace=team-alpha`, then run `kubectl get pods` with
   **no** `-n` flag and confirm `web` shows up. Next, list every Pod in the cluster across **all**
   namespaces with a single command. Finally, restore the context's default namespace to `default`.
   Is the pinned namespace a property of your shell session, or of the kubeconfig context?

3. Delete the `team-beta` namespace, then delete `team-alpha` and watch the `web` Pod vanish along
   with it. Confirm both namespaces and the Pod are gone. Are **all** Kubernetes resources namespaced?
   Name two kinds that are cluster-scoped (live outside any namespace).

## Acceptance criteria

- `team-alpha` (labelled `team=alpha`) and `team-beta` both exist; Pod `web` is `Running` in
  `team-alpha` and absent from `default`.
- `kubectl config set-context --current --namespace=team-alpha` makes `kubectl get pods` show `web`
  with no `-n`; a single `--all-namespaces`/`-A` command lists Pods cluster-wide; the context's
  namespace is restored to `default`.
- Deleting `team-alpha` cascades: the namespace and its `web` Pod are both `NotFound` afterwards;
  `team-beta` is also gone.

## Docs you may reference

- [Namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
