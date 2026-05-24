#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-backlog-triage.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

repo_key() {
  printf '%s\n' "$1" | tr '/: ' '___' | tr -cd '[:alnum:]_.-'
}

make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git checkout -q -B main
    git config user.name "Backlog Triage Test"
    git config user.email "triage@example.invalid"
    printf 'hello\n' >README.md
    printf 'runtime/\n' >.gitignore
    git add README.md .gitignore
    git commit -q -m init
  )
}

run_triage() {
  local repo="$1"
  local state_root="$2"
  local log_file="$3"
  shift 3

  set +e
  "$PROJECT_ROOT/tools/backlog_triage.py" \
    --root "$repo" \
    --state-root "$state_root" \
    --log "$log_file" \
    --no-github \
    "$@" >"$TEST_TMP_ROOT/out.txt" 2>"$TEST_TMP_ROOT/err.txt"
  TRIAGE_RC="$?"
  set -e
  TRIAGE_OUT="$(cat "$TEST_TMP_ROOT/out.txt")"
}

assert_triage() {
  local expected_safe="$1"
  local expected_reason="$2"
  grep -Fq "safe_to_restart=$expected_safe" <<<"$TRIAGE_OUT" ||
    fail "expected safe_to_restart=$expected_safe, got: $TRIAGE_OUT"
  grep -Fq "reason=$expected_reason" <<<"$TRIAGE_OUT" ||
    fail "expected reason=$expected_reason, got: $TRIAGE_OUT"
}

test_clean_noop_is_safe() {
  local repo="$TEST_TMP_ROOT/clean" state_root="$TEST_TMP_ROOT/clean-state" log_file="$TEST_TMP_ROOT/clean.log"
  make_repo "$repo"
  mkdir -p "$state_root"
  : >"$log_file"
  run_triage "$repo" "$state_root" "$log_file" --no-write-obligation
  [[ "$TRIAGE_RC" -eq 0 ]] || fail "clean triage exited $TRIAGE_RC"
  assert_triage yes clean_noop
}

test_dirty_worktree_blocks_restart() {
  local repo="$TEST_TMP_ROOT/dirty" state_root="$TEST_TMP_ROOT/dirty-state" log_file="$TEST_TMP_ROOT/dirty.log"
  make_repo "$repo"
  mkdir -p "$state_root"
  printf 'dirty\n' >>"$repo/README.md"
  : >"$log_file"
  run_triage "$repo" "$state_root" "$log_file" --no-write-obligation
  [[ "$TRIAGE_RC" -eq 3 ]] || fail "dirty triage exited $TRIAGE_RC"
  assert_triage no dirty_worktree
}

test_active_owner_waits() {
  local repo="$TEST_TMP_ROOT/owner" state_root="$TEST_TMP_ROOT/owner-state" log_file="$TEST_TMP_ROOT/owner.log"
  local owner_file
  make_repo "$repo"
  mkdir -p "$state_root"
  owner_file="$state_root/active-owner.$(repo_key "$repo").tsv"
  {
    printf 'pid\t%s\n' "$$"
    printf 'state\trunning\n'
    printf 'detail\tfixture\n'
  } >"$owner_file"
  : >"$log_file"
  run_triage "$repo" "$state_root" "$log_file" --no-write-obligation
  [[ "$TRIAGE_RC" -eq 0 ]] || fail "active owner triage exited $TRIAGE_RC"
  assert_triage wait active_backlog_owner
}

test_active_lock_blocks_restart() {
  local repo="$TEST_TMP_ROOT/lock" state_root="$TEST_TMP_ROOT/lock-state" log_file="$TEST_TMP_ROOT/lock.log"
  make_repo "$repo"
  mkdir -p "$state_root" "$repo/runtime/upkeeper-active.lock"
  : >"$log_file"
  run_triage "$repo" "$state_root" "$log_file" --no-write-obligation
  [[ "$TRIAGE_RC" -eq 3 ]] || fail "active lock triage exited $TRIAGE_RC"
  assert_triage no active_lock_present
}

