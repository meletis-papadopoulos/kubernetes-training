# Exercise 1.2 - Solutions

This exercise is read-only; there are no manifests and no cleanup. All IPs, ages, versions and UIDs
below are **illustrative** - assert only the deterministic parts (roles, groups, scopes, conditions).

## Task 1 - nodes, roles, labels, runtime

```bash
kubectl get nodes -o wide
kubectl get node controlplane --show-labels
```

Expected (values illustrative; note the `ROLES` and `CONTAINER-RUNTIME` columns):

```
NAME           STATUS   ROLES           AGE   VERSION   INTERNAL-IP    ...   CONTAINER-RUNTIME
controlplane   Ready    control-plane   40d   v1.31.1   172.30.1.2     ...   containerd://1.7.22
node01         Ready    <none>          40d   v1.31.1   172.30.2.2     ...   containerd://1.7.22
```

A worker shows `<none>` in `ROLES`. Pull the control-plane node's kubelet version and runtime string
directly:

```bash
kubectl get node controlplane \
  -o jsonpath='{.status.nodeInfo.kubeletVersion}{"\n"}{.status.nodeInfo.containerRuntimeVersion}{"\n"}'
```

Expected:

```
v1.31.1
containerd://1.7.22
```

**Answer:** `kubectl` derives the `ROLES` column from the node label
`node-role.kubernetes.io/control-plane` (an empty-value label). A worker has no such label, so it
prints `<none>`. You can see it in the `--show-labels` output alongside the built-in
`kubernetes.io/hostname`, `kubernetes.io/os`, and `kubernetes.io/arch` labels.

## Task 2 - control-plane components + DNS

```bash
kubectl get pods -n kube-system -o wide | grep -E 'apiserver|etcd|scheduler|controller-manager'
```

Expected - all four run on the control-plane node (IPs/ages illustrative):

```
etcd-controlplane                      1/1   Running   0   40d   172.30.1.2   controlplane
kube-apiserver-controlplane            1/1   Running   0   40d   172.30.1.2   controlplane
kube-controller-manager-controlplane   1/1   Running   0   40d   172.30.1.2   controlplane
kube-scheduler-controlplane            1/1   Running   0   40d   172.30.1.2   controlplane
```

Locate cluster DNS and kube-proxy:

```bash
kubectl get pods,svc -n kube-system -l k8s-app=kube-dns
kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide \
  || echo "kube-proxy may be replaced by the CNI (e.g. Cilium eBPF) on this cluster"
```

Expected (CoreDNS Pods + the `kube-dns` Service; ClusterIP illustrative):

```
NAME                          READY   STATUS    RESTARTS   AGE
pod/coredns-7db6d8ff4d-8x2kq  1/1     Running   0          40d
pod/coredns-7db6d8ff4d-p4rjt  1/1     Running   0          40d

NAME               TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
service/kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   40d
```

**Answer:** the four control-plane components have **no** Deployment/ReplicaSet - they run as
**static Pods**. The kubelet on the control-plane node watches its manifest directory
(`/etc/kubernetes/manifests/`) and starts one Pod per file directly, which is why their Pod names are
suffixed with the node name (`kube-apiserver-controlplane`) and they cannot be scaled or edited via
the API the way a Deployment can.

## Task 3 - api-resources, node capacity/conditions

```bash
kubectl api-resources | grep -E '^deployments|^nodes|^events '
```

Expected (note `APIVERSION` group and the `NAMESPACED` column):

```
NAME          SHORTNAMES   APIVERSION   NAMESPACED   KIND
deployments   deploy       apps/v1      true         Deployment
events        ev           v1           true         Event
nodes         no           v1           false        Node
```

Describe the node and read its health/capacity:

```bash
kubectl describe node controlplane | sed -n '/Conditions:/,/Capacity:/p'
kubectl get node controlplane -o jsonpath='{.status.capacity.cpu}{"\n"}{.status.capacity.memory}{"\n"}'
```

Expected (values illustrative; `Ready=True` and the four pressure conditions `False` are what matter):

```
Conditions:
  Type             Status
  MemoryPressure   False
  DiskPressure     False
  PIDPressure      False
  Ready            True
...
2
1987034Ki
```

**Answer:** for Pods stuck `Pending`, check the **scheduler** side first - start with
`kubectl describe pod <name>` events (they name the exact reason: `Insufficient cpu/memory`, taints
untolerated, no matching node selector, unbound PVC), then confirm node health/capacity from the node
`Conditions` (`Ready`, `*Pressure`) and `Capacity` you inspected here. Insufficient schedulable
CPU/memory or a `NotReady`/pressured node is the most common cause a fresh Pod never leaves `Pending`.

## Cleanup

Nothing to clean up - this exercise created no objects.
