# Lab 6.6 - Jobs & CronJobs

## Objective
Learn how to run batch workloads with Jobs (one-time tasks) and CronJobs (scheduled recurring tasks). Understand completions, parallelism, and scheduling.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### Part A: Jobs

### 1. Create the Job

```bash
kubectl apply -f job.yaml
```

### 2. Watch job execution

```bash
timeout 30s kubectl get jobs -n training -w || true
```

The job requires 3 completions with parallelism of 2, so:
- First, 2 pods run simultaneously
- When one completes, a 3rd pod starts
- Job completes when all 3 succeed

### 3. Watch the pods

```bash
timeout 30s kubectl get pods -n training -l app=hello-job -w || true
```

### 4. View job details

```bash
kubectl describe job hello-job -n training
```

Note the Completions, Parallelism, and Events sections.

### 5. View logs from completed pods

```bash
kubectl wait --for=condition=complete job/hello-job -n training --timeout=120s
kubectl logs -n training -l app=hello-job
```

You should see "Hello from Job" three times.

### 6. Check job status

```bash
kubectl get job hello-job -n training -o jsonpath='{.status.succeeded}'
# Should output: 3
```

### Part B: CronJobs

### 7. Create the CronJob

```bash
kubectl apply -f cronjob.yaml
```

### 8. Verify the CronJob

```bash
kubectl get cronjob date-printer -n training
```

Note the SCHEDULE column shows `*/1 * * * *` (every minute).

### 9. Wait and watch for jobs to be created

```bash
timeout 70s kubectl get jobs -n training -w || true
```

Within a minute, a new job will appear with the name `date-printer-<timestamp>`. The watch stops automatically after 70 seconds.

### 10. Check the CronJob's last schedule time

```bash
kubectl get cronjob date-printer -n training
```

The LAST SCHEDULE column shows when the last job ran.

### 11. View logs from a CronJob-created pod

```bash
kubectl get pods -n training -l app=date-printer
kubectl logs -n training -l app=date-printer --tail=5
```

### 12. Manually trigger a CronJob run

```bash
kubectl create job date-manual --from=cronjob/date-printer -n training
kubectl wait --for=condition=complete job/date-manual -n training --timeout=60s
```

### 13. Suspend a CronJob

```bash
kubectl patch cronjob date-printer -n training -p '{"spec":{"suspend":true}}'
kubectl get cronjob date-printer -n training
```

The SUSPEND column should show `True`. No new jobs will be created.

### 14. Resume the CronJob

```bash
kubectl patch cronjob date-printer -n training -p '{"spec":{"suspend":false}}'
```

## Verification

```bash
# Job completed successfully
kubectl get job hello-job -n training
# COMPLETIONS should show 3/3

# CronJob is scheduled
kubectl get cronjob date-printer -n training
# SCHEDULE should show */1 * * * *

# View CronJob-created jobs
kubectl get jobs -n training | grep date-printer

# Check logs
kubectl logs -n training -l app=date-printer --tail=3
```

## Cleanup

```bash
kubectl delete -f job.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f cronjob.yaml --ignore-not-found --force --grace-period=0
kubectl delete job date-manual -n training --ignore-not-found --force --grace-period=0
```

## Further reading
- [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/) - concept reference
- [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) - concept reference
- [Running Automated Tasks with a CronJob](https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/) - task walkthrough
