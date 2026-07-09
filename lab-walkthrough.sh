#!/usr/bin/env bash
# =============================================================================
# lab-walkthrough.sh - replay lab README commands with command tracing enabled.
#
# Produces command -> output transcripts for review. Commands are extracted from
# bash code blocks in each lab README and scenario file.
#
# Usage:
#   ./lab-walkthrough.sh list
#   ./lab-walkthrough.sh <lab-id>
#   ./lab-walkthrough.sh all
#   ./lab-walkthrough.sh -h|--help
#
# Output:
#   Streams all output to the terminal and appends a colour-stripped transcript
#   to walkthrough.log beside this script.
# =============================================================================
set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${LOG:-${SCRIPT_DIR}/walkthrough.log}"
LAB_DIR="${SCRIPT_DIR}/labs"
ORDER=(1.1 1.2 2.1 2.2 2.3 2.4 2.5 2.6 3.1 3.2 4.1 4.2 4.3 4.4 4.5 4.6 4.7 \
       5.1 5.2 5.3 5.4 5.5 6.1 6.2 6.3 6.4 6.5 6.6 7.1 7.2 7.3 7.4 7.5 7.6 \
       8.1 8.2 8.3 9.1 9.2 9.3 9.4 9.5 9.6 9.7 9.8 9.9 9.10 9.11)

# ---------------------------------------------------------------------------
# Colours and helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GREY='\033[0;90m'
NC='\033[0m'

usage() {
  cat <<EOF_USAGE
lab-walkthrough.sh - replay lab README commands with command tracing enabled.

Usage:
  $0 list        List all labs in delivery order.
  $0 <lab-id>    Replay one lab, for example: $0 4.5
  $0 all         Replay every lab in delivery order.
  $0 -h|--help   Show this help.

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
FIFO="${TMP_DIR}/walkthrough.fifo"
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
# Lab helpers
# ---------------------------------------------------------------------------
lab_path() {
  [[ -d "${LAB_DIR}/$1" ]] && echo "${LAB_DIR}/$1" || return 1
}

topic() {
  head -1 "$1/README.md" 2>/dev/null | sed -E 's/^#+[[:space:]]*//; s/^Lab [0-9.]+[[:space:]]*[--][[:space:]]*//'
}

list_labs() {
  echo "Labs in delivery order:"
  local id d
  for id in "${ORDER[@]}"; do
    d="$(lab_path "${id}")" || { printf "  %-5s ${RED}(MISSING)${NC}\n" "${id}"; continue; }
    printf "  %-5s %s\n" "${id}" "$(topic "${d}")"
  done
}

run_lab() {
  local id="$1" d tmp md status

  d="$(lab_path "${id}")" || { printf "${RED}No such lab: %s${NC}\n" "${id}"; return 1; }

  printf "\n${CYAN}═══════════════════════════════════════════════════════════${NC}\n"
  printf "${CYAN}  LAB %s - %s${NC}\n" "${id}" "$(topic "${d}")"
  printf "${GREY}  dir: %s${NC}\n" "${d#${SCRIPT_DIR}/}"
  printf "${CYAN}═══════════════════════════════════════════════════════════${NC}\n"

  tmp="$(mktemp)"
  for md in "${d}/README.md" "${d}"/scenario-*.md; do
    [[ -f "${md}" ]] && awk '/^```bash$/{f=1;next} /^```$/{f=0} f' "${md}" >> "${tmp}"
  done

  if [[ ! -s "${tmp}" ]]; then
    printf "${GREY}  (README-only lab - no runnable commands to replay)${NC}\n"
    rm -f "${tmp}"
    return 0
  fi

  (
    cd "${d}" || exit 1
    set +e
    set +u
    set -x
    source "${tmp}"
  )
  status=$?
  rm -f "${tmp}"

  if [[ "${status}" -eq 0 ]]; then
    printf "${GREEN}═══ end lab %s ═══${NC}\n" "${id}"
  else
    printf "${RED}═══ lab %s exited with status %s ═══${NC}\n" "${id}" "${status}"
  fi

  return "${status}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
trap stop_transcript_logging EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
start_transcript_logging "$@"

START_TIME="$(date +%s)"
OVERALL_STATUS=0

case "${1:-}" in
  ""|-h|--help|help)
    usage
    echo ""
    list_labs
    ;;
  list)
    list_labs
    ;;
  all)
    for id in "${ORDER[@]}"; do
      run_lab "${id}" || OVERALL_STATUS=$?
    done
    ;;
  *)
    run_lab "$1" || OVERALL_STATUS=$?
    ;;
esac

END_TIME="$(date +%s)"
ELAPSED="$((END_TIME - START_TIME))"

echo ""
echo -e "${GREEN}===========================================================${NC}"
if [[ "${OVERALL_STATUS}" -eq 0 ]]; then
  echo -e "${GREEN}   Lab walkthrough complete${NC}"
else
  echo -e "${RED}   Lab walkthrough completed with errors${NC}"
fi
echo -e "${YELLOW}   Elapsed time: $(format_duration "${ELAPSED}")${NC}"
echo -e "${GREEN}===========================================================${NC}"
echo ""
echo -e "${GREY}transcript appended to: ${LOG}${NC}"

exit "${OVERALL_STATUS}"
