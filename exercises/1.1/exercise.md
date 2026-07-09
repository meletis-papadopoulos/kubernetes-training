# Exercise 1.1 - kubectl & Imperative vs Declarative

*Domain: Foundations. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace kdemo
```

## Tasks

1. Working in the namespace `kdemo`, create three objects the **imperative** way - one command each,
   no YAML. Create a Pod named `web` from image `nginx:1.27.1` exposing container port `80`
   (`kubectl run`). Create a Deployment named `api` from image `httpd:2.4.62` with `2` replicas
   (`kubectl create deployment`). Expose that Deployment as a ClusterIP Service named `api` on port
   `80` (`kubectl expose`). List the pods, deployments and services in `kdemo` to confirm all three
   exist. If you now re-ran the exact same three commands, which of them would fail and why?

2. Now do it the **declarative** way, but do not hand-write YAML. Scaffold a Deployment manifest for a
   Deployment named `cache` (image `nginx:1.27.1`, `1` replica) using
   `--dry-run=client -o yaml` redirected to a file `cache.yaml`, then `kubectl apply -f cache.yaml`.
   Edit the file to request `3` replicas, run `kubectl diff -f cache.yaml` to preview the change
   **before** applying, then apply it again. Confirm the Deployment reports `3` ready replicas. Why is
   re-running `kubectl apply` safe when re-running `kubectl create` is not - and in which situations
   does the declarative approach clearly win?

3. Use `kubectl explain` to discover the exact field path and default for a Pod's restart policy
   (start at `kubectl explain pod.spec` and drill into `restartPolicy`). Then, on the `web` Pod, add
   the **label** `tier=frontend` and the **annotation** `owner=team-a`, and prove the label took by
   filtering with `kubectl get pods -l tier=frontend`. Finally delete the Pod `web`, the Deployment
   `api`, its Service `api`, and the Deployment `cache` imperatively. A label selector matched
   `tier=frontend` - could it have matched the `owner=team-a` annotation instead? Why or why not?

## Acceptance criteria

- After Task 1, `kdemo` contains Pod `web`, Deployment `api` (`2/2`), and ClusterIP Service `api`.
- After Task 2, Deployment `cache` exists and reports `3` ready replicas; `kubectl diff` showed the
  `1 -> 3` replica change before the second apply.
- `kubectl explain pod.spec.restartPolicy` shows the field with default `Always`; `web` carries label
  `tier=frontend` and annotation `owner=team-a`; `kubectl get pods -l tier=frontend` returns `web`.
- All four objects are deleted at the end.

## Docs you may reference

- [kubectl reference](https://kubernetes.io/docs/reference/kubectl/)
- [Managing objects with imperative commands](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/imperative-command/)
- [Declarative management of objects](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/)
