# Exercise 9.11 - Triage a Subtly Failing App with Logs, Events & Metrics

*Domain: Troubleshooting. Target: ~10 min. Do not open `solution/` until you have tried.*

This is a **fix-it** exercise: `setup.yaml` ships a Deployment that keeps restarting for a reason that
is only visible if you correlate **events**, **previous-container logs**, and **metrics**. Diagnose
from the cluster, then apply the minimal fix. Assumes `provision.sh` (metrics-server installed).

## Setup

```bash
kubectl create namespace ts911
kubectl apply -f setup.yaml
```

## Tasks

1. The `orders` Deployment in namespace `ts911` never stabilises. Run the full triage workflow and let
   the three tools converge on the cause:
   - **Events (newest last):** `kubectl get events -n ts911 --sort-by=.lastTimestamp` - what reason
     keeps repeating?
   - **State + previous logs:** `kubectl describe pod -n ts911 -l app=orders | grep -A 6 "Last State"`
     for the exit code, then `kubectl logs -n ts911 -l app=orders --previous` for what the crashed
     instance printed. (Plain `kubectl logs` may be empty - the current instance is too young.)
   - **Metrics (rule out resource):** `kubectl top pods -n ts911` - is memory anywhere near the
     `64Mi` limit (i.e. is this an OOMKill), or is it a clean application exit?

   Quote the exit code and the fatal log line, then fix the Deployment so `orders` reaches `Running`
   and stops restarting.

2. Reflective: this app exits `2`, not `137` - what does that immediately rule out, and why is
   `kubectl top` still worth running here even though it turns out not to be the cause? Which single
   command in the workflow actually produced the root-cause message, and why would events + `describe`
   alone have left you guessing?

## Acceptance criteria

- `orders` in `ts911` is `Running` with a stable `RESTARTS` count; `kubectl logs -n ts911 -l
  app=orders` prints `connected to postgres://db.internal:5432/orders`.
- You identify the fault as a **missing required environment variable** (`DATABASE_URL`), causing the
  app to log `FATAL: DATABASE_URL is not set` and `exit 2` - an application config failure, not an
  OOMKill (exit `137`) or image/scheduling problem.
- You explain that exit `2` (not `137`) rules out an OOMKill, that `kubectl top` confirmed memory was
  nowhere near the limit, and that `kubectl logs --previous` was the load-bearing command.

## Docs you may reference

- [Application Introspection and Debugging](https://kubernetes.io/docs/tasks/debug/debug-application/)
- [Logging Architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/)
