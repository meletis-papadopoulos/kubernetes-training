# Lab 9.3 - ConfigMap & Secret Problems

## Objective
Diagnose and fix the most common ways ConfigMap and Secret consumption breaks a pod: missing references, wrong key names, env-vs-volume mount mismatches, and stale values after an update. Practice using `kubectl describe`, `logs`, and `exec` to tell these apart.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Background
ConfigMap/Secret failures fall into three buckets:

1. **The referenced object doesn't exist** (wrong name, wrong namespace, or just not created yet) - the container never starts; `kubectl get pod` shows `CreateContainerConfigError`.
2. **The object exists but the requested key doesn't** - same error class, unless the reference is marked `optional: true`.
3. **The object and key both resolve fine, but the app still doesn't get what it expects** - a mount path or key name that doesn't match what the app reads, or a value that hasn't propagated yet after an update. The pod reports `Running`; you only find this with `logs`/`exec`, not `describe`.

## Steps

### Problem 1: Missing ConfigMap (`envFrom`)

### 1. Deploy a pod that pulls env vars from a ConfigMap that doesn't exist yet

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: configmap-missing-pod
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "env && sleep 3600"]
      envFrom:
        - configMapRef:
            name: service-settings
  restartPolicy: Never
EOF
```

### 2. Observe the status

```bash
sleep 15
kubectl get pod configmap-missing-pod -n training
```

Status: `CreateContainerConfigError`.

### 3. Diagnose

```bash
kubectl describe pod configmap-missing-pod -n training | tail -10
```

Events show: `Error: configmap "service-settings" not found`

### 4. Fix: create the missing ConfigMap

```bash
kubectl create configmap service-settings --from-literal=GREETING=hello --from-literal=TIMEOUT=30 -n training

kubectl delete pod configmap-missing-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: configmap-missing-pod
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "env && sleep 3600"]
      envFrom:
        - configMapRef:
            name: service-settings
  restartPolicy: Never
EOF
kubectl wait --for=condition=Ready pod/configmap-missing-pod -n training --timeout=60s
kubectl logs configmap-missing-pod -n training | grep -E "GREETING|TIMEOUT"
```

---

### Problem 2: Wrong key name in `configMapKeyRef` / `secretKeyRef`, and the `optional` flag

### 5. Create the ConfigMap and Secret the next pods will (mis)reference

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: db-config
  namespace: training
data:
  DB_HOST: db.internal
---
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
  namespace: training
type: Opaque
data:
  password: UzNjdXJlIVBhc3M=
EOF
```

### 6. Deploy a pod that requests the wrong key names

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: wrong-key-pod
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo DB_HOST=$DB_HOST DB_PASSWORD=$DB_PASSWORD && sleep 3600"]
      env:
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: db-config
              key: DB_HOSTNAME
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-creds
              key: passwd
  restartPolicy: Never
EOF
```

`DB_HOSTNAME` and `passwd` are typos - the real keys are `DB_HOST` and `password`. Neither `valueFrom` entry sets `optional`, so it defaults to `false` (required).

### 7. Observe the status

```bash
sleep 15
kubectl get pod wrong-key-pod -n training
```

Status: `CreateContainerConfigError`.

### 8. Diagnose

```bash
kubectl describe pod wrong-key-pod -n training | tail -10
```

Events show: `Error: couldn't find key DB_HOSTNAME in ConfigMap training/db-config`

The kubelet reports one unresolved reference at a time. Fixing this one may well reveal the `passwd` typo next on the following retry - that's expected, not a new bug.

### 9. Fix: correct both key names

```bash
kubectl delete pod wrong-key-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: wrong-key-pod
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo DB_HOST=$DB_HOST DB_PASSWORD=$DB_PASSWORD && sleep 3600"]
      env:
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: db-config
              key: DB_HOST
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-creds
              key: password
  restartPolicy: Never
EOF
kubectl wait --for=condition=Ready pod/wrong-key-pod -n training --timeout=60s
kubectl logs wrong-key-pod -n training
```

### 10. Contrast: the same typo, but `optional: true`

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: optional-key-pod
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo \"DB_HOST=[$DB_HOST]\" && sleep 3600"]
      env:
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: db-config
              key: DB_HOSTNAME
              optional: true
  restartPolicy: Never
EOF
kubectl wait --for=condition=Ready pod/optional-key-pod -n training --timeout=60s
kubectl logs optional-key-pod -n training
```

Output: `DB_HOST=[]` - the pod starts fine; the env var is simply absent instead of erroring. `optional: true` is right for genuinely optional config, but it silently hides a typo you intended to be required - the default is `false` for a reason.

---

### Problem 3: Secret mounted as a volume - mount-path/key mismatch

### 11. Create the Secret and deploy a pod whose command reads the wrong filename

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: mount-secret
  namespace: training
type: Opaque
data:
  db-password: TW91bnRQQHNzMQ==
---
apiVersion: v1
kind: Pod
metadata:
  name: secret-mount-mismatch-pod
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo starting; cat /etc/app-secret/password || echo 'FILE NOT FOUND'; sleep 3600"]
      volumeMounts:
        - name: secret-vol
          mountPath: /etc/app-secret
          readOnly: true
  volumes:
    - name: secret-vol
      secret:
        secretName: mount-secret
  restartPolicy: Never
EOF
```

