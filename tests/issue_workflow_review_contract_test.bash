#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-issue-workflow-review.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

reset_issue_workflow_env() {
  CODEX_ISSUE_FIX_NEXT=1
  CODEX_ISSUE_FIX_REQUESTED_NUMBER=651
  CODEX_ISSUE_FIX_NUMBER=651
  CODEX_ISSUE_WORKFLOW_STAGE=review
  CODEX_ISSUE_FIX_COMMENTS_JSON='[]'
  RUN_ISSUE_WORKFLOW_COMMENT_FILE=""
  ISSUE_WORKFLOW_FINISH_ARGS=""
}

extract_json_assignment() {
  local file="$1"
  local key="$2"

  python3 - "$file" "$key" <<'PY'
import json
import sys

path, key = sys.argv[1:3]
with open(path, "r", encoding="utf-8", errors="replace") as handle:
    for raw_line in handle:
        line = raw_line.rstrip("\n")
        prefix = key + "="
        if line.startswith(prefix):
            print(json.loads(line[len(prefix):]))
            raise SystemExit(0)
raise SystemExit(1)
PY
}

export PROJECT_ROOT
export ROOT_DIR="$PROJECT_ROOT"
export UPROOT="$PROJECT_ROOT"
export CODEX_LOG_FILE="$TEST_TMP_ROOT/Upkeeper.log"
export UPKEEPER_CONFIG_DISABLE=1
source "$PROJECT_ROOT/Upkeeper"

run_mktemp() {
  mktemp "$TEST_TMP_ROOT/${1:-tmp}.XXXXXX"
}

log_line() {
  :
}

finish_cycle() {
  ISSUE_WORKFLOW_FINISH_ARGS="$*"
  return 99
}

test_review_stage_prompt_includes_latest_proposal_and_read_only_validation_rule() {
  local compiled proposal_text

  reset_issue_workflow_env
  CODEX_ISSUE_FIX_COMMENTS_JSON='[
    {"body":"Older unrelated comment"},
    {"body":"Upkeeper ChimneySweep proposal:\nFirst proposal body"},
    {"body":"Upkeeper ChimneySweep proposal:\nLatest proposal body\nwith current context"}
  ]'
  compiled="$TEST_TMP_ROOT/review-stage.prompt"
  : >"$compiled"

  append_issue_workflow_stage_prompt "$compiled" || fail "review stage prompt unexpectedly failed"

  proposal_text="$(extract_json_assignment "$compiled" "issue_workflow_latest_proposal_comment_json")" ||
    fail "review stage prompt did not emit proposal comment JSON"
  [[ "$proposal_text" == *"Latest proposal body"* ]] ||
    fail "review stage prompt did not use the latest proposal comment"
  [[ "$proposal_text" != *"First proposal body"* ]] ||
    fail "review stage prompt did not prefer the latest proposal comment"
  grep -Fq 'Do not rely on validators that require writable scratch space or `mktemp` success inside the read-only backend sandbox' "$compiled" ||
    fail "review stage prompt missing read-only validation guidance"
}

test_review_stage_prompt_fails_closed_without_proposal_context() {
  local compiled rc

  reset_issue_workflow_env
  CODEX_ISSUE_FIX_COMMENTS_JSON='[
    {"body":"Upkeeper ChimneySweep review: approved"},
    {"body":"General non-proposal comment"}
  ]'
  compiled="$TEST_TMP_ROOT/review-stage-missing-proposal.prompt"
  : >"$compiled"

  set +e
  append_issue_workflow_stage_prompt "$compiled" >/dev/null 2>&1
  rc=$?
  set -e

  [[ "$rc" -eq 99 ]] || fail "review stage missing proposal exited $rc, expected finish_cycle override 99"
  [[ "$ISSUE_WORKFLOW_FINISH_ARGS" == *"2 ISSUE_WORKFLOW_REVIEW_CONTEXT_MISSING WARN"* ]] ||
    fail "review stage missing proposal did not fail closed with the expected reason"
}

test_review_stage_blocked_comment_maps_to_blocked_status_override() {
  local comment_file override

  comment_file="$TEST_TMP_ROOT/review-comment-blocked.md"
  cat >"$comment_file" <<'EOF'
Upkeeper ChimneySweep review: blocked

The proposal is missing transaction rollback context.
EOF

  override="$(upkeeper_issue_workflow_status_marker_override review "$comment_file")" ||
    fail "blocked review comment did not produce a status override"
  [[ "$override" == $'blocked\tBLOCKED' ]] ||
    fail "blocked review comment override was $override"
}

test_review_stage_prompt_includes_latest_proposal_and_read_only_validation_rule
test_review_stage_prompt_fails_closed_without_proposal_context
test_review_stage_blocked_comment_maps_to_blocked_status_override

printf 'issue_workflow_review_contract_test: ok\n'
