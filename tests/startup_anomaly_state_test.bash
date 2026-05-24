#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-startup-anomaly-state.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

log_line() {
  :
}

log_line_parts() {
  local level="$1"
  shift
  local message="" part
  for part in "$@"; do
    message+="$part"
  done
  log_line "$level" "$message"
}

shell_quote() {
  printf '%q' "$1"
}

write_startup_anomaly_state_file() {
  local path="$1"
  local status="$2"
  local owner="$3"
  local schema_version="$4"
  local payload
  local state_signature
  local now_epoch

  now_epoch="$(date '+%s')"
  payload="$(cat <<EOF
active_reasons=${STARTUP_ANOMALY_REASONS:-unrelated-state-test}
created_epoch=$now_epoch
cycle_id=$CYCLE_ID
detail=fixture
reason=fixture
root_dir=$PROJECT_ROOT
run_hash=$CYCLE_RUN_HASH
self_path=$PROJECT_ROOT/Upkeeper
schema_version=$schema_version
status=$status
state_path=$path
owner=$owner
updated_epoch=$now_epoch
EOF
)"
  state_signature="$(startup_anomaly_state_signature "$payload"$'\n' "$UPKEEPER_REDACTION_KEY")"
  [[ "$state_signature" != "unknown" ]] || fail "failed to sign fixture startup anomaly state"

  {
    printf '%s\n' "$payload"
    printf 'state_signature=%s\n' "$state_signature"
  } >"$path"
  chmod 600 "$path"
}

test_mark_startup_anomaly_gate_states_resolved_skips_unowned_and_wrong_schema_states() {
  local state_dir="$TEST_TMP_ROOT/state"
  local foreign_state="$state_dir/foreign.state"
  local bad_schema_state="$state_dir/bad-schema.state"
  local owned_before foreign_before bad_schema_before
  local owned_state

  local UPKEEPER_REDACTION_KEY="startup-anomaly-owner-schema-fix-test"
  local CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$state_dir"
  local CYCLE_ID="startup-anomaly-gate-fix-cycle"
  local CYCLE_RUN_HASH="owned"
  local ROOT_DIR="$PROJECT_ROOT"
  local SELF_PATH="$PROJECT_ROOT/Upkeeper"

  mkdir -p "$state_dir"
  owned_state="$state_dir/$CYCLE_RUN_HASH.state"

  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/upkeeper/startup_anomaly_state.bash"

  write_startup_anomaly_gate_state unresolved "owned"
  write_startup_anomaly_state_file "$foreign_state" "unresolved" "external_state_owner" "1"
  write_startup_anomaly_state_file "$bad_schema_state" "unresolved" "$STARTUP_ANOMALY_GATE_STATE_OWNER" "99"
  owned_before="$(cat "$owned_state")"
  foreign_before="$(cat "$foreign_state")"
  bad_schema_before="$(cat "$bad_schema_state")"

  mark_startup_anomaly_gate_states_resolved

  [[ "$owned_before" != "$(cat "$owned_state")" ]] || fail "owned state file was not rewritten during resolution"
  grep -Fxq "status=resolved" "$owned_state" || fail "owned state file was not marked resolved"
  grep -Fq "resolved_by_cycle_id=$CYCLE_ID" "$owned_state" || fail "owned state file was not annotated with resolving cycle"
  grep -Fq "resolved_by_run_hash=$CYCLE_RUN_HASH" "$owned_state" || fail "owned state file was not annotated with resolving run hash"

  [[ "$foreign_before" == "$(cat "$foreign_state")" ]] || fail "foreign state file was unexpectedly rewritten"
  grep -Fxq "status=unresolved" "$foreign_state" || fail "foreign state status changed unexpectedly"
  ! grep -Fq "resolved_by_cycle_id" "$foreign_state" || fail "foreign state file was unexpectedly annotated as resolved"

  [[ "$bad_schema_before" == "$(cat "$bad_schema_state")" ]] || fail "wrong-schema state file was unexpectedly rewritten"
  grep -Fxq "status=unresolved" "$bad_schema_state" || fail "wrong-schema state status changed unexpectedly"
  ! grep -Fq "resolved_by_cycle_id" "$bad_schema_state" || fail "wrong-schema file was unexpectedly annotated as resolved"
}

test_startup_anomaly_state_readers_ignore_foreign_unresolved_files() {
  local state_dir="$TEST_TMP_ROOT/state-readers"
  local owned_state="$state_dir/owned.state"
  local foreign_state="$state_dir/foreign.state"
  local state_lines_output

  local UPKEEPER_REDACTION_KEY="startup-anomaly-owner-schema-fix-test"
  local CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$state_dir"
  local CYCLE_ID="startup-anomaly-gate-readers-cycle"
  local CYCLE_RUN_HASH="startup-anomaly-gate-readers-run"
  local ROOT_DIR="$PROJECT_ROOT"
  local SELF_PATH="$PROJECT_ROOT/Upkeeper"
  local STARTUP_ANOMALY_REASONS="manual reason with spaces"

  mkdir -p "$state_dir"

  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/upkeeper/startup_anomaly_state.bash"

  write_startup_anomaly_gate_state unresolved "$STARTUP_ANOMALY_REASONS"
  write_startup_anomaly_state_file "$foreign_state" "unresolved" "external_state_owner" "1"

  state_lines_output="$(
    startup_anomaly_state_lines
  )"

  [[ -n "$state_lines_output" ]] || fail "owned unresolved state was not listed"
  [[ "$(printf '%s\n' "$state_lines_output" | wc -l)" -eq 1 ]] || fail "foreign state was included in startup anomaly state summary"
  grep -Fq "reason_class=manual_reason_with_spaces" <<<"$state_lines_output" || fail "startup anomaly state summary omitted expected reason class"

  startup_anomaly_gate_has_unresolved_state "$STARTUP_ANOMALY_REASONS" || fail "owned unresolved state should satisfy reason filter"

  # Resolve all owned states and confirm foreign unresolved file is ignored by reason checks.
  mark_startup_anomaly_gate_states_resolved
  if startup_anomaly_gate_has_unresolved_state "$STARTUP_ANOMALY_REASONS"; then
    fail "foreign unresolved state unexpectedly passed unresolved-state reason filtering"
  fi
}

test_mark_startup_anomaly_gate_states_resolved_skips_unowned_and_wrong_schema_states
test_startup_anomaly_state_readers_ignore_foreign_unresolved_files

printf 'startup_anomaly_state_test: ok\n'
