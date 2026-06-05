#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-backlog-deferred-pr.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

install_fake_gh() {
  mkdir -p "$TEST_TMP_ROOT/bin" "$TEST_TMP_ROOT/gh-state"
  cat >"$TEST_TMP_ROOT/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

log_file="${BACKLOG_TEST_GH_LOG:?}"
state_dir="${BACKLOG_TEST_GH_STATE_DIR:?}"
remote_repo="${BACKLOG_TEST_REMOTE_REPO:?}"

mkdir -p "$(dirname -- "$log_file")" "$state_dir"

case "${1:-} ${2:-}" in
  "pr list")
    if [[ -f "$state_dir/number" && -f "$state_dir/branch" ]]; then
      number="$(<"$state_dir/number")"
      branch="$(<"$state_dir/branch")"
      printf '%s\t%s\n' "$number" "$branch"
    fi
    ;;
  "pr create")
    branch=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --head)
          branch="$2"
          shift 2
          ;;
        --body-file)
          [[ -f "$2" ]] || {
            printf 'missing body file for gh pr create\n' >&2
            exit 2
          }
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    [[ -n "$branch" ]] || {
      printf 'gh pr create missing --head branch\n' >&2
      exit 2
    }
    if [[ -z "$(git ls-remote "$remote_repo" "refs/heads/$branch" | awk '{print $1}')" ]]; then
      printf 'gh pr create called before branch was pushed: %s\n' "$branch" >&2
      exit 3
    fi
    printf 'create branch=%s\n' "$branch" >>"$log_file"
    printf '1\n' >"$state_dir/number"
    printf '%s\n' "$branch" >"$state_dir/branch"
    ;;
  "pr view")
    if [[ ! -f "$state_dir/number" || ! -f "$state_dir/branch" ]]; then
      printf 'gh pr view requested before PR existed\n' >&2
      exit 4
    fi
    cat "$state_dir/number"
    printf '\n'
    ;;
  *)
    printf 'unexpected gh command: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
  chmod 700 "$TEST_TMP_ROOT/bin/gh"
  export PATH="$TEST_TMP_ROOT/bin:$PATH"
  export BACKLOG_TEST_GH_LOG="$TEST_TMP_ROOT/gh.log"
  export BACKLOG_TEST_GH_STATE_DIR="$TEST_TMP_ROOT/gh-state"
  export BACKLOG_TEST_REMOTE_REPO="$TEST_TMP_ROOT/remote.git"
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
    git config user.name "Backlog Deferred PR Test"
    git config user.email "backlog-deferred-pr@example.invalid"
    printf 'base\n' >README.md
    git add README.md
    git commit -q -m init
    git remote add origin "$remote"
    git push -q -u origin main
    git -C "$remote" symbolic-ref HEAD refs/heads/main
  )
}

assert_remote_branch_absent() {
  local branch="$1"

  [[ -z "$(git ls-remote "$BACKLOG_TEST_REMOTE_REPO" "refs/heads/$branch" | awk '{print $1}')" ]] ||
    fail "remote branch $branch unexpectedly existed"
}

assert_remote_branch_present() {
  local branch="$1"

  [[ -n "$(git ls-remote "$BACKLOG_TEST_REMOTE_REPO" "refs/heads/$branch" | awk '{print $1}')" ]] ||
    fail "remote branch $branch was not pushed"
}

test_open_backlog_pr_stays_local() {
  local repo="$TEST_TMP_ROOT/repo-local" remote="$TEST_TMP_ROOT/remote.git"
  local pr_info pr_number branch current_branch current_pr_info

  make_repo "$repo" "$remote"
  (
    cd "$repo"
    pr_info="$(open_backlog_pr)"
    pr_number="$(awk -F '\t' '{print $1}' <<<"$pr_info")"
    branch="$(awk -F '\t' '{print $2}' <<<"$pr_info")"
    [[ -z "$pr_number" ]] || fail "open_backlog_pr published a PR too early"
    [[ "$branch" == backlog/* ]] || fail "open_backlog_pr did not return a backlog branch"
    current_branch="$(git rev-parse --abbrev-ref HEAD)"
    [[ "$current_branch" == "$branch" ]] || fail "open_backlog_pr did not leave the branch checked out"
    current_pr_info="$(current_backlog_pr)"
    [[ "$(awk -F '\t' '{print $1}' <<<"$current_pr_info")" == "" ]] ||
      fail "current_backlog_pr unexpectedly found a PR for the local-only branch"
    [[ "$(awk -F '\t' '{print $2}' <<<"$current_pr_info")" == "$branch" ]] ||
      fail "current_backlog_pr did not resume the local-only backlog branch"
    assert_remote_branch_absent "$branch"
    [[ ! -s "$BACKLOG_TEST_GH_LOG" ]] || fail "gh was called before the first publish"
  )
}

test_first_real_fix_publishes_pr_after_push() {
  local repo="$TEST_TMP_ROOT/repo-publish" remote="$TEST_TMP_ROOT/remote.git"
  local pr_info branch first_result second_result published_info

  make_repo "$repo" "$remote"
  (
    cd "$repo"
    cleanup_ephemeral_artifacts() { :; }
    run_per_bug_validation() { return 0; }
    run_control_plane_pre_staging_audit() { :; }

    pr_info="$(open_backlog_pr)"
    branch="$(awk -F '\t' '{print $2}' <<<"$pr_info")"

    printf 'partial\n' >>README.md
    commit_and_push_changes "" "Preserve partial backlog work for issue #123" tools/upkeeper_lattice.py "" 0
    assert_remote_branch_absent "$branch"
    [[ ! -s "$BACKLOG_TEST_GH_LOG" ]] || fail "gh was called before a publish-worthy commit existed"

    printf 'fix\n' >>README.md
    commit_and_push_changes 123 "" tools/upkeeper_lattice.py "" 1
    assert_remote_branch_present "$branch"
    grep -Fq "create branch=$branch" "$BACKLOG_TEST_GH_LOG" ||
      fail "gh pr create was not called after the branch was pushed"

    published_info="$(current_backlog_pr)"
    [[ "$(awk -F '\t' '{print $1}' <<<"$published_info")" == "1" ]] ||
      fail "current_backlog_pr did not surface the published PR number"
    [[ "$(awk -F '\t' '{print $2}' <<<"$published_info")" == "$branch" ]] ||
      fail "current_backlog_pr did not surface the published PR branch"
    [[ "$BACKLOG_LAST_PUBLISHED_PR_INFO" == $'1\t'"$branch" ]] ||
      fail "commit_and_push_changes did not retain the published PR info"
  )
}

install_fake_gh
BACKLOG_SOURCE_ONLY=1
BACKLOG_PER_BUG_VALIDATION_MODE=none
export BACKLOG_SOURCE_ONLY
export BACKLOG_PER_BUG_VALIDATION_MODE
source "$PROJECT_ROOT/orchestration/backlog.sh"

test_open_backlog_pr_stays_local
test_first_real_fix_publishes_pr_after_push
printf 'backlog_deferred_pr_publication_test: ok\n'
