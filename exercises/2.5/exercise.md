# Exercise 2.5 - Probes

*Domain: Core Workloads. Target: ~15 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace core
```

## Tasks

1. In the namespace `core`, create a Deployment named `probed` with `2` replicas of `nginx:1.27.1` on
   `containerPort: 80`, and give the container all **three** HTTP probes against `path: /` on `port:
   80`: a `startupProbe` (`periodSeconds: 5`, `failureThreshold: 12`) that must pass before the others
   run, a `readinessProbe` (`periodSeconds: 5`), and a `livenessProbe` (`periodSeconds: 10`,
   `failureThreshold: 3`). Also create a ClusterIP Service named `probed` selecting `app=probed` on
   port `80`. Once rolled out, confirm the Service has **two** endpoint addresses. Why does the startup
   probe let a slow-booting server avoid being killed by the liveness probe during boot?

2. Create a Pod named `gated` (`nginx:1.27.1`, label `app=gated`) whose only probe is an **exec
   readiness probe** running `cat /tmp/ready` (`periodSeconds: 5`, `failureThreshold: 1`), plus a
   ClusterIP Service `gated` selecting `app=gated` on port `80`. The file does not exist at start, so
   the pod runs but stays `0/1` and the `gated` Service has **no** endpoints. `kubectl exec` a `touch
   /tmp/ready` into it and watch it become `1/1` and appear in the endpoints; then `rm /tmp/ready` and
   watch it drop back out of the endpoints. Throughout, check the pod's `RESTARTS` count. Which probe
   removes a pod from Service traffic **without** restarting its container?

3. Create a Pod named `livecheck` (`busybox:1.36`) whose container command is `touch /tmp/healthy &&
   sleep 3600` and whose **exec liveness probe** runs `cat /tmp/healthy` (`initialDelaySeconds: 5`,
   `periodSeconds: 5`, `failureThreshold: 3`). Once it is Ready, `kubectl exec` a `rm /tmp/healthy`
   into it and, after roughly 15 seconds (3 failed checks), observe the container's `RESTARTS` count
   increment. Why does the restarted container come back healthy again on its own, and how does this
   outcome differ from the readiness case in Task 2?

## Acceptance criteria

- Deployment `probed` is `2/2` Ready with startup + readiness + liveness HTTP probes on `:80`; the
  `probed` Service lists exactly `2` endpoint addresses.
- `gated` starts `0/1` with the `gated` Service empty; after `touch /tmp/ready` it is `1/1` and appears
  as an endpoint; after `rm /tmp/ready` it returns to `0/1` and drops out - all with `RESTARTS` = `0`.
- `livecheck` starts Ready; after `rm /tmp/healthy` its container `RESTARTS` count increments (liveness
  failure restarts the container), and it recovers because the restart re-runs its `touch` command.

## Docs you may reference

- [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Container probes](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes)
