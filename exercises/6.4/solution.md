# Exercise 6.4 - Solutions

Reference manifests are in `solution/`. Namespace `scale` is assumed to exist, and a working
Metrics Server is required (`kubectl top nodes` returns data). Metric-derived values below are
**illustrative** - exact CPU percentages and timing vary by cluster.

## Task 1 - Deployment, Service and HPA

```bash
kubectl apply -f solution/deployment.yaml
kubectl expose deployment web -n scale --port=80 --name=web-svc
kubectl apply -f solution/hpa.yaml
```

`solution/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: scale
  labels:
    app: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: nginx:1.27.1
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
```

`solution/hpa.yaml`:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web
  namespace: scale
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  minReplicas: 1
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```

Inspect the HPA right after creation:

```bash
kubectl get hpa web -n scale
```

Expected (illustrative) immediately after creation:

```
NAME   REFERENCE        TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
web    Deployment/web   <unknown>/50%   1         4         1          5s
```

After ~30-60 seconds it becomes a real figure, e.g.:

```
NAME   REFERENCE        TARGETS     MINPODS   MAXPODS   REPLICAS   AGE
web    Deployment/web   0%/50%      1         4         1          60s
```

**Answer to the reflective question:** the HPA reads Pod CPU from the **metrics.k8s.io** API, which is
served by the **Metrics Server**. Right after creation there is no scrape sample yet, so the HPA
controller cannot compute a utilization and reports `<unknown>`. Once Metrics Server has scraped the
Pods (its default cycle is ~15s, and the HPA re-syncs every ~15s) the value populates. If Metrics
Server were **not** installed, `TARGETS` would stay `<unknown>/50%` forever and the HPA could never
scale on CPU.

## Task 2 - generate load and scale up

```bash
kubectl apply -f solution/load-generator.yaml
```

`solution/load-generator.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: load-generator
  namespace: scale
spec:
  containers:
  - name: load
    image: busybox:1.36
    command:
    - /bin/sh
    - -c
    - "while true; do wget -q -O- http://web-svc.scale.svc.cluster.local; done"
  restartPolicy: Never
```

Poll the HPA and the Pods every ~15 seconds (re-run these a few times over 1-2 minutes):

```bash
kubectl get hpa web -n scale
kubectl get pods -n scale -l app=web
```

Expected (illustrative) once CPU crosses the target:

```
NAME   REFERENCE        TARGETS     MINPODS   MAXPODS   REPLICAS   AGE
web    Deployment/web   180%/50%    1         4         4          3m
```

**Answer to the reflective question:** the HPA scales to at most **4** replicas - the value of
`maxReplicas`. The scaling formula is `desiredReplicas = ceil(currentReplicas x currentUtil /
targetUtil)`, and the result is clamped between `minReplicas` and `maxReplicas`, so no matter how high
CPU climbs the Deployment will not exceed `4` Pods.

## Task 3 - remove load and scale down

```bash
kubectl delete pod load-generator -n scale --force --grace-period=0
```

Poll again over the next few minutes:

```bash
kubectl get hpa web -n scale
```

Expected (illustrative) after the load stops and the window elapses:

```
NAME   REFERENCE        TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
web    Deployment/web   0%/50%    1         4         1          10m
```

**Answer to the reflective question:** once the load Pod is gone, measured CPU falls below the `50%`
target, so the HPA's computed desired replica count drops and it scales the Deployment back **down**
toward `minReplicas: 1`. It is the same clamp as scale-up - `desiredReplicas` tracks CPU utilisation
bounded by `minReplicas`/`maxReplicas` - now driven by low utilisation instead of high.

## Cleanup

```bash
kubectl delete ns scale --ignore-not-found
```
