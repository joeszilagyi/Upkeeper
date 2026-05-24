#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WATCH_PR_CHECKS_JSON=""
WATCH_PR_CHECKS_GH_RC=0
WATCH_PR_CHECKS_GH_ERROR=""

watch_pr_now() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

usage() {
  cat <<'EOF'
Usage: orchestration/watch-pr.sh [PR_NUMBER]
       orchestration/watch-pr.sh --pr PR_NUMBER [--once] [--interval SECONDS]

Watch GitHub PR checks without launching backend Codex or mutating the repo.

Options:
  --pr PR_NUMBER       Watch the given pull request number.
  --once              Report the current state once and exit.
  --interval SECONDS  Poll interval while checks are pending. Default: 30.
  -h, --help          Show this help.

Exit status:
  0  all reported checks pass
  1  a check failed or check state could not be read
  2  checks are pending when --once is used
EOF
}

watch_pr_die() {
  printf '%s watch-pr: ERROR: %s\n' "$(watch_pr_now)" "$*" >&2
  exit 64
}

watch_pr_nonnegative_integer() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

watch_pr_positive_integer() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

watch_pr_infer_pr_number() {
  local inferred

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    watch_pr_die "not running inside a Git worktree"
  fi

  if ! inferred="$(gh pr view --json number --jq '.number' 2>/dev/null)"; then
    watch_pr_die "could not infer a pull request for the current branch; pass --pr PR_NUMBER"
  fi
  watch_pr_positive_integer "$inferred" ||
    watch_pr_die "current-branch PR inference did not return a numeric PR number"
  printf '%s\n' "$inferred"
}

watch_pr_fetch_checks() {
  local pr_number="$1"
  local err_file rc checks_json

  err_file="$(mktemp "${TMPDIR:-/tmp}/upkeeper-watch-pr.XXXXXX")"
  set +e
  checks_json="$(gh pr checks "$pr_number" --watch=false --json name,state,startedAt,completedAt,link,workflow,bucket 2>"$err_file")"
  rc="$?"
  set -e

  WATCH_PR_CHECKS_JSON="$checks_json"
  WATCH_PR_CHECKS_GH_RC="$rc"
  WATCH_PR_CHECKS_GH_ERROR="$(sed -e 's/[[:space:]]*$//' "$err_file" | tail -n 4 || true)"
  rm -f -- "$err_file"
}

