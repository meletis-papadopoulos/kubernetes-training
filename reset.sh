#!/usr/bin/env bash
# =============================================================================
# reset.sh - reset a training cluster in place, without a fresh sandbox.
#
# Removes lab and exercise artifacts plus ingress-nginx, cert-manager,
# metrics-server, and Gatekeeper, leaving a bare cluster ready for
# ./provision.sh to run again. Exercise namespaces are discovered dynamically
# from exercises/ (no hardcoded list), so the sweep never goes stale.
#
# Usage:
#   ./reset.sh
#   ./reset.sh --force
#   ./reset.sh -h|--help
#
# Output:
#   Streams all output to the terminal and appends a colour-stripped transcript
#   to reset.log beside this script.
# =============================================================================
set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${LOG:-${SCRIPT_DIR}/reset.log}"
TRAINING_NAMESPACE="training"
LAB_NAMESPACES=(quota-lab ns-lab rbac-lab gatekeeper-lab gatekeeper-demo)
LAB_PVS=(lab-pv pv-rwo pv-rox backup-pv)
EXERCISE_DIR="${SCRIPT_DIR}/exercises"
# Never delete these in the exercise sweep (system + provisioned-component + training namespaces).
PROTECTED_NAMESPACES="default kube-system kube-public kube-node-lease ${TRAINING_NAMESPACE} gatekeeper-system cert-manager ingress-nginx local-path-storage kube-flannel"

# ---------------------------------------------------------------------------
# Colours and helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GREY='\033[0;90m'
NC='\033[0m'

log()  { echo -e "${CYAN}[RESET]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
skip() { echo -e "${GREY}[SKIP]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
  cat <<EOF_USAGE
reset.sh - reset the training cluster in place.

Usage:
  $0
  $0 --force
  $0 -h|--help

Options:
  --force    Skip the confirmation prompt.

Output:
  Terminal output is shown live.
  A colour-stripped transcript is appended to: ${LOG}
EOF_USAGE
}

format_duration() {
  local total_seconds="$1"
  printf "%dm%02ds" "$((total_seconds / 60))" "$((total_seconds % 60))"
}

# ---------------------------------------------------------------------------
# Transcript logging
# ---------------------------------------------------------------------------
TMP_DIR="$(mktemp -d)"
FIFO="${TMP_DIR}/reset.fifo"
LOGGER_PID=""

start_transcript_logging() {
  mkdir -p "$(dirname "${LOG}")"
  : >> "${LOG}"

  mkfifo "${FIFO}"
  exec 3>&1
  exec 4>&2

  ( tee /dev/fd/3 < "${FIFO}" | sed -E 's/\x1b\[[0-9;]*m//g' >> "${LOG}" ) &
  LOGGER_PID=$!

  exec >"${FIFO}" 2>&1

  echo "########## $(date '+%F %T')  $0 $*  ##########"
  echo "log file: ${LOG}"
}

stop_transcript_logging() {
  local status=$?
  set +e

  echo "########## exit status: ${status} at $(date '+%F %T') ##########"

  exec 1>&3 2>&4
  exec 3>&- 4>&-
  wait "${LOGGER_PID}" 2>/dev/null || true
  rm -rf "${TMP_DIR}"

  exit "${status}"
}

# ---------------------------------------------------------------------------
# Input handling
# ---------------------------------------------------------------------------
FORCE=false
for arg in "$@"; do
  case "${arg}" in
    --force)
      FORCE=true
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
trap stop_transcript_logging EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
start_transcript_logging "$@"

START_TIME="$(date +%s)"

log "Running pre-flight checks..."
for cmd in kubectl helm; do
  if ! command -v "${cmd}" >/dev/null; then
    err "${cmd} is not installed."
    exit 1
  fi
done

if ! kubectl cluster-info; then
  err "Cannot connect to cluster."
  exit 1
fi
ok "Pre-flight checks passed"