The Secret's only key is `db-password`, so the mounted file is `/etc/app-secret/db-password` - but the app reads `/etc/app-secret/password`.

### 12. Observe the status

```bash
sleep 15
kubectl get pod secret-mount-mismatch-pod -n training
```

Status: `Running`. This is the trap: the mount itself succeeded because the Secret exists, so nothing shows up in `describe`. The problem is one level down, inside the container.

### 13. Diagnose

```bash
kubectl logs secret-mount-mismatch-pod -n training
```

Output: `starting` / `FILE NOT FOUND`

```bash
kubectl exec secret-mount-mismatch-pod -n training -- ls /etc/app-secret/
```

Output: `db-password` - the file is there, just not named what the app expects.

### 14. Fix: remap the key to the filename the app expects, using `items`

```bash
kubectl delete pod secret-mount-mismatch-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: secret-mount-mismatch-pod
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo starting; cat /etc/app-secret/password; sleep 3600"]
      volumeMounts:
        - name: secret-vol
          mountPath: /etc/app-secret
          readOnly: true
  volumes:
    - name: secret-vol
      secret:
        secretName: mount-secret
        items:
          - key: db-password
            path: password
  restartPolicy: Never
EOF
kubectl wait --for=condition=Ready pod/secret-mount-mismatch-pod -n training --timeout=60s
kubectl logs secret-mount-mismatch-pod -n training
```

Output: `starting` / `MountP@ss1`. The fix is either to change the app's expected path, or - as here - use `items`/`path` in the volume spec to rename the key on disk to match.

---

### Problem 4: ConfigMap updated, but the running pod doesn't see it

### 15. Create the ConfigMap and two pods that consume it differently

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: live-config
  namespace: training
data:
  MESSAGE: v1
---
apiVersion: v1
kind: Pod
metadata:
  name: live-config-env-pod
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: MESSAGE
          valueFrom:
            configMapKeyRef:
              name: live-config
              key: MESSAGE
  restartPolicy: Never
---
apiVersion: v1
kind: Pod
metadata:
  name: live-config-volume-pod
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: config-vol
          mountPath: /etc/live-config
  volumes:
    - name: config-vol
      configMap:
        name: live-config
  restartPolicy: Never
EOF
kubectl wait --for=condition=Ready pod/live-config-env-pod pod/live-config-volume-pod -n training --timeout=60s
```

### 16. Confirm the initial value in both pods

```bash
kubectl exec live-config-env-pod -n training -- printenv MESSAGE
kubectl exec live-config-volume-pod -n training -- cat /etc/live-config/MESSAGE
```

Both show `v1`.

### 17. Update the ConfigMap

```bash
kubectl patch configmap live-config -n training --type merge -p '{"data":{"MESSAGE":"v2"}}'
```

### 18. Observe both pods again, immediately

```bash
kubectl exec live-config-env-pod -n training -- printenv MESSAGE
kubectl exec live-config-volume-pod -n training -- cat /etc/live-config/MESSAGE
```

Both may still show `v1` right after the edit.

### 19. Wait for the kubelet sync interval and re-check the volume pod

```bash
sleep 90
kubectl exec live-config-volume-pod -n training -- cat /etc/live-config/MESSAGE
```

Now shows `v2`. Volume-mounted keys update in place once the kubelet resyncs the projected volume (typically within a minute or two, depending on the sync period and cache TTL) - no pod restart needed.

### 20. Diagnose why the env pod is still stale, then fix it

```bash
kubectl exec live-config-env-pod -n training -- printenv MESSAGE
```

Still `v1`. This is expected, not a bug: env vars are copied into the process environment exactly once, at container start. They are a snapshot, not a live link - editing the ConfigMap afterwards can never change them for that running container.

```bash
kubectl delete pod live-config-env-pod -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: live-config-env-pod
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: MESSAGE
          valueFrom:
            configMapKeyRef:
              name: live-config
              key: MESSAGE
  restartPolicy: Never
EOF
kubectl wait --for=condition=Ready pod/live-config-env-pod -n training --timeout=60s
kubectl exec live-config-env-pod -n training -- printenv MESSAGE
```

Now `v2` - a fresh container start re-reads the ConfigMap. In practice you'd trigger this with a Deployment rollout restart (`kubectl rollout restart deployment/<name>`) rather than deleting a bare Pod, so the controller replaces pods for you consistently.

---

### Problem 5 (optional): base64/`stringData` mix-up producing garbage

### 21. Deploy a Secret where a value was mistakenly pre-encoded before being placed in `stringData`

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: bad-secret
  namespace: training
type: Opaque
stringData:
  password: UzNjcjN0IQ==
---
apiVersion: v1
kind: Pod
metadata:
  name: bad-secret-pod
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo PASSWORD=$PASSWORD && sleep 3600"]
      env:
        - name: PASSWORD
          valueFrom:
            secretKeyRef:
              name: bad-secret
              key: password
  restartPolicy: Never
EOF
```

