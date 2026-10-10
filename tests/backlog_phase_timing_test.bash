#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-backlog-phase-timing.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'backlog_phase_timing_test: %s\n' "$*" >&2
  exit 1
}

BACKLOG_STATE_ROOT="$TEST_ROOT/state"
UPKEEPER_OBLIGATION_DIR="$TEST_ROOT/obligations"
BACKLOG_SOURCE_ONLY=1
source "$PROJECT_ROOT/orchestration/backlog.sh" >/dev/null 2>&1

LOG_LINES=()
log() { LOG_LINES+=("$*"); }

BACKLOG_PHASE_TIMING_ENABLED=1
BACKLOG_TEST_NOW_EPOCH=100
backlog_phase_timing_reset
backlog_phase_timing_set_class docs-only
[[ "$BACKLOG_PHASE_TIMING_BUDGET_SECONDS" == "900" ]] || fail "docs-only budget was not selected"

backlog_phase_timing_start model
BACKLOG_TEST_NOW_EPOCH=112
backlog_phase_timing_finish model pass
backlog_phase_timing_start ci_pending
BACKLOG_TEST_NOW_EPOCH=152
backlog_phase_timing_finish ci_pending pass
summary="$(backlog_phase_timing_summary)"
[[ "$summary" == *"total_seconds=52"* ]] || fail "summary omitted total elapsed time: $summary"
[[ "$summary" == *"local_seconds=12"* ]] || fail "summary omitted local elapsed time: $summary"
[[ "$summary" == *"external_seconds=40"* ]] || fail "summary omitted external elapsed time: $summary"
[[ "$summary" == *"dominant_phase=ci_pending"* ]] || fail "summary omitted dominant phase: $summary"

BACKLOG_PHASE_BUDGET_TRIVIAL_SECONDS=10
backlog_phase_timing_reset
backlog_phase_timing_set_class trivial
BACKLOG_TEST_NOW_EPOCH=200
backlog_phase_timing_start local_validation
BACKLOG_TEST_NOW_EPOCH=211
backlog_phase_timing_finish local_validation pass
if backlog_phase_timing_emit_summary; then
  fail "local budget breach did not report a non-success outcome"
else
  status="$?"
fi
[[ "$status" == "2" ]] || fail "local budget breach returned $status instead of 2"
[[ "${LOG_LINES[*]}" == *"budget breached"* ]] || fail "local budget breach was not logged"
[[ -f "$BACKLOG_PHASE_TIMING_EVIDENCE_PATH" ]] || fail "local budget breach did not retain timing evidence"
[[ "$(find "$UPKEEPER_OBLIGATION_DIR/open" -type f -name 'phase-timing-*.json' | wc -l)" == "1" ]] ||
  fail "local budget breach did not create one durable obligation"

backlog_phase_timing_reset
backlog_phase_timing_set_class trivial
BACKLOG_TEST_NOW_EPOCH=300
backlog_phase_timing_start ci_pending
BACKLOG_TEST_NOW_EPOCH=360
backlog_phase_timing_finish ci_pending pass
if ! backlog_phase_timing_emit_summary; then
  fail "external CI wait was treated as an avoidable local budget breach"
fi

BACKLOG_TEST_NOW_EPOCH=""
printf 'backlog_phase_timing_test: ok\n'
