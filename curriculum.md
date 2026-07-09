# Kubernetes Training - Curriculum

**Order philosophy:** move from the cluster model to the smallest practical unit, then build up -
each module uses what the previous one taught. Ordered for progressive learning, day-2 focused.
Key dependency rule: don't teach an object deeply before the object it depends on (probes before
Services, requests/limits before HPA, StatefulSet basics before StatefulSet storage, DNS early,
Kustomize before Helm).
**Scope:** day-2 Kubernetes operations on an existing cluster - understand, deploy, inspect,
secure, operate, troubleshoot. Cluster architecture and the CRI/CNI/CSI extension interfaces are
covered as **concept decks** (slides, no lab). Out of scope: kubeadm install, etcd backup/restore,
HA control plane, cluster upgrades. Fully vendor-neutral - no managed-platform specifics.

Lab folder IDs **match delivery order** and every lab lives directly under `labs/` with no gaps. The
four **Module 0 · Foundations concept decks** (`0.1`-`0.4`: Architecture, CRI, CNI, CSI) are slides
only and have no lab folder. `(slides+lab)` = a topic with both a concept deck and a light hands-on lab (4.2, 8.3).

## Modules (in delivery order)

### M0 · Foundations *(concept decks — slides only, delivered first, no lab folder)*
- `0.1` Cluster Architecture · `0.2` Container Runtime & the CRI · `0.3` Cluster Networking & the CNI · `0.4` Storage & the CSI

### M1 · Foundations
- `1.1` kubectl & Imperative vs Declarative
- `1.2` Inspect Your Cluster - read-only component tour

### M2 · Core Workloads
- `2.1` Pods
- `2.2` Multi-Container Pods (sidecar & init)
- `2.3` Deployments & ReplicaSets
- `2.4` Rollouts & Rollbacks
- `2.5` Probes (liveness / readiness / startup)
- `2.6` StatefulSets Basics (stable identity, ordered pods, per-pod PVCs)

### M3 · Configuration
- `3.1` ConfigMaps
- `3.2` Secrets

### M4 · Networking
- `4.1` Services (ClusterIP / NodePort / LoadBalancer)
- `4.2` CoreDNS & Service Discovery  *(slides+lab)*
- `4.3` Pod-to-Pod Connectivity
- `4.4` Endpoints & Headless Services
- `4.5` Ingress
- `4.6` TLS Ingress (cert-manager)
- `4.7` Network Policies (default-deny, allow-from; Cilium-enforced)

### M5 · Storage
- `5.1` Volumes (emptyDir / hostPath)
- `5.2` PersistentVolumes & PVCs
- `5.3` StorageClasses & dynamic provisioning
- `5.4` PVCs in Deployments & StatefulSets
- `5.5` Access modes & reclaim policies

### M6 · Scheduling, Resources & Scaling
- `6.1` Scheduling (nodeSelector / affinity / taints & tolerations)
- `6.2` Requests & Limits
- `6.3` ResourceQuota & LimitRange
- `6.4` Horizontal Pod Autoscaler
- `6.5` DaemonSets
- `6.6` Jobs & CronJobs

### M7 · Multi-tenancy & Security
- `7.1` Namespaces
- `7.2` RBAC (Roles / ClusterRoles / bindings)
- `7.3` ServiceAccounts
- `7.4` Kubeconfig (contexts, SA-token context, merging)
- `7.5` Image policy & OPA Gatekeeper
- `7.6` Certificate inspection (OpenSSL)

### M8 · Packaging & Extensibility
- `8.1` Kustomize
- `8.2` Helm
- `8.3` CRDs  *(slides+lab)*

### M9 · Troubleshooting (capstone - uses everything above)
- `9.1` Pod failures · `9.2` Image pull · `9.3` ConfigMap & Secret · `9.4` Services · `9.5` DNS · `9.6` Ingress
- `9.7` PVC · `9.8` Probes · `9.9` Resource & HPA · `9.10` Node operations · `9.11` Logs, Events & Metrics

All 48 labs are core - there is no optional/take-home track. Module 9 is the capstone; its labs
inject failures on purpose and are expected to show red output during a walkthrough.

