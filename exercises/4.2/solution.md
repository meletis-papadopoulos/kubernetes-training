# Exercise 4.2 - Solutions

Reference manifests are in `solution/`. Namespaces `net42` and `net42b` are assumed to exist
(see the exercise Setup). `busybox:1.28` is used for DNS lookups because its `nslookup` resolves
cluster DNS reliably; several later busybox builds ship an `nslookup` that fails against the cluster
resolver.

## Task 1 - resolve the Service A record

```bash
kubectl apply -f solution/deployment.yaml
kubectl apply -f solution/service.yaml
kubectl rollout status deployment/dnsweb -n net42 --timeout=60s
```

```bash
kubectl run dnstmp --image=busybox:1.28 -n net42 --restart=Never -i --rm -- \
  nslookup dnsweb.net42.svc.cluster.local
```

Expected (the address is illustrative):

```
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      dnsweb.net42.svc.cluster.local
Address 1: 10.96.140.22 dnsweb.net42.svc.cluster.local
```

Confirm that address is the Service ClusterIP, not a pod IP:

```bash
kubectl get svc dnsweb -n net42 -o jsonpath='{.spec.clusterIP}{"\n"}'
```

**Answer to the reflective question:** a normal ClusterIP Service resolves to a **single address - the
Service's stable ClusterIP** - not the individual pod IPs. Clients connect to that VIP and `kube-proxy`
load-balances onward to a Ready pod. (Only a *headless* Service, `clusterIP: None`, returns per-pod A
records - that is Exercise 4.4.)

## Task 2 - resolv.conf

```bash
kubectl run dnstmp --image=busybox:1.28 -n net42 --restart=Never -i --rm -- \
  cat /etc/resolv.conf
```

Expected:

```
search net42.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

**Answer to the reflective question:** `/etc/resolv.conf` is injected by the kubelet. The `search`
list provides the suffixes that make short names work (so `dnsweb` resolves from inside `net42`), and
`ndots:5` is the trigger explored in Task 3.

## Task 3 - cross-namespace resolution and ndots

Short name from `net42` fails (the search list only appends `net42.*`, never `net42b.*`):

```bash
kubectl run dnstmp --image=busybox:1.28 -n net42 --restart=Never -i --rm -- \
  nslookup otherweb
```

Expected:

```
nslookup: can't resolve 'otherweb'
```

(You need the manifest applied first.)

```bash
kubectl apply -f solution/service-other-ns.yaml
kubectl rollout status deployment/otherweb -n net42b --timeout=60s
```

Now qualify with at least the namespace:

```bash
kubectl run dnstmp --image=busybox:1.28 -n net42 --restart=Never -i --rm -- \
  nslookup otherweb.net42b
kubectl run dnstmp --image=busybox:1.28 -n net42 --restart=Never -i --rm -- \
  nslookup otherweb.net42b.svc.cluster.local
```

Expected (both succeed; address illustrative):

```
Name:      otherweb.net42b.svc.cluster.local
Address 1: 10.96.201.9 otherweb.net42b.svc.cluster.local
```

**Answer to the reflective question:** with `ndots:5`, any name containing **fewer than 5 dots** is
treated as unqualified and tried against every entry in `search` **first**. So `example.com` (1 dot) is
looked up as `example.com.net42.svc.cluster.local`, `example.com.svc.cluster.local`,
`example.com.cluster.local` - all `NXDOMAIN` - and only then as the absolute `example.com.`. That is
several wasted round-trips per external lookup; appending a trailing dot (`example.com.`) or using a
FQDN with >=5 dots skips the search list.

## Cleanup

```bash
kubectl delete ns net42 net42b --ignore-not-found
```
