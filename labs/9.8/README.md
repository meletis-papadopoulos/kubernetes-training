# Lab 9.8 - Probe Problems

## Objective
Diagnose three probe misconfigurations that produce three very different - and easily misread - symptoms:

1. **Liveness too aggressive** on a slow-starting app → `CrashLoopBackOff` masquerading as an app crash
2. **Readiness probe wrong path** → pod stays `Running` but `0/1 Ready` forever, Service has zero endpoints, traffic silently disappears
3. **Probe pointed at wrong port** → instant `CrashLoopBackOff` with no useful app logs

The hardest of the three is #2 - there is no obvious failure and the app *thinks* it's running fine. Knowing what to look for takes practice.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Background - three probe types, three jobs

| Probe | Purpose | Failure consequence |
|---|---|---|
| **livenessProbe** | "Is the container still healthy?" | Container is **killed and restarted** |
| **readinessProbe** | "Should this pod receive traffic?" | Pod is **removed from Service endpoints** (no restart) |
| **startupProbe** | "Has the slow-boot phase finished?" | While running, **liveness/readiness are paused**; if startup fails for too long the container is killed |

The startupProbe is specifically designed for slow boot. Without it, you must tune `livenessProbe.initialDelaySeconds` to be longer than worst-case boot time - but that delays liveness checks for the *entire pod lifetime*, not just startup.

## Steps

### Problem 1: Liveness probe is too aggressive - fixed by adding a startupProbe

### 1. Deploy the slow-starting pod

```bash
kubectl apply -f pod-liveness-aggressive.yaml
```

The container takes ~30s to start nginx (simulated with `sleep 30`). Liveness probe has `initialDelaySeconds: 2, periodSeconds: 5, failureThreshold: 2` - fails after about 12 seconds.

### 2. Watch the restart loop

```bash
sleep 90
kubectl get pod slow-starter -n training
```

What you're looking for is **`RESTARTS` ≥ 2 and climbing** - that's the unambiguous broken-state signal. STATUS often shows `CrashLoopBackOff` by this point, but if you happen to catch the pod a few seconds into a fresh restart attempt it can briefly read `Running`. Don't anchor on STATUS - anchor on RESTARTS.

### 3. Diagnose

```bash
kubectl describe pod slow-starter -n training | grep -A 20 "Events:" | tail -20
```

Events show:

```
Warning  Unhealthy        Liveness probe failed: Get "http://.../": dial tcp ...: connect: connection refused
Normal   Killing          Container nginx failed liveness probe, will be restarted
```

The app *would* start fine if given the time - the kubelet kills it mid-boot before `Boot complete`. Classic startup-vs-liveness confusion. The Events list above (`Liveness probe failed` followed by `Killing`) is the unambiguous fingerprint.

### 4. Fix: add a startupProbe to bracket the slow-boot phase

```bash
kubectl delete pod slow-starter -n training --force --grace-period=0
kubectl apply -f pod-liveness-fixed.yaml
sleep 45
kubectl get pod slow-starter -n training
```

The fixed manifest (in `pod-liveness-fixed.yaml`) adds a `startupProbe` with a 60-second budget (`periodSeconds: 5`, `failureThreshold: 12`). While the startupProbe is in flight, the livenessProbe is suppressed; once the startupProbe succeeds, livenessProbe takes over with the same aggressive thresholds - but the app is already booted by then, so they no longer matter.

Pod is now `1/1 Ready`, `RESTARTS: 0`. The startupProbe gave the app 60 seconds to come up; only after startupProbe succeeded did the livenessProbe begin running.

---

### Problem 2: Readiness probe wrong path - silent traffic disappearance

This is the sneaky one. Pods run forever, the dashboard shows green, but the Service has no endpoints and traffic never lands.

### 5. Deploy the deployment with a wrong readiness path

```bash
kubectl apply -f readiness-wrong-path.yaml
kubectl rollout status deployment/silent-app -n training --timeout=30s 2>&1 | head -5 || true
```

The rollout never reports success because the pods never become Ready. Don't wait - move on.

### 6. Observe - pods are Running but not Ready

```bash
sleep 20
kubectl get pods -n training -l app=silent-app
```

Output:

```
NAME                          READY   STATUS    RESTARTS   AGE
silent-app-XXXXXXXX-XXXXX     0/1     Running   0          25s
silent-app-XXXXXXXX-XXXXX     0/1     Running   0          25s
```

`0/1` ready. Pods aren't crashing - they're alive - but they're not eligible for traffic.

### 7. Observe - Service has zero endpoints

```bash
kubectl get endpoints silent-app-svc -n training
```

Output:

```
NAME              ENDPOINTS   AGE
silent-app-svc    <none>      30s
```

Empty. Traffic to `silent-app-svc` will hit `connection refused` because there are no backends.

This is the one spot in this lab where the legacy `Endpoints` object is actually the better diagnostic than `EndpointSlice`: its default view only lists *ready* addresses, so a fully-not-ready backend prints `<none>` - exactly the signal above. `kubectl get endpointslices -l kubernetes.io/service-name=silent-app-svc` would still show the pod IPs here, because EndpointSlice's default columns list every endpoint address regardless of readiness - you'd have to check `-o yaml` under `endpoints[].conditions.ready` to see they're excluded from traffic. The legacy Endpoints API is deprecated as the preferred read path, but Kubernetes still populates it automatically, which is why the command above still works.

This is the silent-failure mode: **logs are clean, status is Running, but nothing routes**. If you only watched the deployment-level dashboards you'd never know.

