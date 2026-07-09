# Exercise 3.1 - Solutions

Reference manifests are in `solution/`. Namespace `config-demo` is assumed to exist
(see the exercise Setup).

## Task 1 - one ConfigMap from literals and a file

Imperatively you would write the file first, then combine `--from-literal` and `--from-file`:

```bash
cat > app.properties <<'EOF'
ui.theme=dark
ui.locale=en_GB
feature.beta=true
EOF

kubectl create configmap app-config -n config-demo \
  --from-literal=APP_MODE=production \
  --from-literal=LOG_LEVEL=info \
  --from-file=app.properties
```

Or apply the equivalent manifest directly:

```bash
kubectl apply -f solution/app-config.yaml
```

`solution/app-config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: config-demo
data:
  APP_MODE: production
  LOG_LEVEL: info
  app.properties: |
    ui.theme=dark
    ui.locale=en_GB
    feature.beta=true
```

Inspect the data map:

```bash
kubectl describe configmap app-config -n config-demo
```

Expected:

```
Name:         app-config
Namespace:    config-demo
Data
====
APP_MODE:
----
production
LOG_LEVEL:
----
info
app.properties:
----
ui.theme=dark
ui.locale=en_GB
feature.beta=true
```

**Answer to the reflective question:** the two literals become two separate scalar keys, each a
single line. The `--from-file` entry becomes **one key named after the file** (`app.properties`) whose
value is the file's entire multi-line content. That distinction matters downstream: literal keys map
cleanly onto env var names, while a file key is naturally consumed as a mounted file.

## Task 2 - consume as env vars via envFrom

```bash
kubectl apply -f solution/cm-env.yaml
kubectl wait --for=condition=Ready pod/cm-env -n config-demo --timeout=60s
```

`solution/cm-env.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cm-env
  namespace: config-demo
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "env | sort && sleep 3600"]
    envFrom:
    - configMapRef:
        name: app-config
  restartPolicy: Never
```

Read the resolved environment:

```bash
kubectl exec cm-env -n config-demo -- env | grep -E '^(APP_MODE|LOG_LEVEL)'
```

Expected:

```
APP_MODE=production
LOG_LEVEL=info
```

**Answer to the reflective question:** `envFrom` injects the ConfigMap's keys as environment variables,
so `APP_MODE=production` and `LOG_LEVEL=info` appear in the Pod's environment. File-shaped content like
`app.properties` is instead consumed as a mounted volume (Task 3).

## Task 3 - mount as a volume, and observe update behaviour

```bash
kubectl apply -f solution/cm-vol.yaml
kubectl wait --for=condition=Ready pod/cm-vol -n config-demo --timeout=60s
```

`solution/cm-vol.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cm-vol
  namespace: config-demo
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "cat /etc/appcfg/app.properties && sleep 3600"]
    volumeMounts:
    - name: cfg
      mountPath: /etc/appcfg
  volumes:
  - name: cfg
    configMap:
      name: app-config
  restartPolicy: Never
```

Confirm the mounted file (every ConfigMap key becomes a file; the properties file is one of them):

```bash
kubectl exec cm-vol -n config-demo -- ls /etc/appcfg
kubectl exec cm-vol -n config-demo -- cat /etc/appcfg/app.properties
```

Expected:

```
APP_MODE
LOG_LEVEL
app.properties
ui.theme=dark
ui.locale=en_GB
feature.beta=true
```

Now change the ConfigMap and observe both consumers:

```bash
kubectl patch configmap app-config -n config-demo --type merge \
  -p '{"data":{"app.properties":"ui.theme=dark\nui.locale=en_GB\nfeature.beta=false\n"}}'

# the kubelet re-syncs projected volumes periodically (can take up to ~2x the 1-min sync period)
for i in $(seq 1 30); do
  kubectl exec cm-vol -n config-demo -- cat /etc/appcfg/app.properties | grep -q feature.beta=false && break
  sleep 10
done
kubectl exec cm-vol -n config-demo -- cat /etc/appcfg/app.properties
kubectl exec cm-env -n config-demo -- env | grep '^LOG_LEVEL='
```

Expected - the **mounted file** now shows `feature.beta=false`, but the env var is unchanged:

```
ui.theme=dark
ui.locale=en_GB
feature.beta=false
LOG_LEVEL=info
```

**Answer to the reflective question:** a ConfigMap consumed as a **mounted volume updates in place** -
the kubelet periodically re-syncs the projected files (typically within a minute), so the running
container sees the new content without a restart. A ConfigMap consumed as an **environment variable is
resolved only once, at container start**; it never changes for a running container. To pick up new env
values you must recreate the Pod (e.g. roll the owning Deployment).

## Cleanup

```bash
kubectl delete ns config-demo --ignore-not-found
rm -f app.properties
```
