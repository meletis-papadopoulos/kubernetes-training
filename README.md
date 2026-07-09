# Kubernetes Training Labs

Run 48 hands-on Kubernetes labs - plus concept decks on cluster architecture, container runtime, CNI, CSI, and CoreDNS - on any 2-node kubeadm cluster.
No local setup, no registry restrictions, no corporate dependencies.

## Prerequisites

- A 2-node **Kubernetes** cluster: `controlplane` + `node01` (any kubeadm cluster; a free browser-based sandbox works well)

## Quick Start

```bash
# 1. Get the labs onto the cluster (git clone / copy this repo)

# 2. Provision the cluster with the required components
./provision.sh

# 3. Replay + review every lab   (one lab: ./lab-walkthrough.sh 2.3)
./lab-walkthrough.sh all

# 4. Reset when done: start a fresh sandbox and re-run ./provision.sh
#    Can't grab a fresh sandbox? Reset this one in place instead:
./reset.sh
```

> **Setup** is just `provision.sh` (it prints its elapsed time when done). Labs are shared separately (git clone / copy) - not bundled into a self-extracting script.
>
> **Broke something / want a clean slate?** Start a fresh sandbox and re-run `provision.sh` - disposable sandboxes are the cleanest reset. If you can't grab a new sandbox, `./reset.sh` reverses everything `provision.sh` installed plus any lab leftovers, in place on the same cluster, so you can re-run `provision.sh` without starting over. Per-lab resets don't need either script - every lab's own README ends with its own teardown, replayed automatically by `lab-walkthrough.sh`.

## What Gets Installed

The cluster comes with a kubeadm cluster (v1.35.1), Cilium CNI, and Helm.
The `provision.sh` script adds the missing components - chart versions are
**pinned** with an explicit `--version` (no `latest`); run `helm list -A` to
confirm what's installed:

| Component | Purpose | Chart version |
|---|---|---|
| ingress-nginx | Ingress controller (NodePort 30080/30443) | 4.15.1 |
| cert-manager | TLS certificate automation (+ `selfsigned-issuer` ClusterIssuer) | v1.20.3 |
| metrics-server | `kubectl top` and HPA | 3.13.1 |
| OPA Gatekeeper | Admission policy enforcement | 3.22.2 |

## Labs

Labs are numbered `module.sequence` and run in ascending order; every lab has a matching slide deck.
The course opens with **Module 0 · Foundations** - four concept decks (`0.1`-`0.4`, slides only, no
lab): Cluster Architecture, Container Runtime & CRI, Cluster Networking & CNI, and Storage & CSI.

### 0 · Foundations — concept decks (slides only, no lab)

*Four decks that open the course: `0.1` Cluster Architecture · `0.2` Container Runtime & CRI · `0.3` Cluster Networking & CNI · `0.4` Storage & CSI — control-plane/worker components, the runtime/CRI, the Pod network model/CNI, and the CSI storage layer. Lab `1.2` makes them concrete on the real cluster.*

### 1 · Foundations

| Lab | Topic | What you learn |
|---|---|---|
| 1.1 | kubectl & Imperative vs Declarative | kubectl grammar, imperative vs declarative, dry-run, explain, label selectors |
| 1.2 | Inspect Your Cluster | Read-only tour: control-plane pods, runtime, CNI, CSI drivers, CoreDNS on the real cluster |

### 2 · Core Workloads

| Lab | Topic | What you learn |
|---|---|---|
| 2.1 | Pods | The Pod as the atom; create imperatively & declaratively; lifecycle; why bare Pods aren't enough |
| 2.2 | Multi-Container Pods | Sidecar & init-container patterns; shared network/volume; init ordering |
| 2.3 | Deployments & ReplicaSets | Create, inspect, and scale Deployments; manage ReplicaSets and Pods |
| 2.4 | Rollouts & Rollbacks | Perform rolling updates, monitor rollout, and roll back to a previous version |
| 2.5 | Probes | Configure liveness, readiness, and startup probes for health checking |
| 2.6 | StatefulSets Basics | Stable identity, ordered pods, and per-pod PVCs - the intro before storage |

### 3 · Configuration

