# Exercise 8.1 - Solutions

Reference tree is in `solution/` (`solution/base/` and `solution/overlays/prod/`). The base
`deployment.yaml`/`service.yaml` are the same two files from `setup/`.

## Task 1 - base kustomization

`solution/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
labels:
- pairs:
    app: web
  includeSelectors: false
```

Render:

```bash
kubectl kustomize solution/base
```

Expected: the Deployment and Service, each with `app: web` under `metadata.labels`.

**Note on `includeSelectors: false`:** we add the label to metadata only, **not** to the Deployment's
`spec.selector`/pod-template selector. Selectors are immutable once applied, so folding a label into
them would block later promotion between environments. (This is the same reason the older
`commonLabels:` transformer is avoided here - it forces `includeSelectors: true`.)

## Task 2 - prod overlay

`solution/overlays/prod/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod-app
resources:
- ../../base
labels:
- pairs:
    env: prod
  includeSelectors: false
replicas:
- name: web
  count: 3
images:
- name: nginx
  newTag: 1.27.2
configMapGenerator:
- name: web-config
  literals:
  - TIER=prod
```

Render and confirm every transformation:

```bash
kubectl kustomize solution/overlays/prod
```

Expected highlights in the rendered YAML:

```
metadata:
  name: web
  namespace: prod-app
  labels:
    app: web
    env: prod
...
spec:
  replicas: 3
...
        image: nginx:1.27.2
...
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-config-<hash>     # generator base name + hash suffix
  namespace: prod-app
data:
  TIER: prod
```

## Task 3 - apply and verify

```bash
kubectl apply -k solution/overlays/prod
kubectl get deploy,svc,cm -n prod-app
```

Expected:

```
NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/web   3/3     3            3           20s

NAME          TYPE        CLUSTER-IP     PORT(S)   AGE
service/web   ClusterIP   10.96.x.x      80/TCP    20s

NAME                         DATA   AGE
configmap/web-config-abcdef123   1   20s
```

**Answer:** the ConfigMap is `web-config-<hash>` (generator base name `web-config` + a content hash).
Kustomize appends the hash so that **changing the ConfigMap's data
changes its name**, which forces any Deployment referencing it to roll out - a built-in way to avoid
stale config. Disable it with `generatorOptions.disableNameSuffixHash: true` if you need a fixed name.

## Cleanup

```bash
kubectl delete -k solution/overlays/prod --ignore-not-found
kubectl delete ns prod-app --ignore-not-found
rm -rf base overlays    # the working copies created in Setup
```
