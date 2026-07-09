# Exercise 5.1 - Solutions

Reference manifests are in `solution/`. Namespace `vol-demo` is assumed to exist (see the exercise Setup).

## Task 1 - two containers sharing an emptyDir

```bash
kubectl apply -f solution/shared-vol.yaml
kubectl wait --for=condition=Ready pod/shared-vol -n vol-demo --timeout=60s
```

`solution/shared-vol.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shared-vol
  namespace: vol-demo
spec:
  containers:
  - name: writer
    image: busybox:1.36
    command: ["sh", "-c", "echo 'written by writer' > /data/shared.txt && sleep 3600"]
    volumeMounts:
    - name: scratch
      mountPath: /data
  - name: reader
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts:
    - name: scratch
      mountPath: /data
  volumes:
  - name: scratch
    emptyDir: {}
```

Read the writer's file from the **reader** container:

```bash
kubectl exec shared-vol -n vol-demo -c reader -- cat /data/shared.txt
```

Expected:

```
written by writer
```

**Answer to the reflective question:** an `emptyDir` is a *Pod-level* volume. Both containers mount the
same volume at `/data`, so a file the `writer` creates is immediately visible to the `reader`. Containers
in a Pod have separate filesystems and process namespaces, but a shared volume is exactly the supported
mechanism for passing data between them.

## Task 2 - emptyDir dies with the Pod

```bash
kubectl delete pod shared-vol -n vol-demo --force --grace-period=0
kubectl apply -f solution/shared-vol.yaml
kubectl wait --for=condition=Ready pod/shared-vol -n vol-demo --timeout=60s
kubectl exec shared-vol -n vol-demo -c reader -- cat /data/shared.txt
```

Note the writer re-creates `/data/shared.txt` on every start, so to prove the *old* data is gone we check
that this is a fresh file, not the persisted one. The clearest demonstration is that the emptyDir starts
empty on the new Pod - only the writer's fresh write exists, and any file you had added by hand would be
gone. Confirm the volume was re-created empty:

```bash
kubectl exec shared-vol -n vol-demo -c reader -- sh -c 'echo "manually added" >> /data/note.txt'
kubectl delete pod shared-vol -n vol-demo --force --grace-period=0
kubectl apply -f solution/shared-vol.yaml
kubectl wait --for=condition=Ready pod/shared-vol -n vol-demo --timeout=60s
kubectl exec shared-vol -n vol-demo -c reader -- cat /data/note.txt
```

Expected - the manually added file did **not** survive:

```
cat: can't open '/data/note.txt': No such file or directory
command terminated with exit code 1
```

**Answer to the reflective question:** an `emptyDir` is created empty when the Pod is assigned to a node
and is **deleted permanently when the Pod is removed** - its lifetime is tied to the Pod. A
PersistentVolumeClaim (and its backing PersistentVolume) is an independent object that **outlives** the
Pod: delete the Pod and the data remains, ready to be mounted by the next Pod. Use `emptyDir` for scratch
space, a PVC for anything that must survive a restart.

## Task 3 - hostPath data lives on the node

```bash
kubectl apply -f solution/hostpath-pod.yaml
kubectl wait --for=condition=Ready pod/hostpath-pod -n vol-demo --timeout=60s
NODE=$(kubectl get pod hostpath-pod -n vol-demo -o jsonpath='{.spec.nodeName}')
echo "landed on: $NODE"
kubectl exec hostpath-pod -n vol-demo -- cat /host/marker.txt
```

`solution/hostpath-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hostpath-pod
  namespace: vol-demo
spec:
  containers:
  - name: writer
    image: busybox:1.36
    command: ["sh", "-c", "echo 'on the node' > /host/marker.txt && sleep 3600"]
    volumeMounts:
    - name: host
      mountPath: /host
  volumes:
  - name: host
    hostPath:
      path: /tmp/ex51-host
      type: DirectoryOrCreate
```

Expected - the marker was written into the node's directory:

```
on the node
```

**Answer to the reflective question:** a `hostPath` volume is a directory on the *node's* filesystem, so
its data outlives any individual Pod but is **tied to that one node**. If a Pod using this volume is
scheduled onto a different node, it sees that node's (empty or different) `/tmp/ex51-host` - the data does
not follow the Pod. This node-affinity and the security exposure of mounting host paths are why `hostPath`
is unsuitable for real workloads; use a PVC backed by a StorageClass instead.

## Cleanup

```bash
kubectl delete ns vol-demo --ignore-not-found
# hostPath data remains on the node's disk; remove it if you can reach the node:
# ssh $NODE rm -rf /tmp/ex51-host
```
