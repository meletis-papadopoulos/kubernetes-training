# Exercise 8.2 - Solutions

Reference chart is in `solution/webapp-chart/` (identical to the one in `setup/webapp-chart/`).
Namespace `helm-demo` is assumed to exist (see the exercise Setup). Commands below run the chart
straight from its local path - no repo is added.

## Task 1 - lint and render, without touching the cluster

```bash
helm lint solution/webapp-chart
helm template my-web solution/webapp-chart
```

Expected (lint):

```
==> Linting solution/webapp-chart
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```

Expected highlights in the rendered manifests (illustrative):

```yaml
# Source: webapp/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-web
...
spec:
  replicas: 2
...
        image: "nginx:1.27.1"
```

Confirm nothing was created:

```bash
helm list -n helm-demo
kubectl get deploy,svc -n helm-demo -l app.kubernetes.io/instance=my-web
```

Expected: an empty release list and `No resources found in helm-demo namespace.`

**Answer to the reflective question:** `helm template` only renders the chart's templates into YAML
locally (client-side) and prints them; it never contacts the API server and records **no release**.
`helm install` does the extra work: it sends the rendered objects to the cluster **and** stores a
release record (revision 1) in a Secret in the namespace so the release can later be inspected,
upgraded, and rolled back. That release history is exactly what `template` skips.

## Task 2 - install the release

```bash
helm install my-web solution/webapp-chart --namespace helm-demo
helm list -n helm-demo
```

Expected:

```
NAME    NAMESPACE  REVISION  UPDATED  STATUS    CHART          APP VERSION
my-web  helm-demo  1         ...      deployed  webapp-0.1.0   1.27.1
```

Verify the pods:

```bash
kubectl rollout status deploy/my-web -n helm-demo
kubectl get pods -n helm-demo -l app.kubernetes.io/instance=my-web
```

Expected: two pods `Running` (the chart default `replicaCount: 2`).

```
NAME                     READY   STATUS    RESTARTS   AGE
my-web-xxxxxxxxxx-aaaaa  1/1     Running   0          15s
my-web-xxxxxxxxxx-bbbbb  1/1     Running   0          15s
```

## Task 3 - upgrade in place (scale to 3)

```bash
helm upgrade my-web solution/webapp-chart --namespace helm-demo --set replicaCount=3
helm list -n helm-demo
```

Expected: `REVISION` is now `2`, status `deployed`.

```bash
kubectl rollout status deploy/my-web -n helm-demo
kubectl get pods -n helm-demo -l app.kubernetes.io/instance=my-web
helm history my-web -n helm-demo
```

Expected (history, illustrative timestamps):

```
REVISION  UPDATED  STATUS      CHART          APP VERSION  DESCRIPTION
1         ...      superseded  webapp-0.1.0   1.27.1       Install complete
2         ...      deployed    webapp-0.1.0   1.27.1       Upgrade complete
```

**Answer to the reflective question:** `helm history` shows **two** revisions. Revision 1 is the
original install (now marked `superseded`, `replicaCount: 2`); revision 2 is the current `deployed`
state carrying the `--set replicaCount=3` override (three pods). Helm keeps every past revision so it
can diff and roll back between them.

## Task 4 - rollback to revision 1

```bash
helm rollback my-web 1 -n helm-demo
helm history my-web -n helm-demo
```

Expected:

```
REVISION  UPDATED  STATUS      CHART          APP VERSION  DESCRIPTION
1         ...      superseded  webapp-0.1.0   1.27.1       Install complete
2         ...      superseded  webapp-0.1.0   1.27.1       Upgrade complete
3         ...      deployed    webapp-0.1.0   1.27.1       Rollback to 1
```

```bash
kubectl rollout status deploy/my-web -n helm-demo
kubectl get pods -n helm-demo -l app.kubernetes.io/instance=my-web
```

Expected: two pods `Running` again (revision 1's `replicaCount: 2` config re-applied).

**Answer to the reflective question:** the release is now on **revision 3**. A rollback does not erase
history or reset the counter to 1 - it re-applies the *state* captured in revision 1 but records that
as a brand-new revision 3, so the timeline stays append-only and auditable. This is precisely what a
plain `kubectl apply` does **not** give you: Helm tracks a numbered, immutable history of every
applied state (stored as release Secrets), which is what makes `helm rollback` - reverting to an
earlier, known-good configuration in one command - possible. Bare `kubectl apply` keeps no such
revision ledger of the chart-level release.

## Task 5 - uninstall

```bash
helm uninstall my-web -n helm-demo
helm list -n helm-demo
kubectl get deploy,svc -n helm-demo -l app.kubernetes.io/instance=my-web
```

Expected:

```
release "my-web" uninstalled
```

and an empty release list plus `No resources found in helm-demo namespace.` - the Deployment and
Service Helm managed are removed with the release.

## Cleanup

```bash
helm uninstall my-web -n helm-demo --ignore-not-found 2>/dev/null
kubectl delete ns helm-demo --ignore-not-found
```
