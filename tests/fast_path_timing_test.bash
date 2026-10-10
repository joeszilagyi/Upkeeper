#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'fast_path_timing_test: FAIL: %s\n' "$*" >&2
  exit 1
}

LOG_LINES=()
log_line() {
  LOG_LINES+=("$*")
}

# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/upkeeper/fast_path_timing.bash"

UPKEEPER_FAST_PATH_TIMING_ENABLED=1
UPKEEPER_FAST_PATH_TIMING_BUDGET_MS=10
UPKEEPER_FAST_PATH_TIMING_TEST_NOW_MS=100
upkeeper_fast_path_timing_reset
upkeeper_fast_path_timing_start startup_anomaly_scan
UPKEEPER_FAST_PATH_TIMING_TEST_NOW_MS=104
upkeeper_fast_path_timing_finish startup_anomaly_scan pass
upkeeper_fast_path_timing_start lattice_startup
UPKEEPER_FAST_PATH_TIMING_TEST_NOW_MS=111
upkeeper_fast_path_timing_finish lattice_startup pass
UPKEEPER_FAST_PATH_TIMING_TEST_NOW_MS=112
upkeeper_fast_path_timing_emit_summary dry_run

[[ "${LOG_LINES[0]}" == *"total_ms=12 budget_ms=10 outcome=budget_exceeded backend_decision=dry_run phase_count=2 dominant_phase=lattice_startup dominant_ms=7"* ]] ||
  fail "budget summary did not preserve fake-clock phase evidence: ${LOG_LINES[0]:-missing}"
[[ "${LOG_LINES[1]}" == *"fast_path_timing.budget_exceeded total_ms=12 budget_ms=10"* ]] ||
  fail "budget exceedance did not remain visible as a warning"

LOG_LINES=()
UPKEEPER_FAST_PATH_TIMING_TEST_NOW_MS=200
upkeeper_fast_path_timing_reset
upkeeper_fast_path_timing_start prompt_preparation
UPKEEPER_FAST_PATH_TIMING_TEST_NOW_MS=205
upkeeper_fast_path_timing_finish prompt_preparation pass
UPKEEPER_FAST_PATH_TIMING_TEST_NOW_MS=208
upkeeper_fast_path_timing_emit_summary backend_ready
[[ "${LOG_LINES[0]}" == *"total_ms=8 budget_ms=10 outcome=pass backend_decision=backend_ready"* ]] ||
  fail "within-budget summary did not preserve the backend decision"
[[ "${#LOG_LINES[@]}" -eq 1 ]] || fail "within-budget summary unexpectedly emitted a warning"

printf 'fast_path_timing_test: ok\n'
