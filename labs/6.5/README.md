# Lab 6.5 - DaemonSets

## Objective
Learn how DaemonSets work and when they are the right workload type: one pod per node, for per-node agents like log collectors, monitoring agents, or network plugins.

## Prerequisites
- cluster provisioned with `provision.sh` (1 control-plane + 1 worker)
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Create the DaemonSet

```bash
kubectl apply -f daemonset.yaml
kubectl rollout status daemonset/node-logger -n training --timeout=60s
```

### 2. Verify pods run on all nodes

```bash
kubectl get pods -n training -l app=node-logger -o wide
```

You should see one pod per node (2 total: 1 control-plane + 1 worker). The DaemonSet includes a toleration for the control-plane taint.

### 3. Check the DaemonSet status

```bash
kubectl get daemonset node-logger -n training
```

DESIRED, CURRENT, and READY should all be 2.

### 4. View logs from a specific pod

```bash
kubectl logs -n training -l app=node-logger --tail=5
```

Each pod logs its hostname (which is the node name).

### 5. Understand DaemonSet behavior

Try scaling a DaemonSet (it will fail):

```bash
kubectl scale daemonset node-logger --replicas=5 -n training
# Error from server (NotFound): the server could not find the requested resource
```

The error message changed in newer Kubernetes: `kubectl scale` calls the `/scale` subresource on the target object, but DaemonSets don't expose a `/scale` subresource at all, so the API returns a plain 404. Older kubectl versions returned a friendlier `daemonsets do not support scaling`. **Same point either way** - DaemonSets size themselves to the node count, not a user-set replica value. Add a node, a new pod appears. Remove a node, the pod is removed.

## Verification

```bash
# DaemonSet runs on all nodes
kubectl get daemonset node-logger -n training

# One pod per node
kubectl get pods -n training -l app=node-logger -o wide
```

## Cleanup

```bash
kubectl delete -f daemonset.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) - concept reference
