# Lab 8.1 - Kustomize

## Objective
Learn how to use Kustomize to manage Kubernetes manifests with a base/overlay pattern. Create environment-specific configurations (dev vs prod) without duplicating YAML.

## Prerequisites
- cluster provisioned with `provision.sh` (kubectl has kustomize built in)
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 0. Ensure the training namespace exists

```bash
kubectl create namespace training 2>/dev/null || true
```

### 1. Understand the directory structure

```
8.1/
  base/
    deployment.yaml      # Base deployment (2 replicas)
    service.yaml         # Base service
    kustomization.yaml   # Base kustomization - REQUIRED
  overlays/
    dev/
      kustomization.yaml # Dev overlay - REQUIRED
      replica-patch.yaml # Patch to reduce replicas
    prod/
      kustomization.yaml # Prod overlay - REQUIRED
      replica-patch.yaml # Patch to increase replicas
```

**Every directory Kustomize processes needs its own `kustomization.yaml`.** Without it, `kubectl apply -k <dir>` has no entry point and errors with `unable to find one of 'kustomization.yaml'`. The base file lists the actual K8s resources; each overlay file references the base via `resources: [../../base]` and layers env-specific patches/labels/namespace on top.

> **Keep `apiVersion: kustomize.config.k8s.io/v1beta1` and `kind: Kustomization`** at the top of every `kustomization.yaml`. Kustomize tolerates omitting them, but you lose editor schema validation, lose version pinning (Kustomize is migrating to `v1`), and the file stops being self-describing. Two lines, no upside to dropping them.

### Mental model - three orders to keep separate

| Order | Question it answers |
|---|---|
| **Authoring** | Build `base/` first (shared bones) → then `overlays/<env>/` (env-specific deltas). Never the other way around. |
| **Apply** | Always `kubectl apply -k overlays/<env>/`. **Never apply the base directly to a real cluster** - base is intentionally incomplete (no namespace, no env label, generic replica count). |
| **Runtime evaluation** | Kustomize starts at the directory you point at → resolves `resources:` references (recurses into base) → applies base's transformers → layers overlay patches → applies overlay's transformers → emits final merged YAML to the API server. *Inside-out, then top-down.* |

### 2. Preview the base output

```bash
kubectl kustomize base/
```

This shows the rendered YAML without applying it. You should see the deployment with 2 replicas and the `managed-by: kustomize` label. Notice two things the raw files don't show:
- A generated `ConfigMap` named `app-settings-<hash>` (not just `app-settings`) - `configMapGenerator` appends a content hash to the name.
- The Deployment's `envFrom.configMapRef.name` has been **rewritten to that same hashed name** - Kustomize keeps the reference in sync automatically.

> **Preview only.** `kubectl kustomize` (no `apply`) is fine for inspecting what the base would render - useful while authoring. **Never `kubectl apply -k base/`** against a real cluster: the base has no namespace, no env label, and a generic replica count - applying it would deploy a workload that represents no real environment.

### 3. Preview the dev overlay

```bash
kubectl kustomize overlays/dev/
```

Compare with the base:
- Replicas: 1 (patched from 2)
- `environment: dev` label on `metadata.labels` only (NOT on selectors - keeps selectors stable across environments)
- Namespace: `training`

### 4. Preview the prod overlay

```bash
kubectl kustomize overlays/prod/
```

Compare:
- Replicas: 3 (patched from 2)
- `environment: prod` label on `metadata.labels` only (NOT on selectors)
- Namespace: `training`
- Image: `nginx:1.27` (pinned by the `images:` transformer in the prod overlay - dev stays on the base `nginx:1.25`, and neither needed a patch file)

> **Why `includeSelectors: false` for env labels?** The Deployment's `.spec.selector` is **immutable** after creation. If we included `environment:` in the selector, we could never transition from dev to prod (or vice versa) using the same deployment name - kubectl would reject the apply with `field is immutable`. Keeping env labels out of selectors is the idiomatic Kustomize pattern. The base's `managed-by: kustomize` label stays in selectors because it's stable across environments.

### 5. Apply the dev overlay

You apply the **overlay**, not the base. Kustomize walks the `resources: [../../base]` reference automatically and assembles the merged YAML - you never apply base and overlay separately.

```bash
kubectl apply -k overlays/dev/
```

### 6. Verify the dev deployment

