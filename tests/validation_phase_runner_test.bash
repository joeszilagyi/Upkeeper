#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/upkeeper-validation-phase-runner.XXXXXX)"
ARTIFACT_ROOT="$(mktemp -d /tmp/upkeeper-validation-phase-artifact.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT" "$ARTIFACT_ROOT"' EXIT

fail() {
  printf 'validation_phase_runner_test: ERROR: %s\n' "$*" >&2
  exit 1
}

repo="$TEST_ROOT/repo"
mkdir -p "$repo/tools"
cp "$ROOT_DIR/tools/run_validation_phases.sh" "$repo/tools/"
cp "$ROOT_DIR/tools/validation_attestation_lib.bash" "$repo/tools/"
cp "$ROOT_DIR/tools/git_diff_validation.bash" "$repo/tools/"
git -C "$repo" init -q -b main
git -C "$repo" config user.name 'Upkeeper Validation'
git -C "$repo" config user.email 'validation@example.invalid'
printf 'baseline\n' >"$repo/fixture.txt"
git -C "$repo" add .
git -C "$repo" commit -q -m baseline
git -C "$repo" update-ref refs/remotes/origin/main HEAD
printf 'clean committed change\n' >"$repo/fixture.txt"
git -C "$repo" add fixture.txt
git -C "$repo" commit -q -m clean-change

artifact="$ARTIFACT_ROOT/validation.json"
run_phase() {
  (
    cd "$repo"
    UPKEEPER_VALIDATION_ATTESTATION_FILE="$artifact" \
      bash tools/run_validation_phases.sh --serial --phases diff_whitespace --diff-base HEAD^ --diff-head HEAD
  )
}

first_output="$(run_phase 2>&1)" || fail "initial phase run failed: $first_output"
grep -Fq 'validation_reuse_rejected' <<<"$first_output" ||
  fail 'initial artifact did not fail closed to a rerun'
grep -Fq 'validation_attestation: wrote=' <<<"$first_output" ||
  fail 'initial phase run did not write proof'

second_output="$(run_phase 2>&1)" || fail "same-input phase run failed: $second_output"
grep -Fq 'validation_reused command=tools/run_validation_phases.sh' <<<"$second_output" ||
  fail 'same-input phase run did not reuse proof'
grep -Fq 'PHASE diff_whitespace status=reused rc=0' <<<"$second_output" ||
  fail 'same-input phase output did not identify reused phase'

changed_command_output="$(
  cd "$repo"
  UPKEEPER_VALIDATION_ATTESTATION_FILE="$artifact" \
    bash tools/run_validation_phases.sh --serial --phases diff_whitespace --diff-base HEAD --diff-head HEAD 2>&1
)" || fail "changed-command rerun failed: $changed_command_output"
grep -Fq 'validation_reuse_rejected command=tools/run_validation_phases.sh' <<<"$changed_command_output" ||
  fail 'changed phase command did not reject proof'
grep -Fq 'reason=command_mismatch' <<<"$changed_command_output" ||
  fail 'changed phase command did not report command mismatch'

printf 'validation_phase_runner_test: ok\n'
