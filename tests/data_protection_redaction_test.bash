#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-redaction-test.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_log_kv_encodes_control_characters() {
  local encoded

  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/upkeeper/runtime_foundation.bash"

  encoded="$(log_kv prompt_file $'path\nwith-cr\r-and-tab\t.md')"
  [[ "$encoded" != *$'\n'* ]] || fail "log_kv emitted a literal newline"
  [[ "$encoded" != *$'\r'* ]] || fail "log_kv emitted a literal carriage return"
  [[ "$encoded" == prompt_file=* ]] || fail "log_kv did not preserve the field name"
}

test_prompt_file_rejects_control_characters() {
  local capture="$TEST_TMP_ROOT/prompt-file.err"

  if (
    set -euo pipefail
    ROOT_DIR="$TEST_TMP_ROOT/repo"
    SCRIPT_NAME="Upkeeper"
    UPKEEPER_AUTOMATION_LAUNCHER="Upkeeper"
    PROMPT_FILE=$'bad\nprompt.md'
    INLINE_PROMPT=""
    mkdir -p "$ROOT_DIR"
    die() {
      printf '%s\n' "$*" >"$capture"
      exit 44
    }
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/upkeeper/runtime_foundation.bash"
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/upkeeper/fallback_artifacts.bash"
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/upkeeper/codex_io.bash"
    resolve_prompt_file
  ); then
    fail "resolve_prompt_file accepted a control-character path"
  fi

  grep -Fq "control characters" "$capture" || fail "prompt-file control-character rejection was not explicit"
}

test_startup_state_prompt_summary_is_redacted() {
  local state_dir="$TEST_TMP_ROOT/startup gates"
  local output

  mkdir -p "$state_dir"

  output="$(
    cd "$PROJECT_ROOT"
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$state_dir" \
      UPKEEPER_REDACTION_KEY="startup-state-redaction-test" \
      CYCLE_ID="cycle with spaces" \
      CYCLE_RUN_HASH="raw run hash" \
      SELF_PATH="/private/customer/project/Upkeeper" \
      ROOT_DIR="/private/customer/project" \
      STARTUP_ANOMALY_REASONS="manual reason with spaces" \
      bash -c 'source lib/upkeeper/startup_anomaly_state.bash; log_line(){ :; }; shell_quote(){ printf %q "$1"; }; write_startup_anomaly_gate_state unresolved "manual reason with spaces" >/dev/null; startup_anomaly_state_lines'
  )"

  grep -Fq "state_id=state-hmac-sha256:" <<<"$output" || fail "state summary omitted state HMAC"
  grep -Fq "state_file_hmac=path-hmac-sha256:" <<<"$output" || fail "state summary omitted path HMAC"
  grep -Fq "reason_class=manual_reason_with_spaces" <<<"$output" || fail "state summary omitted normalized reason class"
  grep -Fq "detail_redacted=1" <<<"$output" || fail "state summary omitted detail redaction marker"
  ! grep -Fq "/private/customer" <<<"$output" || fail "state summary leaked raw private path"
  ! grep -Fq "customer incident alpha" <<<"$output" || fail "state summary leaked raw detail"
  ! grep -Fq "raw run hash" <<<"$output" || fail "state summary leaked raw run hash"
}

test_startup_changed_path_log_is_redacted_and_diagnostic_is_private() {
  local before_file="$TEST_TMP_ROOT/before.json"
  local after_file="$TEST_TMP_ROOT/after.json"
  local diagnostics_file="$TEST_TMP_ROOT/diagnostics.jsonl"
  local output

  cat >"$before_file" <<'JSON'
{
  "__meta__": {"head": "old-head"},
  "customer alpha/secrets.txt": {"status": "clean", "hash": "old-content-hash"}
}
JSON
  cat >"$after_file" <<'JSON'
{
  "__meta__": {"head": "new-head"},
  "customer alpha/secrets.txt": {"status": "modified", "hash": "new-content-hash"}
}
JSON

  output="$(
    cd "$PROJECT_ROOT"
    UPKEEPER_REDACTION_KEY="changed-path-redaction-test" \
      bash -c 'source lib/upkeeper/worktree_state.bash; startup_anomaly_gate_changed_path_violations "$1" "$2" "$3"' \
        bash "$before_file" "$after_file" "$diagnostics_file"
  )"

  grep -Fq "path_hmac=path-hmac-sha256:" <<<"$output" || fail "changed-path output omitted path HMAC"
  grep -Fq "extension=.txt" <<<"$output" || fail "changed-path output omitted extension class"
  grep -Fq "content_changed=1" <<<"$output" || fail "changed-path output omitted content_changed boolean"
  ! grep -Fq "customer alpha" <<<"$output" || fail "changed-path output leaked raw path"
  ! grep -Fq "old-content-hash" <<<"$output" || fail "changed-path output leaked before hash"
  ! grep -Fq "new-content-hash" <<<"$output" || fail "changed-path output leaked after hash"
  grep -Fq '"path":"customer alpha/secrets.txt"' "$diagnostics_file" || fail "private diagnostics omitted raw changed path"
  grep -Fq '"before_hash":"old-content-hash"' "$diagnostics_file" || fail "private diagnostics omitted before hash"
}

test_log_kv_encodes_control_characters
test_prompt_file_rejects_control_characters
test_startup_state_prompt_summary_is_redacted
test_startup_changed_path_log_is_redacted_and_diagnostic_is_private

printf 'data_protection_redaction_test: ok\n'
