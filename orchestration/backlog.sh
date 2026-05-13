#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

BACKLOG_BRANCH_PREFIX="${BACKLOG_BRANCH_PREFIX:-backlog/}"
BACKLOG_PR_TITLE="${BACKLOG_PR_TITLE:-[backlog] Upkeeper issue batch}"
BACKLOG_BATCH_LIMIT="${BACKLOG_BATCH_LIMIT:-10}"
BACKLOG_ISSUE_LIMIT="${BACKLOG_ISSUE_LIMIT:-200}"
BACKLOG_EXCLUDED_LABELS="${BACKLOG_EXCLUDED_LABELS:-feature,features,enhancement,research,r&d,r-and-d,documentation,docs,in-progress,blocked,duplicate,wontfix,invalid,needs-info,done,merged,has-pr}"
BACKLOG_CODEX_MODEL="${BACKLOG_CODEX_MODEL:-gpt-5.4}"
BACKLOG_CODEX_REASONING_EFFORT="${BACKLOG_CODEX_REASONING_EFFORT:-high}"
BACKLOG_IGNORE_FAILURE_QUEUE="${BACKLOG_IGNORE_FAILURE_QUEUE:-1}"
BACKLOG_PR_CHECK_TIMEOUT_SECONDS="${BACKLOG_PR_CHECK_TIMEOUT_SECONDS:-900}"
BACKLOG_PER_BUG_VALIDATION_MODE="${BACKLOG_PER_BUG_VALIDATION_MODE:-light}"

log() {
  printf 'backlog: %s\n' "$*" >&2
}

fail() {
  printf 'backlog: ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command missing: $1"
}

require_clean_worktree() {
  local status
  status="$(git status --short)"
  [[ -z "$status" ]] || fail "working tree is not clean; finish or stash local changes before running backlog.sh"
}

backlog_state_root() {
  printf '%s\n' "${BACKLOG_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/upkeeper/backlog}"
}

backlog_branch_key() {
  git rev-parse --abbrev-ref HEAD | tr '/:' '__'
}

deferred_issue_file() {
  local state_root
  state_root="$(backlog_state_root)"
  mkdir -p "$state_root"
  chmod 700 "$state_root" 2>/dev/null || true
  printf '%s/deferred-issues.%s.txt\n' "$state_root" "$(backlog_branch_key)"
}

cleanup_ephemeral_artifacts() {
  find "$ROOT_DIR" -type d -name '__pycache__' -prune -exec rm -rf -- {} + 2>/dev/null || true
  find "$ROOT_DIR" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true
}

