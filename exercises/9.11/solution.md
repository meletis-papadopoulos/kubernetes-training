# Exercise 9.11 - Solutions

Reference manifests are in `solution/`. Namespace `ts911` and the broken `orders` Deployment are
assumed applied (see the exercise Setup).

## Task 1 - triage and fix

### Diagnose - correlate the three tools

**Events (newest last):**

```bash
sleep 20
kubectl get events -n ts911 --sort-by=.lastTimestamp | tail -6
```

Expected (values illustrative):

```
LAST SEEN   TYPE      REASON     OBJECT                MESSAGE
...         Normal    Pulled     pod/orders-...        Container image "busybox:1.36" already present
...         Normal    Created    pod/orders-...        Created container app
...         Normal    Started    pod/orders-...        Started container app
...         Warning   BackOff    pod/orders-...        Back-off restarting failed container app
```

`BackOff` repeating tells you it restarts - but not *why*.

**State + previous logs:**

```bash
kubectl describe pod -n ts911 -l app=orders | grep -A 6 "Last State"
kubectl logs -n ts911 -l app=orders --previous
```

Expected:

```
Last State:     Terminated
  Reason:       Error
  Exit Code:    2
```

```
FATAL: DATABASE_URL is not set
```

**Metrics (rule out OOM / resource):**

```bash
kubectl top pods -n ts911
```

Expected (values illustrative) - memory far below the `64Mi` limit, so this is not an OOMKill:

```
NAME           CPU(cores)   MEMORY(bytes)
orders-...     0m           1Mi
```

**Root cause:** the container requires the environment variable `DATABASE_URL`; the Deployment never
sets it, so the app prints `FATAL: DATABASE_URL is not set` and exits `2` on every start, producing
the `BackOff` loop. Exit `2` (a normal application exit) plus low memory rules out an OOMKill (which
would be `Reason: OOMKilled`, `Exit Code: 137`). This is an application **config** failure.

### Fix

Add the missing variable. Re-apply the fixed manifest or patch:

```bash
kubectl apply -f solution/orders-deploy.yaml
# or:
# kubectl set env deployment/orders -n ts911 DATABASE_URL=postgres://db.internal:5432/orders
kubectl rollout status deployment/orders -n ts911 --timeout=90s
```

### Verify

```bash
kubectl get pods -n ts911 -l app=orders
kubectl logs -n ts911 -l app=orders
```

Expected: Pod `1/1 Running`, `RESTARTS: 0`, and:

```
connected to postgres://db.internal:5432/orders
```

## Task 2 - reflective answer

Exit code `2` is a deliberate application exit; the OOM killer uses SIGKILL, which shows as exit `137`
with `Reason: OOMKilled`. Seeing `2` immediately rules out a memory-limit kill. `kubectl top` is still
worth running because it *cheaply confirms* that hypothesis - memory sitting at ~1Mi against a 64Mi
limit proves resource pressure is not involved, so you don't waste time raising limits. The
load-bearing command was `kubectl logs --previous`: events only told you the container keeps
backing off, and `describe` only gave the exit code - neither prints the application's own
`FATAL: DATABASE_URL is not set` message. Correlating all three (events => it restarts; top => not
OOM; previous logs => the actual reason) is the triage workflow.

## Cleanup

```bash
kubectl delete ns ts911 --ignore-not-found
```
