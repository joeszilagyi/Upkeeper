#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source lib/upkeeper/review_modules.bash
source lib/upkeeper/codex_io.bash

TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-contact-budget-test.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP_ROOT"' EXIT

LOG_FILE="$TEST_TMP_ROOT/upkeeper.log"
CYCLE_ID="contact-budget-test-cycle"
CODEX_MODEL="fake-model"
CODEX_REASONING_EFFORT="medium"
CODEX_MODEL_CONTACT_LEDGER="$TEST_TMP_ROOT/model-contacts.jsonl"
CODEX_MODEL_CONTACT_BUDGET_NORMAL="4"
CODEX_MODEL_CONTACT_BUDGET_RECOVERY="3"
CODEX_MODEL_CONTACT_BUDGET_MAXIMUM="8"
CODEX_MODEL_CONTACT_BUDGET_BYPASS="0"
CODEX_ATTEMPT_ROLE="primary"
UPKEEPER_TASK_PROFILE_GRADE="normal-code"
CODEX_FALLBACK_TRIGGER=""
RUN_GENIE_BIN_DIR="$TEST_TMP_ROOT/genie-bin"
RUN_GENIE_REAL_GH_BIN="/bin/true"
RUN_GENIE_GH_CONFIG_DIR="$TEST_TMP_ROOT/gh-config"

mkdir -p "$RUN_GENIE_BIN_DIR" "$RUN_GENIE_GH_CONFIG_DIR"

shell_quote() {
  printf '%q' "$1"
}

log_line() {
  local level="$1"
  shift
  printf '[%s] %s\n' "$level" "$*" >>"$LOG_FILE"
}

upkeeper_path_hmac() {
  printf 'path-hmac-sha256:test'
}

prepare_genie_protocol_env() {
  mkdir -p "$RUN_GENIE_BIN_DIR" "$RUN_GENIE_GH_CONFIG_DIR"
}

terminal_wants_full_output() {
  return 1
}

codex_live_output_filter() {
  cat
}

emit_codex_transcript_summary() {
  return 0
}

fail() {
  printf 'codex_exec_contact_budget_test: %s\n' "$*" >&2
  exit 1
}

make_fake_codex() {
  local path="$1"
  local mode="$2"
  cat >"$path" <<'SH'
#!/usr/bin/env bash
mode="${UPKEEPER_FAKE_CODEX_MODE:-ok}"
printf '%s\n' "$mode" >>"${UPKEEPER_FAKE_CODEX_COUNT_FILE:?}"
case "$mode" in
  ok)
    printf 'fake codex ok\n'
    exit 0
    ;;
  sleep)
    printf 'fake codex sleeping\n'
    sleep 5
    printf 'fake codex woke\n'
    exit 0
    ;;
  *)
    printf 'unknown fake mode: %s\n' "$mode" >&2
    exit 64
    ;;
esac
SH
  chmod +x "$path"
  UPKEEPER_FAKE_CODEX_MODE="$mode"
  export UPKEEPER_FAKE_CODEX_MODE
}

ledger_field() {
  local index="$1"
  local field="$2"
  python3 - "$CODEX_MODEL_CONTACT_LEDGER" "$index" "$field" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
index = int(sys.argv[2])
field = sys.argv[3]
records = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
value = records[index].get(field)
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

run_timeout_case() {
  local fake="$TEST_TMP_ROOT/fake-codex-timeout"
  local transcript="$TEST_TMP_ROOT/timeout.transcript"
  local stdin_file="$TEST_TMP_ROOT/stdin.txt"
  local rc

  printf 'prompt\n' >"$stdin_file"
  : >"$LOG_FILE"
  : >"$TEST_TMP_ROOT/count-timeout.txt"
  UPKEEPER_FAKE_CODEX_COUNT_FILE="$TEST_TMP_ROOT/count-timeout.txt"
  export UPKEEPER_FAKE_CODEX_COUNT_FILE
  make_fake_codex "$fake" sleep
  CODEX_EXEC_TIMEOUT_SECONDS="1"
  CODEX_EXEC_TIMEOUT_KILL_AFTER_SECONDS="1"

  set +e
  run_codex_exec_capture "primary" "$transcript" "$stdin_file" \
    "$fake" exec -m fake-model -c model_reasoning_effort=medium
  rc=$?
  set -e

  [[ "$rc" -eq 124 ]] || fail "timeout case returned $rc, expected 124"
  grep -Fq "fake codex sleeping" "$transcript" || fail "timeout transcript did not preserve partial output"
  grep -Fq "codex.exec_timeout" "$LOG_FILE" || fail "timeout was not logged"
  [[ "$(ledger_field 0 timeout)" == "true" ]] || fail "timeout ledger flag was not true"
  [[ "$(ledger_field 0 contact_executed)" == "true" ]] || fail "timeout ledger contact_executed was not true"
  [[ "$(ledger_field 0 prompt_pass)" == "default" ]] || fail "timeout ledger prompt profile missing"
}

run_budget_case() {
  local fake="$TEST_TMP_ROOT/fake-codex-budget"
  local transcript1="$TEST_TMP_ROOT/budget-1.transcript"
  local transcript2="$TEST_TMP_ROOT/budget-2.transcript"
  local stdin_file="$TEST_TMP_ROOT/stdin-budget.txt"
  local rc

  printf 'prompt\n' >"$stdin_file"
  : >"$LOG_FILE"
  : >"$CODEX_MODEL_CONTACT_LEDGER"
  : >"$TEST_TMP_ROOT/count-budget.txt"
  UPKEEPER_FAKE_CODEX_COUNT_FILE="$TEST_TMP_ROOT/count-budget.txt"
  export UPKEEPER_FAKE_CODEX_COUNT_FILE
  make_fake_codex "$fake" ok
  CODEX_EXEC_TIMEOUT_SECONDS="10"
  CODEX_MODEL_CONTACT_BUDGET_NORMAL="1"

  run_codex_exec_capture "primary" "$transcript1" "$stdin_file" \
    "$fake" exec -m fake-model -c model_reasoning_effort=medium

  set +e
  run_codex_exec_capture "primary" "$transcript2" "$stdin_file" \
    "$fake" exec -m fake-model -c model_reasoning_effort=medium
  rc=$?
  set -e

  [[ "$rc" -eq 88 ]] || fail "budget case returned $rc, expected 88"
  [[ "$(wc -l <"$TEST_TMP_ROOT/count-budget.txt" | tr -d ' ')" == "1" ]] || fail "budget preflight launched fake codex after limit"
  grep -Fq "model contact budget exceeded" "$transcript2" || fail "budget transcript lacks operator explanation"
  [[ "$(ledger_field 0 contact_executed)" == "true" ]] || fail "first budget ledger contact_executed was not true"
  [[ "$(ledger_field 1 contact_executed)" == "false" ]] || fail "budget skip ledger contact_executed was not false"
  [[ "$(ledger_field 1 reason)" == "budget_exceeded" ]] || fail "budget skip reason missing"
}

run_timeout_case
run_budget_case

printf 'codex_exec_contact_budget_test: ok\n'
