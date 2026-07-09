# Exercise 9.5 - Fix DNS Blocked by a NetworkPolicy

*Domain: Troubleshooting. Target: ~10 min. Do not open `solution/` until you have tried.*

This is a **fix-it** exercise: `setup.yaml` ships a Service, a client Pod, and a NetworkPolicy that
introduces the fault. Diagnose from the cluster, then apply the minimal fix.

> This cluster's CNI enforces NetworkPolicy (illustrative: on a CNI that does not enforce policy, this
> fault would not reproduce).

## Setup

```bash
kubectl create namespace ts95
kubectl apply -f setup.yaml
kubectl rollout status deployment/web -n ts95 --timeout=60s
kubectl wait --for=condition=Ready pod/dns-client -n ts95 --timeout=60s
```

## Tasks

1. From the `dns-client` Pod in namespace `ts95`, a DNS lookup of the `web-svc` Service now times out:
   ```bash
   kubectl exec dns-client -n ts95 -- nslookup web-svc.ts95.svc.cluster.local
   ```
   Diagnose the cause **without** assuming it is CoreDNS. First rule CoreDNS out
   (`kubectl -n kube-system get pods -l k8s-app=kube-dns` - both replicas `Running`), then confirm the
   Pod's resolver is unchanged (`kubectl exec dns-client -n ts95 -- cat /etc/resolv.conf`), then look
   at what was recently added to the namespace (`kubectl get networkpolicy -n ts95` and
   `kubectl describe networkpolicy dns-client-deny-egress -n ts95`). Fix DNS for `dns-client` so the
   lookup resolves again - **without** deleting the existing deny policy (leave the default-deny in
   place; punch a hole only for DNS).

2. Reflective: the lookup fails for **every** name, not just one, and it started the moment a policy
   was applied. How does that blast radius let you tell this apart from (a) a single `NXDOMAIN` typo
   and (b) CoreDNS being down clusterwide? Why does an egress NetworkPolicy with **no** egress rules
   silently take DNS down?

## Acceptance criteria

- `kubectl exec dns-client -n ts95 -- nslookup web-svc.ts95.svc.cluster.local` resolves successfully.
- The original `dns-client-deny-egress` policy is **still present**; DNS works because an additive
  allow-policy permits UDP/TCP 53 to `k8s-app=kube-dns` in `kube-system`.
- You explain that a policy selecting a Pod for `Egress` with zero rules denies all egress (including
  port 53), and that the "fails for every name, right after a policy change" fingerprint distinguishes
  it from an NXDOMAIN typo (one name) or a dead CoreDNS (every pod, clusterwide).

## Docs you may reference

- [Debugging DNS Resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