### 8. Diagnose

```bash
kubectl describe pod -n training -l app=silent-app | grep -A 3 "Readiness" | head -10
```

The `Readiness` line shows `http-get http://:80/healthz` - but nginx doesn't serve `/healthz`. Confirm with a direct test:

```bash
POD=$(kubectl get pod -n training -l app=silent-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec "$POD" -n training -- curl -s -o /dev/null -w "%{http_code}\n" http://localhost/healthz
kubectl exec "$POD" -n training -- curl -s -o /dev/null -w "%{http_code}\n" http://localhost/
```

`/healthz` returns `404`, `/` returns `200`. The probe path is wrong.

Events confirm:

```bash
kubectl describe pod -n training -l app=silent-app | grep -A 2 "Readiness probe failed" | head -3
```

Shows `Readiness probe failed: HTTP probe failed with statuscode: 404`.

### 9. Fix: probe a path the app actually serves

```bash
kubectl patch deployment silent-app -n training --type=strategic -p '
spec:
  template:
    spec:
      containers:
        - name: nginx
          readinessProbe:
            httpGet:
              path: /
              port: 80
'
kubectl rollout status deployment/silent-app -n training --timeout=60s
kubectl get pods -n training -l app=silent-app
kubectl get endpoints silent-app-svc -n training
```

Pods are now `1/1 Ready`, and the Service has 2 endpoint IPs.

---

### Problem 3: Probe targets the wrong port - connection refused

### 10. Deploy a pod with liveness probe pointing at the wrong port

```bash
kubectl apply -f pod-probe-wrong-port.yaml
```

nginx listens on 80; the probe targets 8080.

### 11. Watch the restart loop

```bash
sleep 30
kubectl get pod wrong-port-pod -n training
```

Status: `CrashLoopBackOff`, `RESTARTS` climbing.

### 12. Diagnose

```bash
kubectl describe pod wrong-port-pod -n training | grep -A 3 "Liveness probe failed" | head -5
```

Events show:

```
Liveness probe failed: Get "http://.../": dial tcp ...:8080: connect: connection refused
```

The phrase **`connect: connection refused`** at port 8080 is unambiguous - the kubelet TCP-connected to that port and got an immediate RST because nothing was listening. Compare to Problem 1 where the probe failed because the *app* hadn't booted yet - here nginx is running fine, the probe is just pointed at the wrong port.

### 13. Fix: point the probe at the right port

```bash
kubectl delete pod wrong-port-pod -n training --force --grace-period=0
kubectl apply -f pod-probe-fixed.yaml
kubectl wait --for=condition=Ready pod/wrong-port-pod -n training --timeout=60s
```

The fixed manifest is identical to the broken one except `livenessProbe.httpGet.port` is `80` (matching the container's `containerPort`) instead of `8080`.

---

## Diagnostic Cheat Sheet

| Symptom | Probe events / phrase | Root cause |
|---|---|---|
| `CrashLoopBackOff`, RESTARTS climbing, app logs interrupted mid-boot | `Liveness probe failed ... connection refused` early in lifecycle | Liveness too aggressive - app needs more time. **Add startupProbe.** |
| `CrashLoopBackOff`, RESTARTS climbing, app logs look healthy | `connection refused` at probe port | Probe targets wrong port |
| `0/1 Ready` forever, no restarts, Service has no endpoints | `Readiness probe failed ... statuscode: 404` (or 503) | Readiness probe path doesn't match app routes |
| Probe randomly flaps Ready ↔ NotReady | `dial tcp ...: i/o timeout` | `timeoutSeconds` too low for app's response time |
| Pod kills itself under load | `Liveness probe failed: timeout` | App pegged on CPU/blocked I/O - liveness should be **lighter** than the work the app does |

## Probe-design rules of thumb

- **livenessProbe**: should be **cheap** and check only that the process is responsive (`/livez` returning 200 even if dependencies are down). Hitting an endpoint that talks to the database is a footgun - the DB blip restarts every pod.
- **readinessProbe**: can check dependencies (`/readyz` that pings DB) - failing here just removes the pod from Service rotation, no restart.
- **startupProbe**: only used during initial boot, then disabled. Use it for any app whose worst-case startup is unpredictable (JVM, .NET, ML model load).
- **failureThreshold × periodSeconds = total tolerated outage**. `failureThreshold: 3, periodSeconds: 10` = 30s of failure before action.

## Additional notes

- A cluster's events/logging pipeline surfaces probe failures via `KubeEvents` - alert on `Reason=Unhealthy` for blast-radius detection.
- **A slow-start dependency** (e.g., fetching a secret/token from an external service, warming a cache, or loading a large config) that takes 30+ seconds on pod start is a classic startupProbe-needed scenario.
- **Init containers** also have probes (technically - they run sequentially), but the more common "init too slow" pattern is fixed at the init level (longer init timeout) rather than with startupProbe on the main container.

## Verification

```bash
kubectl get pod slow-starter wrong-port-pod -n training
# Both 1/1 Running

kubectl get endpoints silent-app-svc -n training
# legacy API - has endpoints (not <none>)
```

## Cleanup

```bash
kubectl delete pod slow-starter wrong-port-pod -n training --ignore-not-found --force --grace-period=0
kubectl delete deployment silent-app -n training --ignore-not-found
kubectl delete service silent-app-svc -n training --ignore-not-found
```

## Further reading
- [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Pod Lifecycle - When to use which probe](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#types-of-probe)
- [Configuring probes for slow-starting containers](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#protect-slow-starting-containers-with-startup-probes)
