# Exercise 2.1 - Solutions

Reference manifests are in `solution/`. Namespace `core` is assumed to exist (see the exercise Setup).

## Task 1 - Pod created imperatively

```bash
kubectl run quick --image=nginx:1.27.1 -n core
kubectl wait --for=condition=Ready pod/quick -n core --timeout=60s
kubectl get pod quick -n core -o wide
kubectl logs quick -n core
kubectl exec quick -n core -- nginx -v
```

Verify:

```bash
kubectl get pod quick -n core -o jsonpath='{.status.phase}{"\t"}{.spec.containers[0].image}{"\n"}'
kubectl exec quick -n core -- nginx -v
```

Expected (Pod IP and node are illustrative):

```
Running	nginx:1.27.1
nginx version: nginx/1.27.1
```

**Answer to the reflective question:** **nothing** would recreate it. `kubectl run` creates a *bare*
Pod with no owning controller, so if you delete it - or the node hosting it fails - the Pod is simply
gone. Keeping a desired number of Pods alive across failures is exactly what a ReplicaSet/Deployment
adds (exercise 2.3).

## Task 2 - Pod created from a manifest

```bash
kubectl apply -f solution/configured-pod.yaml
kubectl wait --for=condition=Ready pod/configured -n core --timeout=60s
```

`solution/configured-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: configured
  namespace: core
spec:
  containers:
  - name: talker
    image: busybox:1.36
    command: ["sh", "-c"]
    args: ["echo \"$GREETING from $(hostname)\"; while true; do sleep 30; done"]
    env:
    - name: GREETING
      value: "hello-core"
    ports:
    - containerPort: 8080
```

Verify the greeting, the env var, and the port:

```bash
kubectl logs configured -n core
kubectl get pod configured -n core \
  -o jsonpath='{.spec.containers[0].env[0].name}={.spec.containers[0].env[0].value}{"\t"}{.spec.containers[0].ports[0].containerPort}{"\n"}'
```

Expected:

```
hello-core from configured
GREETING=hello-core	8080
```

**Answer to the reflective question:** a container's lifetime **is** its main process. If the `echo`
returned, PID 1 would exit and the container would terminate (then, under the default `restartPolicy:
Always`, restart and echo again - a crash-loop). The `while true; do sleep 30; done` keeps PID 1
alive so the Pod stays `Running` after the one-shot greeting.

## Task 3 - the default restartPolicy

```bash
kubectl get pod configured -n core -o jsonpath='{.spec.restartPolicy}{"\n"}'
```

Expected:

```
Always
```

**Answer to the reflective question:** the manifest omitted `restartPolicy`, so the API server
defaulted it to **`Always`** - the right choice for a long-running service, which should be restarted
whenever it exits. A **Job** runs a task that is *meant to finish*; with `Always` the kubelet would
restart the container even after it succeeded, so the pod could never complete. Jobs therefore require
`OnFailure` or `Never`, letting a successful container exit stay exited.

## Cleanup

```bash
kubectl delete pod quick configured -n core --ignore-not-found --force --grace-period=0
kubectl delete ns core --ignore-not-found
```
