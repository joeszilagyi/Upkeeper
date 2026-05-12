#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "$ROOT_DIR/lib/upkeeper/aux_codex.bash"

TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-aux-codex.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

shell_quote() {
  printf '%q' "$1"
}

log_line() {
  return 0
}

quota_state_json() {
  fail "quota_state_json should not run for invalid auxiliary mode"
}

run_codex_exec_capture() {
  fail "codex exec should not run during aux_codex boundary tests"
}

test_run_aux_codex_exec_rejects_triple_dash_mode() {
  local prompt_file last_message rc

  prompt_file="$TEST_TMP_ROOT/prompt.txt"
  last_message="$TEST_TMP_ROOT/last-message.txt"
  : >"$prompt_file"

  CODEX_HOME_DIR="$TEST_TMP_ROOT/codex-home"
  CODEX_ARG0_TMP_ROOT="$TEST_TMP_ROOT/arg0"
  CODEX_ARG0_TMP_QUARANTINE_ROOT="$TEST_TMP_ROOT/arg0-quarantine"
  CODEX_BWRAP_TMP_ROOT="$TEST_TMP_ROOT/bwrap"
  UPKEEPER_DRY_RUN=0

  set +e
  run_aux_codex_exec "postmortem.report" "gpt-test" "low" "---sandbox workspace-write" "$prompt_file" "$last_message"
  rc=$?
  set -e

  [[ "$rc" -eq 87 ]] || fail "expected invalid aux mode exit 87, got $rc"
  grep -qx 'reason: Codex auxiliary mode is invalid' "$last_message" ||
    fail "invalid aux mode marker reason missing"
  grep -Fq 'detail: invalid first mode token ---sandbox; expected a Codex option beginning with --' "$last_message" ||
    fail "invalid aux mode marker detail missing"
  grep -qx 'CODEX_POSTMORTEM_STATUS: BLOCKED' "$last_message" ||
    fail "blocked marker missing"
}

test_run_aux_codex_exec_rejects_invalid_mode_token() {
  local prompt_file last_message rc

  prompt_file="$TEST_TMP_ROOT/prompt-invalid-token.txt"
  last_message="$TEST_TMP_ROOT/last-message-invalid-token.txt"
  : >"$prompt_file"

  CODEX_HOME_DIR="$TEST_TMP_ROOT/codex-home"
  CODEX_ARG0_TMP_ROOT="$TEST_TMP_ROOT/arg0"
  CODEX_ARG0_TMP_QUARANTINE_ROOT="$TEST_TMP_ROOT/arg0-quarantine"
  CODEX_BWRAP_TMP_ROOT="$TEST_TMP_ROOT/bwrap"
  UPKEEPER_DRY_RUN=1

  set +e
  run_aux_codex_exec "postmortem.report" "gpt-test" "low" "--sandbox workspace-write danger-full-access" "$prompt_file" "$last_message"
  rc=$?
  set -e

  [[ "$rc" -eq 87 ]] || fail "expected invalid aux mode token exit 87, got $rc"
  grep -qx 'reason: Codex auxiliary mode is invalid' "$last_message" ||
    fail "invalid aux mode token marker reason missing"
  grep -Fq 'detail: invalid auxiliary mode token --dangerously-bypass-approvals-and-sandbox; expected a sandboxed mode' "$last_message" ||
    fail "invalid aux mode token marker detail missing"
  grep -qx 'CODEX_POSTMORTEM_STATUS: BLOCKED' "$last_message" ||
    fail "blocked marker missing"
}

test_run_aux_codex_exec_rejects_extra_mode_token() {
  local prompt_file last_message rc

  prompt_file="$TEST_TMP_ROOT/prompt-extra-token.txt"
  last_message="$TEST_TMP_ROOT/last-message-extra-token.txt"
  : >"$prompt_file"

  CODEX_HOME_DIR="$TEST_TMP_ROOT/codex-home"
  CODEX_ARG0_TMP_ROOT="$TEST_TMP_ROOT/arg0"
  CODEX_ARG0_TMP_QUARANTINE_ROOT="$TEST_TMP_ROOT/arg0-quarantine"
  CODEX_BWRAP_TMP_ROOT="$TEST_TMP_ROOT/bwrap"
  UPKEEPER_DRY_RUN=1

  set +e
  run_aux_codex_exec "postmortem.report" "gpt-test" "low" "--sandbox workspace-write --foo=bar" "$prompt_file" "$last_message"
  rc=$?
  set -e

  [[ "$rc" -eq 87 ]] || fail "expected invalid aux extra token exit 87, got $rc"
  grep -qx 'reason: Codex auxiliary mode is invalid' "$last_message" ||
    fail "invalid aux extra token marker reason missing"
  grep -Fq 'detail: invalid auxiliary mode token --foo=bar; auxiliary mode only supports --sandbox workspace-write or --sandbox read-only' "$last_message" ||
    fail "invalid aux extra token marker detail missing"
  grep -qx 'CODEX_POSTMORTEM_STATUS: BLOCKED' "$last_message" ||
    fail "blocked marker missing"
}

test_run_aux_codex_exec_dry_run_accepts_normal_mode() {
  local prompt_file last_message rc

  prompt_file="$TEST_TMP_ROOT/prompt-dry-run.txt"
  last_message="$TEST_TMP_ROOT/last-message-dry-run.txt"
  : >"$prompt_file"

  UPKEEPER_DRY_RUN=1

  set +e
  run_aux_codex_exec "postmortem.report" "gpt-test" "low" "--sandbox workspace-write" "$prompt_file" "$last_message"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "expected dry-run aux mode exit 0, got $rc"
  [[ ! -e "$last_message" ]] || fail "dry-run should not write an aux blocked marker"
}

test_run_aux_codex_exec_dry_run_accepts_empty_mode() {
  local prompt_file last_message rc

  prompt_file="$TEST_TMP_ROOT/prompt-empty-mode.txt"
  last_message="$TEST_TMP_ROOT/last-message-empty-mode.txt"
  : >"$prompt_file"

  UPKEEPER_DRY_RUN=1

  set +e
  run_aux_codex_exec "postmortem.report" "gpt-test" "low" "" "$prompt_file" "$last_message"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "expected empty aux mode dry-run exit 0, got $rc"
  [[ ! -e "$last_message" ]] || fail "empty aux mode dry-run should not write an aux blocked marker"
}

test_run_aux_codex_exec_rejects_triple_dash_mode
test_run_aux_codex_exec_rejects_invalid_mode_token
test_run_aux_codex_exec_rejects_extra_mode_token
test_run_aux_codex_exec_dry_run_accepts_normal_mode
test_run_aux_codex_exec_dry_run_accepts_empty_mode
printf 'ok - aux_codex\n'