| Lab | Topic | What you learn |
|---|---|---|
| 3.1 | ConfigMaps | Create ConfigMaps from literals and files; consume as env vars and volumes |
| 3.2 | Secrets | Create Secrets, decode values, and consume in Pods as env vars and volumes |

### 4 · Networking

| Lab | Topic | What you learn |
|---|---|---|
| 4.1 | Services | Compare ClusterIP, NodePort, and LoadBalancer; selectors and endpoints |
| 4.2 `slides`+lab | CoreDNS & Service Discovery | In-cluster DNS; `<svc>.<ns>.svc.cluster.local`; search domains; resolve Services by name |
| 4.3 | Pod-to-Pod Connectivity | Direct pod-to-pod traffic by IP; Pod IPs are routable and ephemeral |
| 4.4 | Endpoints & Headless Services | How Services track backend pods via Endpoints/EndpointSlices; headless Services |
| 4.5 | Ingress | Expose multiple services through path-based routing with nginx ingress |
| 4.6 | TLS Ingress | Secure Ingress with TLS using cert-manager and self-signed certificates |
| 4.7 | Network Policies | Segment Pod traffic: flat-default → default-deny → allow-from-app, verified with a probe pod |

### 5 · Storage

| Lab | Topic | What you learn |
|---|---|---|
| 5.1 | Volumes | Use emptyDir for inter-container data sharing and hostPath for host access |
| 5.2 | PersistentVolumes & PVCs | Understand PVs and PVCs; static binding; verify data persistence |
| 5.3 | StorageClasses & Dynamic Provisioning | Explore dynamic volume provisioning with StorageClasses |
| 5.4 | PVCs in Deployments & StatefulSets | Compare shared PVC in Deployments vs per-replica PVCs in StatefulSets |
| 5.5 | Access Modes & Reclaim Policies | Understand RWO/ROX/RWX access modes and Retain/Delete reclaim policies |

### 6 · Scheduling, Resources & Scaling

| Lab | Topic | What you learn |
|---|---|---|
| 6.1 | Scheduling | Control pod placement with nodeSelector, nodeName, affinity, taints and tolerations |
| 6.2 | Requests & Limits | Set resource requests/limits; OOMKilled vs CPU throttling; what the scheduler reserves |
| 6.3 | ResourceQuota & LimitRange | Enforce namespace quotas and LimitRange min/max defaults |
| 6.4 | Horizontal Pod Autoscaler | Configure HPA to auto-scale a Deployment based on CPU utilization |
| 6.5 | DaemonSets | Run one pod per node; control-plane toleration; why you can't scale a DaemonSet |
| 6.6 | Jobs & CronJobs | Run one-time batch tasks (Jobs) and scheduled recurring tasks (CronJobs) |

### 7 · Multi-tenancy & Security

| Lab | Topic | What you learn |
|---|---|---|
| 7.1 | Namespaces | Use namespaces for logical isolation with labels and resource constraints |
| 7.2 | RBAC | Configure Roles, RoleBindings, ClusterRoles; test with `kubectl auth can-i` |
| 7.3 | ServiceAccounts | Understand pod identity, token mounting, and Kubernetes API access |
| 7.4 | Kubeconfig & Contexts | Read `clusters`/`users`/`contexts`; pin namespaces; build a second context from an SA token; merge with `KUBECONFIG` |
| 7.5 | Image Policy & OPA Gatekeeper | Enforce admission policies (required labels, allowed repos, enforcement actions, namespace exemption) |
| 7.6 | Certificate Inspection | Inspect certs and keys with OpenSSL; examine API server and TLS secret certificates |

### 8 · Packaging & Extensibility

| Lab | Topic | What you learn |
|---|---|---|
| 8.1 | Kustomize | base/overlay pattern; patches, generators (content-hash-triggered rollout), and the `images` transformer for environment-specific configs |
| 8.2 | Helm | Install, upgrade, roll back, and manage applications with Helm charts |
| 8.3 `slides`+lab | CRDs | Understand Custom Resource Definitions using cert-manager as a real-world example |

### 9 · Troubleshooting Capstone

