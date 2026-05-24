#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-merge-steward.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

install_fake_gh() {
  mkdir -p "$TEST_TMP_ROOT/bin"
  cat >"$TEST_TMP_ROOT/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-} ${2:-}" in
  "pr view")
    case "${BACKLOG_STEWARD_GH_CASE:-green}" in
      merged)
        printf '{"number":1,"state":"MERGED","isDraft":false,"baseRefName":"main","headRefName":"feature","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","url":"https://example.invalid/pull/1"}\n'
        ;;
      draft)
        printf '{"number":1,"state":"OPEN","isDraft":true,"baseRefName":"main","headRefName":"feature","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","url":"https://example.invalid/pull/1"}\n'
        ;;
      conflict)
        printf '{"number":1,"state":"OPEN","isDraft":false,"baseRefName":"main","headRefName":"feature","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","url":"https://example.invalid/pull/1"}\n'
        ;;
      *)
        printf '{"number":1,"state":"OPEN","isDraft":false,"baseRefName":"main","headRefName":"feature","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","url":"https://example.invalid/pull/1"}\n'
        ;;
    esac
    ;;
  "pr checks")
    case "${BACKLOG_STEWARD_GH_CASE:-green}" in
      checks_fail)
        printf 'Local validation\tfail\t1m\thttps://example.invalid\n'
        exit 1
        ;;
      checks_pending)
        printf 'Local validation\tpending\t0\thttps://example.invalid\n'
        exit 8
        ;;
      *)
        printf 'Local validation\tpass\t1m\thttps://example.invalid\n'
        printf 'CodeQL\tpass\t2s\thttps://example.invalid\n'
        ;;
    esac
    ;;
  "pr merge")
    printf 'CODEX_ALLOW_PR_MERGE=%s\n' "${CODEX_ALLOW_PR_MERGE:-}" >>"$BACKLOG_STEWARD_GH_LOG"
    printf 'ARGS=%s\n' "$*" >>"$BACKLOG_STEWARD_GH_LOG"
    ;;
  *)
    printf 'unexpected gh command: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
  chmod 700 "$TEST_TMP_ROOT/bin/gh"
  export PATH="$TEST_TMP_ROOT/bin:$PATH"
  export BACKLOG_STEWARD_GH_LOG="$TEST_TMP_ROOT/gh.log"
}

make_repo() {
  local repo="$1"
  local remote="$2"
  git init -q --bare "$remote"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git checkout -q -B main
    git config user.name "Merge Steward Test"
    git config user.email "merge-steward@example.invalid"
    printf 'hello\n' >README.md
    git add README.md
    git commit -q -m init
    git remote add origin "$remote"
    git push -q -u origin main
  )
}

run_steward() {
  local repo="$1"
  shift
  set +e
  "$PROJECT_ROOT/tools/backlog_merge_steward.py" --root "$repo" --pr-number 1 "$@" \
    >"$TEST_TMP_ROOT/out.txt" 2>"$TEST_TMP_ROOT/err.txt"
  STEWARD_RC="$?"
  set -e
  STEWARD_OUT="$(cat "$TEST_TMP_ROOT/out.txt")"
}

assert_steward() {
  local expected_ready="$1"
  local expected_reason="$2"
  grep -Fq "merge_ready=$expected_ready" <<<"$STEWARD_OUT" ||
    fail "expected merge_ready=$expected_ready, got: $STEWARD_OUT"
  grep -Fq "reason=$expected_reason" <<<"$STEWARD_OUT" ||
    fail "expected reason=$expected_reason, got: $STEWARD_OUT"
}

test_green_dry_run_ready() {
  local repo="$TEST_TMP_ROOT/green" remote="$TEST_TMP_ROOT/green.git"
  make_repo "$repo" "$remote"
  BACKLOG_STEWARD_GH_CASE=green run_steward "$repo"
  [[ "$STEWARD_RC" -eq 0 ]] || fail "green dry-run exited $STEWARD_RC"
  assert_steward yes dry_run_ready
}

test_failing_and_pending_checks_block() {
  local repo="$TEST_TMP_ROOT/checks" remote="$TEST_TMP_ROOT/checks.git"
  make_repo "$repo" "$remote"
  BACKLOG_STEWARD_GH_CASE=checks_fail run_steward "$repo"
  [[ "$STEWARD_RC" -eq 3 ]] || fail "failing checks exited $STEWARD_RC"
  assert_steward no checks_fail
  BACKLOG_STEWARD_GH_CASE=checks_pending run_steward "$repo"
  [[ "$STEWARD_RC" -eq 3 ]] || fail "pending checks exited $STEWARD_RC"
  assert_steward no checks_pending
}

test_dirty_secondary_main_worktree_blocks() {
  local repo="$TEST_TMP_ROOT/worktree" remote="$TEST_TMP_ROOT/worktree.git" main_wt="$TEST_TMP_ROOT/main-wt"
  make_repo "$repo" "$remote"
  (
    cd "$repo"
    git checkout -q -B feature
    git worktree add -q "$main_wt" main
  )
  printf 'dirty\n' >>"$main_wt/README.md"
  BACKLOG_STEWARD_GH_CASE=green run_steward "$repo"
  [[ "$STEWARD_RC" -eq 3 ]] || fail "dirty secondary worktree exited $STEWARD_RC"
  assert_steward no dirty_main_worktree
}

test_already_merged_pr_blocks() {
  local repo="$TEST_TMP_ROOT/merged" remote="$TEST_TMP_ROOT/merged.git"
  make_repo "$repo" "$remote"
  BACKLOG_STEWARD_GH_CASE=merged run_steward "$repo"
  [[ "$STEWARD_RC" -eq 3 ]] || fail "merged PR exited $STEWARD_RC"
  assert_steward no pr_not_open
}

test_execute_uses_guarded_merge_and_delete_branch() {
  local repo="$TEST_TMP_ROOT/execute" remote="$TEST_TMP_ROOT/execute.git"
  make_repo "$repo" "$remote"
  : >"$BACKLOG_STEWARD_GH_LOG"
  BACKLOG_STEWARD_GH_CASE=green run_steward "$repo" --execute
  [[ "$STEWARD_RC" -eq 0 ]] || fail "execute steward exited $STEWARD_RC: $STEWARD_OUT"
  assert_steward yes merged_clean
  grep -Fq 'CODEX_ALLOW_PR_MERGE=1' "$BACKLOG_STEWARD_GH_LOG" ||
    fail "guarded merge env was not passed"
  grep -Fq -- '--delete-branch' "$BACKLOG_STEWARD_GH_LOG" ||
    fail "merge steward did not request branch deletion through gh"
}

install_fake_gh
test_green_dry_run_ready
test_failing_and_pending_checks_block
test_dirty_secondary_main_worktree_blocks
test_already_merged_pr_blocks
test_execute_uses_guarded_merge_and_delete_branch
printf 'backlog_merge_steward_test: ok\n'
