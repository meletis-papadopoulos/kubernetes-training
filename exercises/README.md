# Exercises - hands-on practice tasks

These are **timed, hands-on practice tasks** in the style of the major Kubernetes study guides.
Unlike the `labs/` (which walk you through a topic step by step), an exercise states a task, expects
you to solve it **blind** on a live cluster, and only then reveals a worked solution.

## Scope - what these do and do NOT cover

Exercises exist **only for topics this course already teaches** (the 48 labs in `curriculum.md`).
The course is **day-2 operations, vendor-neutral**: understand, deploy, inspect, secure, operate and
troubleshoot workloads on an existing cluster. It deliberately omits advanced cluster-admin topics,
so those are **not** practised here: kubeadm install/upgrade, etcd backup/restore, HA control plane,
cluster version upgrades, cloud/managed-platform specifics, and the Gateway API.

Faithfully practised here: **workloads & scheduling, services & networking, storage,
troubleshooting**, plus **RBAC / ServiceAccounts / kubeconfig**.

A few in-scope topics have **no equivalent task in the source study guides** because they sit outside
those guides' blueprint: `7.5` image policy / OPA Gatekeeper and `7.6` certificate inspection are
operations-focused additions, and StatefulSets / DaemonSets / Kustomize are thin in the guides. Those exercises are
authored in the same house style but are **extrapolated, not guide-derived** - each is flagged as such
in its file and grounded in the official Kubernetes documentation.

## Sources

Task style and difficulty are modelled on widely-used Kubernetes study-guide practice formats -
principally the chapter-end **Sample Exercises + solutions-appendix** model, enriched with
scenario-framed tasks and realistic gotchas. All tasks reference only the official Kubernetes
documentation (linked per exercise), which is the one resource allowed in the real exams.

## Format (house style)

```
exercises/<lab-id>/
  exercise.md      # the task(s) only - dense imperative prose, concrete literals, no answers
  solution.md      # worked solution: manifest-first, imperative for inspection, always a verify step
  solution/*.yaml  # reference manifests that satisfy the tasks (look only after you have tried)
  setup.yaml       # present only for fix-it tasks that start from a given/broken state
```

Conventions:
- **Every value is concrete** - exact object names, pinned image tags, namespaces, ports, sizes.
- **One task = one dense paragraph** chaining create -> configure -> verify, often ending in a
  reflective question ("where do you expect the Pod to run? why?").
- **Solutions always show a verification command and its expected output**, plus a one-line
  interpretation - that is how you self-grade (there is no auto-validator).
- Imperative-first (the exam rewards speed); YAML shown when a field cannot be set imperatively.
- Each `exercise.md` lists the official docs you may reference while solving.
- Lightweight images only (`nginx`, `busybox`, `alpine`, `httpd`) for the 1 CPU / 2 GB nodes.

## How to use

1. Provision a cluster as per the repo root (`./provision.sh`), or use any 2-node sandbox.
2. Open `exercise.md`, set a timer to the stated target, and solve on the cluster **without**
   looking in `solution/`.
3. Self-grade against `solution.md`'s verification commands, then read the solution.
4. Clean up with the `Cleanup` block at the end of each `solution.md`.

## IDs

Exercise IDs match the lab / curriculum IDs (e.g. `6.2` here == lab `6.2` == curriculum topic 6.2),
so you can practise straight after the matching lab.
