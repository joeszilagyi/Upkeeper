#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-wrapper-contract.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run_codex_mode_case() {
  local mode="$1"
  local output rc

  set +e
  output="$(
    cd "$ROOT_DIR" &&
      CODEX_MODE_STRING="$mode" bash -c '
        source lib/upkeeper/codex_io.bash
        validate_codex_mode_args_or_exit
        printf "CODEX_MODE_STRING=%s\n" "$CODEX_MODE_STRING"
        printf "CODEX_MODE_SANDBOX=%s\n" "$CODEX_MODE_SANDBOX"
        printf "CODEX_MODE_ARGS=%s\n" "${CODEX_MODE_ARGS[*]}"
      ' 2>&1
  )"
  rc=$?
  set -e

  CODEX_MODE_CASE_RC="$rc"
  CODEX_MODE_CASE_OUTPUT="$output"
}

assert_codex_mode_rejected() {
  local mode="$1"
  local expected="$2"

  run_codex_mode_case "$mode"
  [[ "$CODEX_MODE_CASE_RC" -eq 2 ]] ||
    fail "CODEX_MODE $mode exited $CODEX_MODE_CASE_RC, expected 2"
  grep -Fq "$expected" <<<"$CODEX_MODE_CASE_OUTPUT" ||
    fail "CODEX_MODE $mode did not report expected error: $CODEX_MODE_CASE_OUTPUT"
}

test_codex_mode_rejects_malformed_and_unsafe_modes() {
  assert_codex_mode_rejected "sandbox workspace-write" "expected a Codex option beginning with --"
  assert_codex_mode_rejected "---sandbox workspace-write" "expected a Codex option beginning with --"
  assert_codex_mode_rejected "--sandbox" "expected a sandbox mode argument"
  assert_codex_mode_rejected "--sandbox danger-full-access" "Genie Protocol requires sandboxed backend Codex execution"
  assert_codex_mode_rejected "--dangerously-bypass-approvals-and-sandbox" "Genie Protocol requires sandboxed backend Codex execution"
  assert_codex_mode_rejected "--sandbox workspace-write --foo=bar" "CODEX_MODE only supports --sandbox workspace-write or --sandbox read-only"
}

test_codex_mode_accepts_only_allowlisted_sandboxes() {
  run_codex_mode_case "--sandbox workspace-write"
  [[ "$CODEX_MODE_CASE_RC" -eq 0 ]] ||
    fail "workspace-write CODEX_MODE exited $CODEX_MODE_CASE_RC: $CODEX_MODE_CASE_OUTPUT"
  grep -Fxq "CODEX_MODE_STRING=--sandbox workspace-write" <<<"$CODEX_MODE_CASE_OUTPUT" ||
    fail "workspace-write CODEX_MODE was not normalized"
  grep -Fxq "CODEX_MODE_SANDBOX=workspace-write" <<<"$CODEX_MODE_CASE_OUTPUT" ||
    fail "workspace-write sandbox value missing"

  run_codex_mode_case "--sandbox read-only"
  [[ "$CODEX_MODE_CASE_RC" -eq 0 ]] ||
    fail "read-only CODEX_MODE exited $CODEX_MODE_CASE_RC: $CODEX_MODE_CASE_OUTPUT"
  grep -Fxq "CODEX_MODE_STRING=--sandbox read-only" <<<"$CODEX_MODE_CASE_OUTPUT" ||
    fail "read-only CODEX_MODE was not normalized"
  grep -Fxq "CODEX_MODE_SANDBOX=read-only" <<<"$CODEX_MODE_CASE_OUTPUT" ||
    fail "read-only sandbox value missing"
}

test_parent_stop_guard_refuses_unsafe_shells_and_pids() {
  local invalid_pid reason guard_out

  (
    cd "$ROOT_DIR"
    source lib/upkeeper/process_control.bash
    CODEX_DISABLE_PARENT_STOP=0
    guard_out="$TEST_TMP_ROOT/parent-stop.out"

    for invalid_pid in -1 0 1 01 abc "2 3"; do
      if parent_pid_is_stoppable "$invalid_pid"; then
        printf 'unsafe parent PID was accepted: %s\n' "$invalid_pid" >&2
        exit 1
      fi
    done

    reason="$(parent_stop_skip_reason bash bash 0)"
    [[ "$reason" == "interactive_parent_shell" ]] || {
      printf 'interactive shell skip reason was %s\n' "${reason:-<empty>}" >&2
      exit 1
    }

    reason="$(parent_stop_skip_reason bash "sleep 60" 0)"
    [[ "$reason" == "unrecognized_parent_shell_command" ]] || {
      printf 'unknown shell skip reason was %s\n' "${reason:-<empty>}" >&2
      exit 1
    }

    if parent_stop_skip_reason bash "bash -lc while ./Upkeeper; do sleep 60; done" 0 >"$guard_out"; then
      printf 'supervised Upkeeper loop was incorrectly skipped: %s\n' "$(cat "$guard_out")" >&2
      exit 1
    fi

    if parent_stop_skip_reason bash "plain shell" 1 >"$guard_out"; then
      printf 'trusted override was incorrectly skipped: %s\n' "$(cat "$guard_out")" >&2
      exit 1
    fi

    CODEX_DISABLE_PARENT_STOP=1
    reason="$(parent_stop_skip_reason bash "bash -lc while ./Upkeeper" 1)"
    [[ "$reason" == "disabled_by_env" ]] || {
      printf 'disabled parent-stop skip reason was %s\n' "${reason:-<empty>}" >&2
      exit 1
    }
  ) || fail "parent-stop guard contract failed"
}

