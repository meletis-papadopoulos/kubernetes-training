# Lab 4.7 - Network Policies

## Objective
Segment Pod traffic with NetworkPolicies. Prove the flat-network default (everything talks), then apply a **default-deny**, then an **allow-from-a-specific-app** rule - verifying reachability with a probe Pod at each step. (This cluster's Cilium CNI enforces NetworkPolicy.)

## Prerequisites
- cluster provisioned with `provision.sh`
- Namespace `training` created: `kubectl create namespace training`

## Steps

### 1. Deploy the target web app and its Service

```bash
kubectl apply -f web.yaml
kubectl rollout status deployment/web -n training --timeout=60s
```

### 2. Deploy two client Pods - one we will allow, one we won't

```bash
kubectl apply -f client-allowed.yaml
kubectl apply -f client-blocked.yaml
kubectl wait --for=condition=Ready pod/client-allowed pod/client-blocked -n training --timeout=60s
```

### 3. Baseline - with NO policy, the flat network lets both reach web

```bash
kubectl exec client-allowed -n training -- sh -c 'wget -T 3 -q -O- http://web-svc >/dev/null && echo "client-allowed -> web: REACHABLE" || echo "client-allowed -> web: BLOCKED"'
kubectl exec client-blocked -n training -- sh -c 'wget -T 3 -q -O- http://web-svc >/dev/null && echo "client-blocked -> web: REACHABLE" || echo "client-blocked -> web: BLOCKED"'
```

Both print **REACHABLE** - no policy selects `web`, so all ingress is allowed.

### 4. Apply a default-deny - selecting web with no rules blocks ALL ingress

```bash
kubectl apply -f netpol-default-deny.yaml
kubectl exec client-allowed -n training -- sh -c 'wget -T 3 -q -O- http://web-svc >/dev/null && echo "client-allowed -> web: REACHABLE" || echo "client-allowed -> web: BLOCKED"'
kubectl exec client-blocked -n training -- sh -c 'wget -T 3 -q -O- http://web-svc >/dev/null && echo "client-blocked -> web: REACHABLE" || echo "client-blocked -> web: BLOCKED"'
```

Both now print **BLOCKED**. Selecting `app=web` for Ingress with no `ingress:` rules denies everything inbound.

### 5. Allow only the approved client - policies are additive

```bash
kubectl apply -f netpol-allow-from-client.yaml
kubectl exec client-allowed -n training -- sh -c 'wget -T 3 -q -O- http://web-svc >/dev/null && echo "client-allowed -> web: REACHABLE" || echo "client-allowed -> web: BLOCKED"'
kubectl exec client-blocked -n training -- sh -c 'wget -T 3 -q -O- http://web-svc >/dev/null && echo "client-blocked -> web: REACHABLE" || echo "client-blocked -> web: BLOCKED"'
```

Now `client-allowed` (label `app=client-allowed`) prints **REACHABLE**, while `client-blocked` (label `app=other`) stays **BLOCKED**. The two policies combine additively - the deny sets the default, the allow punches a single hole.

### 6. Inspect the policies

```bash
kubectl get networkpolicy -n training
kubectl describe networkpolicy web-allow-from-client -n training
```

## Cleanup

```bash
kubectl delete -f netpol-allow-from-client.yaml -f netpol-default-deny.yaml --ignore-not-found
kubectl delete -f client-allowed.yaml -f client-blocked.yaml --force --grace-period=0 --ignore-not-found
kubectl delete -f web.yaml --force --grace-period=0 --ignore-not-found
```

> **Gotchas:** NetworkPolicy only works if the CNI enforces it (Cilium/Calico do; plain Flannel does not). There is no explicit "deny" - you deny by selecting a Pod and not allowing. Egress (including DNS on port 53) is separate - a default-deny **egress** policy will break name resolution unless you allow it.
