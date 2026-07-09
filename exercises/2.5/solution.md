# Exercise 2.5 - Solutions

Reference manifests are in `solution/`. Namespace `core` is assumed to exist (see the exercise Setup).

## Task 1 - three HTTP probes + readiness gating Service endpoints

```bash
kubectl apply -f solution/probed-deploy.yaml
kubectl rollout status deployment/probed -n core
```

`solution/probed-deploy.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: probed
  namespace: core
  labels:
    app: probed
spec:
  replicas: 2
  selector:
    matchLabels:
      app: probed
  template:
    metadata:
      labels:
        app: probed
    spec:
      containers:
      - name: nginx
        image: nginx:1.27.1
        ports:
        - containerPort: 80
        startupProbe:
          httpGet:
            path: /
            port: 80
          periodSeconds: 5
          failureThreshold: 12
        readinessProbe:
          httpGet:
            path: /
            port: 80
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 80
          periodSeconds: 10
          failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: probed
  namespace: core
spec:
  selector:
    app: probed
  ports:
  - port: 80
    targetPort: 80
```

Confirm two ready pods back the Service:

```bash
kubectl get pods -n core -l app=probed
kubectl get endpoints probed -n core
```

Expected (endpoint IPs illustrative):

```
NAME                      READY   STATUS    RESTARTS   AGE
probed-xxxxxxxxxx-aaaaa   1/1     Running   0          30s
probed-xxxxxxxxxx-bbbbb   1/1     Running   0          30s

NAME     ENDPOINTS                     AGE
probed   10.244.1.5:80,10.244.2.6:80   30s
```

**Answer to the reflective question:** while the `startupProbe` is still failing, Kubernetes
**suspends** the readiness and liveness probes entirely. A slow-booting server therefore gets up to
`periodSeconds x failureThreshold` (here 5 x 12 = 60s) to come up without the liveness probe counting
failures against it and killing the container. Once the startup probe passes once, readiness and
liveness take over for the rest of the container's life.

## Task 2 - readiness gates traffic without restarting

```bash
kubectl apply -f solution/gated.yaml
kubectl get pod gated -n core
kubectl get endpoints gated -n core
```

`solution/gated.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gated
  namespace: core
  labels:
    app: gated
spec:
  containers:
  - name: nginx
    image: nginx:1.27.1
    ports:
    - containerPort: 80
    readinessProbe:
      exec:
        command: ["cat", "/tmp/ready"]
      periodSeconds: 5
      failureThreshold: 1
---
apiVersion: v1
kind: Service
metadata:
  name: gated
  namespace: core
spec:
  selector:
    app: gated
  ports:
  - port: 80
    targetPort: 80
```

Expected at start - the pod runs but is not Ready, so the Service has no endpoints:

```
NAME    READY   STATUS    RESTARTS   AGE
gated   0/1     Running   0          10s

NAME    ENDPOINTS   AGE
gated   <none>      10s
```

Flip it Ready, then Unready, checking endpoints and restart count each time:

```bash
kubectl wait --for=jsonpath='{.status.phase}'=Running pod/gated -n core --timeout=60s
kubectl exec gated -n core -- touch /tmp/ready
sleep 7
kubectl get pod gated -n core
kubectl get endpoints gated -n core

kubectl exec gated -n core -- rm /tmp/ready
sleep 7
kubectl get pod gated -n core
kubectl get endpoints gated -n core
kubectl get pod gated -n core -o jsonpath='restarts={.status.containerStatuses[0].restartCount}{"\n"}'
```

Expected - Ready `1/1` with an endpoint after `touch`, then `0/1` with `<none>` after `rm`, and
`restarts=0` throughout:

```
gated   1/1   Running   0
gated   10.244.1.7:80

gated   0/1   Running   0
gated   <none>
restarts=0
```

**Answer to the reflective question:** the **readiness probe** removes a pod from its Service's
endpoints without restarting the container. A failing readiness probe only flips the pod's `Ready`
condition to `false`, which the endpoints controller uses to withdraw its address from the Service - the
process keeps running (`RESTARTS` stays `0`), so it can rejoin as soon as it is ready again.

## Task 3 - liveness restarts the container

```bash
kubectl apply -f solution/livecheck.yaml
kubectl wait --for=condition=Ready pod/livecheck -n core --timeout=60s
```

`solution/livecheck.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: livecheck
  namespace: core
  labels:
    app: livecheck
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "touch /tmp/healthy && sleep 3600"]
    livenessProbe:
      exec:
        command: ["cat", "/tmp/healthy"]
      initialDelaySeconds: 5
      periodSeconds: 5
      failureThreshold: 3
```

Break the health file and wait for the liveness probe to trip:

```bash
kubectl exec livecheck -n core -- rm /tmp/healthy
sleep 30
kubectl get pod livecheck -n core
kubectl describe pod livecheck -n core | grep -A2 "Liveness"
```

Verify the restart count incremented:

```bash
kubectl get pod livecheck -n core -o jsonpath='restarts={.status.containerStatuses[0].restartCount}{"\n"}'
```

Expected - at least one restart, and the pod back to `Running`:

```
NAME        READY   STATUS    RESTARTS      AGE
livecheck   1/1     Running   1 (10s ago)   2m
restarts=1
```

**Answer to the reflective question:** the **liveness** probe failed 3 times, so the kubelet
**restarted the container** (not the whole pod - the pod object and its name persist, only the
`restartCount` climbs). It recovers on its own because a restart re-runs the container's command,
`touch /tmp/healthy && sleep 3600`, which recreates the file the probe checks. This is the key
contrast with Task 2: **readiness** takes a still-running pod *out of Service traffic* without touching
it, whereas **liveness** *kills and restarts* the container to try to recover a wedged process.

## Cleanup

```bash
kubectl delete -f solution/probed-deploy.yaml -f solution/gated.yaml -f solution/livecheck.yaml \
  --ignore-not-found --force --grace-period=0
kubectl delete ns core --ignore-not-found
```
