#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

TEST_ROOT="$(mktemp -d /tmp/upkeeper-diff-whitespace-test.XXXXXX)"
trap 'rm -r "$TEST_ROOT"' EXIT

fail() {
  printf 'diff_whitespace_validation_test: ERROR: %s\n' "$*" >&2
  exit 1
}

repo="$TEST_ROOT/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.name "Upkeeper Test"
git -C "$repo" config user.email "upkeeper-test@example.invalid"
mkdir -p "$repo/tools"
cp "$ROOT_DIR/tools/git_diff_validation.bash" "$repo/tools/"
cp "$ROOT_DIR/tools/run_validation_phases.sh" "$repo/tools/"
cp "$ROOT_DIR/tools/validation_attestation_lib.bash" "$repo/tools/"

run_fixture_phase() {
  (
    cd "$repo"
    # This fixture owns its Git history. CI exports these variables for the
    # outer checkout, which must not replace the fixture's default range.
    env -u UPKEEPER_VALIDATION_DIFF_BASE -u UPKEEPER_VALIDATION_DIFF_HEAD \
      bash tools/run_validation_phases.sh "$@"
  )
}

printf 'clean baseline\n' >"$repo/fixture.txt"
git -C "$repo" add fixture.txt
git -C "$repo" commit -q -m baseline
git -C "$repo" update-ref refs/remotes/origin/main HEAD
printf 'committed trailing whitespace  \n' >"$repo/fixture.txt"
git -C "$repo" add fixture.txt
git -C "$repo" commit -q -m bad-commit

# Deliberately model an outer CI range that is meaningless inside this private
# repository. Every fixture phase below must select only fixture-owned refs.
export UPKEEPER_VALIDATION_DIFF_BASE='outer-ci-base'
export UPKEEPER_VALIDATION_DIFF_HEAD='outer-ci-head'

set +e
bare_output="$(git -C "$repo" diff --check 2>&1)"
bare_rc=$?
ranged_output="$(run_fixture_phase --serial --phases diff_whitespace --diff-base HEAD^ --diff-head HEAD 2>&1)"
ranged_rc=$?
default_output="$(run_fixture_phase --serial --phases diff_whitespace 2>&1)"
default_rc=$?
set -e
[[ "$bare_rc" -eq 0 && -z "$bare_output" ]] || fail "bare clean-worktree diff unexpectedly found the committed defect"
[[ "$ranged_rc" -ne 0 ]] || fail "committed range accepted trailing whitespace"
grep -Fq 'fixture.txt:1: trailing whitespace.' <<<"$ranged_output" || fail "phase-runner committed-range diagnostic omitted the file"
[[ "$default_rc" -ne 0 ]] || fail "local feature-branch default accepted committed trailing whitespace"
grep -Fq 'fixture.txt:1: trailing whitespace.' <<<"$default_output" || fail "local feature-branch diagnostic omitted the file"

git -C "$repo" checkout -q HEAD^ -- fixture.txt
git -C "$repo" commit -qam clean-commit
run_fixture_phase --serial --phases diff_whitespace --diff-base HEAD^ --diff-head HEAD ||
  fail "phase runner rejected a clean committed range"

set +e
missing_output="$(run_fixture_phase --serial --phases diff_whitespace --diff-base does-not-exist --diff-head HEAD 2>&1)"
missing_rc=$?
set -e
[[ "$missing_rc" -ne 0 ]] || fail "missing base ref was accepted"
grep -Fq 'base ref is unavailable: does-not-exist' <<<"$missing_output" || fail "missing-base diagnostic was unclear"

printf 'unstaged trailing whitespace  \n' >"$repo/fixture.txt"
set +e
local_output="$(run_fixture_phase --serial --phases diff_whitespace --diff-base HEAD^ --diff-head HEAD 2>&1)"
local_rc=$?
set -e
[[ "$local_rc" -ne 0 ]] || fail "unstaged whitespace was accepted"
grep -Fq 'fixture.txt:1: trailing whitespace.' <<<"$local_output" || fail "local diagnostic omitted the file"

printf 'diff_whitespace_validation_test: ok\n'