prepare_backlog_runtime_env() {
  local state_root

  export CODEX_MODEL="$BACKLOG_CODEX_MODEL"
  export CODEX_REASONING_EFFORT="$BACKLOG_CODEX_REASONING_EFFORT"
  export CODEX_FALLBACK_ENABLED="${BACKLOG_CODEX_FALLBACK_ENABLED:-0}"
  export CODEX_FALLBACK_SCREEN_ENABLED="${BACKLOG_CODEX_FALLBACK_SCREEN_ENABLED:-0}"
  export CODEX_POSTMORTEM_ENABLED="${BACKLOG_CODEX_POSTMORTEM_ENABLED:-0}"
  export CODEX_5H_STOP_PERCENT="${BACKLOG_5H_STOP_PERCENT:-0}"
  export CODEX_WEEK_STOP_PERCENT="${BACKLOG_WEEK_STOP_PERCENT:-10}"
  export CODEX_WEEK_STOP_BUFFER_PERCENT="${BACKLOG_WEEK_STOP_BUFFER_PERCENT:-0}"
  export CODEX_SPARK_5H_STOP_PERCENT="${BACKLOG_SPARK_5H_STOP_PERCENT:-0}"
  export CODEX_SPARK_WEEK_STOP_BUFFER_PERCENT="${BACKLOG_SPARK_WEEK_STOP_BUFFER_PERCENT:-0}"
  export CODEX_QUOTA_GUARDRAIL_BYPASS="${BACKLOG_QUOTA_GUARDRAIL_BYPASS:-0}"
  export CODEX_QUOTA_COOLDOWN_BYPASS="${BACKLOG_QUOTA_COOLDOWN_BYPASS:-0}"
  export UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL="${BACKLOG_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL:-1}"
  export PYTHONDONTWRITEBYTECODE=1

  state_root="$(backlog_state_root)"
  mkdir -p \
    "$state_root/logs" \
    "$state_root/tmp" \
    "$state_root/transcripts" \
    "$state_root/postmortems" \
    "$state_root/bug-report-drafts" \
    "$state_root/precontact-vault" \
    "$ROOT_DIR/runtime/upkeeper-backlog-lattice"
  chmod 700 "$state_root" "$state_root/logs" "$state_root/tmp" "$state_root/transcripts" "$state_root/postmortems" "$state_root/bug-report-drafts" "$state_root/precontact-vault" "$ROOT_DIR/runtime/upkeeper-backlog-lattice" 2>/dev/null || true

  export TMPDIR="${BACKLOG_TMPDIR:-$state_root/tmp}"
  export CODEX_LOG_FILE="${BACKLOG_CODEX_LOG_FILE:-$state_root/logs/Upkeeper.log}"
  export CODEX_TRANSCRIPT_DIR="${BACKLOG_CODEX_TRANSCRIPT_DIR:-$state_root/transcripts}"
  export CODEX_POSTMORTEM_DIR="${BACKLOG_CODEX_POSTMORTEM_DIR:-$state_root/postmortems}"
  export UPKEEPER_BUG_REPORT_DRAFT_DIR="${BACKLOG_BUG_REPORT_DRAFT_DIR:-$state_root/bug-report-drafts}"
  export UPKEEPER_LATTICE_DB="${BACKLOG_LATTICE_DB:-$ROOT_DIR/runtime/upkeeper-backlog-lattice/lattice.sqlite3}"
  export UPKEEPER_PRECONTACT_BACKUP_ROOT="${BACKLOG_PRECONTACT_BACKUP_ROOT:-$state_root/precontact-vault}"
  export CODEX_HOME_DIR="${CODEX_HOME_DIR:-${CODEX_HOME:-$HOME/.codex}}"
  export CODEX_SESSION_SCAN_LIMIT="${CODEX_SESSION_SCAN_LIMIT:-200}"
  export LOG_FILE="${LOG_FILE:-$CODEX_LOG_FILE}"
}

quota_preflight_allows_backlog_run() {
  local quota_json primary_bucket_current secondary_bucket_current
  local primary_projected_left secondary_projected_left
  local primary_decision secondary_decision

  prepare_backlog_runtime_env
  source "$ROOT_DIR/lib/upkeeper/config_validation.bash"
  source "$ROOT_DIR/lib/upkeeper/quota_state.bash"
  source "$ROOT_DIR/lib/upkeeper/quota_guardrails.bash"

  quota_json="$(quota_state_json "$CODEX_MODEL")" || return 0
  [[ -n "$quota_json" ]] || return 0
  if jq -e '.error? != null' >/dev/null 2>&1 <<<"$quota_json"; then
    return 0
  fi

  primary_bucket_current="$(jq -r '.snapshot.primary_bucket_current // "false"' <<<"$quota_json")"
  secondary_bucket_current="$(jq -r '.snapshot.secondary_bucket_current // "false"' <<<"$quota_json")"
  primary_projected_left="$(jq -r '100 - ((.snapshot.primary_used_percent // 0) + (.projection.primary_delta // 0))' <<<"$quota_json")"
  secondary_projected_left="$(jq -r '100 - ((.snapshot.secondary_used_percent // 0) + (.projection.secondary_delta // 0))' <<<"$quota_json")"
  primary_decision="$(quota_bucket_decision "$primary_bucket_current" "$primary_projected_left" "$(quota_5h_stop_percent_for_model "$CODEX_MODEL")")"
  secondary_decision="$(quota_bucket_decision "$secondary_bucket_current" "$secondary_projected_left" "$(quota_week_stop_percent_for_model "$CODEX_MODEL")")"

  if [[ "$primary_decision" == "defer" || "$secondary_decision" == "defer" ]]; then
    log "quota preflight: deferring backlog run this cycle (primary=$primary_decision secondary=$secondary_decision)"
    return 3
  fi
  return 0
}

current_backlog_pr() {
  gh pr list --state open --json number,title,headRefName \
    --jq '.[] | select(.headRefName | startswith("'"$BACKLOG_BRANCH_PREFIX"'")) | [.number, .headRefName] | @tsv' \
    | sed -n '1p'
}

checkout_backlog_branch() {
  local branch="$1"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout "$branch" >/dev/null
    git pull --ff-only origin "$branch"
  else
    git fetch origin "$branch"
    git checkout -b "$branch" "origin/$branch" >/dev/null
  fi
}

