#!/usr/bin/env bash
# =============================================================================
# provision.sh - prepare a Kubernetes cluster for lab work.
#
# Installs ingress-nginx, cert-manager, metrics-server, Gatekeeper, configures
# Vim, and creates the training namespace. The existing CNI is left untouched.
#
# Usage:
#   ./provision.sh
#   ./provision.sh -h|--help
#
# Output:
#   Streams all output to the terminal and appends a colour-stripped transcript
#   to provision.log beside this script.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${LOG:-${SCRIPT_DIR}/provision.log}"
VIM_CONFIG_SCRIPT="vim-onedark.sh"
TRAINING_NAMESPACE="training"

INGRESS_HTTP_NODEPORT=30080
INGRESS_HTTPS_NODEPORT=30443

INGRESS_NGINX_CHART_VERSION="4.15.1"
CERT_MANAGER_CHART_VERSION="v1.20.3"
METRICS_SERVER_CHART_VERSION="3.13.1"
GATEKEEPER_CHART_VERSION="3.22.2"

# ---------------------------------------------------------------------------
# Colours and helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[PROVISION]${NC} $*"; }
ok()  { echo -e "${GREEN}[OK]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
  cat <<EOF_USAGE
provision.sh - prepare a Kubernetes cluster for lab work.

Usage:
  $0
  $0 -h|--help

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
FIFO="${TMP_DIR}/provision.fifo"
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
case "${1:-}" in
  "") ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
esac

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

log "Configuring Vim..."
if [[ ! -f "${SCRIPT_DIR}/${VIM_CONFIG_SCRIPT}" ]]; then
  err "Missing ${SCRIPT_DIR}/${VIM_CONFIG_SCRIPT}"
  exit 1
fi
bash "${SCRIPT_DIR}/${VIM_CONFIG_SCRIPT}"
ok "Vim configured"

log "Waiting for all nodes to be Ready..."
NOT_READY=1
for _ in $(seq 60); do
  NOT_READY="$(kubectl get nodes --no-headers 2>/dev/null | grep -cv ' Ready ' || true)"
  [[ "${NOT_READY}" -eq 0 ]] && break
  sleep 5
done

if [[ "${NOT_READY}" -ne 0 ]]; then
  err "Timed out waiting for nodes. Current state:"
  kubectl get nodes
  exit 1
fi
ok "All nodes Ready"
kubectl get nodes -o wide

log "Removing control-plane taint..."
kubectl taint nodes controlplane node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null \
  && ok "Control-plane taint removed" \
  || ok "Control-plane taint already absent"

log "Adding Helm repositories..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts --force-update
helm repo update
ok "Helm repos added"

log "Installing ingress-nginx ${INGRESS_NGINX_CHART_VERSION} (NodePort ${INGRESS_HTTP_NODEPORT}/${INGRESS_HTTPS_NODEPORT})..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --version "${INGRESS_NGINX_CHART_VERSION}" \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http="${INGRESS_HTTP_NODEPORT}" \
  --set controller.service.nodePorts.https="${INGRESS_HTTPS_NODEPORT}" \
  --wait --timeout 5m
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=120s
ok "ingress-nginx installed"

log "Installing cert-manager ${CERT_MANAGER_CHART_VERSION}..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --version "${CERT_MANAGER_CHART_VERSION}" \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait --timeout 5m
kubectl apply -f - <<EOF_MANIFEST
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF_MANIFEST
ok "cert-manager installed"

log "Installing metrics-server ${METRICS_SERVER_CHART_VERSION}..."
helm upgrade --install metrics-server metrics-server/metrics-server \
  --version "${METRICS_SERVER_CHART_VERSION}" \
  --namespace kube-system \
  --set args='{--kubelet-insecure-tls}' \
  --wait --timeout 5m
ok "metrics-server installed"

log "Installing Gatekeeper ${GATEKEEPER_CHART_VERSION}..."
helm upgrade --install gatekeeper gatekeeper/gatekeeper \
  --version "${GATEKEEPER_CHART_VERSION}" \
  --namespace gatekeeper-system \
  --create-namespace \
  --set replicas=1 \
  --set audit.replicas=1 \
  --wait --timeout 5m
ok "Gatekeeper installed"

log "Creating ${TRAINING_NAMESPACE} namespace..."
kubectl create namespace "${TRAINING_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
ok "${TRAINING_NAMESPACE} namespace ready"

NODE_IP="$(kubectl get node controlplane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)"
if [[ -z "${NODE_IP}" ]]; then
  NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
fi

END_TIME="$(date +%s)"
ELAPSED="$((END_TIME - START_TIME))"

log "Verification..."
echo ""
kubectl get pods -A --no-headers | awk '{print $1}' | sort | uniq -c | sort -rn
echo ""
helm list -A
echo ""

echo -e "${GREEN}===========================================================${NC}"
echo -e "${GREEN}   Provisioning complete${NC}"
echo -e "${YELLOW}   Elapsed time: $(format_duration "${ELAPSED}")${NC}"
echo -e "${GREEN}===========================================================${NC}"
echo ""
echo -e "  Node IP:         ${NODE_IP}"
echo -e "  Ingress (HTTP):  http://${NODE_IP}:${INGRESS_HTTP_NODEPORT}"
echo -e "  Ingress (HTTPS): https://${NODE_IP}:${INGRESS_HTTPS_NODEPORT}"
echo -e "  metrics-server:  kubectl top nodes (may take ~60s to populate)"
echo -e "  transcript:      ${LOG}"
echo ""
