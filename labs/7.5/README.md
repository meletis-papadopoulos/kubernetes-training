# Lab 7.5 - Image Policy & OPA Gatekeeper

## Objective
Learn how to use OPA Gatekeeper to enforce admission policies in a Kubernetes cluster. The scenarios in this lab mimic real-world Gatekeeper policies: enforcing required labels with regex validation and restricting container image repos to approved registries.

## Prerequisites
- cluster provisioned with `provision.sh`

## Scenarios

| Scenario | Description |
|----------|-------------|
| [Scenario 1](scenario-1-required-labels.md) | Enforce required labels (`owner`, `appName`) with regex validation |
| [Scenario 2](scenario-2-allowed-repos.md) | Restrict container images to an approved registry |
| [Scenario 3](scenario-3-enforcement-actions.md) | Compare enforcement actions: deny vs warn vs dryrun |
| [Scenario 4](scenario-4-namespace-exemption.md) | Exempt a namespace from policies (per-constraint `excludedNamespaces` and cluster-wide `Config`) |

## Setup (run once before any scenario)

Gatekeeper is **already installed** by `provision.sh` (via Helm). You only need to verify it's healthy and create the lab namespace.

### 1. Verify Gatekeeper is running

```bash
kubectl get pods -n gatekeeper-system
kubectl get crd | grep gatekeeper.sh | head -5
```

Expect the controller-manager + audit pods `Running`, and several `*.gatekeeper.sh` CRDs.

### 2. Create the lab namespace

```bash
kubectl apply -f namespace.yaml
```

## Teardown

Each scenario cleans up its own resources in its own Destroy section. Scenario 4 runs last and its Destroy section removes the shared `gatekeeper-lab` and `gatekeeper-demo` namespaces along with the `Config` singleton - there's nothing left to tear down here.

Do **not** uninstall Gatekeeper itself - it's managed by Helm and shared across labs.

## Further reading
- [Gatekeeper documentation](https://open-policy-agent.github.io/gatekeeper/website/docs/) - official docs
- [Admission Controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/) - concept reference
- [Rego Policy Language](https://www.openpolicyagent.org/docs/latest/policy-language/) - OPA reference
