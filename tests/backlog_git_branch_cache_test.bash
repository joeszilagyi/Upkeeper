#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-backlog-branch-cache.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

BACKLOG_SOURCE_ONLY=1
export BACKLOG_SOURCE_ONLY
# shellcheck source=/dev/null
source "$PROJECT_ROOT/orchestration/backlog.sh"

make_repo() {
  local repo="$1"

  mkdir -p "$repo"
  (
    cd "$repo"
    command git init -q
    command git checkout -q -B main
    command git config user.name "Backlog Branch Cache Test"
    command git config user.email "backlog-branch-cache@example.invalid"
    printf 'base\n' >README.md
    command git add README.md
    command git commit -q -m init
  )
}

test_branch_cache_reuses_until_explicit_invalidation() {
  local repo="$TEST_TMP_ROOT/repo" first second refreshed count
  local real_git

  make_repo "$repo"
  real_git="$(command -v git)"
  BACKLOG_TEST_GIT_LOG="$TEST_TMP_ROOT/git.log"
  : >"$BACKLOG_TEST_GIT_LOG"
  git() {
    if [[ "${1:-}" == "rev-parse" && "${2:-}" == "--abbrev-ref" && "${3:-}" == "HEAD" ]]; then
      printf '%s\n' "$*" >>"$BACKLOG_TEST_GIT_LOG"
    fi
    command "$real_git" "$@"
  }

  pushd "$repo" >/dev/null
  backlog_invalidate_git_branch_cache
  backlog_assign_cached_git_branch first
  backlog_assign_cached_git_branch second
  [[ "$first" == main && "$second" == main ]] || fail "stable branch was not preserved"
  count="$(wc -l <"$BACKLOG_TEST_GIT_LOG")"
  [[ "$count" == 1 ]] || fail "stable branch lookup ran $count times instead of once"

  command git checkout -q -b cache-next
  backlog_invalidate_git_branch_cache
  backlog_assign_cached_git_branch refreshed
  [[ "$refreshed" == cache-next ]] || fail "cache did not refresh after branch transition: $refreshed"
  count="$(wc -l <"$BACKLOG_TEST_GIT_LOG")"
  [[ "$count" == 2 ]] || fail "branch transition did not cause exactly one refresh: $count"

  command git checkout -q --detach
  backlog_invalidate_git_branch_cache
  backlog_assign_cached_git_branch refreshed
  [[ "$refreshed" == HEAD ]] || fail "detached branch compatibility changed: $refreshed"
  popd >/dev/null
}

test_branch_cache_reuses_until_explicit_invalidation

printf 'backlog_git_branch_cache_test: ok\n'