watch_pr_render_checks() {
  local pr_number="$1"
  local checks_json="$2"
  local gh_rc="$3"
  local gh_error="$4"
  local summary status total pass pending fail other rows ts line_status name conclusion state workflow link rendered rc

  ts="$(watch_pr_now)"
  if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$checks_json"; then
    printf '%s PR #%s checks: status=fail reason=github_check_read_failed gh_exit=%s\n' "$ts" "$pr_number" "$gh_rc"
    if [[ -n "$gh_error" ]]; then
      sed 's/^/'"$ts"' github: /' <<<"$gh_error"
    fi
    return 1
  fi

  summary="$(jq -r '
    def bucket_name:
      ((.bucket // .conclusion // .state // "unknown") | tostring | ascii_downcase);
    def class_name:
      if bucket_name | test("^(pass|success|successful|skipped|skipping|neutral)$") then "pass"
      elif bucket_name | test("^(pending|queued|in_progress|waiting|requested|expected)$") then "pending"
      elif bucket_name | test("^(fail|failed|failure|error|cancelled|timed_out|action_required)$") then "fail"
      else "other"
      end;
    def count_class($name): [.[] | select(class_name == $name)] | length;
    {
      total: length,
      pass: count_class("pass"),
      pending: count_class("pending"),
      fail: count_class("fail"),
      other: count_class("other")
    }
    | .status = (
      if .fail > 0 then "fail"
      elif .pending > 0 then "pending"
      elif .total == 0 then "pending"
      elif .other > 0 then "pending"
      else "pass"
      end
    )
    | [.status, .total, .pass, .pending, .fail, .other] | @tsv
  ' <<<"$checks_json")"
  IFS=$'\t' read -r status total pass pending fail other <<<"$summary"

  printf '%s PR #%s checks: status=%s total=%s pass=%s pending=%s fail=%s other=%s\n' \
    "$ts" "$pr_number" "$status" "$total" "$pass" "$pending" "$fail" "$other"

  if [[ "$total" == "0" ]]; then
    printf '%s PR #%s checks: no check runs reported yet\n' "$ts" "$pr_number"
  fi

  rows="$(jq -r '
    def value($name): (($name // "") | tostring);
    def conclusion_name:
      if (.conclusion // "") != "" then (.conclusion | tostring)
      elif (.bucket // "") != "" then (.bucket | tostring)
      elif (.state // "") != "" then (.state | tostring)
      else "unknown"
      end;
    def bucket_name:
      ((.bucket // .conclusion // .state // "unknown") | tostring | ascii_downcase);
    def class_name:
      if bucket_name | test("^(pass|success|successful|skipped|skipping|neutral)$") then "pass"
      elif bucket_name | test("^(pending|queued|in_progress|waiting|requested|expected)$") then "pending"
      elif bucket_name | test("^(fail|failed|failure|error|cancelled|timed_out|action_required)$") then "fail"
      else "other"
      end;
    def sort_weight:
      if class_name == "fail" then 0
      elif class_name == "pending" then 1
      elif class_name == "other" then 2
      else 3
      end;
    sort_by(sort_weight, (.name // ""))
    | .[]
    | [
        class_name,
        value(.name // "unnamed check"),
        conclusion_name,
        value(.state // "unknown"),
        value(.workflow // ""),
        value(.link // "")
      ]
    | @tsv
  ' <<<"$checks_json")"

  while IFS=$'\t' read -r line_status name conclusion state workflow link; do
    [[ -n "${name:-}" ]] || continue
    rendered="$ts $line_status check=$(printf '%s' "$name" | jq -Rr @sh) conclusion=$(printf '%s' "$conclusion" | jq -Rr @sh) state=$(printf '%s' "$state" | jq -Rr @sh)"
    if [[ -n "$workflow" ]]; then
      rendered="$rendered workflow=$(printf '%s' "$workflow" | jq -Rr @sh)"
    fi
    if [[ -n "$link" ]]; then
      rendered="$rendered url=$link"
    fi
    printf '%s\n' "$rendered"
  done <<<"$rows"

  case "$status" in
    pass) rc=0 ;;
    fail) rc=1 ;;
    *) rc=2 ;;
  esac
  return "$rc"
}

main() {
  local pr_number=""
  local once=0
  local interval=30
  local status=0

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --pr)
        [[ "$#" -ge 2 ]] || watch_pr_die "--pr requires a value"
        pr_number="$2"
        shift 2
        ;;
      --pr=*)
        pr_number="${1#--pr=}"
        shift
        ;;
      --once)
        once=1
        shift
        ;;
      --interval)
        [[ "$#" -ge 2 ]] || watch_pr_die "--interval requires a value"
        interval="$2"
        shift 2
        ;;
      --interval=*)
        interval="${1#--interval=}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        watch_pr_die "unknown option: $1"
        ;;
      *)
        if [[ -n "$pr_number" ]]; then
          watch_pr_die "only one PR number may be supplied"
        fi
        pr_number="$1"
        shift
        ;;
    esac
  done

  watch_pr_nonnegative_integer "$interval" || watch_pr_die "--interval must be a non-negative integer"
  if [[ -z "$pr_number" ]]; then
    pr_number="$(watch_pr_infer_pr_number)"
  fi
  watch_pr_positive_integer "$pr_number" || watch_pr_die "PR number must be a positive integer"

  while true; do
    watch_pr_fetch_checks "$pr_number"
    if watch_pr_render_checks "$pr_number" "$WATCH_PR_CHECKS_JSON" "$WATCH_PR_CHECKS_GH_RC" "$WATCH_PR_CHECKS_GH_ERROR"; then
      exit 0
    else
      status="$?"
    fi

    if [[ "$status" -eq 1 ]]; then
      exit 1
    fi
    if [[ "$once" == "1" ]]; then
      exit 2
    fi

    printf '%s PR #%s checks: still pending; checking again in %ss\n' "$(watch_pr_now)" "$pr_number" "$interval"
    sleep "$interval"
  done
}

main "$@"
