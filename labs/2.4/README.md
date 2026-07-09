# Lab 2.4 - Rollouts & Rollbacks

## Objective
Learn how to perform rolling updates on a Deployment, monitor the rollout, view rollout history, and rollback to a previous version.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Create the Deployment with nginx:1.24

```bash
kubectl apply -f deployment.yaml
```

### 2. Verify the initial deployment

```bash
kubectl get deployment rolling-nginx -n training
kubectl get pods -n training -l app=rolling-nginx -o wide
```

Confirm all 3 replicas are running with `nginx:1.24`.

### 3. Check the current image version

```bash
kubectl get deployment rolling-nginx -n training -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Should output: `nginx:1.24`

### 4. Perform a rolling update to nginx:1.25

```bash
kubectl set image deployment/rolling-nginx nginx=nginx:1.25 -n training
```

### 5. Watch the rollout in real-time

```bash
kubectl rollout status deployment/rolling-nginx -n training
```

You should see messages like:
```
Waiting for deployment "rolling-nginx" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "rolling-nginx" rollout to finish: 2 out of 3 new replicas have been updated...
deployment "rolling-nginx" successfully rolled out
```

### 6. Verify the new image

```bash
kubectl get deployment rolling-nginx -n training -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Should output: `nginx:1.25`

### 7. Check rollout history

```bash
kubectl rollout history deployment/rolling-nginx -n training
```

You should see two revisions.

### 8. View details of a specific revision

```bash
kubectl rollout history deployment/rolling-nginx -n training --revision=1
kubectl rollout history deployment/rolling-nginx -n training --revision=2
```

### 9. Check the ReplicaSets

```bash
kubectl get replicasets -n training -l app=rolling-nginx
```

You should see two ReplicaSets: the old one with 0 replicas and the new one with 3.

### 10. Rollback to the previous version

```bash
kubectl rollout undo deployment/rolling-nginx -n training
```

### 11. Verify the rollback

```bash
kubectl rollout status deployment/rolling-nginx -n training
kubectl get deployment rolling-nginx -n training -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Should output: `nginx:1.24` (rolled back to the original version).

### 12. Rollback to a specific revision

Deployments can roll back to any revision still in history - not just the previous one.

**Important:** Kubernetes **dedupes** rollout history. When you `rollout undo`, the target revision is removed and recreated at the top with a new number. That means revisions 1 and 2 from earlier steps are **no longer in history** by the time you reach this step - the current history only contains the two most recent distinct revisions.

First, update the image again so you have multiple revisions to choose from:

```bash
kubectl set image deployment/rolling-nginx nginx=nginx:1.25 -n training
kubectl rollout status deployment/rolling-nginx -n training
```

Inspect what's currently in history and pick a revision that exists:

```bash
kubectl rollout history deployment/rolling-nginx -n training
```

Then roll back to the **oldest** revision shown (programmatically, to avoid hardcoding):

```bash
OLD_REV=$(kubectl rollout history deployment/rolling-nginx -n training \
  | awk '/^[0-9]+/{print $1; exit}')
echo "Rolling back to revision: $OLD_REV"
kubectl rollout undo deployment/rolling-nginx -n training --to-revision=$OLD_REV
kubectl rollout status deployment/rolling-nginx -n training
kubectl get deployment rolling-nginx -n training -o jsonpath='{.spec.template.spec.containers[0].image}'
echo
```

### 13. Record changes for better history

```bash
kubectl set image deployment/rolling-nginx nginx=nginx:1.25 -n training
kubectl annotate deployment/rolling-nginx -n training kubernetes.io/change-cause="Updated nginx to 1.25"
kubectl rollout history deployment/rolling-nginx -n training
```

The CHANGE-CAUSE column now shows your annotation.

## Verification

```bash
# Confirm the deployment is healthy
kubectl rollout status deployment/rolling-nginx -n training

# Check current revision number
kubectl rollout history deployment/rolling-nginx -n training

# Confirm pods are running
kubectl get pods -n training -l app=rolling-nginx
```

## Cleanup

```bash
kubectl delete -f deployment.yaml --ignore-not-found --force --grace-period=0
```

## Further reading
- [Updating a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment) - concept reference
- [Performing a Rolling Update](https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/) - tutorial
- [`kubectl rollout`](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout) - command reference