The intended password is `S3cr3t!`. Whoever wrote this manifest base64-encoded it by hand and pasted the result into `stringData` - which already expects plain text and encodes it for you exactly once.

### 22. Observe the status

```bash
kubectl wait --for=condition=Ready pod/bad-secret-pod -n training --timeout=60s
kubectl get pod bad-secret-pod -n training
```

Status: `Running` - no error at all. This is the dangerous case: everything looks healthy, but the value the app receives is wrong.

### 23. Diagnose

```bash
kubectl logs bad-secret-pod -n training
```

Output: `PASSWORD=UzNjcjN0IQ==` - garbage: that's the base64 text itself, not the intended password.

```bash
kubectl get secret bad-secret -n training -o jsonpath='{.data.password}' | base64 -d && echo
```

Output: `UzNjcjN0IQ==` - decoding the Secret's stored data just returns the base64 string again, because the value was encoded twice (once by hand, once by the API server).

### 24. Fix: put the plain value in `stringData` (don't pre-encode)

```bash
kubectl delete pod bad-secret-pod -n training --force --grace-period=0
kubectl delete secret bad-secret -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: bad-secret
  namespace: training
type: Opaque
stringData:
  password: S3cr3t!
---
apiVersion: v1
kind: Pod
metadata:
  name: bad-secret-pod
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo PASSWORD=$PASSWORD && sleep 3600"]
      env:
        - name: PASSWORD
          valueFrom:
            secretKeyRef:
              name: bad-secret
              key: password
  restartPolicy: Never
EOF
kubectl wait --for=condition=Ready pod/bad-secret-pod -n training --timeout=60s
kubectl logs bad-secret-pod -n training
```

Output: `PASSWORD=S3cr3t!`

Rule of thumb: `data:` fields hold values **you** have already base64-encoded (encode once, yourself); `stringData:` fields hold plain text and the API server encodes it for you (never pre-encode). Mixing the two conventions is the most common cause of a Secret that "works" but delivers garbage.

## Troubleshooting Cheat Sheet

| Symptom | Cause | Diagnostic |
|---|---|---|
| `CreateContainerConfigError`, `configmap "X" not found` / `secret "X" not found` | `envFrom`/`valueFrom` references a ConfigMap or Secret that doesn't exist (wrong name, wrong namespace, not created yet) | `kubectl describe pod` (Events) |
| `CreateContainerConfigError`, `couldn't find key X in ConfigMap/Secret Y` | `configMapKeyRef`/`secretKeyRef` key name typo, with `optional` unset or `false` | `kubectl describe pod` (Events) |
| Pod `Running`, env var empty/unset even though a key is "missing" | Same key typo, but `optional: true` suppresses the error | `kubectl exec -- printenv` |
| Pod `Running`, app reports file not found | Volume mount succeeded (object exists) but the file name on disk doesn't match what the app reads - no `items`/`path` remap | `kubectl exec -- ls <mountPath>`, `kubectl logs` |
| Env var value unchanged right after editing a ConfigMap/Secret | Env vars are resolved once at container start - they are a snapshot, not live | `kubectl exec -- printenv`, then restart the pod |
| Volume-mounted file value unchanged immediately after an edit | kubelet syncs projected ConfigMap/Secret volumes on a delay (roughly a minute or two), not instantly | `kubectl exec -- cat <file>`, wait and retry |
| Secret value is still base64-looking text after decoding | `stringData` value was pre-encoded by mistake (double-encoded), or `data`/`stringData` conventions were mixed | `kubectl get secret -o jsonpath='{.data.KEY}' \| base64 -d` |

## Verification

```bash
# All pods Running
kubectl get pods -n training

# Correct values resolved end to end
kubectl exec wrong-key-pod -n training -- printenv DB_HOST DB_PASSWORD
kubectl exec secret-mount-mismatch-pod -n training -- cat /etc/app-secret/password
kubectl exec live-config-volume-pod -n training -- cat /etc/live-config/MESSAGE
kubectl exec live-config-env-pod -n training -- printenv MESSAGE
kubectl exec bad-secret-pod -n training -- printenv PASSWORD
```

## Cleanup

```bash
kubectl delete pod configmap-missing-pod wrong-key-pod optional-key-pod secret-mount-mismatch-pod live-config-env-pod live-config-volume-pod bad-secret-pod -n training --ignore-not-found --force --grace-period=0
kubectl delete configmap service-settings db-config live-config -n training --ignore-not-found --force --grace-period=0
kubectl delete secret db-creds mount-secret bad-secret -n training --ignore-not-found --force --grace-period=0
```

## Further reading
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) - concept reference
- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) - concept reference
- [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) - task walkthrough
- [Distribute Credentials Securely Using Secrets](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/) - task walkthrough
- [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/) - task walkthrough
