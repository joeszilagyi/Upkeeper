#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-bug-fix-278.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

contract_field() {
  local key="$1"
  local source_text="$2"

  awk -F= -v key="$key" '$1 == key { sub("^[^=]*=", ""); print; exit }' <<<"$source_text"
}

require_field() {
  local actual expected field
  field="$1"
  expected="$2"
  actual="$3"
  [[ "$actual" == "$expected" ]] || fail "$field expected=$expected actual=$actual"
}

test_fallback_child_inherits_effective_issue_fix_and_selection_contract() {
  local contract_file bad_config manifest_path selected_path
  local child_output child_rc
  bad_config="$TEST_TMP_ROOT/missing-upkeeper.conf"
  rm -f "$bad_config"
  manifest_path="$TEST_TMP_ROOT/manifest.json"
  selected_path="contracts/fix-me.sh"
  contract_file="$TEST_TMP_ROOT/fallback-278.contract"

  cat >"$contract_file" <<EOF
UPKEEPER_CONFIG_DISABLE=1
UPKEEPER_CONFIG_FILE_EXPLICIT=1
UPKEEPER_CONFIG_FILE=/tmp/missing-upkeeper-contract.conf
UPKEEPER_CONFIG_LOADED=0
UPKEEPER_CONFIG_SOURCE=contract-driven
CODEX_SELECTION_SOURCE=enumerate
CODEX_SELECTION_ORDER=random
CODEX_FILE_MANIFEST_MODE=refresh
CODEX_FILE_MANIFEST_PATH=$manifest_path
CODEX_TARGET_ROOT=target-root
CODEX_TARGET_MAX_DEPTH=7
CODEX_SELECTION_INCLUDE_GLOBS=*.md
CODEX_SELECTION_EXCLUDE_GLOBS=*.tmp
CODEX_SELECTION_REVIEW_MODULES=p24,p25
CODEX_SELECTION_RANDOM_SEED=42
CODEX_MAX_COVER_MODE=1
CODEX_ISSUE_FIX_NEXT=1
CODEX_ISSUE_FIX_REQUESTED_NUMBER=278
CODEX_ISSUE_WORKFLOW_STAGE=review
CODEX_ISSUE_FIX_NUMBER=278
CODEX_ISSUE_FIX_SELECTED_LABEL=explicit
CODEX_ISSUE_FIX_LABELS=security,data-integrity
CODEX_ISSUE_FIX_TARGET_FILE=$selected_path
CODEX_ISSUE_FIX_TITLE=Example\ security\ bug
CODEX_ISSUE_FIX_URL=https://example.test/issues/278
CODEX_ISSUE_FIX_CREATED_AT=2026-05-10T00:22:12Z
CODEX_ISSUE_FIX_BODY=Body\ text\ for\ issue\ 278
CODEX_ISSUE_FIX_COMMENTS_JSON=\[\{\"body\":\"first\ comment\"\}\]
CODEX_TOOL_FAILURE_QUEUE_DIR=$TEST_TMP_ROOT/queue
CODEX_TOOL_FAILURE_QUEUE_BYPASS=1
RUN_SELECTED_REVIEW_PATH=$selected_path
RUN_SELECTED_REVIEW_BASIS=issue-fix
RUN_SELECTED_FROM_FAILURE_QUEUE=1
RUN_SELECTED_FAILURE_MARKER_ID=issue-278
RUN_SELECTED_FAILURE_MARKER_PATH=$TEST_TMP_ROOT/marker
EOF

set +e
  child_output="$(
    CODEX_FALLBACK_CHAIN_ACTIVE=1 \
    CODEX_FALLBACK_CONTRACT_PATH="$contract_file" \
    CODEX_LOG_FILE="$TEST_TMP_ROOT/fallback-child.log" \
    CODEX_POSTMORTEM_DIR="$TEST_TMP_ROOT" \
    UPKEEPER_CONFIG_FILE="$bad_config" \
    UPKEEPER_CONFIG_FILE_EXPLICIT=1 \
    UPROOT="$PROJECT_ROOT" \
    bash -c 'set -euo pipefail
      source "$UPROOT/Upkeeper"
      printf "cfg_disable=%s\n" "$UPKEEPER_CONFIG_DISABLE"
      printf "cfg_file=%s\n" "$UPKEEPER_CONFIG_FILE"
      printf "cfg_loaded=%s\n" "$UPKEEPER_CONFIG_LOADED"
      printf "cfg_source=%s\n" "$UPKEEPER_CONFIG_SOURCE"
      printf "selection_source=%s\n" "$CODEX_SELECTION_SOURCE"
      printf "selection_order=%s\n" "$CODEX_SELECTION_ORDER"
      printf "manifest_mode=%s\n" "$CODEX_FILE_MANIFEST_MODE"
      printf "manifest_path=%s\n" "$CODEX_FILE_MANIFEST_PATH"
      printf "target_root=%s\n" "$CODEX_TARGET_ROOT"
      printf "target_depth=%s\n" "$CODEX_TARGET_MAX_DEPTH"
      printf "include_globs=%s\n" "$CODEX_SELECTION_INCLUDE_GLOBS"
      printf "exclude_globs=%s\n" "$CODEX_SELECTION_EXCLUDE_GLOBS"
      printf "issue_next=%s\n" "$CODEX_ISSUE_FIX_NEXT"
      printf "issue_requested=%s\n" "$CODEX_ISSUE_FIX_REQUESTED_NUMBER"
      printf "issue_stage=%s\n" "$CODEX_ISSUE_WORKFLOW_STAGE"
      printf "issue_number=%s\n" "$CODEX_ISSUE_FIX_NUMBER"
      printf "issue_selected_label=%s\n" "$CODEX_ISSUE_FIX_SELECTED_LABEL"
      printf "issue_target=%s\n" "$CODEX_ISSUE_FIX_TARGET_FILE"
      printf "queue_dir=%s\n" "$CODEX_TOOL_FAILURE_QUEUE_DIR"
      printf "queue_bypass=%s\n" "$CODEX_TOOL_FAILURE_QUEUE_BYPASS"
      printf "run_selected_path=%s\n" "$RUN_SELECTED_REVIEW_PATH"
      printf "run_selected_from_failure_queue=%s\n" "$RUN_SELECTED_FROM_FAILURE_QUEUE"
      printf "run_selected_marker=%s\n" "$RUN_SELECTED_FAILURE_MARKER_ID"
    '
  )"
child_rc="$?"
set -e
  [[ "$child_rc" -eq 0 ]] || fail "fallback startup did not inherit fallback contract and exited $child_rc"

  require_field "cfg_disable" "1" "$(contract_field cfg_disable "$child_output")"
  require_field "cfg_file" "/tmp/missing-upkeeper-contract.conf" "$(contract_field cfg_file "$child_output")"
  require_field "cfg_loaded" "0" "$(contract_field cfg_loaded "$child_output")"
  require_field "cfg_source" "contract-driven" "$(contract_field cfg_source "$child_output")"
  require_field "selection_source" "enumerate" "$(contract_field selection_source "$child_output")"
  require_field "selection_order" "random" "$(contract_field selection_order "$child_output")"
  require_field "manifest_mode" "refresh" "$(contract_field manifest_mode "$child_output")"
  require_field "manifest_path" "$manifest_path" "$(contract_field manifest_path "$child_output")"
  require_field "target_root" "target-root" "$(contract_field target_root "$child_output")"
  require_field "target_depth" "7" "$(contract_field target_depth "$child_output")"
  require_field "issue_next" "1" "$(contract_field issue_next "$child_output")"
  require_field "issue_requested" "278" "$(contract_field issue_requested "$child_output")"
  require_field "issue_stage" "review" "$(contract_field issue_stage "$child_output")"
  require_field "issue_number" "278" "$(contract_field issue_number "$child_output")"
  require_field "issue_selected_label" "explicit" "$(contract_field issue_selected_label "$child_output")"
  require_field "issue_target" "$selected_path" "$(contract_field issue_target "$child_output")"
  require_field "queue_dir" "$TEST_TMP_ROOT/queue" "$(contract_field queue_dir "$child_output")"
  require_field "queue_bypass" "1" "$(contract_field queue_bypass "$child_output")"
  require_field "run_selected_path" "$selected_path" "$(contract_field run_selected_path "$child_output")"
  require_field "run_selected_from_failure_queue" "1" "$(contract_field run_selected_from_failure_queue "$child_output")"
  require_field "run_selected_marker" "issue-278" "$(contract_field run_selected_marker "$child_output")"
}

test_screen_fallback_private_stage_preserves_contract() {
  local postmortem_root stage_parent stage_root contract_file output runner_path visible_root contract_q mode

  postmortem_root="$TEST_TMP_ROOT/postmortems"
  stage_parent="$TEST_TMP_ROOT/private-stage"
  stage_root="$stage_parent/fallback-screen"
  mkdir -p "$postmortem_root/cycle-screen" "$stage_parent"
  chmod 700 "$postmortem_root" "$postmortem_root/cycle-screen" "$stage_parent"

  contract_file="$postmortem_root/cycle-screen/fallback.contract"
  printf 'CODEX_TARGET_FILE=%q\n' "selected/from-contract.sh" >"$contract_file"
  chmod 600 "$contract_file"

  output="$(
    UPKEEPER_CONFIG_DISABLE=1 \
    CODEX_FALLBACK_CHAIN_ACTIVE=0 \
    CODEX_LOG_FILE="$TEST_TMP_ROOT/screen-fallback.log" \
    CODEX_POSTMORTEM_DIR="$postmortem_root" \
    CODEX_FALLBACK_SCREEN_STAGE_ROOT="$stage_root" \
    UPROOT="$PROJECT_ROOT" \
    bash -s <<'SH'
set -euo pipefail

source "$UPROOT/Upkeeper"

parent_shell_details() {
  printf '123\tbash\twhile ./Upkeeper; do sleep 60; done\t0\n'
}

generate_fallback_chain_token() {
  printf 'test-token'
}

CYCLE_ID="cycle-screen"
ROOT_DIR="$UPROOT"
SELF_INVOKE_PATH="$UPROOT/Upkeeper"
UPKEEPER_DRY_RUN="1"
CODEX_FALLBACK_MODEL="gpt-test"
CODEX_FALLBACK_REASONING_EFFORT="low"
CODEX_FALLBACK_MODE="--sandbox workspace-write"
CODEX_MODEL="gpt-primary"
CODEX_FALLBACK_CONTRACT_PATH="$CODEX_POSTMORTEM_DIR/$CYCLE_ID/fallback.contract"
PROMPT_FILE=""
INLINE_PROMPT=""
CODEX_TARGET_FILE=""
CODEX_PROMPT_PASS=""
CODEX_REVIEW_MODULES=()

launch_screen_fallback_loop blocked test-detail
printf 'runner=%s\n' "$FALLBACK_SCREEN_RUNNER_PATH"
printf 'transcript=%s\n' "$FALLBACK_SCREEN_TRANSCRIPT_PATH"
SH
  )"

  runner_path="$(contract_field runner "$output")"
  [[ -n "$runner_path" ]] || fail "screen fallback did not report runner path"
  [[ "$runner_path" == "$stage_root/"* ]] || fail "screen fallback runner was not staged under private root: $runner_path"
  [[ "$runner_path" != "$postmortem_root/"* ]] || fail "screen fallback runner leaked into postmortem evidence root"
  [[ -f "$runner_path" ]] || fail "screen fallback runner was not created"
  mode="$(stat -Lc '%a' "$runner_path" 2>/dev/null || stat -f '%Lp' "$runner_path")"
  [[ "$mode" == "700" ]] || fail "screen fallback runner mode expected 700 actual=$mode"
  bash -n "$runner_path"

  visible_root="$postmortem_root/cycle-screen/screen"
  [[ "$(tr -d '[:space:]' <"$visible_root/final-exit-code.txt")" == "0" ]] || fail "dry-run screen fallback did not mirror final exit"
  [[ "$(tr -d '[:space:]' <"$visible_root/done.txt")" != "" ]] || fail "dry-run screen fallback did not mirror done state"

  printf -v contract_q '%q' "$contract_file"
  grep -Fq "CODEX_FALLBACK_CONTRACT_PATH=$contract_q" "$runner_path" || fail "screen runner did not preserve fallback contract path"
  ! grep -Fq "CODEX_FALLBACK_CONTRACT_PATH=''" "$runner_path" || fail "screen runner reset fallback contract path to empty"
}

test_fallback_child_inherits_effective_issue_fix_and_selection_contract
test_screen_fallback_private_stage_preserves_contract

printf 'bug_fix_batch_278_test: ok\n'
