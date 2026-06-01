#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source lib/upkeeper/review_modules.bash
source lib/upkeeper/prompt_pruning.bash

TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-prompt-compile-test.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP_ROOT"' EXIT

RUN_TMP_DIR="$TEST_TMP_ROOT/run"
LOG_FILE="$TEST_TMP_ROOT/upkeeper.log"
UPKEEPER_IMPLEMENTATION_DIR="$ROOT_DIR"
UPKEEPER_TASK_PROFILE_ENABLED="1"
UPKEEPER_TASK_PROFILE_GRADE="trivial-code"
UPKEEPER_TASK_PROFILE_VALIDATION_GRADE="focused"
UPKEEPER_TASK_PROFILE_PROMPT_SCOPE="lean"
UPKEEPER_TASK_PROFILE_PROMPT_PASS="default"
UPKEEPER_TASK_PROFILE_PROMPT_PASS_SCOPE="targeted"
UPKEEPER_PROMPT_PAYLOAD_METRICS="1"
UPKEEPER_LEAN_TARGET_BLOCK_MAX_BYTES="200"
CODEX_PROMPT_PASS=""
CODEX_REVIEW_MODULES=()
CODEX_TARGET_FILE="tests/prompt_compile_profile_test.bash"
CYCLE_ID="prompt-profile-test-cycle"
SCRIPT_NAME="Upkeeper"
PROMPT_FILE=""
INLINE_PROMPT=""
PREVIOUS_RUN_ANOMALIES=""
DISK_SPACE_PROMPT_NOTE=""

mkdir -p "$RUN_TMP_DIR"
: >"$LOG_FILE"

config_truthy() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
  esac
  return 1
}

shell_quote() {
  printf '%q' "$1"
}

log_line() {
  local level="$1"
  shift
  printf '[%s] %s\n' "$level" "$*" >>"$LOG_FILE"
}

log_line_parts() {
  log_line "$@"
}

finish_cycle() {
  printf 'prompt_compile_profile_test: unexpected finish_cycle: %s\n' "$*" >&2
  exit 99
}

ensure_run_tmp_dir() {
  mkdir -p "$RUN_TMP_DIR"
}

run_mktemp() {
  local stem="${1:-tmp}"
  mktemp "$RUN_TMP_DIR/${stem}.XXXXXX"
}

truthy_as_int() {
  if config_truthy "${1:-0}"; then
    printf '1'
  else
    printf '0'
  fi
}

upkeeper_apply_task_profile() {
  return 0
}

append_preselected_review_target() {
  local compiled_file="$1"
  {
    printf 'WRAPPER_PRESELECTED_REVIEW_TARGET\n'
    printf 'path=tests/prompt_compile_profile_test.bash\n'
    printf 'selection_basis=test\n'
    printf 'padding=%s\n' "$(printf 'x%.0s' {1..800})"
    printf '\nRules for this preselected target:\n'
    printf -- '- Stub target block for prompt profile test.\n'
  } >>"$compiled_file"
}

upkeeper_issue_fix_next_enabled() {
  return 1
}

upkeeper_bug_report_only_enabled() {
  return 1
}

source lib/upkeeper/prompt_compile.bash

fail() {
  printf 'prompt_compile_profile_test: %s\n' "$*" >&2
  exit 1
}

compiled_file="$TEST_TMP_ROOT/compiled.md"
compile_prompt "$compiled_file"

grep -Fq 'WRAPPER_LEAN_REVIEW_PROMPT' "$compiled_file" ||
  fail "lean prompt profile was not emitted"
! grep -Fq 'Background Review Prompt Repertoire' "$compiled_file" ||
  fail "lean prompt included the full default doctrine"
grep -Fq 'WRAPPER_TARGET_BLOCK_TRUNCATED' "$compiled_file" ||
  fail "lean target block was not truncated under the test cap"
grep -Fq 'prompt_pass_scope=targeted' "$compiled_file" ||
  fail "task profile context does not include prompt pass scope"
grep -Fq 'UPKEEPER_INTERNAL_CURRENT_CYCLE_LOG_REVIEW=1' "$compiled_file" ||
  fail "compiled prompt does not use the sanitized log-review helper"
! grep -Fq 'Recommended compute command (for digest)' "$compiled_file" ||
  fail "compiled prompt still exposes raw log digest command"
grep -Fq 'review.prompt_section section=default_review' "$LOG_FILE" ||
  fail "prompt section metrics were not logged"
grep -Fq 'review.prompt_payload final_bytes=' "$LOG_FILE" ||
  fail "prompt payload summary was not logged"

printf 'prompt_compile_profile_test: ok\n'
