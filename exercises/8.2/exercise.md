# Exercise 8.2 - Helm

*Domain: Packaging & Extensibility. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

You are given a self-contained local chart in `setup/webapp-chart/` - `Chart.yaml` (metadata),
`values.yaml` (defaults: `replicaCount: 2`, image `nginx:1.27.1`, a `ClusterIP` Service on port 80),
and a templated Deployment + Service in `templates/`. Run every `helm` command against that local
path - there is **no** external chart repository.

```bash
kubectl create namespace helm-demo
```

## Tasks

1. Before touching the cluster, validate and preview the chart. Run `helm lint` against
   `setup/webapp-chart` and confirm it reports no failures. Then render the chart locally with
   `helm template` under the release name `my-web`, and read the output: confirm the rendered
   Deployment carries `replicas: 2` and the image `nginx:1.27.1`. Nothing should appear in
   `helm list` or `kubectl get` afterwards - why not? What does `helm template` deliberately **not**
   do that `helm install` does?

2. Install the chart as a release named `my-web` into namespace `helm-demo` from the local path
   `setup/webapp-chart`. Confirm with `helm list -n helm-demo` that the release is present at
   **revision 1** with status `deployed`, and that two pods carrying the label
   `app.kubernetes.io/instance=my-web` are `Running`.

3. Upgrade the **same** release in place, overriding only the replica count to `3` via
   `--set replicaCount=3` (do not edit any chart file). Confirm the release is now at **revision 2**
   and that three pods are running. Then run `helm history my-web -n helm-demo` - how many revisions
   does Helm show, and what distinguishes revision 1 from revision 2?

4. You decide the scale-up was a mistake. Roll the release back to **revision 1** with
   `helm rollback`, then inspect the history again. What revision number is the release on now, how
   many pods are running, and why did rolling *back* create a *new*, higher revision rather than
   simply reverting to revision 1? What does Helm track across these actions that a plain
   `kubectl apply` of the same manifests would not?

5. Remove the release entirely with `helm uninstall` and confirm that both the release and its
   managed objects are gone from `helm-demo`.

## Acceptance criteria

- `helm lint setup/webapp-chart` passes; `helm template my-web setup/webapp-chart` renders a
  Deployment with `replicas: 2` and image `nginx:1.27.1`, and creates **nothing** on the cluster.
- `my-web` is installed in `helm-demo` at revision 1 (2 pods), then upgraded to revision 2 (3 pods).
- `helm history` lists the successive revisions; after `helm rollback my-web 1` the release is at
  **revision 3** with 2 pods running again.
- `helm uninstall my-web -n helm-demo` removes the release; `helm list -n helm-demo` is empty and no
  `app.kubernetes.io/instance=my-web` objects remain.

## Docs you may reference

- [Helm documentation](https://helm.sh/docs/)
- [Charts](https://helm.sh/docs/topics/charts/)