| Lab | Topic | What you learn |
|---|---|---|
| 9.1 | Pod Failures | Diagnose CrashLoopBackOff, ImagePullBackOff, Pending, config errors, and init failures |
| 9.2 | Image Pull Problems | Diagnose bad registry, missing tags, and missing/broken `imagePullSecrets` |
| 9.3 | ConfigMap & Secret Problems | Missing/renamed keys, mount-vs-env drift, and stale-config-until-restart |
| 9.4 | Service Problems | Diagnose selector mismatches and targetPort/containerPort mismatches |
| 9.5 | DNS Problems | NXDOMAIN, blocked DNS egress, and CoreDNS availability |
| 9.6 | Ingress Problems | Diagnose 503 (bad backend), 404 (path mismatch), and TLS secret failures |
| 9.7 | PVC Problems | Missing StorageClass, PV-too-small, and pod referencing wrong claimName |
| 9.8 | Probe Problems | Liveness too aggressive, readiness silent failure, probe wrong port |
| 9.9 | Resource & HPA Problems | OOMKilled/throttling/Pending and HPA `<unknown>` metrics: wrong `scaleTargetRef`, missing requests |
| 9.10 | Node Operations | Cordon, drain, and uncordon nodes for maintenance |
| 9.11 | Logs, Events & Metrics | Container logs, `kubectl get events`, and `kubectl top` for everyday debugging |

## Running the labs

Two ways, both after `./provision.sh`:

```bash
# 1. By hand - read and follow a lab's own README (the real instructions)
cat labs/2.3/README.md
cd labs/2.3 && kubectl apply -f deployment.yaml   # ...then follow the steps

# 2. Guided replay - echoes each command + its output (great for review/screenshots)
./lab-walkthrough.sh list       # list all labs in delivery order
./lab-walkthrough.sh 2.3        # replay ONE lab
./lab-walkthrough.sh all        # replay every lab in delivery order
```

All labs use the `training` namespace (created by `provision.sh`; recreate with
`kubectl create namespace training`).

## Practice exercises

Beyond the guided labs, `exercises/` holds **48 timed, hands-on practice tasks** (one per lab ID) in
the style of the major study guides: each states a task, you solve it **blind** on the cluster, then
check a worked solution. Where the labs walk you through a topic, the exercises make you *produce* the
answer.

```bash
# after ./provision.sh, on any 2-node cluster:
cat exercises/6.2/exercise.md     # read the task - don't peek in exercises/6.2/solution/
# ...solve it yourself, then compare against:
cat exercises/6.2/solution.md

# author-time replay (runs each exercise's setup+solution+cleanup, logs a transcript for review):
./exercise-verify.sh list         # list all 48
./exercise-verify.sh 6.2          # verify ONE
./exercise-verify.sh all          # verify every exercise
```

See `exercises/README.md` for scope and house style. The deny/forbidden steps (6.2, 6.3, 7.5) and the
Module-9 fault-injection exercises show red output on purpose.

## File Structure

```
kubernetes-training/
├── provision.sh          # Install cluster components (Helm): ingress-nginx, cert-manager, metrics-server, gatekeeper
├── lab-walkthrough.sh    # Replay every lab's commands (for review)
├── exercise-verify.sh    # Replay each exercise's setup+solution (author-time verification)
├── reset.sh              # Reset the same cluster in place (reverses provision.sh) when a fresh sandbox isn't an option
├── README.md             # This file
├── curriculum.md         # Module spine, scope, and delivery plan (instructor)
├── labs/                 # 48 labs (X.Y/)
│   └── 1.1/ … 9.11/      # each holds YAML files + README.md
├── exercises/            # 48 practice exercises (X.Y/): exercise.md + solution.md + solution/ (+ setup.yaml for M9)
├── slides/               # 52 PDF decks (per-lab + 4 concept decks)
└── vim-onedark.sh        # In-terminal vim colorscheme/config setup (invoked automatically by provision.sh)
```

> Slide decks ship as pre-rendered PDFs in `slides/`.

## Cluster Details

| Property | Value |
|---|---|
| Kubernetes | v1.35.1 (kubeadm) |
| Container runtime | containerd 1.7.28 |
| CNI | Cilium |
| Nodes | controlplane + node01 |
| StorageClass | local-path (default) |
| OS | Ubuntu 24.04.4 LTS |
