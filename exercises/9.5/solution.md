# Exercise 9.5 - Solutions

Reference manifests are in `solution/`. Namespace `ts95` with the `web` Deployment, `web-svc`
Service, `dns-client` Pod, and the `dns-client-deny-egress` NetworkPolicy are assumed applied
(see the exercise Setup).

## Task 1 - diagnose and fix DNS egress

### Diagnose

```bash
kubectl exec dns-client -n ts95 -- nslookup web-svc.ts95.svc.cluster.local
```

Expected:

```
;; connection timed out; no servers could be reached
```

Rule out CoreDNS and the resolver config, then look at what changed:

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl exec dns-client -n ts95 -- cat /etc/resolv.conf
kubectl get networkpolicy -n ts95
kubectl describe networkpolicy dns-client-deny-egress -n ts95
```

Expected (illustrative):

```
# CoreDNS: both replicas Running  -> server side is healthy
# resolv.conf: still nameserver 10.96.0.10 + search ...svc.cluster.local  -> config unchanged
NAME                     POD-SELECTOR     ...
dns-client-deny-egress   app=dns-client   ...

# describe:
PodSelector:  app=dns-client
Policy Types: Egress
  Allowing egress traffic:
    <none> (Selected pod is isolated for egress; no traffic is allowed)
```

**Root cause:** `dns-client-deny-egress` selects `app=dns-client` for `Egress` and defines **no**
egress rules. Any policy that isolates a Pod for a direction and lists no matching rules denies **all**
traffic in that direction - including the DNS queries to CoreDNS on UDP/TCP 53. CoreDNS is healthy and
the resolver config is untouched; the packets simply never leave the Pod.

### Fix

Add an **additive** allow-policy that permits DNS egress only - do not delete the deny policy:

```bash
kubectl apply -f solution/allow-dns-egress.yaml
sleep 5
```

`solution/allow-dns-egress.yaml` also selects `app=dns-client` for `Egress` (policies are additive)
and allows UDP/TCP 53 to Pods labelled `k8s-app=kube-dns` in `kube-system`. All other egress stays
blocked.

### Verify

```bash
kubectl get networkpolicy -n ts95
kubectl exec dns-client -n ts95 -- nslookup web-svc.ts95.svc.cluster.local
```

Expected: both policies still listed, and the lookup resolves:

```
Name:      web-svc.ts95.svc.cluster.local
Address 1: 10.x.x.x web-svc.ts95.svc.cluster.local
```

## Task 2 - reflective answer

The blast radius is the tell. A **single-name NXDOMAIN** affects exactly one query (a typo or
wrong-namespace name) - other lookups still work. **CoreDNS down** breaks lookups for **every Pod in
every namespace**. This failure sits in between: it breaks **every** name but only for `dns-client`
(and any Pod sharing its labels), and it began the instant a policy was applied - the classic
"everything timed out right after we added a default-deny" incident. An egress policy with no rules is
a default-deny for that Pod's outbound traffic; DNS is just traffic, so it dies with everything else
unless you explicitly allow port 53 to kube-dns.

## Cleanup

```bash
kubectl delete ns ts95 --ignore-not-found
```
