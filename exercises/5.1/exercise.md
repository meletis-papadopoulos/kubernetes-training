# Exercise 5.1 - Volumes (emptyDir / hostPath)

*Domain: Storage. Target: ~10 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace vol-demo
```

## Tasks

1. In the namespace `vol-demo`, create a Pod named `shared-vol` with **two** containers that share a
   single `emptyDir` volume named `scratch` mounted at `/data` in both. The first container `writer`
   (image `busybox:1.36`) runs `echo 'written by writer' > /data/shared.txt && sleep 3600`; the second
   container `reader` (image `busybox:1.36`) just runs `sleep 3600`. Apply it, wait until the Pod is
   `2/2` Ready, then read `/data/shared.txt` **from the `reader` container**. Does the reader see the
   file the writer created, and if so, why - they are two separate containers?

2. Delete the `shared-vol` Pod (`--force --grace-period=0`) and re-create it from the same manifest.
   Once it is Ready again, read `/data/shared.txt` from the `reader` container. Is the previous content
   still there? Given what you observe, how does the lifetime of an `emptyDir` compare to that of a
   PersistentVolumeClaim?

3. In the namespace `vol-demo`, create a Pod named `hostpath-pod` (image `busybox:1.36`) that mounts a
   `hostPath` volume with `path: /tmp/ex51-host` and `type: DirectoryOrCreate` at `/host`, running
   `echo 'on the node' > /host/marker.txt && sleep 3600`. Apply it, capture the node it landed on
   (`.spec.nodeName`), and read `/host/marker.txt` back. The file is written into a directory on that
   node's own filesystem - what happens to that data if a Pod using this volume is later scheduled onto
   a *different* node?

## Acceptance criteria

- `shared-vol` reaches `2/2` Ready; the `reader` container reads `written by writer` from
  `/data/shared.txt` (both containers share the one `emptyDir`).
- After deleting and re-creating `shared-vol`, `/data/shared.txt` is gone from the fresh Pod - the
  `emptyDir` was destroyed with the old Pod.
- `hostpath-pod` reads `on the node` from `/host/marker.txt`, written into `/tmp/ex51-host` on the node
  it landed on - the data lives on that node's filesystem, not inside the Pod.

## Docs you may reference

- [Volumes](https://kubernetes.io/docs/concepts/storage/volumes/)
- [emptyDir](https://kubernetes.io/docs/concepts/storage/volumes/#emptydir)
- [hostPath](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath)
