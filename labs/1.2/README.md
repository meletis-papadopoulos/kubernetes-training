# Lab 1.2 - Inspect Your Cluster

## Objective
A **read-only** tour that makes the Foundations concept decks (Cluster Architecture, Container Runtime & CRI, CNI, CSI) and the CoreDNS deck (4.2) concrete: see the control-plane components, the worker-node agents, the container runtime, the CNI, the CSI drivers, and CoreDNS on the real cluster. Nothing here changes state. (On many clusters the control-plane components are abstracted away from users - this works here because the training cluster is vanilla kubeadm.)

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training` (used only for the throwaway `dnsutil` Pod)

## Steps

### 1. Control-plane components (static Pods in kube-system)

```bash
kubectl get pods -n kube-system -l tier=control-plane -o wide
kubectl get pods -n kube-system | grep -E 'apiserver|etcd|scheduler|controller-manager'
```

These are the pieces from the Architecture slide: `kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager` - run as static Pods by the kubelet on the control-plane node.

### 2. Nodes and worker-node agents

```bash
kubectl get nodes -o wide
kubectl get node controlplane -o jsonpath='{.status.nodeInfo.kubeletVersion}{"\n"}{.status.nodeInfo.containerRuntimeVersion}{"\n"}{.status.nodeInfo.osImage}{"\n"}'
```

`kubectl get nodes -o wide` shows each node's **CONTAINER-RUNTIME** (`containerd://…`) and internal IP. The kubelet + kube-proxy run on every node.

### 3. Container runtime (CRI)

```bash
kubectl get nodes -o wide --no-headers | awk '{print $1, $NF}'
kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide 2>/dev/null || echo "kube-proxy replaced by the CNI (eBPF) on this cluster"
```

The runtime column confirms containerd via the CRI. (This cluster's Cilium may replace kube-proxy with eBPF - hence the fallback message.)

### 4. CNI - the Pod network

```bash
kubectl get pods -n kube-system -o wide | grep -i cilium
kubectl get pods -A -o wide --no-headers | awk '{print $1"/"$2, $7}' | head
```

Cilium is the CNI. The second command shows Pods with IPs assigned from the Pod CIDR - that IP assignment is the CNI's job.

### 5. CSI - storage drivers and classes

```bash
kubectl get csidrivers
kubectl get storageclass
```

`local-path` is the default StorageClass on this cluster; its provisioner is what dynamically creates PVs (the CSI slide's flow).

### 6. CoreDNS - cluster DNS

```bash
kubectl get pods,svc -n kube-system -l k8s-app=kube-dns
kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}{"\n"}'
```

The `kube-dns` Service ClusterIP is what every Pod's `/etc/resolv.conf` points at.

### 7. Resolve names from a throwaway Pod

```bash
kubectl run dnsutil --image=busybox:1.36 --restart=Never -n training --command -- sleep 600
kubectl wait --for=condition=Ready pod/dnsutil -n training --timeout=60s
kubectl exec dnsutil -n training -- cat /etc/resolv.conf
kubectl exec dnsutil -n training -- nslookup kubernetes.default.svc.cluster.local
kubectl exec dnsutil -n training -- nslookup kube-dns.kube-system.svc.cluster.local
```

Note the `search` domains and `ndots:5` in `resolv.conf` - that's why short names resolve inside a namespace. The Service names resolve to ClusterIPs served by CoreDNS.

## Cleanup

```bash
kubectl delete pod dnsutil -n training --force --grace-period=0 --ignore-not-found
```

> Everything except the throwaway `dnsutil` Pod was read-only. This lab pairs with the Foundations concept decks (**Cluster Architecture**, **Container Runtime & CRI**, **CNI**, **CSI**) and the **4.2 CoreDNS** deck.
