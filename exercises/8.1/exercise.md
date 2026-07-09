# Exercise 8.1 - Kustomize

*Domain: Packaging & Extensibility. Target: ~12 min. Do not open `solution/` until you have tried.*
*Authored in-house (not derived from a study guide); grounded in the official docs linked below.*

## Setup

You are given two raw manifests in `setup/` - a Deployment `web` (nginx:1.27.1, 1 replica) and a
Service `web`. Copy them into a working `base/` directory to build on:

```bash
mkdir -p base overlays/prod
cp setup/deployment.yaml setup/service.yaml base/
kubectl create namespace prod-app
```

Use `kubectl kustomize <dir>` to render (no cluster change) and `kubectl apply -k <dir>` to apply.

## Tasks

1. Author `base/kustomization.yaml` so that it includes both `deployment.yaml` and `service.yaml` as
   resources and stamps the common label `app: web` onto every resource it manages. Render the base
   with `kubectl kustomize base` and confirm both objects appear with the label.

2. Author an overlay in `overlays/prod/kustomization.yaml` that builds on `../../base` and applies
   **all** of the following, without editing any base file:
   - target namespace `prod-app`
   - an extra common label `env: prod`
   - the Deployment scaled to `3` replicas (use the kustomize `replicas` field, not a hand-written
     patch)
   - the container image tag overridden to `nginx:1.27.2` (use the kustomize `images` field)
   - a `configMapGenerator` producing a ConfigMap named `web-config` from the literal `TIER=prod`

   Render with `kubectl kustomize overlays/prod` and confirm every transformation took effect.

3. Apply the prod overlay to the cluster and verify the live objects. What is the exact name of the
   generated ConfigMap, and why does it end in a hash suffix?

## Acceptance criteria

- `kubectl kustomize base` emits the Deployment and Service, both carrying `app: web`.
- `kubectl kustomize overlays/prod` shows: `namespace: prod-app`, labels
  `app: web` + `env: prod`, Deployment `replicas: 3`, image `nginx:1.27.2`, and a `web-config-<hash>`
  ConfigMap with `TIER: prod`.
- After `kubectl apply -k overlays/prod`, `kubectl get deploy,svc,cm -n prod-app` shows `web`
  (3/3), `web` Service, and `web-config-<hash>`.

## Docs you may reference

- [Declarative Management with Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
- [Kustomize reference (kubectl)](https://kubectl.docs.kubernetes.io/references/kustomize/)
