#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-backlog-wrapper-failure.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

BACKLOG_SOURCE_ONLY=1
BACKLOG_OBLIGATION_DIR="$TEST_TMP_ROOT/obligations"
BACKLOG_STATE_ROOT="$TEST_TMP_ROOT/state"
export BACKLOG_SOURCE_ONLY BACKLOG_OBLIGATION_DIR BACKLOG_STATE_ROOT
source "$ROOT_DIR/orchestration/backlog.sh"

test_wrapper_failure_opens_deduped_obligation() {
  local output_file output rc record_count record_file selected_json

  output_file="$TEST_TMP_ROOT/upkeeper-child.log"
  cat >"$output_file" <<EOF
2026-05-24T21:15:35 [ERROR] cycle=abc run_hash=def run.finish codex_exit=1
$ROOT_DIR/lib/upkeeper/report_analysis.bash: line 3: \$2: unbound variable
./Upkeeper: line 7236: marker_candidate_line: unbound variable
EOF

  if output="$(backlog_open_wrapper_failure_obligation 1 "$output_file" "obligation-repair" "prior-run-example" "Upkeeper" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  [[ "$rc" -eq 0 ]] || fail "wrapper failure obligation writer exited $rc"
  grep -Fq "automation obligation opened for Upkeeper child failure" <<<"$output" ||
    fail "wrapper failure writer did not report obligation creation"

  record_count="$(find "$BACKLOG_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$record_count" == "1" ]] || fail "wrapper failure wrote $record_count obligations, expected 1"
  record_file="$(find "$BACKLOG_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | sort | head -n 1)"
  [[ "$(jq -r '.kind' "$record_file")" == "wrapper_execution_failure" ]] ||
    fail "obligation kind did not identify wrapper execution failure"
  [[ "$(jq -r '.reason' "$record_file")" == "UPKEEPER_CHILD_EXIT_NONZERO" ]] ||
    fail "obligation reason did not preserve child nonzero exit"
  [[ "$(jq -r '.exit_code' "$record_file")" == "1" ]] ||
    fail "obligation did not preserve child exit code"
  [[ "$(jq -r '.repair_target_file' "$record_file")" == "lib/upkeeper/report_analysis.bash" ]] ||
    fail "wrapper failure was not mapped to the crashing module"
  [[ "$(jq -r '.specific_issue_required' "$record_file")" == "true" ]] ||
    fail "wrapper failure obligation did not require concrete issue custody"
  jq -e '.required_resolution[] | select(. == "rerun tests/backlog_wrapper_failure_obligation_test.bash")' "$record_file" >/dev/null ||
    fail "obligation does not require wrapper failure regression test proof"
  jq -e '.evidence.normalized_excerpt | contains("<repo-root>/lib/upkeeper/report_analysis.bash")' "$record_file" >/dev/null ||
    fail "obligation did not store normalized shell-crash evidence"

  backlog_open_wrapper_failure_obligation 1 "$output_file" "obligation-repair" "prior-run-example" "Upkeeper" >/dev/null
  record_count="$(find "$BACKLOG_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$record_count" == "1" ]] || fail "duplicate wrapper failure wrote $record_count obligations, expected 1"
  [[ "$(jq -r '.seen_count' "$record_file")" == "2" ]] ||
    fail "duplicate wrapper failure did not update seen_count"

  selected_json="$(backlog_select_open_obligation_json)"
  [[ "$(jq -r '.status' <<<"$selected_json")" == "ok" ]] ||
    fail "open wrapper failure obligation was not selectable"
  [[ "$(jq -r '.kind' <<<"$selected_json")" == "wrapper_execution_failure" ]] ||
    fail "selected obligation did not preserve wrapper failure kind"
  [[ "$(jq -r '.repair_target_file' <<<"$selected_json")" == "lib/upkeeper/report_analysis.bash" ]] ||
    fail "selected obligation lost crashing-module repair target"
}

test_context_overflow_opens_specific_obligation() {
  local old_obligation_dir output_file record_count record_file selected_json

  old_obligation_dir="$BACKLOG_OBLIGATION_DIR"
  BACKLOG_OBLIGATION_DIR="$TEST_TMP_ROOT/context-obligations"
  export BACKLOG_OBLIGATION_DIR

  output_file="$TEST_TMP_ROOT/upkeeper-context-overflow.log"
  cat >"$output_file" <<EOF
2026-05-25T09:21:24 [ERROR] cycle=20260525T091753-0700-794159 run_hash=37298bda08cddbd0 primary failure transcript tail
error: context_length_exceeded while remote compact tried to preserve backend context
tokens used 187,563
2026-05-25T09:21:24 [ERROR] cycle=20260525T091753-0700-794159 run_hash=37298bda08cddbd0 run.finish execution_origin=primary codex_exit=1
EOF

  backlog_open_wrapper_failure_obligation 3 "$output_file" "obligation-repair" "prior-run-context" "Upkeeper" >/dev/null
  record_count="$(find "$BACKLOG_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$record_count" == "1" ]] || fail "context overflow wrote $record_count obligations, expected 1"
  record_file="$(find "$BACKLOG_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | sort | head -n 1)"
  [[ "$(jq -r '.kind' "$record_file")" == "backend_context_overflow" ]] ||
    fail "context overflow was not classified as backend_context_overflow"
  [[ "$(jq -r '.reason' "$record_file")" == "BACKEND_CONTEXT_LENGTH_EXCEEDED" ]] ||
    fail "context overflow did not preserve a specific reason"
  [[ "$(jq -r '.repair_target_file' "$record_file")" == "lib/upkeeper/transcript_output.bash" ]] ||
    fail "context overflow was not mapped to transcript-output repair"
  [[ "$(jq -r '.source_cycle_id' "$record_file")" == "20260525T091753-0700-794159" ]] ||
    fail "context overflow did not preserve source cycle id"
  [[ "$(jq -r '.source_run_hash' "$record_file")" == "37298bda08cddbd0" ]] ||
    fail "context overflow did not preserve source run hash"
  jq -e '.issue_title | contains("backend context overflow")' "$record_file" >/dev/null ||
    fail "context overflow issue title was not descriptive"
  jq -e '.required_resolution[] | select(contains("bounded"))' "$record_file" >/dev/null ||
    fail "context overflow obligation did not require bounded evidence"

  selected_json="$(backlog_select_open_obligation_json)"
  [[ "$(jq -r '.kind' <<<"$selected_json")" == "backend_context_overflow" ]] ||
    fail "selected context overflow obligation did not preserve specific kind"

  BACKLOG_OBLIGATION_DIR="$old_obligation_dir"
  export BACKLOG_OBLIGATION_DIR
}

test_wrapper_failure_opens_deduped_obligation
test_context_overflow_opens_specific_obligation
printf 'backlog_wrapper_failure_obligation_test: ok\n'
