# Lab 9.7 - PVC Problems

## Objective
Diagnose three PVC/storage issues that look superficially similar (PVC stays `Pending`, pod stays `ContainerCreating`) but have very different root causes: a non-existent StorageClass, a static PV that's too small to satisfy the PVC, and a pod referencing a PVC name that doesn't exist.

## Prerequisites
- cluster provisioned with `provision.sh` (default StorageClass `local-path` is the dynamic provisioner)
- Namespace `training` created: `kubectl create namespace training`
- Confirm: `kubectl get storageclass` should show `local-path` as `(default)`.

## Background

The PVC binding flow has three layers, and a stuck pod could be blocked at any of them:

| Layer | What happens | Failure symptom |
|---|---|---|
| **1. PVC → StorageClass** | Provisioner sees PVC, creates a PV | PVC `Pending`, no PV created |
| **2. PVC ↔ PV** | A matching PV (size, accessMode, sc) gets bound | PVC `Pending` even though PVs exist |
| **3. Pod → PVC** | Kubelet mounts the bound volume into the pod | Pod stuck `ContainerCreating` |

Same `kubectl get pvc` symptom (`Pending`), three completely different fixes.

## Steps

### Problem 1: PVC references a non-existent StorageClass

### 1. Apply a PVC with a made-up StorageClass

```bash
kubectl apply -f pvc-bad-storageclass.yaml
```

### 2. Observe

```bash
sleep 10
kubectl get pvc app-data-pvc -n training
```

Status: `Pending`. AGE keeps growing, `VOLUME` is empty.

### 3. Diagnose

```bash
kubectl describe pvc app-data-pvc -n training | tail -10
```

Events show:

```
Warning  ProvisioningFailed  ...  storageclass.storage.k8s.io "fast-ssd-premium" not found
```

Confirm the StorageClass is missing:

```bash
kubectl get storageclass
```

`fast-ssd-premium` is not in the list. The provisioner can't act because there's no StorageClass to delegate to.

### 4. Fix: use an existing StorageClass

