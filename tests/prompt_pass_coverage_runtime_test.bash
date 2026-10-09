#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-pass-coverage-runtime.XXXXXX")"
trap 'rm -r "$TEST_ROOT"' EXIT

fail() {
  printf 'prompt_pass_coverage_runtime_test: ERROR: %s\n' "$*" >&2
  exit 1
}

complete_message="$TEST_ROOT/complete.txt"
incomplete_message="$TEST_ROOT/incomplete.txt"
missing_message="$TEST_ROOT/missing.txt"

for ((pass_number = 1; pass_number <= 23; pass_number++)); do
  printf 'UPKEEPER_PASS_RESULT: pass=P%s file=Upkeeper applicable=1 outcome=clean changed=0 regression=0\n' \
    "$pass_number" >>"$complete_message"
done
printf 'UPKEEPER_PASS_RESULT: pass=P1 file=Upkeeper applicable=1 outcome=clean changed=0 regression=0\n' \
  >"$incomplete_message"

run_case() {
  local name="$1"
  local message_file="$2"
  local output_file="$TEST_ROOT/$name.out"
  local log_file="$TEST_ROOT/$name.log"

  CODEX_TERMINAL_VERBOSITY=silent CODEX_PROMPT_PASS=all \
    bash -c 'cd "$1"; source ./Upkeeper; LOG_FILE="$2"; \
      status_marker="WORK_DONE"; status_marker_source="exact"; codex_exit=0; \
      prompt_pass_enforce_coverage_status "$3" "$codex_exit"; \
      printf "%s\t%s\n" "$status_marker" "$status_marker_source"' \
      bash "$ROOT_DIR" "$log_file" "$message_file" >"$output_file"
}

run_case complete "$complete_message"
grep -Fxq $'WORK_DONE\texact' "$TEST_ROOT/complete.out" ||
  fail "complete coverage changed the runtime status"
if [[ -f "$TEST_ROOT/complete.log" ]] &&
    grep -Fq 'status_marker.overridden_for_prompt_pass_coverage' "$TEST_ROOT/complete.log"; then
  fail "complete coverage logged a status override"
fi

run_case incomplete "$incomplete_message"
grep -Fxq $'BLOCKED\tprompt_pass_coverage' "$TEST_ROOT/incomplete.out" ||
  fail "incomplete coverage did not force BLOCKED"
grep -Fq 'status_marker.overridden_for_prompt_pass_coverage marker=BLOCKED codex_exit=0 coverage_gate_rc=2' \
  "$TEST_ROOT/incomplete.log" || fail "incomplete coverage lost gate status 2"

run_case unavailable "$missing_message"
grep -Fxq $'BLOCKED\tprompt_pass_coverage' "$TEST_ROOT/unavailable.out" ||
  fail "unavailable coverage did not force BLOCKED"
grep -Fq 'status_marker.overridden_for_prompt_pass_coverage marker=BLOCKED codex_exit=0 coverage_gate_rc=3' \
  "$TEST_ROOT/unavailable.log" || fail "unavailable coverage lost gate status 3"

printf 'prompt_pass_coverage_runtime_test: ok\n'
