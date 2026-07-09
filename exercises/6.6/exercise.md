# Exercise 6.6 - Jobs & CronJobs

*Domain: Workloads & Scheduling. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace batch
```

## Tasks

1. In the namespace `batch`, create a Job named `batch-worker` (image `busybox:1.36`) that requires
   `4` successful **completions** run at a **parallelism** of `2`, with `backoffLimit: 4`. Each Pod
   should run `echo "processed item on $(hostname)" && sleep 5` and then exit. Apply it and wait for
   it to finish, then confirm `.status.succeeded` is `4`. Reflective: which `restartPolicy` values are
   valid for a Job's Pod template, and why is `Always` **not** one of them?

2. In `batch`, create a CronJob named `heartbeat` that runs **every minute** (`*/1 * * * *`), with
   `successfulJobsHistoryLimit: 2` and `failedJobsHistoryLimit: 1`. Its
   Pod runs `echo "heartbeat at $(date -u +%H:%M:%S)"` (image `busybox:1.36`). Apply it, wait ~70
   seconds for the first Job to be spawned, and confirm the CronJob's `LAST SCHEDULE` populates. After
   several minutes, how many completed Jobs does the CronJob retain, and which field controls that?

3. Trigger an **immediate**, one-off run of the CronJob without waiting for the schedule, by creating
   a Job named `heartbeat-manual` from the CronJob template (`kubectl create job --from=cronjob/...`).
   Wait for it to complete and read its Pod's log. Why is this `--from=cronjob` shortcut preferable to
   hand-writing a new Job manifest for an ad-hoc run?

## Acceptance criteria

- `batch-worker` reaches `COMPLETIONS 4/4`; `.status.succeeded == 4`; its Pods used `restartPolicy:
  Never` (or `OnFailure`).
- `heartbeat` CronJob exists with schedule `*/1 * * * *`; it spawns a Job each minute and retains at
  most `2` successful Jobs.
- `heartbeat-manual` (created via `--from=cronjob/heartbeat`) completes and logs a `heartbeat at ...`
  line.

## Docs you may reference

- [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- [Running Automated Tasks with a CronJob](https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/)
