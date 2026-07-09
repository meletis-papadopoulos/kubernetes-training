# Lab 9.5 - DNS Problems

## Objective
Diagnose four distinct DNS failure modes in a Kubernetes cluster, each with a different fingerprint: a **name that doesn't exist** (NXDOMAIN, one name only), a **NetworkPolicy blocking egress to CoreDNS** (everything times out for one pod, right after a default-deny was added - this cluster's Cilium CNI enforces NetworkPolicy), **CoreDNS itself unavailable** (SERVFAIL/timeout clusterwide, for every pod), and a **dnsPolicy/ndots pitfall** (one pod quietly using the wrong resolver). Learn to tell them apart fast using `kubectl -n kube-system get pods -l k8s-app=kube-dns`, `/etc/resolv.conf`, and `kubectl describe`.

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### Problem 1: Wrong Service name / NXDOMAIN

### 1. Deploy the backend and its Service

```bash
kubectl apply -f deployment.yaml
kubectl rollout status deployment/dns-target -n training --timeout=60s
```

### 2. Deploy the test client

```bash
kubectl apply -f client.yaml
kubectl wait --for=condition=Ready pod/dns-client -n training --timeout=60s
```

### 3. Break: query a name that doesn't exist

A typo in the Service name:

```bash
kubectl exec dns-client -n training -- nslookup dns-target.training.svc.cluster.local
```

Output:

```
Server:    10.96.0.10
Address:   10.96.0.10:53

** server can't find dns-target.training.svc.cluster.local: NXDOMAIN
```

The Service is actually named `dns-target-svc`, not `dns-target`. The same failure shows up with the right name in the wrong namespace:

```bash
kubectl exec dns-client -n training -- nslookup dns-target-svc.default.svc.cluster.local
```

Also `NXDOMAIN` - the Service lives in `training`, not `default`.

### 4. Diagnose

First rule out CoreDNS itself - if it's healthy, the problem is the name being queried, not the resolver:

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

Both replicas `Running`. CoreDNS is fine. Now compare what was queried against what actually exists:

```bash
kubectl get svc -n training
```

Output shows `dns-target-svc` (not `dns-target`), in namespace `training` (not `default`). `nslookup` against a name with no matching Service/Endpoint object always returns `NXDOMAIN` - CoreDNS answered correctly that the name genuinely does not exist.

### 5. Fix: use the correct FQDN

Every Service is addressable at `<service-name>.<namespace>.svc.cluster.local`:

```bash
kubectl exec dns-client -n training -- nslookup dns-target-svc.training.svc.cluster.local
```

Resolves cleanly. Since `dns-client` and `dns-target-svc` are in the **same** namespace, the short name also works (the search domains in `/etc/resolv.conf` fill in the rest):

```bash
kubectl exec dns-client -n training -- nslookup dns-target-svc
kubectl exec dns-client -n training -- getent hosts dns-target-svc
```

Both succeed. Cross-namespace lookups always need at least `<service>.<namespace>` - the bare short name only works inside the Service's own namespace.

---

### Problem 2: NetworkPolicy blocking DNS egress

The classic "everything timed out right after we added a default-deny" incident. This cluster's Cilium CNI enforces NetworkPolicy, so this is fully reproducible.

### 6. Confirm the baseline works before breaking anything

```bash
kubectl exec dns-client -n training -- nslookup dns-target-svc.training.svc.cluster.local
```

Resolves fine - this is our known-good baseline.

### 7. Break: apply a default-deny egress policy to the client

```bash
kubectl apply -f netpol-deny-egress.yaml
sleep 5
```

`netpol-deny-egress.yaml` selects `app=dns-client` for `Egress` with **no** egress rules - Cilium now drops every outbound packet from this pod, including DNS queries to CoreDNS on port 53.

### 8. Observe

```bash
kubectl exec dns-client -n training -- nslookup dns-target-svc.training.svc.cluster.local
```

Output:

```
;; connection timed out; no servers could be reached
```

Note this is now failing for a name that worked a moment ago - and it will fail for **every** name, not just one. That's the tell that distinguishes this from Problem 1.

### 9. Diagnose

Rule out CoreDNS first - same command as Problem 1:

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

Both replicas still `Running`. CoreDNS is healthy, so the failure is not on the server side - it must be on the path between the pod and CoreDNS. Check the pod's resolver config:

```bash
kubectl exec dns-client -n training -- cat /etc/resolv.conf
```

Unchanged - still points at the CoreDNS ClusterIP. Nothing wrong with the config; the packets just aren't arriving. Now check what changed recently:

```bash
kubectl get networkpolicy -n training
kubectl describe networkpolicy dns-client-deny-egress -n training
```

