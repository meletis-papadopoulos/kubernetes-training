# Exercise 2.2 - Solutions

Reference manifest is in `solution/`. Namespace `core` is assumed to exist (see the exercise Setup).
Both tasks build the same Pod - `solution/multi-pod.yaml` is the final, three-container version.

## Task 1 - init container prepares a shared emptyDir

Build the Pod with the ordinary init container `seed` and the main `app` container sharing an
`emptyDir` (the final manifest below also contains the native sidecar from Task 2):

```bash
kubectl apply -f solution/multi-pod.yaml
kubectl wait --for=condition=Ready pod/shared-demo -n core --timeout=90s
```

`solution/multi-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shared-demo
  namespace: core
  labels:
    app: shared-demo
spec:
  volumes:
  - name: shared
    emptyDir: {}
  initContainers:
  - name: seed
    image: busybox:1.36
    command: ["sh", "-c", "echo \"seeded at $(date)\" > /shared/app.log"]
    volumeMounts:
    - name: shared
      mountPath: /shared
  - name: streamer
    image: busybox:1.36
    restartPolicy: Always
    command: ["sh", "-c", "tail -f /shared/app.log"]
    volumeMounts:
    - name: shared
      mountPath: /shared
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do date >> /shared/app.log; sleep 5; done"]
    volumeMounts:
    - name: shared
      mountPath: /shared
```

Confirm the main container sees what `seed` wrote:

```bash
kubectl logs shared-demo -c seed -n core
kubectl exec shared-demo -c app -n core -- head -n1 /shared/app.log
```

Expected (timestamp illustrative):

```
seeded at Wed Jul  8 10:00:00 UTC 2026
```

**Answer to the reflective question:** if `seed` exited non-zero the Pod would be stuck in
`Init:Error` / `Init:CrashLoopBackOff` - the kubelet restarts a failed init container and holds **all**
app containers back until every init container succeeds. Your first stop would be
`kubectl logs shared-demo -c seed -n core`.

## Task 2 - a native sidecar

The `streamer` container in the manifest above is the native sidecar: it lives under `initContainers`
but carries `restartPolicy: Always`. Check the READY count and its logs:

```bash
kubectl get pod shared-demo -n core
sleep 8
kubectl logs shared-demo -c streamer -n core
```

Expected - `2/2` ready (main + native sidecar), and the stream shows the seeded line plus appended
timestamps:

```
NAME          READY   STATUS    RESTARTS   AGE
shared-demo   2/2     Running   0          20s
```

```
seeded at Wed Jul  8 10:00:00 UTC 2026
Wed Jul  8 10:00:05 UTC 2026
Wed Jul  8 10:00:10 UTC 2026
```

Inspect the init-container states to see one finished and one still running:

```bash
kubectl get pod shared-demo -n core \
  -o jsonpath='{range .status.initContainerStatuses[*]}{.name}={.state}{"\n"}{end}'
```

Expected:

```
seed={"terminated":{...,"reason":"Completed"}}
streamer={"running":{...}}
```

**Answer to the reflective question:** start order is **`seed` -> `streamer` -> `app`**. Init
containers (including native sidecars) start in listed order; `seed` runs to completion first, then
the native sidecar `streamer` starts and - because of `restartPolicy: Always` - is considered
"started" (not "finished") so the next container may begin, then the main `app` starts. `streamer`
keeps running for the Pod's life.

## Task 3 - native sidecar vs ordinary init container

```bash
kubectl get pod shared-demo -n core \
  -o jsonpath='{range .spec.initContainers[*]}{.name}{" restartPolicy="}{.restartPolicy}{"\n"}{end}'
```

Expected:

```
seed restartPolicy=
streamer restartPolicy=Always
```

**Answer to the reflective question:** an **ordinary init container** (`seed`) runs *to completion
before* the app starts and then stays terminated; it never counts toward Pod readiness. A **native
sidecar** is an init container with `restartPolicy: Always` (`streamer`): it also starts before the
app, but instead of finishing it **keeps running alongside** the app for the Pod's whole life and
**does** count toward readiness (hence `2/2`). The single field `restartPolicy: Always` on an
`initContainers` entry is what turns it from a one-shot setup step into an always-on sidecar - with
the bonus that it is guaranteed to be up before the main container and torn down after it.

## Cleanup

```bash
kubectl delete -f solution/multi-pod.yaml --ignore-not-found --force --grace-period=0
kubectl delete ns core --ignore-not-found
```
