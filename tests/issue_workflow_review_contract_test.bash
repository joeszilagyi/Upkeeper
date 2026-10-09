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

test_issue_comment_actuator_requires_typed_action_record() {
  local action draft_file posted_file rc

  reset_issue_workflow_env
  CODEX_ISSUE_WORKFLOW_STAGE=comment
  CODEX_ISSUE_FIX_NUMBER=651
  RUN_SELECTED_REVIEW_PATH=Upkeeper
  draft_file="$TEST_TMP_ROOT/comment-action.md"
  posted_file="$TEST_TMP_ROOT/comment-posted.md"
  RUN_ISSUE_WORKFLOW_COMMENT_FILE="$draft_file"
  mkdir -p "$TEST_TMP_ROOT/bin"
  cat >"$TEST_TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == issue && "${2:-}" == comment && "${3:-}" == 651 && "${4:-}" == --body-file ]]
cp -- "$5" "$UPKEEPER_TEST_POSTED_FILE"
EOF
  chmod +x "$TEST_TMP_ROOT/bin/gh"
  PATH="$TEST_TMP_ROOT/bin:$PATH"
  UPKEEPER_TEST_POSTED_FILE="$posted_file"
  export UPKEEPER_TEST_POSTED_FILE

  printf 'Upkeeper ChimneySweep proposal:\n\nValidated action.\n' >"$draft_file"
  action="$(upkeeper_issue_workflow_comment_action_json WORK_DONE 0 unchanged "$RUN_SELECTED_REVIEW_PATH")" ||
    fail "valid comment action record was not created"
  jq -e '
    .schema_version == "upkeeper.issue_comment_action.v1" and
    .issue_number == "651" and .stage == "comment" and
    .accepted_status == "WORK_DONE" and .codex_exit == 0 and
    .source_guard_outcome == "unchanged" and .selected_target == "Upkeeper" and
    (.draft_path_hash | test("^path-hmac-sha256:[0-9a-f]{64}$")) and
    (.draft_sha256 | test("^[0-9a-f]{64}$"))
  ' <<<"$action" >/dev/null || fail "valid comment action record omitted required bindings"
  upkeeper_issue_workflow_post_comment "$action" WORK_DONE 0 unchanged "$RUN_SELECTED_REVIEW_PATH" ||
    fail "valid typed comment action was not posted"
  cmp -s "$draft_file" "$posted_file" || fail "valid typed comment action posted wrong body"

  if upkeeper_issue_workflow_comment_action_json "" 0 unchanged "$RUN_SELECTED_REVIEW_PATH" >/dev/null; then
    fail "comment action builder accepted missing status"
  fi
  if upkeeper_issue_workflow_comment_action_json WORK_DONE 0 violation "$RUN_SELECTED_REVIEW_PATH" >/dev/null; then
    fail "comment action builder accepted source mutation violation"
  fi

  rm -f -- "$posted_file"
  printf 'tampered after action creation\n' >>"$draft_file"
  set +e
  upkeeper_issue_workflow_post_comment "$action" WORK_DONE 0 unchanged "$RUN_SELECTED_REVIEW_PATH"
  rc=$?
  set -e
  [[ "$rc" -ne 0 && ! -e "$posted_file" ]] || fail "comment actuator accepted altered draft content"
  printf 'Upkeeper ChimneySweep proposal:\n\nValidated action.\n' >"$draft_file"

  RUN_SELECTED_REVIEW_PATH=other-target
  set +e
  upkeeper_issue_workflow_post_comment "$action" WORK_DONE 0 unchanged "$RUN_SELECTED_REVIEW_PATH"
  rc=$?
  set -e
  [[ "$rc" -ne 0 && ! -e "$posted_file" ]] || fail "comment actuator accepted wrong selected target"
  RUN_SELECTED_REVIEW_PATH=Upkeeper

  set +e
  upkeeper_issue_workflow_post_comment '{}' WORK_DONE 0 unchanged "$RUN_SELECTED_REVIEW_PATH"
  rc=$?
  set -e
  [[ "$rc" -ne 0 && ! -e "$posted_file" ]] || fail "comment actuator accepted invalid action record"

  action="$(jq -c '.source_guard_outcome="violation"' <<<"$action")"
  set +e
  upkeeper_issue_workflow_post_comment "$action" WORK_DONE 0 unchanged "$RUN_SELECTED_REVIEW_PATH"
  rc=$?
  set -e
  [[ "$rc" -ne 0 && ! -e "$posted_file" ]] || fail "comment actuator accepted mutation-violation action"

  printf 'Wrong comment prefix.\n' >"$draft_file"
  action="$(upkeeper_issue_workflow_comment_action_json WORK_DONE 0 unchanged "$RUN_SELECTED_REVIEW_PATH")" ||
    fail "wrong-prefix fixture action record was not created"
  set +e
  upkeeper_issue_workflow_post_comment "$action" WORK_DONE 0 unchanged "$RUN_SELECTED_REVIEW_PATH"
  rc=$?
  set -e
  [[ "$rc" -ne 0 && ! -e "$posted_file" ]] || fail "comment actuator accepted wrong prefix"
}

test_review_stage_prompt_includes_latest_proposal_and_read_only_validation_rule
test_review_stage_prompt_fails_closed_without_proposal_context
test_review_stage_blocked_comment_maps_to_blocked_status_override
test_issue_comment_actuator_requires_typed_action_record

printf 'issue_workflow_review_contract_test: ok\n'