`Policy Types: Egress`, zero egress rules. Any NetworkPolicy that selects a pod for a `policyTypes` direction and defines no matching rules denies **all** traffic in that direction - including DNS. This is the same gotcha called out in Lab 4.7: an egress default-deny silently takes DNS down with it unless you explicitly punch a hole for it.

### 10. Fix: allow egress to kube-dns specifically

```bash
kubectl apply -f netpol-allow-dns-egress.yaml
```

`netpol-allow-dns-egress.yaml` also selects `app=dns-client` for `Egress` - NetworkPolicies selecting the same pod are **additive** - and adds an explicit rule permitting UDP/TCP port 53 to pods labeled `k8s-app=kube-dns` in the `kube-system` namespace. All other egress from `dns-client` stays blocked; only DNS is punched through.

### 11. Confirm

```bash
kubectl exec dns-client -n training -- nslookup dns-target-svc.training.svc.cluster.local
```

Resolves again.

---

### Problem 3: CoreDNS unavailable

The most severe failure mode: DNS breaks **clusterwide**, for every pod, not just one. This step is destructive to the cluster's DNS, so we capture the original replica count first and restore it before moving on.

### 12. Capture the current CoreDNS replica count

```bash
ORIGINAL_REPLICAS=$(kubectl -n kube-system get deployment coredns -o jsonpath='{.spec.replicas}')
echo "CoreDNS is currently running with $ORIGINAL_REPLICAS replicas"
```

### 13. Break: scale CoreDNS to zero

```bash
kubectl -n kube-system scale deployment coredns --replicas=0
sleep 15
```

### 14. Observe

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

Output: `No resources found in kube-system namespace.` Every CoreDNS pod is gone. Now try a lookup from a pod that isn't even affected by the Problem 2 NetworkPolicy:

```bash
kubectl run dns-scratch --image=busybox:1.36 -n training --rm -it --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local
```

Output:

```
;; connection timed out; no servers could be reached
```

This time it fails for **every pod in every namespace** - not just `dns-client`. That clusterwide blast radius is what separates this from Problem 2.

### 15. Diagnose

```bash
kubectl -n kube-system get deployment coredns
kubectl -n kube-system get endpoints kube-dns
```

`coredns` shows `0/0` ready. `kube-dns` Endpoints is empty - the Service exists and its ClusterIP is still what every pod's `/etc/resolv.conf` points at, but there is nothing behind it to answer. Queries simply go nowhere and time out.

If CoreDNS pods exist but are crashing instead of being scaled to 0, the same diagnostic path applies - check logs:

```bash
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=30
```

### 16. Fix: restore CoreDNS to its original replica count

```bash
kubectl -n kube-system scale deployment coredns --replicas="$ORIGINAL_REPLICAS"
kubectl -n kube-system rollout status deployment/coredns --timeout=60s
```