open_backlog_pr() {
  local branch

  git checkout main >/dev/null
  git pull --ff-only origin main >/dev/null

  branch="${BACKLOG_BRANCH_PREFIX}$(date +%Y%m%d-%H%M%S)"
  git checkout -b "$branch" >/dev/null
  git commit --allow-empty -m "Start backlog issue batch" >/dev/null
  git push -u origin "$branch" >/dev/null
  gh pr create \
    --base main \
    --head "$branch" \
    --title "$BACKLOG_PR_TITLE" \
    --body "Backlog wrench batch.

Target: up to ${BACKLOG_BATCH_LIMIT} bug or data-protection fixes, newest non-feature/non-research issue first.

Validation: script-local quick validation plus required PR checks before merge." >/dev/null

  printf '%s\t%s\n' "$(gh pr view --json number --jq '.number')" "$branch"
}

pr_body() {
  local pr_number="$1"
  gh pr view "$pr_number" --json body --jq '.body // ""'
}

fixed_issue_numbers() {
  local pr_number="$1"
  pr_body "$pr_number" | rg -o '^Fixes #[0-9]+' -r '$0' | sed 's/^Fixes #//' || true
}

deferred_issue_numbers() {
  local deferred_file

  deferred_file="$(deferred_issue_file)"
  [[ -f "$deferred_file" ]] || return 0
  sed -n '/^[0-9][0-9]*$/p' "$deferred_file"
}

defer_issue() {
  local issue_number="$1"
  local deferred_file

  [[ -n "$issue_number" ]] || return 0
  deferred_file="$(deferred_issue_file)"
  touch "$deferred_file"
  chmod 600 "$deferred_file" 2>/dev/null || true
  grep -Fxq "$issue_number" "$deferred_file" || printf '%s\n' "$issue_number" >>"$deferred_file"
}

clear_deferred_issues() {
  local deferred_file

  deferred_file="$(deferred_issue_file)"
  [[ -f "$deferred_file" ]] && rm -f "$deferred_file"
}

fix_count() {
  local pr_number="$1"
  fixed_issue_numbers "$pr_number" | sed '/^$/d' | wc -l | tr -d ' '
}

append_pr_fix_line() {
  local pr_number="$1"
  local issue_number="$2"
  local body_file

  pr_body "$pr_number" | grep -Fq "Fixes #$issue_number" && return 0
  body_file="$(mktemp "${TMPDIR:-/tmp}/upkeeper-backlog-pr-body.XXXXXX")"
  {
    pr_body "$pr_number"
    printf '\nFixes #%s\n' "$issue_number"
  } >"$body_file"
  gh pr edit "$pr_number" --body-file "$body_file"
  rm -f "$body_file"
}

selected_issue() {
  local pr_number="$1"
  local fixed_csv
  local deferred_csv

  fixed_csv="$(fixed_issue_numbers "$pr_number" | paste -sd, -)"
  deferred_csv="$(deferred_issue_numbers | paste -sd, -)"
  gh issue list --state open --limit "$BACKLOG_ISSUE_LIMIT" --json number,title,createdAt,labels \
    | jq -r \
      --arg excluded "$BACKLOG_EXCLUDED_LABELS" \
      --arg fixed ",$fixed_csv," \
      --arg deferred ",$deferred_csv," '
        def label_names: [.labels[]?.name | ascii_downcase];
        def excluded_labels: ($excluded | split(",") | map(ascii_downcase | gsub("^ +| +$"; "")) | map(select(length > 0)));
        def label_matches($label; $needle):
          $label == $needle
          or ($needle == "feature" and ($label | contains("feature")))
          or ($needle == "research" and ($label | contains("research")));
        def excluded_by_title:
          (.title // "" | ascii_downcase) as $title
          | ($title | contains("feature:"))
            or ($title | contains("enhancement:"))
            or ($title | contains("research:"))
            or ($title | contains("r&d:"))
            or ($title | contains("r-and-d:"));
        def excluded_by_label:
          label_names as $labels
          | any(excluded_labels[]; . as $needle | any($labels[]; label_matches(.; $needle)));
        map(select((.number | tostring) as $number | (excluded_by_label | not) and (excluded_by_title | not) and (($fixed | contains("," + $number + ",")) | not) and (($deferred | contains("," + $number + ",")) | not)))
        | sort_by(.createdAt)
        | reverse
        | .[0]
        | if . then [.number, .title] | @tsv else empty end
      ' \
    | sed -n '1p'
}

target_hint_for_issue() {
  local issue_number="$1"
  local issue_text

  [[ -n "$issue_number" ]] || return 0
  issue_text="$(gh issue view "$issue_number" --json title,body --jq '((.title // "") + "\n" + (.body // "")) | ascii_downcase')"
  case "$issue_text" in
    *cycle.start*|*record-cycle-start*|*verbose\ metadata*|*operator\ and\ config\ metadata*|*config\ file*|*issue\ labels*|*include/exclude\ globs*|*manifest\ path*)
      [[ -f Upkeeper ]] && printf '%s\n' "Upkeeper"
      ;;
    *lattice*|*pass_result*|*pass-result*)
      [[ -f tools/upkeeper_lattice.py ]] && printf '%s\n' "tools/upkeeper_lattice.py"
      ;;
    *bug-report-only*|*source_mutation_guard*|*source\ mutation\ fingerprint*|*dirty-state\ fingerprint*|*dirty\ worktree*|*untracked\ path*)
      [[ -f lib/upkeeper/codex_io.bash ]] && printf '%s\n' "lib/upkeeper/codex_io.bash"
      ;;
  esac
}