You can't mutate `storageClassName` on a bound PVC, and you can't mutate it on a Pending one in some K8s versions either (it's an immutable field once set). Easier - recreate:

```bash
kubectl delete pvc app-data-pvc -n training
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data-pvc
  namespace: training
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
EOF
sleep 5
kubectl get pvc app-data-pvc -n training
```

`local-path` uses `volumeBindingMode: WaitForFirstConsumer`, so the PVC will stay `Pending` until a pod consumes it. That's expected - not the same kind of `Pending` as before. To confirm the StorageClass was found:

```bash
kubectl describe pvc app-data-pvc -n training | grep -A 3 Events
```

Look for `WaitForFirstConsumer` (good - provisioner is healthy, just waiting) versus the previous `ProvisioningFailed`.

---

### Problem 2: Static PV too small to satisfy PVC

This scenario is more common with **statically provisioned PVs** (e.g., pre-created disk or NFS-backed references) where someone hand-crafts a PV but the PVC asks for more storage than the PV provides.

### 5. Apply a 100Mi static PV alongside a PVC requesting 1Gi

```bash
kubectl apply -f pv-too-small.yaml
sleep 5
```

### 6. Observe

```bash
kubectl get pv,pvc -n training | grep -E "backup|NAME"
```

The PV is `Available` (no PVC matched it) and the PVC is `Pending`.

### 7. Diagnose

```bash
kubectl describe pvc backup-pvc -n training | tail -10
```

You'll likely see something like:

```
Warning  ProvisioningFailed  ...  persistentvolume-controller  storageclass.storage.k8s.io "manual-backup" not found
```

**This event is misleading noise - not the real failure.** `manual-backup` is just a label tying the static PV to the PVC; it's not a real StorageClass. Whenever a PVC isn't bound, the controller speculatively tries dynamic provisioning, and that path fails because no `manual-backup` StorageClass exists. The actual binding failure is silent: a static PV exists with this label, but the controller didn't pick it.

The crucial diagnostic is comparing the PV and PVC side by side:

```bash
kubectl get pv backup-pv -o jsonpath='Capacity={.spec.capacity.storage}, AccessModes={.spec.accessModes}, SC={.spec.storageClassName}{"\n"}'
kubectl get pvc backup-pvc -n training -o jsonpath='Request={.spec.resources.requests.storage}, AccessModes={.spec.accessModes}, SC={.spec.storageClassName}{"\n"}'
```

Output:

```
Capacity=100Mi, AccessModes=[ReadWriteOnce], SC=manual-backup
Request=1Gi, AccessModes=[ReadWriteOnce], SC=manual-backup
```

The PV offers 100Mi but the PVC asks for 1Gi. **The PV must be ≥ the PVC request** - same StorageClass, same accessMode, but the size mismatch is the binding blocker. Less obvious failure than mismatched accessModes (which produces an event) - easy to miss without an explicit comparison.

### 8. Fix: shrink the request to fit (or expand the PV)

```bash
kubectl delete pvc backup-pvc -n training
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-pvc
  namespace: training
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: manual-backup
  resources:
    requests:
      storage: 100Mi
EOF
sleep 5
kubectl get pvc backup-pvc -n training
```

PVC is now `Bound` to `backup-pv`.

---

### Problem 3: Pod references a PVC name that doesn't exist

### 9. Apply a pod whose `volumes.persistentVolumeClaim.claimName` is wrong

```bash
kubectl apply -f pod-wrong-claim-name.yaml
```

The PVC is named `data-pvc`, but the pod asks for `data-pvc-typo`.

### 10. Observe

```bash
sleep 15
kubectl get pod data-consumer -n training
```

Status: `Pending` (note: not `ContainerCreating` - the kubelet rejects scheduling because it can't satisfy the volume).

### 11. Diagnose

```bash
kubectl describe pod data-consumer -n training | tail -10
```

Events show:

```
Warning  FailedScheduling  ...  persistentvolumeclaim "data-pvc-typo" not found
```

This is a **scheduling** failure, not a kubelet runtime failure - the scheduler refuses to place a pod that depends on a non-existent volume claim.

The actual PVC exists with a different name:

```bash
kubectl get pvc -n training
```

You'll see `data-pvc` in the list - the pod was just looking for the wrong name.

### 12. Fix: recreate the pod with the correct claimName

```bash
kubectl delete pod data-consumer -n training --force --grace-period=0
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: data-consumer
  namespace: training
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
      resources:
        requests:
          cpu: 50m
          memory: 32Mi
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: data-pvc
EOF
kubectl wait --for=condition=Ready pod/data-consumer -n training --timeout=60s
```

The pod is now Running. The PVC `data-pvc` was bound at this moment (because `local-path` waits for first consumer).

```bash
kubectl get pvc data-pvc -n training
```

Status: `Bound`.

---

## Diagnostic Cheat Sheet

| Symptom | Event / clue | Root cause |
|---|---|---|
| PVC `Pending`, no PV | `storageclass.storage.k8s.io "X" not found` | StorageClass typo / missing |
| PVC `Pending`, PV `Available` | (silent - no event) | PV smaller than PVC request, or AccessMode mismatch, or different StorageClass |
| PVC `Pending`, default SC | `WaitForFirstConsumer` | **Expected** - binding deferred until pod consumes; not actually broken |
| Pod `Pending` | `persistentvolumeclaim "X" not found` | Pod's `claimName` typo'd or PVC in different namespace |
| Pod `ContainerCreating` indefinitely | `MountVolume.SetUp failed` / `volume not attached` | CSI driver issue, AccessMode RWX requested but driver only supports RWO |
| Pod `ContainerCreating` + `multi-attach error` | `Volume is already used by pod(s) X` | RWO PVC referenced by two pods on different nodes |

## Additional notes

- **Multi-attach error during deployment rollouts**: a Deployment with an RWO PVC + `RollingUpdate` strategy will hit `Multi-Attach error for volume` because the new pod is scheduled before the old one fully terminates and the disk detaches. Fix: use `strategy: Recreate`, or move to a ReadWriteMany-capable StorageClass if RWX is the actual requirement.
- **Pod stuck `ContainerCreating` for 6+ minutes**: usually a CSI issue - check the CSI driver pods in `kube-system` and look for `attach` errors. Disk attachment is per-node; many storage backends cap the number of disks a single node can have attached.
- **PV stuck `Released`**: with `reclaimPolicy: Retain`, a PV stays in the cluster after PVC deletion. To rebind, you need to manually clear `spec.claimRef` on the PV.

## Verification

```bash
kubectl get pvc -n training
# Expected end state:
#   app-data-pvc  Pending  (local-path is WaitForFirstConsumer, and we never gave it a consumer)
#   backup-pvc    Bound    backup-pv      (Problem 2 fixed - size now matches)
#   data-pvc      Bound    pvc-...        (Problem 3 fixed - pod consumed it, dynamic provisioning kicked in)

kubectl get pods -n training
# data-consumer Running
```

The `app-data-pvc Pending` is intentional - Problem 1's fix proved the StorageClass works (`WaitForFirstConsumer` event surfaced) without needing to round-trip through binding. To bind it, you'd attach a pod that mounts it.

## Cleanup

```bash
kubectl delete pod data-consumer -n training --ignore-not-found --force --grace-period=0
kubectl delete pvc app-data-pvc backup-pvc data-pvc -n training --ignore-not-found
kubectl delete pv backup-pv --ignore-not-found
```

## Further reading
- [Persistent Volumes - Lifecycle](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#lifecycle-of-a-volume-and-claim)
- [Volume Binding Mode - WaitForFirstConsumer](https://kubernetes.io/docs/concepts/storage/storage-classes/#volume-binding-mode)
