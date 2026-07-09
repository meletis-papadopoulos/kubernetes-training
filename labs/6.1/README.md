# Lab 6.1 - Scheduling

## Objective
Learn how to control pod placement using nodeSelector, nodeName, node affinity, pod anti-affinity, and taints/tolerations.

## Prerequisites
- cluster provisioned with `provision.sh` (1 control-plane + 1 worker)
- Namespace `training` created: `kubectl create namespace training`

## Steps

### Part A: NodeSelector

### 1. List your nodes

```bash
kubectl get nodes --show-labels
```

### 2. Label a worker node

```bash
kubectl label node node01 disktype=ssd
```

### 3. Deploy a pod with nodeSelector

```bash
kubectl apply -f pod-nodeselector.yaml
```

### 4. Verify the pod landed on the labeled node

```bash
kubectl get pod pod-nodeselector -n training -o wide
```

The NODE column should show `node01`.

### 5. What happens without the label?

If all nodes with that label were unavailable, the pod would stay `Pending`.

### Part B: nodeName (Direct Assignment)

### 6. Deploy a pod with nodeName

```bash
kubectl apply -f pod-nodename.yaml
```

### 7. Verify it landed on the exact node

```bash
kubectl get pod pod-nodename -n training -o wide
```

The NODE column must show `node01`. Unlike `nodeSelector`, `nodeName` bypasses the scheduler entirely -- the pod is assigned directly to the named node.

### 8. Understand when to use nodeName

- `nodeName`: hardcodes the pod to one specific node. The scheduler is skipped entirely.
- Use cases: debugging, DaemonSet-like one-off pods, testing a specific node.
- Risk: if the node does not exist, the pod stays `Pending`. If the node is down, the pod is not rescheduled.

### Part C: Node Affinity

### 9. Deploy a pod with node affinity

```bash
kubectl apply -f pod-affinity.yaml
```

### 10. Check where it was scheduled

```bash
kubectl get pod pod-node-affinity -n training -o wide
```

The pod has:
- **required** affinity for `kubernetes.io/os=linux` (all nodes match)
- **preferred** affinity for `disktype=ssd` (prefers `node01`)

### 11. Compare nodeSelector vs nodeName vs affinity

- `nodeName`: bypasses the scheduler, hardcodes to a specific node
- `nodeSelector`: simple key-value match, hard requirement
- `requiredDuringScheduling`: must match (like nodeSelector but with operators: In, NotIn, Exists, etc.)
- `preferredDuringScheduling`: soft preference with weights, scheduler tries but does not guarantee

### Part D: Pod Anti-Affinity

### 12. Deploy the anti-affinity deployment

```bash
kubectl apply -f pod-anti-affinity.yaml
```

### 13. Verify pods are spread across nodes

```bash
kubectl get pods -n training -l app=spread-app -o wide
```

With `preferredDuringSchedulingIgnoredDuringExecution` and `topologyKey: kubernetes.io/hostname`, the scheduler tries to place each pod on a different node. With 3 replicas and 2 nodes (including control-plane), pods should spread across the available nodes.

### Part E: Taints and Tolerations

### 14. Check existing taints

```bash
kubectl describe node controlplane | grep -i taint
```

The control-plane has a taint `node-role.kubernetes.io/control-plane:NoSchedule`.

### 15. Taint both nodes

On a typical Kubernetes cluster the control-plane has a `NoSchedule` taint by default, so tainting the single worker is enough to make a pod unschedulable. On the cluster, `provision.sh` **removes** the control-plane taint (both nodes need to be usable on a 2-node sandbox), so we have to add our own taint there too - otherwise plain pods just fall through to the control-plane and the demo loses its teeth.

```bash
kubectl taint nodes controlplane environment=production:NoSchedule
kubectl taint nodes node01 environment=production:NoSchedule
```

### 16. Try scheduling a pod on the tainted nodes

```bash
kubectl run taint-test --image=nginx:1.25 -n training
kubectl get pod taint-test -n training -o wide
```

The pod will stay `Pending` because **every** node is tainted and the pod has no matching toleration.

### 17. Create a pod with a toleration

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: taint-tolerant
  namespace: training
spec:
  tolerations:
    - key: environment
      operator: Equal
      value: production
      effect: NoSchedule
  containers:
    - name: nginx
      image: nginx:1.25
EOF
```

### 18. Verify the tolerant pod can run on the tainted node

```bash
kubectl get pod taint-tolerant -n training -o wide
```

The pod **may** run on `node01` because it tolerates the taint. It is not guaranteed to land there -- it merely tolerates the taint.

### 19. Remove the taints

```bash
kubectl taint nodes controlplane environment=production:NoSchedule-
kubectl taint nodes node01 environment=production:NoSchedule-
```

Note the trailing `-` which removes the taint.

## Verification

```bash
# NodeSelector pod on labeled node
kubectl get pod pod-nodeselector -n training -o wide

# nodeName pod on exact node
kubectl get pod pod-nodename -n training -o wide

# Anti-affinity pods spread across nodes
kubectl get pods -n training -l app=spread-app -o wide

# Check node labels
kubectl get nodes --show-labels | grep disktype

# Check node taints
kubectl describe nodes | grep -A2 Taints
```

## Cleanup

```bash
kubectl delete -f pod-nodeselector.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pod-nodename.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pod-affinity.yaml --ignore-not-found --force --grace-period=0
kubectl delete -f pod-anti-affinity.yaml --ignore-not-found --force --grace-period=0
kubectl delete pod taint-test taint-tolerant -n training --ignore-not-found --force --grace-period=0
kubectl label node node01 disktype-
kubectl taint nodes controlplane environment=production:NoSchedule- 2>/dev/null || true
kubectl taint nodes node01 environment=production:NoSchedule- 2>/dev/null || true
```

## Further reading
- [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) - concept reference
- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) - concept reference
- [Assign Pods to Nodes using Node Affinity](https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes-using-node-affinity/) - task walkthrough
