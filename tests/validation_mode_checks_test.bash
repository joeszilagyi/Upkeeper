#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'validation_mode_checks_test: ERROR: %s\n' "$*" >&2
  exit 1
}

declare -a RECORDED_CHECKS=()
declare -a RECORDED_SKIPS=()
VALIDATION_INTEGRATION_TIMEOUT_SECONDS=300
VALIDATION_FULL_TIMEOUT_SECONDS=420
VALIDATION_FILE_MANIFEST_TIMEOUT_SECONDS=600

run_bounded_check() {
  RECORDED_CHECKS+=("$1:$2:$3")
}

validation_timing_record_skip() {
  RECORDED_SKIPS+=("$*")
}

source "$ROOT_DIR/tools/validation_mode_checks.bash"

run_validation_mode_checks quick || fail "quick mode dispatch failed"
[[ "${#RECORDED_CHECKS[@]}" -eq 0 ]] || fail "quick mode unexpectedly ran bounded checks"
[[ "${RECORDED_SKIPS[*]}" == *"integration_checks mode_quick tools/validate_upkeeper.sh --full"* ]] ||
  fail "quick mode did not record the integration skip"

RECORDED_CHECKS=()
RECORDED_SKIPS=()
run_validation_mode_checks full || fail "full mode dispatch failed"
[[ "${#RECORDED_SKIPS[@]}" -eq 0 ]] || fail "full mode unexpectedly recorded an integration skip"
[[ "${#RECORDED_CHECKS[@]}" -eq 34 ]] ||
  fail "full mode ran ${#RECORDED_CHECKS[@]} checks, expected 34"
[[ "${RECORDED_CHECKS[0]}" == "review_module_flags:300:check_review_module_flags" ]] ||
  fail "full mode did not begin with the integration checks"
[[ "${RECORDED_CHECKS[26]}" == "fallback_artifact_helpers:300:check_fallback_artifact_helpers" ]] ||
  fail "full mode integration boundary moved"
[[ "${RECORDED_CHECKS[27]}" == "central_dry_runs:300:check_central_dry_runs" ]] ||
  fail "full-only checks did not follow the integration checks"
[[ "${RECORDED_CHECKS[33]}" == "stress_corpus_harness:420:check_stress_corpus_harness" ]] ||
  fail "full mode did not retain the final full-only check"

set +e
unsupported_output="$(run_validation_mode_checks smoke 2>&1)"
unsupported_rc=$?
set -e
[[ "$unsupported_rc" -eq 2 ]] || fail "unsupported mode exited $unsupported_rc, expected 2"
grep -Fq 'unsupported mode: smoke' <<<"$unsupported_output" ||
  fail "unsupported mode did not report a specific diagnostic"

# The production caller invokes the dispatcher as a plain command under
# errexit. A failing bounded check must stop dispatch immediately instead of
# being hidden by a later successful check.
set +e
failure_output="$(
  (
    set -e
    run_bounded_check() {
      [[ "$1" == "review_module_flags" ]] || exit 92
      printf 'forced dispatch failure\n' >&2
      return 91
    }
    run_validation_mode_checks full
    printf 'unexpected successful dispatch\n'
    exit 0
  ) 2>&1
)"
failure_rc=$?
set -e
[[ "$failure_rc" -eq 91 ]] || fail "bounded-check failure exited $failure_rc, expected 91"
grep -Fq 'forced dispatch failure' <<<"$failure_output" ||
  fail "bounded-check failure did not retain its diagnostic"
if grep -Fq 'unexpected successful dispatch' <<<"$failure_output"; then
  fail "bounded-check failure was masked by later dispatch"
fi

printf 'validation_mode_checks_test: ok\n'