if [[ "${FORCE}" != "true" ]]; then
  echo -e "${RED}This will remove every lab artifact and provisioned component from the cluster.${NC}"
  echo -n "Continue? [y/N] "
  read -r REPLY
  [[ "${REPLY}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

log "Removing Gatekeeper constraints..."
CONSTRAINT_KINDS="$(kubectl get constrainttemplates -o jsonpath='{.items[*].spec.crd.spec.names.kind}' 2>/dev/null || true)"
if [[ -n "${CONSTRAINT_KINDS}" ]]; then
  for kind in ${CONSTRAINT_KINDS}; do
    kubectl get "${kind}" -o name 2>/dev/null | xargs -r kubectl delete --ignore-not-found
  done
  ok "Removed constraint instances (${CONSTRAINT_KINDS})"
else
  skip "No ConstraintTemplates found"
fi

kubectl delete config config -n gatekeeper-system --ignore-not-found 2>/dev/null \
  && ok "Removed Gatekeeper Config singleton" \
  || skip "No Gatekeeper Config singleton"

kubectl get constrainttemplates -o name 2>/dev/null | xargs -r kubectl delete --ignore-not-found \
  && ok "Removed ConstraintTemplates" \
  || skip "No ConstraintTemplates to remove"

log "Wiping ${TRAINING_NAMESPACE} namespace contents..."
kubectl delete \
  deployment,replicaset,statefulset,daemonset,job,cronjob,pod,service,configmap,secret,pvc,ingress,networkpolicy,role,rolebinding,certificate \
  --all -n "${TRAINING_NAMESPACE}" --ignore-not-found --force --grace-period=0 2>/dev/null
ok "${TRAINING_NAMESPACE} namespace wiped"

log "Removing lab namespaces..."
for ns in "${LAB_NAMESPACES[@]}"; do
  kubectl delete namespace "${ns}" --ignore-not-found --timeout=30s \
    && ok "Deleted namespace: ${ns}" \
    || skip "Namespace not found or timed out: ${ns}"
done

log "Removing exercise namespaces (discovered from exercises/)..."
if [[ -d "${EXERCISE_DIR}" ]]; then
  # Drift-proof: derive the list at runtime from every exercise's Setup and
  # manifests - `kubectl create namespace <x>` plus any `namespace: <x>` field.
  EXERCISE_NAMESPACES="$(
    {
      grep -rhoE 'kubectl create namespace [a-z0-9][a-z0-9-]*' "${EXERCISE_DIR}" 2>/dev/null | awk '{print $NF}'
      grep -rhoE '^[[:space:]]*namespace:[[:space:]]*[a-z0-9][a-z0-9-]*' "${EXERCISE_DIR}" 2>/dev/null | awk '{print $NF}'
    } | sort -u
  )"
  removed=0
  for ns in ${EXERCISE_NAMESPACES}; do
    case " ${PROTECTED_NAMESPACES} " in *" ${ns} "*) continue ;; esac
    if kubectl get namespace "${ns}" >/dev/null 2>&1; then
      kubectl delete namespace "${ns}" --ignore-not-found --timeout=30s >/dev/null 2>&1 \
        && { ok "Deleted exercise namespace: ${ns}"; removed=$((removed + 1)); }
    fi
  done
  [[ "${removed}" -eq 0 ]] && skip "No exercise namespaces present" || ok "Removed ${removed} exercise namespace(s)"
else
  skip "No exercises/ directory - skipping exercise namespace sweep"
fi

log "Removing cluster-scoped lab RBAC..."
kubectl delete clusterrolebinding node-viewer-binding viewer-binding --ignore-not-found
kubectl delete clusterrole node-viewer --ignore-not-found
kubectl delete deployment nginx-demo -n default --ignore-not-found
kubectl delete serviceaccount viewer -n default --ignore-not-found
ok "Cluster-scoped lab RBAC removed"

log "Removing lab PersistentVolumes..."
kubectl delete pv "${LAB_PVS[@]}" --ignore-not-found
ok "Lab PersistentVolumes removed"

log "Reverting node taints and labels..."
for n in $(kubectl get nodes -o name 2>/dev/null); do
  node_name="${n#node/}"
  kubectl taint nodes "${node_name}" environment=production:NoSchedule- 2>/dev/null || true
  kubectl taint nodes "${node_name}" workload=gpu:NoSchedule- 2>/dev/null || true
  kubectl label "${n}" disktype- 2>/dev/null || true
done
ok "Node taints and labels reverted"

log "Uninstalling Helm releases..."
helm uninstall gatekeeper -n gatekeeper-system 2>/dev/null \
  && ok "Uninstalled Gatekeeper" \
  || skip "Gatekeeper not installed"
helm uninstall cert-manager -n cert-manager 2>/dev/null \
  && ok "Uninstalled cert-manager" \
  || skip "cert-manager not installed"
helm uninstall metrics-server -n kube-system 2>/dev/null \
  && ok "Uninstalled metrics-server" \
  || skip "metrics-server not installed"
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null \
  && ok "Uninstalled ingress-nginx" \
  || skip "ingress-nginx not installed"

log "Removing leftover CRDs..."
kubectl get crd -o name 2>/dev/null | grep cert-manager | xargs -r kubectl delete --ignore-not-found \
  && ok "Removed cert-manager CRDs" \
  || skip "No cert-manager CRDs left"
kubectl get crd -o name 2>/dev/null | grep gatekeeper | xargs -r kubectl delete --ignore-not-found \
  && ok "Removed Gatekeeper CRDs" \
  || skip "No Gatekeeper CRDs left"

log "Removing component namespaces..."
for ns in gatekeeper-system cert-manager ingress-nginx; do
  kubectl delete namespace "${ns}" --ignore-not-found --timeout=60s \
    && ok "Deleted namespace: ${ns}" \
    || skip "Namespace not found or timed out: ${ns}"
done

log "Removing Helm repos..."
for repo in ingress-nginx jetstack metrics-server gatekeeper; do
  helm repo remove "${repo}" 2>/dev/null || true
done
ok "Helm repos removed"

log "Reverting Vim configuration..."
if [[ -f "${SCRIPT_DIR}/vim-onedark.sh" ]]; then
  bash "${SCRIPT_DIR}/vim-onedark.sh" --restore >/dev/null 2>&1 \
    && ok "Vim configuration reverted" \
    || skip "Vim not configured"
else
  skip "vim-onedark.sh not found"
fi

END_TIME="$(date +%s)"
ELAPSED="$((END_TIME - START_TIME))"

echo ""
echo -e "${GREEN}===========================================================${NC}"
echo -e "${GREEN}   Reset complete${NC}"
echo -e "${YELLOW}   Elapsed time: $(format_duration "${ELAPSED}")${NC}"
echo -e "${GREEN}===========================================================${NC}"
echo ""
echo "Remaining pods:"
kubectl get pods -A --no-headers 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn
echo ""
echo "transcript: ${LOG}"
echo ""
