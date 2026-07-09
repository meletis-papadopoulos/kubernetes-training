# Exercise 6.5 - Solutions

Reference manifests are in `solution/`. Namespace `logging` is assumed to exist.

## Task 1 - DaemonSet, one pod per eligible node

```bash
kubectl apply -f solution/daemonset.yaml
```

`solution/daemonset.yaml`:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-logger
  namespace: logging
spec:
  selector:
    matchLabels:
      app: node-logger
  template:
    metadata:
      labels:
        app: node-logger
    spec:
      containers:
      - name: logger
        image: busybox:1.36
        command: ["sleep", "3600"]
        volumeMounts:
        - name: varlog
          mountPath: /host/var/log
          readOnly: true
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
```

Verify:

```bash
kubectl get ds node-logger -n logging
kubectl get pods -n logging -o wide
```

Expected on a standard 2-node cluster:

```
NAME          DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
node-logger   1         1         1       1            1           <none>          15s
```

**Answer:** you get **1** pod, not 2. A DaemonSet schedules one pod on every node that its pod can
tolerate. The control-plane node carries the `node-role.kubernetes.io/control-plane:NoSchedule` taint,
and this pod has no matching toleration, so it is placed only on the worker.

## Task 2 - tolerate the control-plane taint

```bash
kubectl apply -f solution/daemonset-tolerated.yaml
```

The only change is the added toleration:

```yaml
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
```

Verify:

```bash
kubectl get ds node-logger -n logging
```

Expected (total node count):

```
NAME          DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   AGE
node-logger   2         2         2       2            2           1m
```

**Answer:** with the toleration, the control-plane taint no longer repels the pod, so the DaemonSet
now runs on **every** node - `DESIRED` rises to the total node count.

## Task 3 - rolling update

```bash
kubectl patch ds node-logger -n logging --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["sleep","7200"]}]'
kubectl rollout status ds/node-logger -n logging
```

Expected:

```
daemon set "node-logger" successfully rolled out
```

Confirm:

```bash
kubectl get ds node-logger -n logging
```

`UP-TO-DATE` equals `DESIRED`.

**Answer:** the `UP-TO-DATE` column reports how many pods are running the latest pod template. Under
the default `RollingUpdate` strategy the DaemonSet deletes and recreates one pod at a time
(`maxUnavailable: 1`), so a node agent is never fully absent across the fleet.

**Why a DaemonSet, not a Deployment?** A Deployment places N interchangeable replicas wherever the
scheduler likes; a DaemonSet guarantees exactly one pod **per node**, and automatically adds/removes
pods as nodes join/leave - which is what a node-local agent (logs, metrics, CNI) needs.

## Cleanup

```bash
kubectl delete ns logging --ignore-not-found
```