test_open_obligation_blocks_restart() {
  local repo="$TEST_TMP_ROOT/obligation" state_root="$TEST_TMP_ROOT/obligation-state" log_file="$TEST_TMP_ROOT/obligation.log"
  make_repo "$repo"
  mkdir -p "$state_root" "$repo/runtime/upkeeper-obligations/open"
  printf '{"id":"fixture","status":"open"}\n' >"$repo/runtime/upkeeper-obligations/open/fixture.json"
  : >"$log_file"
  run_triage "$repo" "$state_root" "$log_file" --no-write-obligation
  [[ "$TRIAGE_RC" -eq 3 ]] || fail "obligation triage exited $TRIAGE_RC"
  assert_triage no open_automation_obligation
}

test_quota_hibernation_waits() {
  local repo="$TEST_TMP_ROOT/quota" state_root="$TEST_TMP_ROOT/quota-state" log_file="$TEST_TMP_ROOT/quota.log"
  make_repo "$repo"
  mkdir -p "$state_root"
  printf '2026-05-24T01:00:00 INFO backlog: quota preflight: quota blocked bucket=backend_usage_limit until=2099-01-01T00:00:00 wake=2099-01-01T00:01:00\n' >"$log_file"
  run_triage "$repo" "$state_root" "$log_file" --no-write-obligation
  [[ "$TRIAGE_RC" -eq 0 ]] || fail "quota triage exited $TRIAGE_RC"
  assert_triage wait quota_hibernating
}

test_pending_ci_waits_and_failed_validation_blocks() {
  local repo="$TEST_TMP_ROOT/checks" state_root="$TEST_TMP_ROOT/checks-state" log_file="$TEST_TMP_ROOT/checks.log"
  make_repo "$repo"
  mkdir -p "$state_root"
  printf '2026-05-24T01:00:00 INFO backlog: PR #1 checks pending; holding owner lease\n' >"$log_file"
  run_triage "$repo" "$state_root" "$log_file" --no-write-obligation
  [[ "$TRIAGE_RC" -eq 0 ]] || fail "pending checks triage exited $TRIAGE_RC"
  assert_triage wait local_log_checks_pending

  printf '2026-05-24T01:00:00 INFO Local validation\tfail\t52s\thttps://example.invalid\n' >"$log_file"
  run_triage "$repo" "$state_root" "$log_file" --no-write-obligation
  [[ "$TRIAGE_RC" -eq 3 ]] || fail "failed validation triage exited $TRIAGE_RC"
  assert_triage no failed_validation_or_checks
}

test_merged_pr_cleanup_needed() {
  local repo="$TEST_TMP_ROOT/merged" state_root="$TEST_TMP_ROOT/merged-state" log_file="$TEST_TMP_ROOT/merged.log"
  make_repo "$repo"
  mkdir -p "$state_root"
  (
    cd "$repo"
    git checkout -q -B backlog/test
  )
  printf '2026-05-24T01:00:00 INFO backlog: merged PR #1\n' >"$log_file"
  run_triage "$repo" "$state_root" "$log_file" --no-write-obligation
  [[ "$TRIAGE_RC" -eq 3 ]] || fail "merged cleanup triage exited $TRIAGE_RC"
  assert_triage no merged_pr_cleanup_needed
}

test_unknown_page_error_opens_obligation() {
  local repo="$TEST_TMP_ROOT/unknown" state_root="$TEST_TMP_ROOT/unknown-state" log_file="$TEST_TMP_ROOT/unknown.log"
  make_repo "$repo"
  mkdir -p "$state_root"
  printf '2026-05-24T01:00:00 PAGE [ERROR] unexpected bad state\n' >"$log_file"
  run_triage "$repo" "$state_root" "$log_file"
  [[ "$TRIAGE_RC" -eq 3 ]] || fail "unknown error triage exited $TRIAGE_RC"
  assert_triage no unknown_log_error
  find "$repo/runtime/upkeeper-obligations/open" -name 'backlog-triage-*.json' -print -quit | grep -q . ||
    fail "unknown error did not create a visible obligation"
}

test_clean_noop_is_safe
test_dirty_worktree_blocks_restart
test_active_owner_waits
test_active_lock_blocks_restart
test_open_obligation_blocks_restart
test_quota_hibernation_waits
test_pending_ci_waits_and_failed_validation_blocks
test_merged_pr_cleanup_needed
test_unknown_page_error_opens_obligation
printf 'backlog_triage_test: ok\n'
