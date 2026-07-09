# Exercise 4.2 - CoreDNS & Service Discovery

*Domain: Networking. Target: ~12 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace net42
kubectl create namespace net42b
```

## Tasks

1. In the namespace `net42`, create a Deployment named `dnsweb` (`2` replicas, image `nginx:1.27.1`,
   label `app=dnsweb`, port `80`) and a ClusterIP Service named `dnsweb` whose port `80` is **named**
   `http`. From a throwaway `busybox:1.28` pod in `net42`, resolve the Service's A record at its FQDN
   `dnsweb.net42.svc.cluster.local`. What single address comes back - and is it a pod IP or the
   Service's ClusterIP?

2. From the same `busybox:1.28` pod, print `/etc/resolv.conf` and read off the `search` list and the
   `ndots` option.

3. In the namespace `net42b`, create a Deployment `otherweb` and Service `otherweb` (same shape as
   Task 1). From the `busybox:1.28` pod **in `net42`**, resolve `otherweb` first by its short name
   (expect failure) and then by `otherweb.net42b` and its full FQDN (expect success). Given the
   `ndots:5` you saw in Task 2, what does the resolver do to an *external* name like `example.com`
   before it finally resolves it?

## Acceptance criteria

- `dnsweb.net42.svc.cluster.local` resolves to the Service's ClusterIP (a single address, not the two
  pod IPs).
- `/etc/resolv.conf` shows `search net42.svc.cluster.local svc.cluster.local cluster.local ...` and
  `options ndots:5`.
- `otherweb` (short) fails from `net42`, but `otherweb.net42b` and
  `otherweb.net42b.svc.cluster.local` resolve.

## Docs you may reference

- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
