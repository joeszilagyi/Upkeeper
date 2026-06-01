#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source lib/upkeeper/review_modules.bash
source lib/upkeeper/codex_io.bash

TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-task-profile-test.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP_ROOT"' EXIT

LOG_FILE="$TEST_TMP_ROOT/upkeeper.log"

shell_quote() {
  printf '%q' "$1"
}

log_line() {
  local level="$1"
  shift
  printf '[%s] %s\n' "$level" "$*" >>"$LOG_FILE"
}

reset_profile_state() {
  CODEX_ATTEMPT_ROLE="primary"
  CODEX_FALLBACK_TRIGGER=""
  CODEX_REASONING_EFFORT="xhigh"
  CODEX_MODEL_OVERRIDE_APPLIED="0"
  CODEX_PROMPT_PASS=""
  UPKEEPER_TASK_PROFILE_ENABLED="1"
  UPKEEPER_TASK_PROFILE_AUTO_EFFORT="1"
  UPKEEPER_TASK_PROFILE_AUTO_MODULES="1"
  UPKEEPER_TASK_PROFILE_GRADE=""
  UPKEEPER_TASK_PROFILE_VALIDATION_GRADE=""
  UPKEEPER_TASK_PROFILE_PROMPT_SCOPE=""
  UPKEEPER_TASK_PROFILE_PROMPT_PASS=""
  CODEX_REVIEW_MODULES_FROM_CONFIG="0"
  CODEX_REVIEW_MODULES_CLI_OVERRIDE="0"
  CODEX_REVIEW_MODULES=()
  : >"$LOG_FILE"
}

fail() {
  printf 'task_profile_test: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

reset_profile_state
CODEX_REVIEW_MODULES=(p24 p26)
CODEX_REVIEW_MODULES_FROM_CONFIG="1"
upkeeper_apply_task_profile "tests/task_profile_test.bash"
assert_eq "trivial-code" "$UPKEEPER_TASK_PROFILE_GRADE" "routine test grade"
assert_eq "focused" "$UPKEEPER_TASK_PROFILE_VALIDATION_GRADE" "routine validation grade"
assert_eq "lean" "$UPKEEPER_TASK_PROFILE_PROMPT_SCOPE" "routine prompt scope"
assert_eq "default" "$UPKEEPER_TASK_PROFILE_PROMPT_PASS" "routine prompt pass"
assert_eq "medium" "$CODEX_REASONING_EFFORT" "routine effort"
assert_eq "0" "${#CODEX_REVIEW_MODULES[@]}" "routine config modules pruned"
grep -Fq "task.profile grade=trivial-code" "$LOG_FILE" || fail "routine profile was not logged"
grep -Fq "modules_action=pruned_config_modules_for_lean_profile" "$LOG_FILE" || fail "routine module pruning was not logged"

reset_profile_state
CODEX_MODEL_OVERRIDE_APPLIED="1"
upkeeper_apply_task_profile "tests/task_profile_test.bash"
assert_eq "xhigh" "$CODEX_REASONING_EFFORT" "model override should preserve explicit effort"

reset_profile_state
CODEX_REVIEW_MODULES=(p24)
CODEX_REVIEW_MODULES_CLI_OVERRIDE="1"
upkeeper_apply_task_profile "tests/task_profile_test.bash"
assert_eq "1" "${#CODEX_REVIEW_MODULES[@]}" "CLI-requested modules should be preserved"

reset_profile_state
upkeeper_apply_task_profile "lib/upkeeper/precontact_backup.bash"
assert_eq "contract-security" "$UPKEEPER_TASK_PROFILE_GRADE" "precontact backup grade"
assert_eq "full" "$UPKEEPER_TASK_PROFILE_VALIDATION_GRADE" "precontact validation grade"
assert_eq "full" "$UPKEEPER_TASK_PROFILE_PROMPT_SCOPE" "precontact prompt scope"
assert_eq "xhigh" "$CODEX_REASONING_EFFORT" "precontact effort"

reset_profile_state
upkeeper_apply_task_profile "docs/scripts/upkeeper.md"
assert_eq "docs-only" "$UPKEEPER_TASK_PROFILE_GRADE" "docs grade"
assert_eq "docs-only" "$UPKEEPER_TASK_PROFILE_VALIDATION_GRADE" "docs validation grade"
assert_eq "lean" "$UPKEEPER_TASK_PROFILE_PROMPT_SCOPE" "docs prompt scope"
assert_eq "low" "$CODEX_REASONING_EFFORT" "docs effort"

printf 'task_profile_test: ok\n'
