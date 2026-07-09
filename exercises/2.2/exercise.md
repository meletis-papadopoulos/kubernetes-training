# Exercise 2.2 - Multi-Container Pods (sidecar & init)

*Domain: Core Workloads. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace core
```

## Tasks

1. In the namespace `core`, create a single Pod named `shared-demo` (label `app=shared-demo`) that
   wires three containers to one `emptyDir` volume named `shared` mounted at `/shared` in each. First,
   an **ordinary init container** named `seed` (image `busybox:1.36`) must run to completion and write
   a first line into `/shared/app.log` (e.g. `echo "seeded at $(date)" > /shared/app.log`). Then a main
   container named `app` (`busybox:1.36`) appends the current date to `/shared/app.log` every 5 seconds
   in an endless loop. Apply it, wait until it is Ready, and confirm the main container sees the line
   `seed` wrote before it ever ran. What state would the Pod be stuck in if `seed` exited non-zero?

2. Add a **native sidecar** to the same Pod: a third container named `streamer` (`busybox:1.36`)
   declared in `initContainers` **with `restartPolicy: Always`**, running `tail -f /shared/app.log`
   against the shared volume. Re-apply and observe: the Pod's `READY` column should settle at `2/2`
   (the main `app` plus the always-on `streamer`), while the one-shot `seed` does **not** count toward
   readiness. Read `streamer`'s logs and confirm it is streaming both the seeded line and the
   timestamps `app` keeps appending. In what order do `seed`, `streamer`, and `app` start?

3. Compare the two init-style containers you now have. Using the running Pod, explain the difference
   in behaviour between the ordinary init container `seed` and the native sidecar `streamer` - both are
   listed under `initContainers`, yet one has finished (`Completed`/`Terminated`) while the other is
   still `Running` for the life of the Pod. How does a native sidecar differ from an ordinary init
   container, and what makes `streamer` one?

## Acceptance criteria

- Pod `shared-demo` in `core` reaches `READY 2/2` (main `app` + native sidecar `streamer`); the init
  container `seed` shows `Completed` and does not count toward readiness.
- The main `app` container can read the `seeded at ...` line that `seed` wrote, proving the `emptyDir`
  volume is shared - not copied.
- `streamer` is an `initContainers` entry with `restartPolicy: Always`, runs for the Pod's lifetime,
  and its logs show both the seeded line and the timestamps `app` appends.

## Docs you may reference

- [Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Sidecar Containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)
