#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-recovery-defaults.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'recovery_default_policy_test: ERROR: %s\n' "$*" >&2
  exit 1
}

run_policy_case() {
  local config_file="$1"
  shift

  env \
    -u CODEX_FALLBACK_ON_PRIMARY_QUOTA \
    -u CODEX_FALLBACK_ON_NO_OUTPUT \
    -u CODEX_FALLBACK_ON_FAILURE \
    -u CODEX_FALLBACK_ON_BLOCKED \
    -u CODEX_FALLBACK_ON_DIRTY_NO_BACKEND_TASK \
    -u CODEX_POSTMORTEM_ENABLED \
    HOME="$TEST_TMP_ROOT/home" \
    XDG_CONFIG_HOME="$TEST_TMP_ROOT/config" \
    UPKEEPER_CONFIG_FILE="$config_file" \
    UPKEEPER_LOCAL_ENV_DISABLE=1 \
    CODEX_LOG_FILE="$TEST_TMP_ROOT/Upkeeper.log" \
    "$@" \
    bash -c '
      source "$1/Upkeeper"
      missing_status=0
      explicit_failure=0
      quota=0
      blocked=0
      dirty=0
      fallback_failure_trigger_enabled "" && missing_status=1
      fallback_failure_trigger_enabled "BACKEND_ERROR" && explicit_failure=1
      fallback_trigger_enabled primary_quota_after_run && quota=1
      fallback_trigger_enabled blocked && blocked=1
      fallback_trigger_enabled dirty_no_backend_task && dirty=1
      printf "%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n" \
        "$CODEX_FALLBACK_ON_PRIMARY_QUOTA" \
        "$CODEX_FALLBACK_ON_NO_OUTPUT" \
        "$CODEX_FALLBACK_ON_FAILURE" \
        "$CODEX_FALLBACK_ON_BLOCKED" \
        "$CODEX_FALLBACK_ON_DIRTY_NO_BACKEND_TASK" \
        "$CODEX_POSTMORTEM_ENABLED" \
        "$missing_status" \
        "$explicit_failure" \
        "$quota" \
        "$blocked" \
        "$dirty"
    ' bash "$PROJECT_ROOT"
}

assert_policy() {
  local label="$1"
  local expected="$2"
  shift 2
  local actual

  actual="$(run_policy_case "$@")" || fail "$label fixture failed"
  [[ "$actual" == "$expected" ]] ||
    fail "$label policy expected $expected, got $actual"
}

expected_default=$'1\t1\t0\t0\t0\t0\t1\t0\t1\t0\t0'
assert_policy "central defaults" "$expected_default" "$PROJECT_ROOT/Upkeeper.conf"
profile_defaults="$(
  env \
    -u CODEX_FALLBACK_ON_PRIMARY_QUOTA \
    -u CODEX_FALLBACK_ON_NO_OUTPUT \
    -u CODEX_FALLBACK_ON_FAILURE \
    -u CODEX_FALLBACK_ON_BLOCKED \
    -u CODEX_FALLBACK_ON_DIRTY_NO_BACKEND_TASK \
    -u CODEX_POSTMORTEM_ENABLED \
    bash -c '
      source "$1"
      printf "%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n" \
        "$CODEX_FALLBACK_ON_PRIMARY_QUOTA" \
        "$CODEX_FALLBACK_ON_NO_OUTPUT" \
        "$CODEX_FALLBACK_ON_FAILURE" \
        "$CODEX_FALLBACK_ON_BLOCKED" \
        "$CODEX_FALLBACK_ON_DIRTY_NO_BACKEND_TASK" \
        "$CODEX_POSTMORTEM_ENABLED"
    ' bash "$PROJECT_ROOT/configurations/default.conf"
)"
[[ "$profile_defaults" == $'1\t1\t0\t0\t0\t0' ]] ||
  fail "named default profile policy changed: $profile_defaults"

expected_override=$'1\t1\t1\t1\t1\t1\t1\t1\t1\t1\t1'
assert_policy \
  "explicit recovery override" \
  "$expected_override" \
  "$PROJECT_ROOT/Upkeeper.conf" \
  CODEX_FALLBACK_ON_FAILURE=1 \
  CODEX_FALLBACK_ON_BLOCKED=1 \
  CODEX_FALLBACK_ON_DIRTY_NO_BACKEND_TASK=1 \
  CODEX_POSTMORTEM_ENABLED=1

printf 'recovery_default_policy_test: ok\n'
