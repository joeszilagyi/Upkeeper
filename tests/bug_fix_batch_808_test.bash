#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-bug-fix-808.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT
source "$PROJECT_ROOT/lib/upkeeper/runtime_foundation.bash"
source "$PROJECT_ROOT/lib/upkeeper/config_validation.bash"
source "$PROJECT_ROOT/lib/upkeeper/log_rotation.bash"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_rotate_wrapper_log_if_needed_returns_cleanly() {
  local root log_file before_content after_content output status
  local expected_int expected_term expected_hup

  root="$TEST_TMP_ROOT/issue-808"
  mkdir -p "$root"
  log_file="$root/Upkeeper.log"
  before_content="2026-06-05T14:00:00-0700 seed"
  printf '%s\n' "$before_content" >"$log_file"

  LOG_FILE="$log_file"
  LOG_FILE_DIR="$root"
  LOG_FILE_NAME="Upkeeper.log"
  LOG_ARCHIVE_GLOB="Upkeeper.log.*.zip"
  ROOT_DIR="$root"
  CYCLE_ID="cycle-808"
  CYCLE_RUN_HASH="run-808"
  CODEX_LOG_ROTATE_AFTER_HOURS=0
  CODEX_LOG_ROTATE_KEEP_HOURS=144

  trap ':' INT TERM HUP
  log_rotation_store_marker "$(log_rotation_marker_path)" "$(log_rotation_marker_expected)"
  expected_int="$(trap -p INT)"
  expected_term="$(trap -p TERM)"
  expected_hup="$(trap -p HUP)"

  set +e
  output="$(rotate_wrapper_log_if_needed 2>&1)"
  status=$?
  set -e

  [[ "$status" -eq 0 ]] || fail "rotate_wrapper_log_if_needed returned $status"
  [[ -z "$output" ]] || fail "unexpected rotation output: $output"
  [[ "$(trap -p INT)" == "$expected_int" ]] || fail "INT trap was not restored"
  [[ "$(trap -p TERM)" == "$expected_term" ]] || fail "TERM trap was not restored"
  [[ "$(trap -p HUP)" == "$expected_hup" ]] || fail "HUP trap was not restored"

  after_content="$(<"$log_file")"
  [[ "$after_content" == "$before_content" ]] || fail "log file content changed"

  if find "$root" -maxdepth 1 -type f \( -name 'Upkeeper.log.rotation.*' -o -name 'Upkeeper.log.*.zip' \) | grep -q .; then
    fail "rotation temp or archive artifacts were left behind"
  fi
}

test_rotate_wrapper_log_if_needed_returns_cleanly

printf 'bug_fix_batch_808_test: ok\n'