## Slides
- **One PDF deck per topic** (52 decks in `slides/`): 48 map to labs 1:1 by ID; 4 are lab-less
  **Module 0 · Foundations** concept decks (`0.1`-`0.4`: Architecture, CRI, CNI, CSI). Each lab's deck
  shares its lab's ID; the Foundations decks (`0.x`) open the course.
- **Labs are the source of truth; slides are derived from them** (plus official Kubernetes docs).
  Standalone lecture notes have been retired - the lab README carries the hands-on detail and the
  deck carries the concept layer, with no duplicated content between them.
- Slide flow: Why it matters → Concept + diagram → Manifest anatomy (minimal) → Do it
  (imperative + declarative, `--dry-run` bridge) → See it → Gotchas → Toolkit → Recap + lab pointer.
- Decks ship as pre-rendered PDFs in `slides/`. Diagrams are drawn natively (inline SVG/CSS) -
  no lifted images, no branding.

## Exercises
`exercises/` holds 48 timed, hands-on practice tasks (one per lab ID, same numbering) in the style of
the major study guides: the task is stated, the trainee solves it blind, then checks a worked solution
(`exercise.md` + `solution.md` + reference `solution/*.yaml`; `setup.yaml` for the Module-9 fix-it
scenarios). Scope matches the 48 labs exactly - see `exercises/README.md`. Five topics with no
study-guide equivalent (StatefulSets, DaemonSets, Kustomize, image policy/Gatekeeper, certificate
inspection) are authored in-house and flagged as such.

## Delivery
- `provision.sh` - installs cluster components (Helm).
- `lab-walkthrough.sh` - replays every lab's commands (from the lab READMEs) for review.
- `exercise-verify.sh` - replays each exercise's setup+solution on the cluster for author-time verification (`list` | `<id>` | `all`).
- `reset.sh` - resets the same cluster in place when a fresh sandbox isn't available.
- Labs are shared separately (git clone / copy this repo), not bundled.
- Have trainees apply the provided manifests and inspect/modify - not type from scratch.
- Images: lightweight only (nginx, busybox, alpine, httpd) for speed on the 1 CPU / 2 GB nodes.
- Many browser-based sandboxes are time-limited. If yours expires mid-way through a delivery
  block, provision a fresh sandbox and re-run `provision.sh` to continue.

## Pre-flight - validate a fresh sandbox
1. Get the labs onto the cluster (upload + extract the tarball, or `git clone`).
2. `./provision.sh` - wait for the green "Provisioning complete" summary; it prints the Node IP,
   ingress NodePorts, and the transcript path.
3. Smoke-check:
   - `kubectl get nodes` → both **Ready**
   - `kubectl get pods -A` → no CrashLoop/Pending (ignore brief cilium/kube-controller restarts)
   - `helm list -A` → ingress-nginx, cert-manager, metrics-server, gatekeeper present
   - `kubectl top nodes` → returns data (needed for 6.4 / 9.9)
4. Full dry-run (recommended before delivering): `./lab-walkthrough.sh all` - replays every lab's
   commands with each echoed, appending a transcript to `walkthrough.log`. Review that file for
   unexpected red output. *(Module-9 troubleshooting labs fail on purpose - that's expected.)*

## Live-validation watch-list (most cluster-dependent - check these first)
- **NodePort ingress:** 4.5 / 4.6 / 9.6 curl `NODE_IP:30080` / `:30443`.
- **NetworkPolicy enforcement:** 4.7 - the probe must show `BLOCKED` after default-deny (relies on
  Cilium enforcing); 9.5 uses a DNS-egress-blocking policy that must actually block port 53.
- **metrics-driven:** 6.4 HPA + 9.9 (need `kubectl top` populated).
- **cert-manager issuance:** 4.6 / 9.6 (self-signed cert takes a few seconds).
- **CoreDNS scale-down/restore:** 9.5 scales CoreDNS to 0 then back - confirm it returns healthy.
- **Helm:** 8.2 `helm install my-web ./webapp-chart` (local chart - no external repo).