test_status_marker_rejects_decorated_or_ambiguous_candidates() {
  local marker_file analysis

  marker_file="$TEST_TMP_ROOT/ambiguous-marker.txt"
  cat >"$marker_file" <<'EOF'
Review complete.
UPKEEPER_STATUS: WORK_DONE and UPKEEPER_STATUS: BLOCKED
EOF
  analysis="$(cd "$ROOT_DIR"; source lib/upkeeper/report_analysis.bash; while_marker_analysis_json "$marker_file")"
  grep -Fq '"accepted_marker":""' <<<"$analysis" ||
    fail "ambiguous marker was accepted: $analysis"
  grep -Fq '"candidate_rejection_reason":"multiple_markers"' <<<"$analysis" ||
    fail "ambiguous marker rejection reason missing: $analysis"

  marker_file="$TEST_TMP_ROOT/decorated-marker.txt"
  cat >"$marker_file" <<'EOF'
```text
UPKEEPER_STATUS: WORK_DONE
```
EOF
  analysis="$(cd "$ROOT_DIR"; source lib/upkeeper/report_analysis.bash; while_marker_analysis_json "$marker_file")"
  grep -Fq '"accepted_marker":""' <<<"$analysis" ||
    fail "code-fenced marker was accepted: $analysis"

  marker_file="$TEST_TMP_ROOT/trailing-status-marker.txt"
  cat >"$marker_file" <<'EOF'
Review complete.
UPKEEPER_STATUS: WORK_DONE

If you want, I can add another test.
EOF
  analysis="$(
    cd "$ROOT_DIR"
    source lib/upkeeper/runtime_format_json.bash
    source lib/upkeeper/report_analysis.bash
    source lib/upkeeper/status_session.bash
    marker_analysis="$(while_marker_analysis_json "$marker_file")"
    recovered="$(resolved_status_marker_from_analysis "$marker_analysis" 0 present)"
    printf '%s\nrecovered=%s\n' "$marker_analysis" "$recovered"
  )"
  grep -Fq '"candidate_rejection_reason":"trailing_content_after_marker"' <<<"$analysis" ||
    fail "trailing marker recovery reason missing: $analysis"
  grep -Fq 'recovered=WORK_DONE' <<<"$analysis" ||
    fail "strict marker followed by trailing non-control text was not recovered: $analysis"
}

test_startup_anomaly_allowlist_reports_only_unallowed_redacted_paths() {
  local before_file after_file output

  before_file="$TEST_TMP_ROOT/startup-before.json"
  after_file="$TEST_TMP_ROOT/startup-after.json"
  cat >"$before_file" <<'JSON'
{
  "Upkeeper": {"status": "clean", "hash": "old"},
  "change_notes_2026.md": {"status": "clean", "hash": "old"},
  "docs/scripts/upkeeper.md": {"status": "clean", "hash": "old"},
  "lib/upkeeper/worktree_state.bash": {"status": "clean", "hash": "old"},
  "tools/validate_upkeeper.sh": {"status": "clean", "hash": "old"},
  "unrelated.txt": {"status": "clean", "hash": "old"}
}
JSON
  cat >"$after_file" <<'JSON'
{
  "Upkeeper": {"status": "modified", "hash": "new"},
  "change_notes_2026.md": {"status": "modified", "hash": "new"},
  "docs/scripts/upkeeper.md": {"status": "modified", "hash": "new"},
  "lib/upkeeper/worktree_state.bash": {"status": "modified", "hash": "new"},
  "tools/validate_upkeeper.sh": {"status": "modified", "hash": "new"},
  "unrelated.txt": {"status": "modified", "hash": "new"}
}
JSON

  output="$(
    cd "$ROOT_DIR"
    UPKEEPER_REDACTION_KEY=wrapper-contract-test \
      bash -c 'source lib/upkeeper/worktree_state.bash; startup_anomaly_gate_changed_path_violations "$1" "$2"' \
      bash "$before_file" "$after_file"
  )"
  grep -Fq "changed_path path_hmac=path-hmac-sha256:" <<<"$output" ||
    fail "startup anomaly allowlist did not report an unrelated path HMAC"
  grep -Fq "extension=.txt" <<<"$output" ||
    fail "startup anomaly allowlist did not report extension class"
  grep -Fq "content_changed=1" <<<"$output" ||
    fail "startup anomaly allowlist did not report content change"
  if grep -Eq "unrelated.txt|Upkeeper|change_notes|docs/scripts|lib/upkeeper|tools/validate" <<<"$output"; then
    fail "startup anomaly allowlist leaked or reported allowed raw paths: $output"
  fi
}

