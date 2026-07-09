# Exercise 4.7 - Network Policies

*Domain: Networking. Target: ~15 min. Do not open `solution/` until you have tried.*
*NetworkPolicy is only enforced if the CNI supports it (this cluster's Cilium does; plain Flannel would not).*

## Setup

```bash
kubectl create namespace net47
```

## Tasks

1. In the namespace `net47`, create a Deployment `api` (`1` replica, `nginx:1.27.1`, label `app=api`,
   port `80`) with a ClusterIP Service `api-svc`, plus two `busybox:1.36` client Pods:
   `client-ok` (label `app=trusted`) and `client-no` (label `app=untrusted`), each `sleep 3600`.
   Before any policy exists, prove the flat-network baseline: from **both** clients,
   `wget -T 3 -q -O- http://api-svc` and confirm both reach `api`.

2. Apply a **default-deny** ingress policy named `api-default-deny` that selects `app=api` with
   `policyTypes: [Ingress]` and **no** `ingress:` rules. Re-run both probes. Both should now be
   BLOCKED. Why does selecting a Pod with an empty ingress rule set deny everything inbound?

3. Add an additive policy `api-allow-from-trusted` (still selecting `app=api`) whose single ingress
   rule allows `from` a `podSelector` matching `app=trusted` on TCP `80`. Re-run both probes:
   `client-ok` must become REACHABLE while `client-no` stays BLOCKED. Finally, reflect: if a policy
   selecting `app=api` declared **only** `policyTypes: [Egress]`, would that leave `api`'s **ingress**
   open or closed?

## Acceptance criteria

- Baseline (no policy): both `client-ok` and `client-no` reach `api-svc`.
- After `api-default-deny`: both clients are BLOCKED.
- After `api-allow-from-trusted`: `client-ok` is REACHABLE, `client-no` is BLOCKED.

## Docs you may reference

- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
