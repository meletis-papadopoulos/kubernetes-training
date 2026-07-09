# Lab 8.2 - Helm

## Objective
Learn how to use Helm to install, upgrade, rollback, and manage Kubernetes applications. Understand Helm charts, releases, revisions, and values - using a **self-contained local chart** shipped with this lab (`webapp-chart/`), so there's no external chart repository to depend on.

## Prerequisites
- cluster provisioned with `provision.sh`
- Helm installed (`helm version` should work)
- Namespace `training` created: `kubectl create namespace training`
- Run these commands from the lab directory: `cd labs/8.2` (the chart is at `./webapp-chart`)

## Steps

### 1. Verify Helm and look at the chart

```bash
helm version
ls webapp-chart webapp-chart/templates
```

`webapp-chart/` is a minimal chart: `Chart.yaml` (metadata), `values.yaml` (defaults), and `templates/` (a templated Deployment + Service + NOTES).

### 2. Lint the chart

```bash
helm lint ./webapp-chart
```

`helm lint` validates the chart structure and templates before you install.

### 3. Inspect the chart's default values

```bash
helm show chart ./webapp-chart      # chart metadata (name, version, appVersion)
helm show values ./webapp-chart     # configurable values + defaults
```

These are the configurable values and their defaults (replicaCount, image, service, resources).

### 4. Render the templates locally (no cluster changes)

```bash
helm template my-web ./webapp-chart --set replicaCount=2
```

`helm template` shows exactly what Helm would apply - useful for review before installing.

### 5. Install the chart

```bash
helm install my-web ./webapp-chart \
  --namespace training \
  --set replicaCount=2
```

### 6. Verify the installation

```bash
helm list -n training
kubectl get all -n training -l app.kubernetes.io/instance=my-web
```

### 7. Get the deployed values

```bash
helm get values my-web -n training
helm get values my-web -n training --all
```

The first shows only the values you set; `--all` shows defaults + overrides.

### 8. Get other release information

```bash
helm get manifest my-web -n training | head -40   # rendered manifests
helm get notes my-web -n training                  # release notes (from NOTES.txt)
helm status my-web -n training                      # full release status
helm get all my-web -n training | head -40          # values + manifest + notes + hooks in one
```

### 9. Upgrade the release (scale up)

```bash
helm upgrade my-web ./webapp-chart \
  --namespace training \
  --set replicaCount=3
```

### 10. Verify the upgrade

```bash
helm list -n training
kubectl get pods -n training -l app.kubernetes.io/instance=my-web
```

The REVISION column now shows `2`; there should be 3 pods.

### 11. View release history

```bash
helm history my-web -n training
```

### 12. Rollback to the first revision

```bash
helm rollback my-web 1 -n training
```

### 13. Verify the rollback

```bash
helm list -n training
kubectl get pods -n training -l app.kubernetes.io/instance=my-web
```

REVISION is now `3` (rollbacks create a new revision), and the pod count is back to 2.

### 14. Upgrade with a values file

```bash
cat <<'EOF' > /tmp/web-values.yaml
replicaCount: 2
service:
  type: ClusterIP
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi
EOF

helm upgrade my-web ./webapp-chart --namespace training -f /tmp/web-values.yaml
```

This is REVISION `4` - same 2 replicas, now with resource requests/limits.

### 15. Simulate a bad deployment and recover

Push a broken upgrade with a non-existent image tag:

```bash
helm upgrade my-web ./webapp-chart -n training \
  --set image.tag=doesnotexist999 \
  --set replicaCount=2
```

Give the new ReplicaSet time to attempt pulls, then observe - old pods keep running (rolling-update protection):

```bash
sleep 30
kubectl get pods -n training -l app.kubernetes.io/instance=my-web -o wide
```

The new pod is stuck in `ErrImagePull` / `ImagePullBackOff` while the existing pods stay `Running`.

Check the damage:

```bash
helm list -n training
kubectl describe pod -n training -l app.kubernetes.io/instance=my-web | grep -A3 "State:"
```

Rollback to the last known-good revision (revision 4, the values-file upgrade):

```bash
helm rollback my-web 4 -n training
```

Verify recovery:

```bash
kubectl get pods -n training -l app.kubernetes.io/instance=my-web
helm history my-web -n training
```

The history shows the full lifecycle - install, upgrade, rollback, upgrade (values file), broken upgrade, rollback-to-recovery (6 revisions). Each action, including rollbacks, creates a new revision number.

### 16. List releases across the cluster

```bash
helm list --all-namespaces
```

You'll see the components `provision.sh` installed - ingress-nginx, cert-manager, metrics-server, and gatekeeper - alongside `my-web`.

### 17. Inspect a provisioned release

```bash
helm get values ingress-nginx -n ingress-nginx 2>/dev/null || echo "Chart not found in this namespace"
```

### 18. Uninstall the release

```bash
helm uninstall my-web -n training
```

### 19. Verify removal

```bash
helm list -n training
kubectl get all -n training -l app.kubernetes.io/instance=my-web
```

## Key Helm Commands Summary

| Command | Purpose |
|---------|---------|
| `helm search repo` / `show chart` / `show values` | Discover a chart and its options |
| `helm lint` | Validate a chart |
| `helm template` | Render manifests locally (no apply) |
| `helm install` / `upgrade --install` | Install (the `--install` form is idempotent) |
| `helm upgrade` (+ `--dry-run` / `--atomic` / `--wait`) | Apply new values safely |
| `helm rollback` | Rollback to a previous revision (creates a new one) |
| `helm list` | List releases (`-A` = all namespaces) |
| `helm status` | Release state + NOTES |
| `helm history` | View release history |
| `helm get values` / `manifest` / `notes` / `all` | Inspect a release |
| `helm uninstall` | Remove a release (`--keep-history` to retain) |

## Challenge - the same change, both ways

Back in step 9 you scaled this app to 3 replicas with Helm. The *identical* change in Kustomize
(Lab 8.1) looks completely different - compare the two mental models (illustrative, not run by the
walkthrough):

    # Helm - set a value; the template fills in `replicas: {{ .Values.replicaCount }}`
    helm upgrade my-web ./webapp-chart -n training --set replicaCount=3

    # Kustomize - strategic-merge a patch onto the plain YAML you own
    #   overlays/prod/replica-patch.yaml:
    #     spec:
    #       replicas: 3
    kubectl apply -k overlays/prod          # from Lab 8.1

Both land 3 replicas. Helm **renders** a template from a value; Kustomize **patches** complete YAML -
no placeholders, no release state to track. Same result, opposite philosophy. Many teams use both:
Helm to package an app, Kustomize to patch it per environment.

## Cleanup

```bash
helm uninstall my-web -n training 2>/dev/null
rm -f /tmp/web-values.yaml
```

## Further reading
- [Helm documentation](https://helm.sh/docs/) - official docs
- [Helm Quickstart](https://helm.sh/docs/intro/quickstart/) - tutorial
- [Chart Best Practices](https://helm.sh/docs/chart_best_practices/) - reference
