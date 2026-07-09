# Exercise 9.8 - Fix Pods That Never Become Ready

*Domain: Troubleshooting. Target: ~9 min. Do not open `solution/` until you have tried.*

This is a **fix-it** exercise: `setup.yaml` ships a Deployment + Service with a misconfigured probe.
Diagnose from the cluster, then apply the minimal fix.

## Setup

```bash
kubectl create namespace ts98
kubectl apply -f setup.yaml
```

## Tasks

1. The `frontend` Deployment in namespace `ts98` rolls out, but its Pods never become Ready and the
   `frontend-svc` Service serves no traffic. Wait ~20s. Note the trap: `kubectl get pods -n ts98 -l
   app=frontend` shows `Running` but `0/2` (or `0/1`) READY, with `RESTARTS: 0` - the containers are
   **not** crashing. Diagnose: confirm the Service has no endpoints
   (`kubectl get endpoints frontend-svc -n ts98`), then read the probe result in
   `kubectl describe pod -n ts98 -l app=frontend` (look for `Readiness probe failed`). Fix the probe
   so both Pods become Ready and the Service gets endpoints.

2. Reflective: the container process is healthy and never restarts, yet nothing routes to it - why
   does a failing **readiness** probe produce that exact symptom (as opposed to a failing **liveness**
   probe)? Why is a `Service has no endpoints` combined with `Running` Pods the fingerprint of a
   readiness problem rather than a selector mismatch (9.4)?

## Acceptance criteria

- Both `frontend` Pods in `ts98` are `Running` and `Ready` (`2/2` across the Deployment), and
  `frontend-svc` lists endpoint IPs.
- You identify the fault as a **readiness probe pointing at a path the app does not serve**
  (`/healthz` returns 404; nginx serves `/`).
- You explain that a failing readiness probe removes the Pod from Service endpoints **without**
  restarting it (liveness would restart it), and that `Running` + `0/N Ready` + empty endpoints is the
  readiness signature - distinct from the selector mismatch in 9.4 (where Pods are `Ready` but still
  unselected).

## Docs you may reference

- [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
