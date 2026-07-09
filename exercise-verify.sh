#!/usr/bin/env bash
# =============================================================================
# exercise-verify.sh - replay each exercise's Setup + Solution commands with
# command tracing enabled.
#
# Produces command -> output transcripts for review. Commands are extracted from
# bash code blocks in each exercise.md and solution.md. Some steps (denials,
# quota rejections) are expected to exit non-zero.
#
# Usage:
#   ./exercise-verify.sh list
#   ./exercise-verify.sh <exercise-id>
#   ./exercise-verify.sh all
#   ./exercise-verify.sh -h|--help
#
# Output:
#   Streams all output to the terminal and appends a colour-stripped transcript
#   to exercise-verify.log beside this script.
# =============================================================================
set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${LOG:-${SCRIPT_DIR}/exercise-verify.log}"
EX_DIR="${SCRIPT_DIR}/exercises"

# Discover exercise IDs from exercises/*/exercise.md, version-sorted.
discover_ids() {
  local d
  for d in "${EX_DIR}"/*/; do
    [[ -f "${d}exercise.md" ]] && basename "${d}"
  done | sort -V
}
mapfile -t ORDER < <(discover_ids)

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
exercise-verify.sh - replay exercise Setup + Solution commands for review.

Usage:
  $0 list        List all discovered exercises in order.
  $0 <ex-id>     Verify one exercise, for example: $0 6.2
  $0 all         Verify every exercise in order.
  $0 -h|--help   Show this help.

Output:
  Terminal output is shown live.
  A colour-stripped transcript is appended to: ${LOG}

Note:
  Some steps are expected to exit non-zero (denied/forbidden) - that is the
  point of those tasks. Compare output against each "Expected" block by eye.
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
FIFO="${TMP_DIR}/verify.fifo"
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
# Exercise helpers
# ---------------------------------------------------------------------------
ex_path() {
  [[ -d "${EX_DIR}/$1" ]] && echo "${EX_DIR}/$1" || return 1
}

topic() {
  head -1 "$1/exercise.md" 2>/dev/null | sed -E 's/^#+[[:space:]]*//; s/^Exercise [0-9.]+[[:space:]]*[--][[:space:]]*//'
}

list_exercises() {
  echo "Exercises in order:"
  local id d
  for id in "${ORDER[@]}"; do
    d="$(ex_path "${id}")" || { printf "  %-5s ${RED}(MISSING)${NC}\n" "${id}"; continue; }
    printf "  %-5s %s\n" "${id}" "$(topic "${d}")"
  done
}

run_exercise() {
  local id="$1" d tmp md status
  d="$(ex_path "${id}")" || { printf "${RED}No such exercise: %s${NC}\n" "${id}"; return 1; }

  printf "\n${CYAN}═══════════════════════════════════════════════════════════${NC}\n"
  printf "${CYAN}  EXERCISE %s - %s${NC}\n" "${id}" "$(topic "${d}")"
  printf "${GREY}  dir: %s${NC}\n" "${d#${SCRIPT_DIR}/}"
  printf "${CYAN}═══════════════════════════════════════════════════════════${NC}\n"

  tmp="$(mktemp)"
  for md in "${d}/exercise.md" "${d}/solution.md"; do
    [[ -f "${md}" ]] && awk '/^```bash$/{f=1;next} /^```$/{f=0} f' "${md}" >> "${tmp}"
  done

  if [[ ! -s "${tmp}" ]]; then
    printf "${GREY}  (no runnable commands to replay)${NC}\n"
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
    printf "${GREEN}═══ end exercise %s ═══${NC}\n" "${id}"
  else
    printf "${YELLOW}═══ exercise %s ended non-zero (status %s) - expected for deny/forbidden steps; verify by eye ═══${NC}\n" "${id}" "${status}"
  fi

  return 0   # never fail the overall run on an expected non-zero step
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
trap stop_transcript_logging EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
start_transcript_logging "$@"

START_TIME="$(date +%s)"

case "${1:-}" in
  ""|-h|--help|help)
    usage
    echo ""
    list_exercises
    ;;
  list)
    list_exercises
    ;;
  all)
    for id in "${ORDER[@]}"; do
      run_exercise "${id}"
    done
    ;;
  *)
    run_exercise "$1"
    ;;
esac

END_TIME="$(date +%s)"
ELAPSED="$((END_TIME - START_TIME))"

echo ""
echo -e "${GREEN}===========================================================${NC}"
echo -e "${GREEN}   Exercise verification replay complete${NC}"
echo -e "${YELLOW}   Elapsed time: $(format_duration "${ELAPSED}")${NC}"
echo -e "${GREY}   Compare each step's output against the solution's Expected blocks.${NC}"
echo -e "${GREEN}===========================================================${NC}"
echo ""
echo -e "${GREY}transcript appended to: ${LOG}${NC}"

exit 0
