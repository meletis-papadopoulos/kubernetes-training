# Exercise 4.7 - Solutions

Reference manifests are in `solution/`. Namespace `net47` is assumed to exist (see the exercise Setup).
The probe uses `wget -T 3` so a blocked call fails fast instead of hanging.

## Task 1 - baseline: flat network lets both clients in

```bash
kubectl apply -f solution/api.yaml
kubectl apply -f solution/clients.yaml
kubectl rollout status deployment/api -n net47 --timeout=60s
kubectl wait --for=condition=Ready pod/client-ok pod/client-no -n net47 --timeout=60s
```

```bash
kubectl exec client-ok -n net47 -- sh -c 'wget -T 3 -q -O- http://api-svc >/dev/null && echo "client-ok -> api: REACHABLE" || echo "client-ok -> api: BLOCKED"'
kubectl exec client-no -n net47 -- sh -c 'wget -T 3 -q -O- http://api-svc >/dev/null && echo "client-no -> api: REACHABLE" || echo "client-no -> api: BLOCKED"'
```

Expected:

```
client-ok -> api: REACHABLE
client-no -> api: REACHABLE
```

Both reach `api` - with no policy selecting it, all ingress is allowed.

## Task 2 - default-deny blocks everything

```bash
kubectl apply -f solution/netpol-default-deny.yaml
kubectl exec client-ok -n net47 -- sh -c 'wget -T 3 -q -O- http://api-svc >/dev/null && echo "client-ok -> api: REACHABLE" || echo "client-ok -> api: BLOCKED"'
kubectl exec client-no -n net47 -- sh -c 'wget -T 3 -q -O- http://api-svc >/dev/null && echo "client-no -> api: REACHABLE" || echo "client-no -> api: BLOCKED"'
```

Expected:

```
client-ok -> api: BLOCKED
client-no -> api: BLOCKED
```

**Answer to the reflective question:** NetworkPolicy has no explicit "deny" verb - it works by
*allow-listing*. The instant a policy selects a Pod for a given direction (`policyTypes: [Ingress]`),
that Pod flips from "default allow" to "default deny" for that direction, and **only** traffic matching
an `ingress:` rule is permitted. With the rule list empty, nothing matches, so everything inbound is
dropped.

## Task 3 - additive allow for the trusted client

```bash
kubectl apply -f solution/netpol-allow-from-trusted.yaml
kubectl exec client-ok -n net47 -- sh -c 'wget -T 3 -q -O- http://api-svc >/dev/null && echo "client-ok -> api: REACHABLE" || echo "client-ok -> api: BLOCKED"'
kubectl exec client-no -n net47 -- sh -c 'wget -T 3 -q -O- http://api-svc >/dev/null && echo "client-no -> api: REACHABLE" || echo "client-no -> api: BLOCKED"'
```

Expected:

```
client-ok -> api: REACHABLE
client-no -> api: BLOCKED
```

Inspect the two policies:

```bash
kubectl get networkpolicy -n net47
kubectl describe networkpolicy api-allow-from-trusted -n net47
```

`client-ok` carries `app=trusted`, which the allow rule's `podSelector` matches, so its traffic to
TCP 80 is permitted; `client-no` (`app=untrusted`) matches nothing and stays denied by the
default-deny. Policies are **additive** - the union of what any policy allows - so the deny sets the
baseline and the allow punches one hole.

**Answer to the reflective question:** a policy selecting `app=api` with **only**
`policyTypes: [Egress]` would constrain `api`'s *outbound* traffic and leave its **ingress
untouched**. `policyTypes` is per-direction: listing only `Egress` never engages ingress default-deny,
so inbound stays governed by whatever else selects the Pod (here, still open unless the default-deny is
also present). To lock down inbound you must have a policy that lists `Ingress` in its `policyTypes`.

## Cleanup

```bash
kubectl delete ns net47 --ignore-not-found
```
