#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-backlog-validation-obligation.XXXXXX")"
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

write_failing_validator() {
  local script_path="$1"

  cat >"$script_path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'validate_upkeeper: ERROR: backlog launcher job start summary did not emit two green bars'
exit 64
SH
}

test_batch_validation_failure_opens_and_updates_obligation() {
  local validator output rc record_count record_file selected_json

  validator="$TEST_TMP_ROOT/fail-validator.sh"
  write_failing_validator "$validator"

  if output="$(run_batch_validation_phase "batch_validation.quick_validator" "quick validator" bash "$validator" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  [[ "$rc" -eq 64 ]] || fail "failing validation phase exited $rc, expected 64"
  grep -Fq "automation obligation opened for batch validation failure" <<<"$output" ||
    fail "batch validation failure did not report obligation creation"

  record_count="$(find "$BACKLOG_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$record_count" == "1" ]] || fail "batch validation failure wrote $record_count obligations, expected 1"
  record_file="$(find "$BACKLOG_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | sort | head -n 1)"
  [[ "$(jq -r '.kind' "$record_file")" == "local_validation_failure" ]] ||
    fail "obligation kind did not identify local validation failure"
  [[ "$(jq -r '.failed_phase' "$record_file")" == "batch_validation.quick_validator" ]] ||
    fail "obligation did not preserve failed phase"
  [[ "$(jq -r '.exit_code' "$record_file")" == "64" ]] ||
    fail "obligation did not preserve validation exit code"
  [[ "$(jq -r '.repair_target_file' "$record_file")" == "orchestration/backlog.sh" ]] ||
    fail "validator failure was not mapped to backlog launcher owner"
  jq -e '.required_resolution[] | select(. == "rerun tools/validate_upkeeper.sh --quick")' "$record_file" >/dev/null ||
    fail "obligation does not require quick validation proof"
  jq -e '.evidence.tail[] | select(contains("validate_upkeeper: ERROR"))' "$record_file" >/dev/null ||
    fail "obligation did not capture bounded validation output evidence"

  if run_batch_validation_phase "batch_validation.quick_validator" "quick validator" bash "$validator" >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi
  [[ "$rc" -eq 64 ]] || fail "second failing validation phase exited $rc, expected 64"
  record_count="$(find "$BACKLOG_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$record_count" == "1" ]] || fail "duplicate validation failure wrote $record_count obligations, expected 1"
  [[ "$(jq -r '.seen_count' "$record_file")" == "2" ]] ||
    fail "duplicate validation failure did not update seen_count"

  selected_json="$(backlog_select_open_obligation_json)"
  [[ "$(jq -r '.status' <<<"$selected_json")" == "ok" ]] ||
    fail "open batch validation obligation was not selectable"
  [[ "$(jq -r '.kind' <<<"$selected_json")" == "local_validation_failure" ]] ||
    fail "selected obligation did not preserve local validation failure kind"
  [[ "$(jq -r '.repair_target_file' <<<"$selected_json")" == "orchestration/backlog.sh" ]] ||
    fail "selected obligation lost repair target"
}

test_batch_validation_failure_opens_and_updates_obligation
printf 'backlog_batch_validation_obligation_test: ok\n'
