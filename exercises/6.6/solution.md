# Exercise 6.6 - Solutions

Reference manifests are in `solution/`. Namespace `batch` is assumed to exist (see the exercise
Setup). Timestamps in the outputs below are **illustrative**.

## Task 1 - Job with completions and parallelism

```bash
kubectl apply -f solution/job.yaml
```

`solution/job.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: batch-worker
  namespace: batch
spec:
  completions: 4
  parallelism: 2
  backoffLimit: 4
  template:
    metadata:
      labels:
        app: batch-worker
    spec:
      containers:
      - name: worker
        image: busybox:1.36
        command:
        - /bin/sh
        - -c
        - 'echo "processed item on $(hostname)" && sleep 5'
      restartPolicy: Never
```

Wait for completion, then confirm the success count:

```bash
kubectl wait --for=condition=complete job/batch-worker -n batch --timeout=120s
kubectl get job batch-worker -n batch
kubectl get job batch-worker -n batch -o jsonpath='{.status.succeeded}{"\n"}'
```

Expected:

```
job.batch/batch-worker condition met
NAME           STATUS     COMPLETIONS   DURATION   AGE
batch-worker   Complete   4/4           15s        20s
4
```

**Answer to the reflective question:** a Job Pod template may set `restartPolicy: Never` or
`restartPolicy: OnFailure` - and nothing else. `Always` is rejected at creation (the API server
returns a validation error). A Job's whole purpose is to run a Pod **to completion** and then track
success; `Always` means "restart the container forever regardless of exit code", which contradicts the
notion of a terminating task - the container would never be allowed to reach a terminal `Succeeded`
state, so the Job could never count a completion. Retries on failure are handled by the Job's
`backoffLimit` (recreating Pods), not by an `Always` container restart.

## Task 2 - CronJob with concurrency policy and history limits

```bash
kubectl apply -f solution/cronjob.yaml
```

`solution/cronjob.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: heartbeat
  namespace: batch
spec:
  schedule: "*/1 * * * *"
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            app: heartbeat
        spec:
          containers:
          - name: beat
            image: busybox:1.36
            command:
            - /bin/sh
            - -c
            - 'echo "heartbeat at $(date -u +%H:%M:%S)"'
          restartPolicy: OnFailure
```

Wait ~70 seconds for the first scheduled Job, then inspect:

```bash
kubectl get cronjob heartbeat -n batch
kubectl get jobs -n batch -l app=heartbeat
```

Expected (after the first fire; `LAST SCHEDULE` is populated):

```
NAME        SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
heartbeat   */1 * * * *   <none>     False     0        20s             70s
```

After several minutes, list the retained Jobs:

```bash
kubectl get jobs -n batch -l app=heartbeat
```

Expected - at most **2** successful Jobs are kept:

```
NAME                 STATUS     COMPLETIONS   DURATION   AGE
heartbeat-29...      Complete   1/1           4s         2m
heartbeat-29...      Complete   1/1           4s         62s
```

**Answer to the reflective question:** the CronJob retains at most **2** completed Jobs, because
`successfulJobsHistoryLimit: 2` caps how many finished successful Jobs (and their Pods) are kept for
inspection - older ones are garbage-collected. `failedJobsHistoryLimit: 1` does the same for failed
Jobs (keeping only the most recent failure).

## Task 3 - manual one-off run from the CronJob

```bash
kubectl create job heartbeat-manual --from=cronjob/heartbeat -n batch
kubectl wait --for=condition=complete job/heartbeat-manual -n batch --timeout=60s
kubectl logs -n batch -l job-name=heartbeat-manual
```

Expected:

```
job.batch/heartbeat-manual created
job.batch/heartbeat-manual condition met
heartbeat at 14:07:11
```

**Answer to the reflective question:** `--from=cronjob/heartbeat` clones the CronJob's `jobTemplate`
verbatim into a standalone Job, so the ad-hoc run uses the *exact* same image, command, labels and Pod
spec as the scheduled runs - no drift, no copy-paste mistakes. It is the standard way to trigger a
scheduled task immediately (e.g. to test it or to force an off-cycle run) without editing the schedule,
suspending the CronJob, or maintaining a second hand-written manifest that could fall out of sync.

## Cleanup

```bash
kubectl delete ns batch --ignore-not-found
```
