#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-backlog-parallel-leases.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run_lease() {
  set +e
  "$PROJECT_ROOT/tools/backlog_parallel_leases.py" \
    --root "$TEST_TMP_ROOT/main" \
    --state-root "$TEST_TMP_ROOT/state" \
    --now-epoch "$LEASE_NOW" \
    "$@" >"$TEST_TMP_ROOT/out.txt" 2>"$TEST_TMP_ROOT/err.txt"
  LEASE_RC="$?"
  set -e
  LEASE_OUT="$(cat "$TEST_TMP_ROOT/out.txt")"
  LEASE_ERR="$(cat "$TEST_TMP_ROOT/err.txt")"
}

assert_out_contains() {
  local needle="$1"
  grep -Fq "$needle" <<<"$LEASE_OUT" ||
    fail "missing output '$needle' in: $LEASE_OUT stderr=$LEASE_ERR"
}

mkdir -p "$TEST_TMP_ROOT/main" "$TEST_TMP_ROOT/worker-a" "$TEST_TMP_ROOT/worker-b" "$TEST_TMP_ROOT/worker-c"

LEASE_NOW=1000
run_lease claim \
  --worker-id worker-a \
  --issue-number 101 \
  --issue-title "First issue" \
  --target-file Upkeeper \
  --branch backlog/worker-a \
  --worktree "$TEST_TMP_ROOT/worker-a" \
  --model gpt-5.4-mini \
  --effort high \
  --ttl-seconds 100
[[ "$LEASE_RC" -eq 0 ]] || fail "initial claim exited $LEASE_RC"
assert_out_contains "lease_status=claimed"
assert_out_contains "issue_number=101"
assert_out_contains "target_file=Upkeeper"

run_lease claim \
  --worker-id worker-b \
  --issue-number 101 \
  --target-file lib/upkeeper/file_manifest.bash \
  --branch backlog/worker-b \
  --worktree "$TEST_TMP_ROOT/worker-b" \
  --ttl-seconds 100
[[ "$LEASE_RC" -eq 2 ]] || fail "same-issue conflict exited $LEASE_RC"
assert_out_contains "lease_status=conflict"
assert_out_contains "conflict_reason=issue"
assert_out_contains "owner_worker=worker-a"

run_lease claim \
  --worker-id worker-b \
  --issue-number 102 \
  --target-file Upkeeper \
  --branch backlog/worker-b \
  --worktree "$TEST_TMP_ROOT/worker-b" \
  --ttl-seconds 100
[[ "$LEASE_RC" -eq 2 ]] || fail "same-target conflict exited $LEASE_RC"
assert_out_contains "conflict_reason=target_file"
assert_out_contains "owner_issue=101"

run_lease claim \
  --worker-id worker-b \
  --issue-number 102 \
  --target-file lib/upkeeper/file_manifest.bash \
  --branch backlog/worker-b \
  --worktree "$TEST_TMP_ROOT/worker-b" \
  --ttl-seconds 100
[[ "$LEASE_RC" -eq 0 ]] || fail "independent claim exited $LEASE_RC"
assert_out_contains "lease_status=claimed"
assert_out_contains "issue_number=102"

run_lease claim \
  --worker-id worker-main \
  --issue-number 103 \
  --target-file tools/upkeeper_lattice.py \
  --branch backlog/worker-main \
  --worktree "$TEST_TMP_ROOT/main" \
  --ttl-seconds 100
[[ "$LEASE_RC" -eq 3 ]] || fail "main-worktree claim exited $LEASE_RC"
assert_out_contains "lease_status=blocked"
assert_out_contains "reason=worker_worktree_is_main_checkout"

LEASE_NOW=1201
run_lease claim \
  --worker-id worker-c \
  --issue-number 101 \
  --target-file Upkeeper \
  --branch backlog/worker-c \
  --worktree "$TEST_TMP_ROOT/worker-c" \
  --ttl-seconds 100
[[ "$LEASE_RC" -eq 0 ]] || fail "stale issue reclaim exited $LEASE_RC"
assert_out_contains "lease_status=claimed"
assert_out_contains "expired_count=2"

run_lease status
[[ "$LEASE_RC" -eq 0 ]] || fail "status exited $LEASE_RC"
assert_out_contains $'worker-c\tactive\t101'
assert_out_contains $'worker-a\texpired\t101'
assert_out_contains $'worker-b\texpired\t102'

run_lease release --worker-id worker-c --issue-number 101 --reason merged
[[ "$LEASE_RC" -eq 0 ]] || fail "release exited $LEASE_RC"
assert_out_contains "release_status=released"
assert_out_contains "reason=merged"

run_lease status --json
[[ "$LEASE_RC" -eq 0 ]] || fail "json status exited $LEASE_RC"
jq -e '.leases | map(select(.worker_id == "worker-c" and .status == "released" and .release_reason == "merged")) | length == 1' \
  <<<"$LEASE_OUT" >/dev/null ||
  fail "released worker lease missing from JSON status"

printf 'backlog_parallel_leases_test: ok\n'
