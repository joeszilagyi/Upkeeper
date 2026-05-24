#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-backlog-local-ahead.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

BACKLOG_SOURCE_ONLY=1
export BACKLOG_SOURCE_ONLY
source "$PROJECT_ROOT/orchestration/backlog.sh"

make_repo() {
  local repo="$1"
  local remote="$2"

  git init -q --bare "$remote"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git checkout -q -B main
    git config user.name "Backlog Local Ahead Test"
    git config user.email "backlog-local-ahead@example.invalid"
    printf 'base\n' >README.md
    git add README.md
    git commit -q -m init
    git remote add origin "$remote"
    git push -q -u origin main
    git -C "$remote" symbolic-ref HEAD refs/heads/main
    git checkout -q -B backlog/test
    git push -q -u origin backlog/test
  )
}

commit_local_change() {
  local repo="$1"
  local text="$2"

  (
    cd "$repo"
    printf '%s\n' "$text" >>README.md
    git add README.md
    git commit -q -m "$text"
  )
}

remote_head() {
  local remote="$1"

  git ls-remote "$remote" refs/heads/backlog/test | awk '{print $1}'
}

test_clean_local_ahead_branch_is_pushed() {
  local repo="$TEST_TMP_ROOT/clean-ahead" remote="$TEST_TMP_ROOT/clean-ahead.git"
  local output local_head upstream_head

  make_repo "$repo" "$remote"
  commit_local_change "$repo" "local remediation"
  pushd "$repo" >/dev/null
  local_head="$(git rev-parse HEAD)"
  if output="$(backlog_ensure_local_branch_pushed 123 backlog/test pre_batch_merge 2>&1)"; then
    :
  else
    fail "clean local-ahead branch was not pushed: $output"
  fi
  upstream_head="$(remote_head "$remote")"
  [[ "$upstream_head" == "$local_head" ]] ||
    fail "clean local-ahead branch was not pushed to origin"
  popd >/dev/null
  grep -Fq "action=push_before_pr_checks" <<<"$output" ||
    fail "push guard did not explain push-before-checks action"
  grep -Fq "action=pushed_wait_for_fresh_checks" <<<"$output" ||
    fail "push guard did not explain fresh-check wait action"
}

test_dirty_local_ahead_branch_blocks() {
  local repo="$TEST_TMP_ROOT/dirty-ahead" remote="$TEST_TMP_ROOT/dirty-ahead.git"
  local output local_head upstream_head

  make_repo "$repo" "$remote"
  commit_local_change "$repo" "local remediation"
  pushd "$repo" >/dev/null
  local_head="$(git rev-parse HEAD)"
  printf 'dirty\n' >>README.md
  if output="$(backlog_ensure_local_branch_pushed 123 backlog/test pre_batch_merge 2>&1)"; then
    fail "dirty local-ahead branch was allowed to push"
  fi
  upstream_head="$(remote_head "$remote")"
  [[ "$upstream_head" != "$local_head" ]] ||
    fail "dirty local-ahead branch unexpectedly pushed to origin"
  popd >/dev/null
  grep -Fq "reason=dirty_worktree" <<<"$output" ||
    fail "push guard did not explain dirty worktree blocker"
}

test_diverged_local_branch_blocks() {
  local repo="$TEST_TMP_ROOT/diverged" remote="$TEST_TMP_ROOT/diverged.git" other="$TEST_TMP_ROOT/diverged-other"
  local output local_head upstream_before upstream_after

  make_repo "$repo" "$remote"
  git clone -q "$remote" "$other"
  (
    cd "$other"
    git checkout -q backlog/test
    git config user.name "Backlog Local Ahead Test"
    git config user.email "backlog-local-ahead@example.invalid"
    printf 'remote\n' >>README.md
    git add README.md
    git commit -q -m "remote advance"
    git push -q origin backlog/test
  )
  commit_local_change "$repo" "local remediation"
  pushd "$repo" >/dev/null
  local_head="$(git rev-parse HEAD)"
  upstream_before="$(remote_head "$remote")"
  if output="$(backlog_ensure_local_branch_pushed 123 backlog/test pre_batch_merge 2>&1)"; then
    fail "diverged local branch was allowed to push"
  fi
  upstream_after="$(remote_head "$remote")"
  [[ "$upstream_after" == "$upstream_before" ]] ||
    fail "diverged local branch changed origin"
  [[ "$upstream_after" != "$local_head" ]] ||
    fail "diverged local branch unexpectedly pushed local head"
  popd >/dev/null
  grep -Fq "reason=diverged_or_behind" <<<"$output" ||
    fail "push guard did not explain diverged branch blocker"
}

test_clean_local_ahead_branch_is_pushed
test_dirty_local_ahead_branch_blocks
test_diverged_local_branch_blocks
printf 'backlog_local_ahead_guard_test: ok\n'
