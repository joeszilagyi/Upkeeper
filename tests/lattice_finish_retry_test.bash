#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-lattice-finish-retry.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

shell_quote() {
  printf '%q' "$1"
}

log_line() {
  printf '%s %s\n' "$1" "$2" >>"$TEST_LOG"
}

log_line_parts() {
  local level="$1" part message=""
  shift
  for part in "$@"; do
    message+="$part"
  done
  log_line "$level" "$message"
}

source "$PROJECT_ROOT/lib/upkeeper/lattice.bash"

lattice_warn_once() {
  WARN_REASON="${1:-}"
}

reset_state() {
  ROOT_DIR="$TEST_TMP_ROOT/repo"
  TEST_LOG="$TEST_TMP_ROOT/test.log"
  mkdir -p "$ROOT_DIR"
  : >"$TEST_LOG"
  CYCLE_ID="cycle-finish-retry"
  CYCLE_RUN_HASH="run-finish-retry"
  UPKEEPER_LATTICE_ENABLED="1"
  UPKEEPER_LATTICE_AVAILABLE="1"
  UPKEEPER_LATTICE_FINISH_RECORDED="0"
  UPKEEPER_LATTICE_FINISH_SPOOL_PATH=""
  UPKEEPER_DRY_RUN="0"
  LOG_FILE="$ROOT_DIR/Upkeeper.log"
  RUN_LAST_MESSAGE_FILE=""
  RUN_TRANSCRIPT_FILE="$ROOT_DIR/transcript.jsonl"
  RUN_COMPILED_PROMPT_FILE="$ROOT_DIR/compiled.txt"
  RUN_SELECTED_REVIEW_PATH="src/example.sh"
  WARN_REASON=""
  : >"$LOG_FILE"
}

test_failed_first_write_retries_and_records_once() {
  (
    local_calls=0
    reset_state
    lattice_run() {
      local_calls=$((local_calls + 1))
      [[ "$1" == "record-cycle-finish" ]] || fail "finish retry invoked the wrong command"
      [[ "$UPKEEPER_LATTICE_FINISH_RECORDED" == "0" ]] || fail "finish guard was set before persistence"
      if [[ "$local_calls" -eq 1 ]]; then
        LATTICE_LAST_OUTPUT='{"status":"injected_first_failure"}'
        return 3
      fi
      LATTICE_LAST_OUTPUT='{"status":"ok"}'
      return 0
    }

    lattice_record_cycle_finish 7 BLOCKED ERROR BLOCKED 19 1 "$RUN_SELECTED_REVIEW_PATH"
    [[ "$local_calls" == "2" ]] || fail "finish write was not retried exactly once"
    [[ "$UPKEEPER_LATTICE_FINISH_RECORDED" == "1" ]] || fail "successful retry did not set finish guard"
    grep -Fq 'lattice.finish.retry attempt=2' "$TEST_LOG" || fail "retry was not reported to the operator"
    grep -Fq 'lattice.finish.persisted attempt=retry' "$TEST_LOG" || fail "retry persistence was not reported"

    lattice_record_cycle_finish 7 BLOCKED ERROR BLOCKED 19 1 "$RUN_SELECTED_REVIEW_PATH"
    [[ "$local_calls" == "2" ]] || fail "successful finish was written more than once"
  )
}

test_persistent_failure_spools_private_replay_payload() {
  (
    local_calls=0
    reset_state
    lattice_run() {
      local_calls=$((local_calls + 1))
      LATTICE_LAST_OUTPUT='{"status":"injected_persistent_failure"}'
      return 3
    }

    if lattice_record_cycle_finish 9 STORAGE_FAILURE ERROR BLOCKED 22 1 "$RUN_SELECTED_REVIEW_PATH"; then
      fail "persistently failing finish write unexpectedly succeeded"
    fi
    [[ "$local_calls" == "2" ]] || fail "persistent failure did not receive one bounded retry"
    [[ "$UPKEEPER_LATTICE_FINISH_RECORDED" == "0" ]] || fail "spooled finish was misclassified as recorded"
    [[ -s "$UPKEEPER_LATTICE_FINISH_SPOOL_PATH" ]] || fail "persistent failure did not create replay payload"
    [[ "$(stat -c '%a' "$UPKEEPER_LATTICE_FINISH_SPOOL_PATH")" == "600" ]] || fail "finish replay payload is not private"
    grep -Fq 'lattice.finish.spooled attempts=2' "$TEST_LOG" || fail "spooled finish was not reported"
    [[ "$WARN_REASON" == "record_cycle_finish_failed" ]] || fail "persistent failure did not retain degraded evidence"

    python3 - "$UPKEEPER_LATTICE_FINISH_SPOOL_PATH" <<'PY' || fail "finish replay payload is incomplete"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
assert payload["schema"] == "upkeeper.lattice-finish-retry.v1"
assert payload["status"] == "pending"
assert payload["attempt_count"] == 2
assert payload["cycle_id"] == "cycle-finish-retry"
assert payload["run_hash"] == "run-finish-retry"
args = payload["command_args"]
assert args[0] == "record-cycle-finish"
assert args[args.index("--wrapper-exit") + 1] == "9"
assert args[args.index("--finish-reason") + 1] == "STORAGE_FAILURE"
assert args[args.index("--selected-path") + 1] == "src/example.sh"
PY
  )
}

test_later_success_clears_existing_spool() {
  (
    local_calls=0
    reset_state
    lattice_run() {
      local_calls=$((local_calls + 1))
      LATTICE_LAST_OUTPUT='{"status":"still_failing"}'
      return 3
    }
    lattice_record_cycle_finish 5 RETRY_LATER WARN "" "" 0 "$RUN_SELECTED_REVIEW_PATH" || true
    spool_path="$UPKEEPER_LATTICE_FINISH_SPOOL_PATH"
    [[ -s "$spool_path" ]] || fail "recovery fixture did not create a spool"

    lattice_run() {
      local_calls=$((local_calls + 1))
      LATTICE_LAST_OUTPUT='{"status":"ok"}'
      return 0
    }
    lattice_record_cycle_finish 5 RETRY_LATER WARN "" "" 0 "$RUN_SELECTED_REVIEW_PATH"
    [[ "$UPKEEPER_LATTICE_FINISH_RECORDED" == "1" ]] || fail "later success did not set finish guard"
    [[ ! -e "$spool_path" ]] || fail "later success left stale retry custody behind"
    [[ -z "$UPKEEPER_LATTICE_FINISH_SPOOL_PATH" ]] || fail "later success retained stale spool state"
    grep -Fq 'lattice.finish.persisted attempt=initial' "$TEST_LOG" || fail "later persistence was not reported"
  )
}

test_failed_first_write_retries_and_records_once
test_persistent_failure_spools_private_replay_payload
test_later_success_clears_existing_spool
printf 'lattice_finish_retry_test: ok\n'