```bash
kubectl get deployment kustom-app -n training
kubectl get pods -n training -l app=kustom-app
```

Should show 1 replica with the `environment: dev` label.

```bash
kubectl get deployment kustom-app -n training -o jsonpath='{.metadata.labels}'
```

### 7. Apply the prod overlay (overwrites dev)

```bash
kubectl apply -k overlays/prod/
```

### 8. Verify the prod deployment

```bash
kubectl get deployment kustom-app -n training
kubectl get pods -n training -l app=kustom-app
```

Should show 3 replicas with the `environment: prod` label.

### 9. See the generated ConfigMap and its hash suffix

The prod overlay you just applied created a ConfigMap from the base's `configMapGenerator` - with a content hash in its name:

```bash
kubectl get configmap -n training -l app=kustom-app
kubectl get pod -n training -l app=kustom-app \
  -o jsonpath='{.items[0].spec.containers[0].envFrom[0].configMapRef.name}{"\n"}'
```

Both print the same `app-settings-<hash>` name. The pod's `envFrom` points at the hashed name, not the bare `app-settings` - Kustomize rewrote the reference for you.

### 10. Change a value and watch the hash trigger a rollout

Edit the literal in `base/kustomization.yaml` (change `LOG_LEVEL=info` to `LOG_LEVEL=debug`), then re-apply prod and watch:

```bash
sed -i 's/LOG_LEVEL=info/LOG_LEVEL=debug/' base/kustomization.yaml
kubectl apply -k overlays/prod/
kubectl rollout status deployment/kustom-app -n training
kubectl get configmap -n training -l app=kustom-app
```

The new content produces a **new hash** → a new ConfigMap name → the Deployment's pod template changes → a rolling update. This is the whole point of `configMapGenerator`: config changes roll pods automatically, instead of silently leaving old pods running stale config (the trap you hit with a hand-written ConfigMap in Lab 3.1). Kustomize also garbage-collects the old hashed ConfigMap on apply.

Restore the literal so the lab is repeatable:

```bash
sed -i 's/LOG_LEVEL=debug/LOG_LEVEL=info/' base/kustomization.yaml
```

### 11. Use diff to see what would change

```bash
kubectl diff -k overlays/dev/
```

This shows what would change if you applied the dev overlay again.

### 12. Understand Kustomize features

| Feature | Purpose |
|---------|---------|
| `apiVersion` + `kind` | Schema declaration - keep at the top of every `kustomization.yaml` |
| `resources` | List of base manifests (or `../<other-dir>` to compose from another kustomization) |
| `labels` | Add labels to all resources (replaces deprecated `commonLabels`); use `includeSelectors:false` for env labels to keep selectors stable |
| `namespace` | Set namespace for all resources |
| `patches` | Modify specific fields (strategic merge or JSON 6902) |
| `namePrefix` | Add prefix to all resource names |
| `nameSuffix` | Add suffix to all resource names |
| `images` | Override image name/tag/digest without editing the base |
| `replicas` | Override replica count without a patch file |
| `configMapGenerator` | Generate ConfigMaps from files/literals (auto hash suffix triggers rollout on change) |
| `secretGenerator` | Generate Secrets from files/literals (same hash-suffix behavior) |

### 13. Kustomize vs Helm

| Feature | Kustomize | Helm |
|---------|-----------|------|
| Approach | Overlay/patch | Template |
| Complexity | Simple | More complex |
| Built into kubectl | Yes | Separate binary |
| Parameterization | Patches only | Full templating |
| Package distribution | Not designed for it | Charts in repos |
| Best for | Internal config management | Distributable packages |

## Verification

```bash
# Rendered output includes correct replicas
kubectl kustomize overlays/dev/ | grep "replicas:"
# Should show: replicas: 1

kubectl kustomize overlays/prod/ | grep "replicas:"
# Should show: replicas: 3

# Labels are applied
kubectl kustomize overlays/dev/ | grep "environment:"
# Should show: environment: dev
```

## Cleanup

```bash
kubectl delete -k overlays/prod/ --ignore-not-found --force --grace-period=0
# dev overlay targets the same resource names - --ignore-not-found makes this safe to run either way
kubectl delete -k overlays/dev/ --ignore-not-found --force --grace-period=0
```

## Further reading
- [Declarative Management with Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) - task walkthrough
- [Kustomize introduction](https://kubectl.docs.kubernetes.io/guides/introduction/kustomize/) - official guide
