# Bounded pre-model timing evidence for the normal wrapper path.
#
# This owner deliberately observes existing gates instead of deciding whether
# they run.  A normal cycle only records a warning when its local budget is
# exceeded; the explicit isolated probe is the enforcement surface.

UPKEEPER_FAST_PATH_TIMING_ENABLED="${UPKEEPER_FAST_PATH_TIMING_ENABLED:-1}"
UPKEEPER_FAST_PATH_TIMING_BUDGET_MS="${UPKEEPER_FAST_PATH_TIMING_BUDGET_MS:-10000}"
UPKEEPER_FAST_PATH_TIMING_ROWS=()
UPKEEPER_FAST_PATH_TIMING_STARTED_MS=""
UPKEEPER_FAST_PATH_TIMING_PHASE_STARTED_MS=""
UPKEEPER_FAST_PATH_TIMING_CURRENT_PHASE=""

upkeeper_fast_path_timing_enabled() {
  case "${UPKEEPER_FAST_PATH_TIMING_ENABLED:-1}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

upkeeper_fast_path_timing_now_ms() {
  local epoch seconds fraction

  if [[ "${UPKEEPER_FAST_PATH_TIMING_TEST_NOW_MS:-}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$UPKEEPER_FAST_PATH_TIMING_TEST_NOW_MS"
    return 0
  fi
  epoch="${EPOCHREALTIME:-}"
  if [[ "$epoch" =~ ^[0-9]+\.[0-9]+$ ]]; then
    seconds="${epoch%%.*}"
    fraction="${epoch#*.}000"
    printf '%s\n' "$((10#$seconds * 1000 + 10#${fraction:0:3}))"
    return 0
  fi
  date '+%s%3N'
}

upkeeper_fast_path_timing_reset() {
  UPKEEPER_FAST_PATH_TIMING_ROWS=()
  UPKEEPER_FAST_PATH_TIMING_CURRENT_PHASE=""
  UPKEEPER_FAST_PATH_TIMING_STARTED_MS="$(upkeeper_fast_path_timing_now_ms)"
  UPKEEPER_FAST_PATH_TIMING_PHASE_STARTED_MS=""
}

upkeeper_fast_path_timing_start() {
  local phase="$1"

  upkeeper_fast_path_timing_enabled || return 0
  UPKEEPER_FAST_PATH_TIMING_CURRENT_PHASE="$phase"
  UPKEEPER_FAST_PATH_TIMING_PHASE_STARTED_MS="$(upkeeper_fast_path_timing_now_ms)"
}

upkeeper_fast_path_timing_finish() {
  local phase="$1"
  local status="${2:-pass}"
  local finished elapsed

  upkeeper_fast_path_timing_enabled || return 0
  [[ "$UPKEEPER_FAST_PATH_TIMING_CURRENT_PHASE" == "$phase" ]] || return 0
  finished="$(upkeeper_fast_path_timing_now_ms)"
  elapsed=$((finished - UPKEEPER_FAST_PATH_TIMING_PHASE_STARTED_MS))
  ((elapsed >= 0)) || elapsed=0
  UPKEEPER_FAST_PATH_TIMING_ROWS+=("$phase"$'\t'"$elapsed"$'\t'"$status")
  UPKEEPER_FAST_PATH_TIMING_CURRENT_PHASE=""
  UPKEEPER_FAST_PATH_TIMING_PHASE_STARTED_MS=""
}

upkeeper_fast_path_timing_emit_summary() {
  local backend_decision="$1"
  local total elapsed phase status dominant_phase="none" dominant_ms=0
  local row budget outcome="pass"

  upkeeper_fast_path_timing_enabled || return 0
  [[ "${UPKEEPER_FAST_PATH_TIMING_STARTED_MS:-}" =~ ^[0-9]+$ ]] || return 0
  total="$(upkeeper_fast_path_timing_now_ms)"
  total=$((total - UPKEEPER_FAST_PATH_TIMING_STARTED_MS))
  ((total >= 0)) || total=0
  budget="${UPKEEPER_FAST_PATH_TIMING_BUDGET_MS:-10000}"
  [[ "$budget" =~ ^[0-9]+$ ]] || budget=10000

  for row in "${UPKEEPER_FAST_PATH_TIMING_ROWS[@]}"; do
    IFS=$'\t' read -r phase elapsed status <<<"$row"
    if [[ "$elapsed" =~ ^[0-9]+$ && "$elapsed" -gt "$dominant_ms" ]]; then
      dominant_phase="$phase"
      dominant_ms="$elapsed"
    fi
  done
  if [[ "$total" -gt "$budget" ]]; then
    outcome="budget_exceeded"
  fi
  log_line "fast_path_timing.summary total_ms=$total budget_ms=$budget outcome=$outcome backend_decision=$backend_decision phase_count=${#UPKEEPER_FAST_PATH_TIMING_ROWS[@]} dominant_phase=$dominant_phase dominant_ms=$dominant_ms"
  if [[ "$outcome" == "budget_exceeded" ]]; then
    log_line "WARN fast_path_timing.budget_exceeded total_ms=$total budget_ms=$budget action=inspect_local_phase_evidence"
  fi
}