run_upkeeper_for_one_target() {
  local issue_number="${1:-}"
  local target_hint=""
  local upkeeper_args=()
  local upkeeper_status=0

  prepare_backlog_runtime_env

  if [[ -n "$issue_number" ]]; then
    if [[ "$BACKLOG_IGNORE_FAILURE_QUEUE" == "1" ]]; then
      upkeeper_args+=(--ignore-failure-queue)
    fi
    target_hint="$(target_hint_for_issue "$issue_number")"
    if [[ -n "$target_hint" ]]; then
      upkeeper_args+=(--target-file="$target_hint")
    fi
    upkeeper_args+=(--fix-issue="$issue_number")
    log "running Upkeeper for issue #$issue_number with $CODEX_MODEL/$CODEX_REASONING_EFFORT target=${target_hint:-wrapper-inferred}"
    ./Upkeeper "${upkeeper_args[@]}"
    upkeeper_status="$?"
    if [[ "$upkeeper_status" -ne 0 ]]; then
      if [[ "$upkeeper_status" -eq 2 ]]; then
        return 2
      fi
      return "$upkeeper_status"
    fi
  else
    log "no eligible issue found; running normal newest-file Upkeeper pass with $CODEX_MODEL/$CODEX_REASONING_EFFORT"
    ./Upkeeper --selection-order=newest
  fi
}

has_worktree_changes() {
  [[ -n "$(git status --short)" ]]
}

run_per_bug_validation() {
  local validation_start

  [[ "${BACKLOG_SKIP_LOCAL_VALIDATION:-0}" == "1" ]] && return 0

  validation_start="$SECONDS"
  log "per-bug validation: bash syntax"
  bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh
  log "per-bug validation: diff whitespace"
  git diff --check
  log "per-bug validation: complete in $((SECONDS - validation_start))s"
}

