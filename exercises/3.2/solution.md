# Exercise 3.2 - Solutions

Reference manifests are in `solution/`. Namespace `secret-demo` is assumed to exist
(see the exercise Setup).

## Task 1 - create the Secret and reveal how it is stored

Imperatively (the `create secret generic` command base64-encodes the literals for you):

```bash
kubectl create secret generic db-cred -n secret-demo \
  --from-literal=username=admin \
  --from-literal=password='S3cr3tP@ss'
```

Or apply the equivalent manifest, where the values are already base64-encoded under `data`:

```bash
kubectl apply -f solution/db-cred.yaml
```

`solution/db-cred.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-cred
  namespace: secret-demo
type: Opaque
data:
  username: YWRtaW4=
  password: UzNjcjN0UEBzcw==
```

Reveal the stored form and decode it yourself:

```bash
kubectl get secret db-cred -n secret-demo -o jsonpath='{.data.password}'; echo
kubectl get secret db-cred -n secret-demo -o jsonpath='{.data.password}' | base64 -d; echo
```

Expected:

```
UzNjcjN0UEBzcw==
S3cr3tP@ss
```

**Answer to the reflective question:** the value is **base64-encoded, not encrypted**. base64 is a
reversible transport encoding - anyone who can read the Secret object (via the API or from etcd if it
is not encrypted at rest) can decode it back to the plaintext with a single `base64 -d`. So a Secret
is *not* a vault; its protection comes from **RBAC** limiting who can read it and from **encryption at
rest** for etcd, not from the encoding itself. `describe` deliberately hides the values (it prints
byte counts), but `get -o jsonpath` exposes them.

## Task 2 - consume as environment variables

```bash
kubectl apply -f solution/sec-env.yaml
kubectl wait --for=condition=Ready pod/sec-env -n secret-demo --timeout=60s
```

`solution/sec-env.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sec-env
  namespace: secret-demo
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "echo user=$DB_USER && sleep 3600"]
    env:
    - name: DB_USER
      valueFrom:
        secretKeyRef:
          name: db-cred
          key: username
    - name: DB_PASS
      valueFrom:
        secretKeyRef:
          name: db-cred
          key: password
  restartPolicy: Never
```

Confirm the values resolved inside the container:

```bash
kubectl exec sec-env -n secret-demo -- env | grep -E '^DB_'
```

Expected:

```
DB_USER=admin
DB_PASS=S3cr3tP@ss
```

**Answer to the reflective question:** env vars are easy to leak. They are visible to every process
in the container via `/proc/<pid>/environ`, they are commonly dumped by crash handlers and error
reporters, they often land in application logs, and any tool that prints the environment (like the
`env` command above, or `kubectl describe pod`) reveals them. A child process inherits them wholesale.

## Task 3 - mount as a read-only volume

```bash
kubectl apply -f solution/sec-vol.yaml
kubectl wait --for=condition=Ready pod/sec-vol -n secret-demo --timeout=60s
```

`solution/sec-vol.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sec-vol
  namespace: secret-demo
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "cat /etc/db/username && sleep 3600"]
    volumeMounts:
    - name: cred
      mountPath: /etc/db
      readOnly: true
  volumes:
  - name: cred
    secret:
      secretName: db-cred
  restartPolicy: Never
```

Each key becomes its own file; confirm and then prove the mount is read-only:

```bash
kubectl exec sec-vol -n secret-demo -- ls /etc/db
kubectl exec sec-vol -n secret-demo -- cat /etc/db/username; echo
kubectl exec sec-vol -n secret-demo -- sh -c 'echo x > /etc/db/username'
```

Expected - two files, the decoded username, and a write failure:

```
password
username
admin
sh: can't create /etc/db/username: Read-only file system
```

**Answer to the reflective question:** a mounted Secret is generally safer because the values live
only as files on a **tmpfs** (in-memory, never written to the node's disk) that is mounted **read-only**
into the container. They are not inherited by child processes, they are not dumped by env-printing
tools or crash handlers, and access is naturally scoped to whichever process reads the file. A mounted
Secret also **tracks updates** - if the Secret changes, the projected files refresh (with a delay),
whereas an env var is frozen at container start. The trade-off is that the application must read a file
rather than an env var.

## Cleanup

```bash
kubectl delete ns secret-demo --ignore-not-found
```