### 17. Confirm

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system get endpoints kube-dns
kubectl exec dns-client -n training -- nslookup dns-target-svc.training.svc.cluster.local
```

CoreDNS pods are `Running` again, `kube-dns` Endpoints is populated, and lookups succeed. **Do not skip this step** - leaving CoreDNS at 0 replicas breaks DNS for the entire cluster, not just this lab.

---

### Problem 4 (optional): dnsPolicy pitfall - one pod using the wrong resolver

`dnsPolicy: Default` is a trap for the name - it does **not** mean "the Kubernetes default." It means "ignore CoreDNS and inherit the node's own `/etc/resolv.conf`." The actual Kubernetes default (used when `dnsPolicy` is omitted) is `ClusterFirst`.

### 18. Break: deploy a pod with dnsPolicy: Default

```bash
kubectl apply -f pod-wrong-dnspolicy.yaml
kubectl wait --for=condition=Ready pod/dns-wrong-policy -n training --timeout=30s
```

### 19. Observe

```bash
kubectl exec dns-wrong-policy -n training -- nslookup dns-target-svc.training.svc.cluster.local
```

Output: `NXDOMAIN` or `SERVFAIL`, depending on the node's own resolver - the node's DNS server has never heard of `cluster.local`.

### 20. Diagnose

Compare the pod's resolver config against a normal pod's:

```bash
kubectl exec dns-wrong-policy -n training -- cat /etc/resolv.conf
kubectl exec dns-client -n training -- cat /etc/resolv.conf
```

`dns-wrong-policy` shows the **node's** nameserver and no `cluster.local` search domains. `dns-client` shows the CoreDNS ClusterIP and `search training.svc.cluster.local svc.cluster.local cluster.local ...`. Confirm the field directly:

```bash
kubectl get pod dns-wrong-policy -n training -o jsonpath='{.spec.dnsPolicy}{"\n"}'
```

Prints `Default` - the misleadingly-named setting.

### 21. Fix: remove dnsPolicy so ClusterFirst (the real default) applies

```bash
kubectl delete pod dns-wrong-policy -n training --force --grace-period=0
kubectl apply -f pod-fixed-dnspolicy.yaml
kubectl wait --for=condition=Ready pod/dns-wrong-policy -n training --timeout=30s
```

### 22. Confirm

```bash
kubectl exec dns-wrong-policy -n training -- nslookup dns-target-svc.training.svc.cluster.local
```

Resolves correctly.

### 23. Bonus: why short names need ndots:5

```bash
kubectl exec dns-client -n training -- cat /etc/resolv.conf
```

Note `options ndots:5`. Any query with **fewer than 5 dots** is tried against each entry in `search` first, in order, before being tried as an absolute name:

```
dns-target-svc                              -> dns-target-svc.training.svc.cluster.local  (found, 1st try)
dns-target-svc.training.svc.cluster.local.  -> tried as-is, absolute                       (found, 1st try - already 5+ dots)
some-external-api.example.com               -> tried against all 4 search suffixes first, THEN absolute (5 lookups)
```

This is why cluster-internal short names resolve in one query, but any application that talks mostly to **external** hosts pays for 4 wasted NXDOMAIN round-trips per lookup unless it either uses a trailing dot (`example.com.`) to force an absolute query, or sets a lower `ndots` via the pod's `dnsConfig.options`. No break/fix here - just inspect the config and understand the cost.

## Troubleshooting Cheat Sheet

| Symptom | Scope | Likely Cause | Diagnostic |
|---|---|---|---|
| `NXDOMAIN` for one specific name | Single query | Typo, or Service is in a different namespace | `kubectl get svc -A`, compare to the FQDN used |
| Sudden timeout on lookups that worked before, right after a NetworkPolicy was added | One pod (or pods sharing its labels) | Egress NetworkPolicy blocking UDP/TCP 53 to kube-dns | `kubectl get networkpolicy -n <ns>`, `kubectl -n kube-system get pods -l k8s-app=kube-dns` (Running rules out CoreDNS) |
| Timeout/SERVFAIL on every lookup, from every pod, every namespace | Clusterwide | CoreDNS deployment scaled down or crashing | `kubectl -n kube-system get pods -l k8s-app=kube-dns`, `kubectl -n kube-system get deployment coredns`, `kubectl -n kube-system get endpoints kube-dns` |
| One pod can't resolve any cluster name; its `/etc/resolv.conf` looks nothing like its neighbours' | Single pod | `dnsPolicy: Default` (inherits node resolver instead of CoreDNS) | `kubectl get pod -o jsonpath='{.spec.dnsPolicy}'`, compare `/etc/resolv.conf` across pods |
| External lookups feel slow / generate extra NXDOMAIN churn | Application-level | `ndots:5` expands short-looking external names against the search list first | `cat /etc/resolv.conf` (`options ndots:5`), consider `dnsConfig` or a trailing dot |

## Verification

```bash
# CoreDNS is back to its original replica count and healthy
kubectl -n kube-system get deployment coredns -o jsonpath='{.spec.replicas}{"\n"}'
kubectl -n kube-system get pods -l k8s-app=kube-dns

# In-namespace and cross-namespace lookups both succeed
kubectl exec dns-client -n training -- nslookup dns-target-svc
kubectl exec dns-client -n training -- nslookup dns-target-svc.training.svc.cluster.local

# The dnsPolicy-fixed pod resolves cluster names
kubectl exec dns-wrong-policy -n training -- nslookup dns-target-svc.training.svc.cluster.local
```

## Cleanup

```bash
# Make absolutely sure CoreDNS is restored, even if Problem 3 was skipped or interrupted
kubectl -n kube-system scale deployment coredns --replicas=2
kubectl -n kube-system rollout status deployment/coredns --timeout=60s

kubectl delete -f netpol-allow-dns-egress.yaml --ignore-not-found
kubectl delete -f netpol-deny-egress.yaml --ignore-not-found

kubectl delete pod dns-client dns-wrong-policy -n training --force --grace-period=0 --ignore-not-found
kubectl delete -f deployment.yaml --force --grace-period=0 --ignore-not-found
```

> **Note:** the cleanup above scales CoreDNS back to `2` (the typical kubeadm default). If your cluster's CoreDNS normally runs a different replica count, use the `$ORIGINAL_REPLICAS` value captured in step 12 instead.

## Further reading
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) - concept reference (search domains, ndots, dnsPolicy)
- [Debugging DNS Resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/) - task walkthrough
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) - concept reference (egress rules)
