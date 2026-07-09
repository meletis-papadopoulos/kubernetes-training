# Lab 1.1 - kubectl & Imperative vs Declarative

## Objective
Get comfortable with `kubectl` before building anything: talk to the cluster, discover resources, and understand the two ways to manage objects - **imperative** (quick commands) and **declarative** (YAML you apply). This is the on-ramp for every lab that follows.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Talk to the cluster

```bash
kubectl cluster-info
kubectl get nodes -o wide
```

`cluster-info` shows the control-plane endpoint; `get nodes` shows the machines you can schedule on (`controlplane` + `node01`).

### 2. Discover what you can create

```bash
kubectl api-resources | head -20
```

Every object type (`pods`, `deployments`, `services`, …), its short name (`po`, `deploy`, `svc`), and whether it's namespaced.

### 3. Learn a resource's fields without leaving the terminal

```bash
kubectl explain pod
kubectl explain pod.spec.containers
```

`kubectl explain` is your built-in documentation - use it whenever you forget a field.

### 4. Imperative: create things with a single command

```bash
kubectl run nginx --image=nginx:1.25 -n training
kubectl create deployment web --image=nginx:1.25 --replicas=2 -n training
```

**Imperative** = you tell Kubernetes *what to do, now*. Fast, great for one-offs and exams.

### 5. Inspect what you made

```bash
kubectl get pods,deployments -n training
kubectl get pod nginx -n training -o wide
kubectl describe deployment web -n training
```

`get` for a summary, `-o wide` for more columns, `-o yaml` for the full object, `describe` for a human-readable breakdown + events.

### 6. Imperative edit and scale

```bash
kubectl scale deployment web --replicas=3 -n training
kubectl label pod nginx tier=frontend -n training
kubectl get pods -n training --show-labels
```

### 7. Declarative: generate YAML instead of applying blindly

```bash
kubectl create deployment web2 --image=nginx:1.25 --replicas=2 -n training --dry-run=client -o yaml > web2.yaml
cat web2.yaml
```

`--dry-run=client -o yaml` builds the manifest **without touching the cluster** - the fastest way to author correct YAML.

### 8. Apply the manifest

```bash
kubectl apply -f web2.yaml
```

**Declarative** = you describe the *desired state* in a file and `apply` it. Re-applying is safe (idempotent), and the file is your source of truth - the model for GitOps/production.

### 9. `apply` is idempotent; preview changes with `diff`

```bash
sed -i 's/replicas: 2/replicas: 4/' web2.yaml
kubectl diff -f web2.yaml        # shows exactly what would change
kubectl apply -f web2.yaml       # applies only the diff
```

### 10. Filter with label selectors

```bash
kubectl get pods -n training -l app=web
kubectl get pods -n training -l tier=frontend
```

Selectors are how you target subsets of objects - the same mechanism Services and controllers use internally.

## Imperative vs Declarative - when to use which
| | Imperative (`run`, `create`, `scale`, `edit`) | Declarative (`apply -f`) |
|---|---|---|
| Style | Do it now | Describe desired state |
| Best for | Quick tasks, learning, exams | Repeatable, reviewable, production/GitOps |
| Re-run | May error ("already exists") | Safe / idempotent |
| Source of truth | The live cluster | The YAML file |

## Verification

```bash
# Deployment created declaratively is running
kubectl get deployment web2 -n training -o jsonpath='{.status.readyReplicas}'
# Should output a number (2, or 4 after step 9)
```

## Cleanup

```bash
kubectl delete deployment web web2 -n training --ignore-not-found
kubectl delete pod nginx -n training --force --grace-period=0 --ignore-not-found
rm -f web2.yaml
```

## Further reading
- [kubectl overview](https://kubernetes.io/docs/reference/kubectl/) - command structure
- [Managing objects: imperative vs declarative](https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/) - the three management styles
- [kubectl quick reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/) - cheat sheet