test_operator_status_commands_are_local_and_structured() {
  local status_root status_log json_output output command

  status_root="$TEST_TMP_ROOT/operator-status"
  status_log="$status_root/Upkeeper.log"
  mkdir -p "$status_root/codex-home/sessions" "$status_root/failures/open" "$status_root/obligations/open"
  cat >"$status_log" <<'EOF'
2026-05-24T01:00:00 [INFO] cycle=cycle-status run_hash=hash-status cycle.summary execution_origin=primary model=gpt-5.5 status_marker=WORK_DONE codex_exit=0
2026-05-24T01:00:01 [INFO] cycle=cycle-status run_hash=hash-status cycle.exit exit_code=0 reason=WORK_DONE
EOF
  printf '{}\n' >"$status_root/failures/open/example.json"
  printf '{}\n' >"$status_root/obligations/open/example.json"

  json_output="$(
    cd "$ROOT_DIR"
    CODEX_HOME="$status_root/codex-home" \
      CODEX_LOG_FILE="$status_log" \
      CODEX_ACTIVE_LOCK_DIR="$status_root/active.lock" \
      CODEX_TOOL_FAILURE_QUEUE_DIR="$status_root/failures" \
      UPKEEPER_OBLIGATION_DIR="$status_root/obligations" \
      ./Upkeeper --json-status
  )" || fail "--json-status failed"
  python3 - "$json_output" <<'PY' || fail "--json-status did not emit expected schema"
import json, sys
data = json.loads(sys.argv[1])
assert data["schema"] == "upkeeper.status.v1", data
assert data["last_run"]["cycle_id"] == "cycle-status", data["last_run"]
assert data["last_run"]["status_marker"] == "WORK_DONE", data["last_run"]
assert data["open_failures"]["tool_failure_count"] == 1, data["open_failures"]
assert data["open_failures"]["automation_obligation_count"] == 1, data["open_failures"]
assert data["quota"]["snapshot"] == "missing", data["quota"]
PY

  for command in --status --doctor --last-run --open-failures --quota-status; do
    output="$(
      cd "$ROOT_DIR"
      CODEX_HOME="$status_root/codex-home" \
        CODEX_LOG_FILE="$status_log" \
        CODEX_ACTIVE_LOCK_DIR="$status_root/active.lock" \
        CODEX_TOOL_FAILURE_QUEUE_DIR="$status_root/failures" \
        UPKEEPER_OBLIGATION_DIR="$status_root/obligations" \
        ./Upkeeper "$command"
    )" || fail "$command failed"
    [[ -n "$output" ]] || fail "$command produced no output"
  done

  output="$(
    cd "$ROOT_DIR"
    CODEX_MODE="invalid-backend-mode" \
      CODEX_HOME="$status_root/codex-home" \
      CODEX_LOG_FILE="$status_log" \
      CODEX_ACTIVE_LOCK_DIR="$status_root/active.lock" \
      CODEX_TOOL_FAILURE_QUEUE_DIR="$status_root/failures" \
      UPKEEPER_OBLIGATION_DIR="$status_root/obligations" \
      ./Upkeeper --doctor
  )" || fail "--doctor should report status even when backend CODEX_MODE is invalid"
  grep -Fq "Doctor" <<<"$output" || fail "--doctor with invalid backend CODEX_MODE did not emit doctor output"
  grep -Fq "invalid_backend_mode" <<<"$output" || fail "--doctor with invalid backend CODEX_MODE did not report invalid_backend_mode"

  [[ ! -e "$status_root/active.lock" ]] || fail "status command acquired or created active lock"
}

test_codex_mode_rejects_malformed_and_unsafe_modes
test_codex_mode_accepts_only_allowlisted_sandboxes
test_parent_stop_guard_refuses_unsafe_shells_and_pids
test_status_marker_rejects_decorated_or_ambiguous_candidates
test_startup_anomaly_allowlist_reports_only_unallowed_redacted_paths
test_operator_status_commands_are_local_and_structured
printf 'ok - wrapper_contract\n'
