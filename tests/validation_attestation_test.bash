#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tools/validation_attestation_lib.bash"

TEST_ROOT="$(mktemp -d /tmp/upkeeper-validation-attestation.XXXXXX)"
TEST_ARTIFACT_ROOT="$(mktemp -d /tmp/upkeeper-validation-attestation-artifact.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT" "$TEST_ARTIFACT_ROOT"' EXIT

fail() {
  printf 'validation_attestation_test: ERROR: %s\n' "$*" >&2
  exit 1
}

git -C "$TEST_ROOT" init -q -b main
git -C "$TEST_ROOT" config user.name 'Upkeeper Validation'
git -C "$TEST_ROOT" config user.email 'validation@example.invalid'
printf 'baseline\n' >"$TEST_ROOT/fixture.txt"
git -C "$TEST_ROOT" add fixture.txt
git -C "$TEST_ROOT" commit -q -m baseline

expected="$TEST_ARTIFACT_ROOT/expected.tsv"
results="$TEST_ARTIFACT_ROOT/results.tsv"
artifact="$TEST_ARTIFACT_ROOT/validation.json"
printf 'shell_syntax\tbash -n fixture.txt\n' >"$expected"
printf 'shell_syntax\tbash -n fixture.txt\tpass\t0\t12\n' >"$results"

upkeeper_validation_attestation_write "$TEST_ROOT" "$artifact" "$results" 12 'fixture-validation' >/dev/null
[[ "$(stat -c '%a' "$artifact")" == '600' ]] || fail 'artifact permissions were not private'
jq -e '
  .schema == "upkeeper.validation-attestation.v1" and
  .command == "fixture-validation" and .exit_status == 0 and
  (.duration_ms | type == "number") and (.timestamp | type == "string") and
  (.git_head | type == "string") and (.git_tree | type == "string") and
  (.worktree_fingerprint | type == "string") and
  (.input_hashes | type == "array" and length > 0) and
  (.tool_versions | type == "object") and
  (.phases == [{"command":"bash -n fixture.txt","duration_ms":12,"exit_status":0,"name":"shell_syntax","status":"pass"}])
' "$artifact" >/dev/null || fail 'artifact omitted required proof fields'
upkeeper_validation_attestation_load "$TEST_ROOT" "$artifact" "$expected" 'fixture-validation' ||
  fail "matching artifact rejected: $UPKEEPER_VALIDATION_ATTESTATION_REASON"

printf 'second revision\n' >>"$TEST_ROOT/fixture.txt"
git -C "$TEST_ROOT" add fixture.txt
git -C "$TEST_ROOT" commit -q -m second
if upkeeper_validation_attestation_load "$TEST_ROOT" "$artifact" "$expected" 'fixture-validation'; then
  fail 'stale git head was accepted'
fi
[[ "$UPKEEPER_VALIDATION_ATTESTATION_REASON" == 'git_head_mismatch' ]] ||
  fail "stale head rejection was $UPKEEPER_VALIDATION_ATTESTATION_REASON"

upkeeper_validation_attestation_write "$TEST_ROOT" "$artifact" "$results" 12 'fixture-validation' >/dev/null
printf 'shell_syntax\tbash -n another-command\n' >"$expected"
if upkeeper_validation_attestation_load "$TEST_ROOT" "$artifact" "$expected" 'fixture-validation'; then
  fail 'changed command was accepted'
fi
[[ "$UPKEEPER_VALIDATION_ATTESTATION_REASON" == 'command_mismatch' ]] ||
  fail "changed command rejection was $UPKEEPER_VALIDATION_ATTESTATION_REASON"

printf 'shell_syntax\tbash -n fixture.txt\n' >"$expected"
if CI=1 upkeeper_validation_attestation_load "$TEST_ROOT" "$artifact" "$expected" 'fixture-validation'; then
  fail 'different environment was accepted'
fi
[[ "$UPKEEPER_VALIDATION_ATTESTATION_REASON" == 'environment_mismatch' ]] ||
  fail "environment rejection was $UPKEEPER_VALIDATION_ATTESTATION_REASON"

printf 'broader tracked change\n' >"$TEST_ROOT/another-tracked-file.txt"
git -C "$TEST_ROOT" add another-tracked-file.txt
if upkeeper_validation_attestation_load "$TEST_ROOT" "$artifact" "$expected" 'fixture-validation'; then
  fail 'broader tracked change was accepted'
fi
[[ "$UPKEEPER_VALIDATION_ATTESTATION_REASON" == 'input_hashes_mismatch' ]] ||
  fail "broader-change rejection was $UPKEEPER_VALIDATION_ATTESTATION_REASON"

printf 'validation_attestation_test: ok\n'
