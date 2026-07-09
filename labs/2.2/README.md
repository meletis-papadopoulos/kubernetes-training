# Lab 2.2 - Multi-Container Pods

## Objective
Learn why a Pod can hold **more than one container**, and the two most common patterns for it:
- the **sidecar** pattern - helper containers that run *alongside* your app and share its resources, and
- the **init container** pattern - setup containers that run *to completion, in order, before* your app starts.

You'll see how containers in the same Pod share a network and a volume, and why that co-location is the whole point.

## Background - what a Pod actually guarantees
A Pod is not "one container." It's a group of containers that are **always scheduled together on the same node** and share two things:

- **A network namespace** - every container in the Pod shares the same IP address and `localhost`. Container A can reach container B on `localhost:<port>`.
- **Storage volumes** - any `volume` declared on the Pod can be mounted into multiple containers, so they can hand files to each other.

They do **not** share a filesystem by default (each container has its own root FS) - sharing happens only through the volumes you mount into both. That shared-fabric-but-isolated-processes model is exactly what makes the sidecar and init patterns work.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

---

## Part A - The Sidecar Pattern

A **sidecar** is a second container that extends or supports the main app without being baked into it - log shippers, proxies, config reloaders, metrics exporters. It shares the Pod's volumes/network, so it can observe or serve the app's data.

In `pod-sidecar.yaml`: the **`app`** container appends a timestamp to `/shared/log.txt` every 5 seconds; the **`sidecar`** container `tail -f`s that same file. They share it through an `emptyDir` volume mounted into both.

### 1. Create the sidecar Pod

```bash
kubectl apply -f pod-sidecar.yaml
kubectl wait --for=condition=Ready pod/sidecar-demo -n training --timeout=60s
```

### 2. Note that the Pod has TWO containers ready

```bash
kubectl get pod sidecar-demo -n training
```

Look at the **READY** column: `2/2` - both containers must be running for the Pod to be Ready.

### 3. Read each container's logs separately

Because there are multiple containers, you must say **which one** with `-c`:

```bash
kubectl logs sidecar-demo -c app -n training
kubectl logs sidecar-demo -c sidecar -n training
```

The `app` log shows it writing timestamps; the `sidecar` log shows the **same lines** - it's reading what `app` wrote, purely through the shared volume. Neither container knows about the other's process; they only meet at `/shared`.

### 4. Prove the volume is shared, not copied

```bash
kubectl exec sidecar-demo -c sidecar -n training -- cat /shared/log.txt
kubectl exec sidecar-demo -c app -n training -- cat /shared/log.txt
```

Identical output from both containers - it's one `emptyDir` mounted twice, not two copies.

> **Why this matters:** the classic real-world sidecar is a **log shipper** (app writes logs to a shared volume; a Fluent Bit sidecar reads and forwards them) or a **service-mesh proxy** (Envoy intercepts the app's traffic on `localhost`). Same mechanics as this toy.

---

## Part B - Init Containers

An **init container** runs **before** the app containers, **to completion**, and **in the order listed**. If an init container fails, the kubelet restarts it until it succeeds - the app containers never start until every init container has finished. Use them for setup work that must happen first: fetching config/secrets, running migrations, waiting for a dependency, or preparing a shared volume.

In `pod-init.yaml`: the **`setup`** init container writes an `index.html` into a shared `work` volume; then the **`web`** (nginx) container starts and serves exactly that file.

### 5. Create the init Pod

```bash
kubectl apply -f pod-init.yaml
```

### 6. Watch the init phase (do this immediately)

```bash
kubectl get pod init-demo -n training
```

For the first moment you may catch `STATUS: Init:0/1` (the init container is running) or `PodInitializing`, then it flips to `Running`. That transition **is** the init phase - the app container was held back until `setup` finished.

If you missed it, `describe` shows the ordered lifecycle:

```bash
kubectl describe pod init-demo -n training
```

Under **Events** you'll see the init container `Pulled → Created → Started` and complete, *then* the `web` container start.

Wait for the app container to be ready before inspecting it:

```bash
kubectl wait --for=condition=Ready pod/init-demo -n training --timeout=60s
```

### 7. Read the init container's logs

```bash
kubectl logs init-demo -c setup -n training
```

Init containers have logs too, addressed with `-c <init-name>` - your first stop when a Pod is stuck in `Init:`.

### 8. Confirm the app served what init prepared

```bash
kubectl exec init-demo -c web -n training -- cat /usr/share/nginx/html/index.html
```

Output: `prepared by the init container`. The nginx container never wrote that file - the init container did, and handed it over through the shared `work` volume before nginx ever started.

---

## Sidecar vs Init - the key difference
| | Init container | Sidecar (app) container |
|---|---|---|
| When it runs | Before app containers, to completion | Alongside app containers, for the Pod's life |
| Order | Sequential, in listed order | Concurrent |
| Counts toward READY | No (must finish first) | Yes (must stay running) |
| Typical use | Setup: fetch/prepare/wait/migrate | Ongoing helper: logs, proxy, metrics |

> **Note (Kubernetes 1.28+):** there is now a *native* sidecar - an init container with `restartPolicy: Always` - which starts before the app but keeps running alongside it. This lab uses the classic patterns (portable across versions); the native sidecar is a refinement of the same idea.

## Verification

```bash
# Sidecar Pod: both containers ready (2/2)
kubectl get pod sidecar-demo -n training -o jsonpath='{.status.containerStatuses[*].ready}'
# Should output: true true

# Init Pod: app is serving the file the init container wrote
kubectl exec init-demo -c web -n training -- cat /usr/share/nginx/html/index.html
# Should output: prepared by the init container

# Init Pod reached Running (init completed)
kubectl get pod init-demo -n training -o jsonpath='{.status.phase}'
# Should output: Running
```

## Cleanup

```bash
kubectl delete -f pod-sidecar.yaml -f pod-init.yaml --force --grace-period=0 --ignore-not-found
```

## Further reading
- [Pods - multiple containers](https://kubernetes.io/docs/concepts/workloads/pods/#how-pods-manage-multiple-containers) - concept reference
- [Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/) - behaviour, ordering, and debugging
- [Sidecar Containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/) - the native (1.28+) sidecar
- [Communicate between containers via a shared volume](https://kubernetes.io/docs/tasks/access-application-cluster/communicate-containers-same-pod-shared-volume/) - task walkthrough
