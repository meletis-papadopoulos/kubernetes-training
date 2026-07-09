# Exercise 2.1 - Pods

*Domain: Core Workloads. Target: ~10 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace core
```

## Tasks

1. In the namespace `core`, create a Pod **imperatively** named `quick` that runs a single container
   from the image `nginx:1.27.1`. Wait until it reaches `Running`, then inspect it `-o wide` to read
   the node it landed on and its Pod IP, read the container's logs, and finally exec `nginx -v` inside
   the running container to confirm the server version. A bare Pod like this has no controller watching
   it - what would recreate `quick` if you deleted it right now?

2. In the same namespace `core`, create a Pod **from a manifest** named `configured` running
   `busybox:1.36`. Give the container an environment variable `GREETING=hello-core`, override its
   entrypoint with `command: ["sh", "-c"]` and `args` that echo `"$GREETING from $(hostname)"` once and
   then sleep forever, and declare a `containerPort` of `8080`. Apply it, wait for `Running`, then read
   its logs to confirm the greeting printed with the substituted value. Why did you have to keep the
   container alive with a `sleep` loop rather than letting the `echo` command simply return?

3. Inspect the **effective `restartPolicy`** of the `configured` Pod - you never set one in the
   manifest, so read it back from the live object with `kubectl get pod configured -n core
   -o jsonpath='{.spec.restartPolicy}'`. What value did the API server default it to, and why does a
   Job set this field to `OnFailure` or `Never` instead of leaving it at the Pod default?

## Acceptance criteria

- `quick` is `Running` in `core` from image `nginx:1.27.1`; `kubectl logs` and `kubectl exec ... --
  nginx -v` both succeed against it.
- `configured` is `Running` in `core`; its logs contain `hello-core from configured`, it exposes
  `containerPort: 8080`, and the `GREETING` env var is set on the container.
- `configured`'s effective `.spec.restartPolicy` reads back as `Always` (the Pod default, applied by
  the API server because the manifest omitted it).

## Docs you may reference

- [Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [Get a Shell to a Running Container](https://kubernetes.io/docs/tasks/debug/debug-application/get-shell-running-container/)
