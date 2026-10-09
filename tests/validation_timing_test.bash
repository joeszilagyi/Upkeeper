#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tools/validation_timing_lib.bash"

TEST_ROOT="$(mktemp -d /tmp/upkeeper-validation-timing-test.XXXXXX)"
trap 'rm -r "$TEST_ROOT"' EXIT

fail_test() {
  printf 'validation_timing_test: ERROR: %s\n' "$*" >&2
  exit 1
}

fixture_pass() {
  printf 'pass fixture\n' >/dev/null
}

fixture_fail() {
  return 23
}

fixture_timeout() {
  bash -c 'sleep 30 & printf "%s\n" "$!" >"$1"; wait' bash \
    "$TEST_ROOT/timeout-grandchild.pid" &
  printf '%s\n' "$!" >"$TEST_ROOT/timeout-child.pid"
  wait
}

artifact="$TEST_ROOT/timing.jsonl"
validation_timing_initialize quick "$ROOT_DIR" "$artifact" 1 >/dev/null

validation_run_check pass_fixture 0 fixture_pass

set +e
validation_run_check fail_fixture 0 fixture_fail
rc=$?
set -e
[[ "$rc" -eq 23 ]] || fail_test "failure fixture exited $rc, expected 23"

set +e
validation_run_check timeout_fixture 1 fixture_timeout 2>"$TEST_ROOT/timeout.err"
rc=$?
set -e
[[ "$rc" -eq 124 ]] || fail_test "timeout fixture exited $rc, expected 124"
timeout_child="$(<"$TEST_ROOT/timeout-child.pid")"
timeout_grandchild="$(<"$TEST_ROOT/timeout-grandchild.pid")"
if kill -0 "$timeout_child" 2>/dev/null; then
  fail_test "timeout fixture left child $timeout_child running"
fi
if kill -0 "$timeout_grandchild" 2>/dev/null; then
  fail_test "timeout fixture left grandchild $timeout_grandchild running"
fi
grep -Fq 'check timeout_fixture exceeded 1s timeout; command=fixture_timeout cleanup=process_tree_term_kill artifact=' \
  "$TEST_ROOT/timeout.err" || fail_test "timeout diagnostic did not name the check and cleanup"

validation_timing_record_skip full_only_checks mode_quick tools/validate_upkeeper.sh --full
validation_timing_finish 0

python3 - "$artifact" <<'PY'
import json
import sys

path = sys.argv[1]
rows = [json.loads(line) for line in open(path, encoding="utf-8")]
by_check = {row["check"]: row for row in rows}

expected = {
    "pass_fixture": ("pass", 0),
    "fail_fixture": ("fail", 23),
    "timeout_fixture": ("timeout", 124),
    "full_only_checks": ("skipped", 0),
    "__run__": ("pass", 0),
}
for check, (status, exit_code) in expected.items():
    row = by_check.get(check)
    if row is None:
        raise SystemExit(f"missing timing row: {check}")
    if row["status"] != status or row["exit_code"] != exit_code:
        raise SystemExit(f"bad timing result for {check}: {row}")
    for key in ("mode", "git_head", "git_tree", "command", "duration_ms"):
        if key not in row:
            raise SystemExit(f"{check} missing {key}")

timeout = by_check["timeout_fixture"]
if timeout["cleanup"] != "process_tree_term_kill" or timeout["timeout_seconds"] != 1:
    raise SystemExit(f"timeout cleanup evidence missing: {timeout}")
if by_check["full_only_checks"]["reason"] != "mode_quick":
    raise SystemExit("skip reason missing")
PY

# Prove that an early dependency failure still writes a machine-readable row.
minimal_bin="$TEST_ROOT/minimal-bin"
mkdir -p "$minimal_bin"
for command_name in bash chmod cp date diff dirname find git grep ln mkdir mktemp python3 rm sed sort touch tr uname wc ps sleep; do
  command_path="$(command -v "$command_name")"
  ln -s "$command_path" "$minimal_bin/$command_name"
done
early_artifact="$TEST_ROOT/early-dependency.jsonl"
set +e
PATH="$minimal_bin" \
  UPKEEPER_VALIDATION_TIMING_FILE="$early_artifact" \
  /bin/bash "$ROOT_DIR/tools/validate_upkeeper.sh" --quick \
  >"$TEST_ROOT/early.out" 2>"$TEST_ROOT/early.err"
rc=$?
set -e
[[ "$rc" -eq 1 ]] || fail_test "early dependency fixture exited $rc, expected 1"
grep -Fq 'missing required command: jq' "$TEST_ROOT/early.err" || \
  fail_test "early dependency fixture did not report missing jq"
python3 - "$early_artifact" <<'PY'
import json
import sys

rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
dependency = next((row for row in rows if row["check"] == "dependency_preflight"), None)
if dependency is None or dependency["status"] != "fail" or dependency["exit_code"] != 1:
    raise SystemExit(f"missing early dependency failure timing: {dependency}")
PY

printf 'validation_timing_test: ok\n'