run_batch_validation() {
  local validation_start

  [[ "${BACKLOG_SKIP_LOCAL_VALIDATION:-0}" == "1" ]] && return 0

  validation_start="$SECONDS"
  log "batch validation: bash syntax"
  bash -n Upkeeper ChimneySweep FlameOn lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf orchestration/backlog.sh
  log "batch validation: unit tests"
  for test_script in tests/*.bash; do
    bash "$test_script"
  done
  log "batch validation: docs quick checks"
  tools/check_public_docs.sh --quick
  log "batch validation: diff whitespace"
  git diff --check
  log "batch validation: quick validator"
  tools/validate_upkeeper.sh --quick
  log "batch validation: complete in $((SECONDS - validation_start))s"
}

commit_and_push_changes() {
  local issue_number="${1:-}"
  local commit_message="${2:-}"
  local message

  cleanup_ephemeral_artifacts
  has_worktree_changes || return 1
  case "$BACKLOG_PER_BUG_VALIDATION_MODE" in
    none)
      log "per-bug validation: skipped by BACKLOG_PER_BUG_VALIDATION_MODE=none"
      ;;
    light)
      run_per_bug_validation
      ;;
    full)
      run_batch_validation
      ;;
    *)
      fail "unsupported BACKLOG_PER_BUG_VALIDATION_MODE: $BACKLOG_PER_BUG_VALIDATION_MODE"
      ;;
  esac
  cleanup_ephemeral_artifacts
  log "staging tracked changes"
  git add --all
  git diff --cached --check
  if [[ -n "$commit_message" ]]; then
    message="$commit_message"
  elif [[ -n "$issue_number" ]]; then
    message="Fix backlog issue #$issue_number"
  else
    message="Apply backlog Upkeeper pass"
  fi
  log "committing: $message"
  git commit -m "$message"
  log "pushing branch updates"
  git push
  return 0
}

wait_for_pr_checks() {
  local pr_number="$1"
  log "waiting for PR #$pr_number checks"
  if timeout "$BACKLOG_PR_CHECK_TIMEOUT_SECONDS" gh pr checks "$pr_number" --watch; then
    log "PR #$pr_number checks passed"
    return 0
  fi

  if [[ "$?" -eq 124 ]]; then
    log "PR #$pr_number checks still pending after ${BACKLOG_PR_CHECK_TIMEOUT_SECONDS}s; retry on the next backlog iteration"
    return 2
  fi

  return 1
}

merge_and_clean() {
  local pr_number="$1"
  local branch="$2"

  run_batch_validation
  wait_for_pr_checks "$pr_number" || {
    local status="$?"
    [[ "$status" -eq 2 ]] && return 2
    return "$status"
  }
  CODEX_ALLOW_PR_MERGE="$pr_number" gh pr merge "$pr_number" --merge --delete-branch
  git checkout main >/dev/null
  git pull --ff-only origin main
  git fetch --prune origin
  clear_deferred_issues
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git branch -d "$branch" >/dev/null || true
  fi
  require_clean_worktree
  log "merged PR #$pr_number and returned to clean main"
}

main() {
  local pr_info pr_number branch issue_info issue_number count run_status

  require_command git
  require_command gh
  require_command jq
  require_command rg

  require_clean_worktree
  pr_info="$(current_backlog_pr)"
  if [[ -z "$pr_info" ]]; then
    log "opening new backlog PR"
    pr_info="$(open_backlog_pr)"
  fi

  pr_number="$(awk -F '\t' '{print $1}' <<<"$pr_info")"
  branch="$(awk -F '\t' '{print $2}' <<<"$pr_info")"
  checkout_backlog_branch "$branch"

  count="$(fix_count "$pr_number")"
  if [[ "$count" -ge "$BACKLOG_BATCH_LIMIT" ]]; then
    log "PR #$pr_number has $count recorded fixes; merging batch"
    merge_and_clean "$pr_number" "$branch" || {
      local status="$?"
      [[ "$status" -eq 2 ]] && exit 0
      exit "$status"
    }
    exit 0
  fi

  quota_preflight_allows_backlog_run
  local quota_status="$?"
  if [[ "$quota_status" -ne 0 ]]; then
    [[ "$quota_status" -eq 3 ]] && exit 0
    exit "$quota_status"
  fi

  issue_info="$(selected_issue "$pr_number")"
  issue_number="$(awk -F '\t' '{print $1}' <<<"$issue_info")"

  run_upkeeper_for_one_target "$issue_number"
  run_status="$?"

  if [[ "$run_status" -eq 2 ]]; then
    if has_worktree_changes; then
      if commit_and_push_changes "" "Preserve partial backlog work for issue #$issue_number"; then
        log "preserved partial work for blocked issue #$issue_number"
      fi
    fi
    defer_issue "$issue_number"
    log "deferred blocked issue #$issue_number for this backlog branch"
    exit 0
  elif [[ "$run_status" -ne 0 ]]; then
    exit "$run_status"
  fi

  if commit_and_push_changes "$issue_number"; then
    if [[ -n "$issue_number" ]]; then
      append_pr_fix_line "$pr_number" "$issue_number"
    fi
  else
    log "Upkeeper produced no tracked changes"
  fi

  count="$(fix_count "$pr_number")"
  if [[ "$count" -ge "$BACKLOG_BATCH_LIMIT" ]]; then
    log "PR #$pr_number reached $count fixes; merging batch"
    merge_and_clean "$pr_number" "$branch" || {
      local status="$?"
      [[ "$status" -eq 2 ]] && exit 0
      exit "$status"
    }
  else
    log "PR #$pr_number now has $count/$BACKLOG_BATCH_LIMIT recorded fixes"
  fi
}

main "$@"
