#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-backlog-parallel-leases.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run_lease_for_root() {
  local lease_root="$1"
  shift
  set +e
  "$PROJECT_ROOT/tools/backlog_parallel_leases.py" \
    --root "$lease_root" \
    --state-root "$TEST_TMP_ROOT/state" \
    --now-epoch "$LEASE_NOW" \
    "$@" >"$TEST_TMP_ROOT/out.txt" 2>"$TEST_TMP_ROOT/err.txt"
  LEASE_RC="$?"
  set -e
  LEASE_OUT="$(cat "$TEST_TMP_ROOT/out.txt")"
  LEASE_ERR="$(cat "$TEST_TMP_ROOT/err.txt")"
}

run_lease() {
  run_lease_for_root "$TEST_TMP_ROOT/main" "$@"
}

assert_out_contains() {
  local needle="$1"
  grep -Fq "$needle" <<<"$LEASE_OUT" ||
    fail "missing output '$needle' in: $LEASE_OUT stderr=$LEASE_ERR"
}

mkdir -p \
  "$TEST_TMP_ROOT/main" \
  "$TEST_TMP_ROOT/other-main" \
  "$TEST_TMP_ROOT/worker-a" \
  "$TEST_TMP_ROOT/worker-b" \
  "$TEST_TMP_ROOT/worker-c" \
  "$TEST_TMP_ROOT/other-worker-a" \
  "$TEST_TMP_ROOT/other-worker-b"

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

run_lease_for_root "$TEST_TMP_ROOT/other-main" claim \
  --worker-id worker-a \
  --issue-number 101 \
  --target-file Upkeeper \
  --branch backlog/other-worker-a \
  --worktree "$TEST_TMP_ROOT/other-worker-a" \
  --ttl-seconds 100
[[ "$LEASE_RC" -eq 0 ]] || fail "cross-repo same-worker/issue claim exited $LEASE_RC"
assert_out_contains "lease_status=claimed"

run_lease status --json
[[ "$LEASE_RC" -eq 0 ]] || fail "cross-repo status exited $LEASE_RC"
jq -e --arg main "$TEST_TMP_ROOT/main" --arg other "$TEST_TMP_ROOT/other-main" '
  [.leases[] | select(.status == "active" and .worker_id == "worker-a" and .issue_number == "101")] as $matching
  | ($matching | length) == 2
    and ($matching | any((.root == $main) and (.worktree | endswith("/worker-a"))))
    and ($matching | any((.root == $other) and (.worktree | endswith("/other-worker-a"))))
' <<<"$LEASE_OUT" >/dev/null ||
  fail "cross-repo claim renewed or overwrote the original lease"

run_lease_for_root "$TEST_TMP_ROOT/other-main" claim \
  --worker-id other-worker-b \
  --issue-number 101 \
  --target-file lib/upkeeper/file_manifest.bash \
  --branch backlog/other-worker-b \
  --worktree "$TEST_TMP_ROOT/other-worker-b" \
  --ttl-seconds 100
[[ "$LEASE_RC" -eq 2 ]] || fail "same-repo issue conflict in second repo exited $LEASE_RC"
assert_out_contains "conflict_reason=issue"
assert_out_contains "owner_worker=worker-a"

run_lease_for_root "$TEST_TMP_ROOT/other-main" release \
  --worker-id worker-a \
  --issue-number 101 \
  --reason cross-repo-test-complete
[[ "$LEASE_RC" -eq 0 ]] || fail "cross-repo scoped release exited $LEASE_RC"
assert_out_contains "release_status=released"

run_lease status --json
[[ "$LEASE_RC" -eq 0 ]] || fail "post-release scoped status exited $LEASE_RC"
jq -e --arg main "$TEST_TMP_ROOT/main" --arg other "$TEST_TMP_ROOT/other-main" '
  (.leases | any(.root == $main and .worker_id == "worker-a" and .status == "active"))
  and (.leases | any(.root == $other and .worker_id == "worker-a" and .status == "released"))
' <<<"$LEASE_OUT" >/dev/null ||
  fail "cross-repo release changed the wrong repository lease"

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

registry_file="$TEST_TMP_ROOT/state/parallel-workers/leases.json"
printf '{not-json\n' >"$registry_file"
corrupt_before="$(sha256sum "$registry_file")"
run_lease status --json
[[ "$LEASE_RC" -eq 4 ]] || fail "decode-corrupt registry did not fail closed: $LEASE_RC"
assert_out_contains "lease_status=blocked"
assert_out_contains "reason=registry_json_invalid"
[[ "$(sha256sum "$registry_file")" == "$corrupt_before" ]] ||
  fail "decode-corrupt registry was rewritten"

printf '{"schema":1,"leases":{}}\n' >"$registry_file"
shape_before="$(sha256sum "$registry_file")"
run_lease status --json
[[ "$LEASE_RC" -eq 4 ]] || fail "shape-invalid registry did not fail closed: $LEASE_RC"
assert_out_contains "reason=registry_shape_invalid"
[[ "$(sha256sum "$registry_file")" == "$shape_before" ]] ||
  fail "shape-invalid registry was rewritten"

printf 'backlog_parallel_leases_test: ok\n'
