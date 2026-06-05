#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-backlog-effort.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

BACKLOG_SOURCE_ONLY=1
source "$PROJECT_ROOT/orchestration/backlog.sh" >/dev/null 2>&1

assert_selection() {
  local context_kind="$1"
  local target_hint="$2"
  local job_reason="$3"
  local expected_effort="$4"
  local expected_class="$5"
  local expected_source="$6"
  local expected_reason="$7"
  local selected_effort task_class source reason

  IFS=$'\t' read -r selected_effort task_class source reason < <(
    backlog_reasoning_effort_select "$context_kind" "$target_hint" "$job_reason"
  )
  [[ "$selected_effort" == "$expected_effort" ]] ||
    fail "expected effort $expected_effort for context=$context_kind target=$target_hint reason=$job_reason, got $selected_effort"
  [[ "$task_class" == "$expected_class" ]] ||
    fail "expected class $expected_class for context=$context_kind target=$target_hint reason=$job_reason, got $task_class"
  [[ "$source" == "$expected_source" ]] ||
    fail "expected source $expected_source for context=$context_kind target=$target_hint reason=$job_reason, got $source"
  [[ "$reason" == "$expected_reason" ]] ||
    fail "expected reason $expected_reason for context=$context_kind target=$target_hint reason=$job_reason, got $reason"
}

test_docs_only_target_selects_low() {
  BACKLOG_REASONING_EFFORT_AUTOSIZE=1
  BACKLOG_REASONING_EFFORT_OVERRIDE=""
  BACKLOG_CODEX_REASONING_EFFORT="xhigh"

  assert_selection \
    "issue_repair" \
    "docs/scripts/upkeeper.md" \
    "issue #1: docs snapshot refresh" \
    "low" \
    "docs-only" \
    "auto" \
    "docs-oriented issue or job context"
}

test_mechanical_target_selects_medium() {
  BACKLOG_REASONING_EFFORT_AUTOSIZE=1
  BACKLOG_REASONING_EFFORT_OVERRIDE=""
  BACKLOG_CODEX_REASONING_EFFORT="xhigh"

  assert_selection \
    "issue_repair" \
    "Upkeeper.conf" \
    "issue #2: tiny config tweak" \
    "medium" \
    "mechanical" \
    "auto" \
    "small mechanical issue or job context"
}

test_high_risk_issue_title_selects_xhigh() {
  BACKLOG_REASONING_EFFORT_AUTOSIZE=1
  BACKLOG_REASONING_EFFORT_OVERRIDE=""
  BACKLOG_CODEX_REASONING_EFFORT="xhigh"

  assert_selection \
    "issue_repair" \
    "" \
    "issue #720: HIGH PRIORITY: Backlog triage does not size reasoning effort by task difficulty" \
    "xhigh" \
    "high-risk" \
    "auto" \
    "high-risk keywords in issue or job context"
}

test_newest_file_review_defaults_high() {
  BACKLOG_REASONING_EFFORT_AUTOSIZE=1
  BACKLOG_REASONING_EFFORT_OVERRIDE=""
  BACKLOG_CODEX_REASONING_EFFORT="xhigh"

  assert_selection \
    "newest_file_review" \
    "" \
    "no eligible backlog issue found" \
    "high" \
    "normal" \
    "auto" \
    "newest_file_review_without_target"
}

test_override_and_legacy_fallback_export_runtime_env() {
  BACKLOG_STATE_ROOT="$TEST_TMP_ROOT/state"
  BACKLOG_REASONING_EFFORT_AUTOSIZE=1
  BACKLOG_REASONING_EFFORT_OVERRIDE="medium"
  BACKLOG_CODEX_REASONING_EFFORT="xhigh"
  prepare_backlog_runtime_env "issue_repair" "Upkeeper.conf" "issue #2: tiny config tweak"
  [[ "$CODEX_REASONING_EFFORT" == "medium" ]] || fail "override did not export CODEX_REASONING_EFFORT=medium"
  [[ "$BACKLOG_SELECTED_REASONING_EFFORT" == "medium" ]] || fail "override did not export BACKLOG_SELECTED_REASONING_EFFORT=medium"
  [[ "$BACKLOG_REASONING_EFFORT_CLASS" == "mechanical" ]] || fail "override did not export BACKLOG_REASONING_EFFORT_CLASS=mechanical"
  [[ "$BACKLOG_REASONING_EFFORT_SOURCE" == "override" ]] || fail "override did not export BACKLOG_REASONING_EFFORT_SOURCE=override"
  [[ "$BACKLOG_REASONING_EFFORT_REASON" == "BACKLOG_REASONING_EFFORT_OVERRIDE" ]] || fail "override did not export BACKLOG_REASONING_EFFORT_REASON"

  BACKLOG_REASONING_EFFORT_AUTOSIZE=0
  BACKLOG_REASONING_EFFORT_OVERRIDE=""
  BACKLOG_CODEX_REASONING_EFFORT="high"
  prepare_backlog_runtime_env "newest_file_review" "" "no eligible backlog issue found"
  [[ "$CODEX_REASONING_EFFORT" == "high" ]] || fail "legacy fallback did not export CODEX_REASONING_EFFORT=high"
  [[ "$BACKLOG_SELECTED_REASONING_EFFORT" == "high" ]] || fail "legacy fallback did not export BACKLOG_SELECTED_REASONING_EFFORT=high"
  [[ "$BACKLOG_REASONING_EFFORT_CLASS" == "normal" ]] || fail "legacy fallback did not export BACKLOG_REASONING_EFFORT_CLASS=normal"
  [[ "$BACKLOG_REASONING_EFFORT_SOURCE" == "legacy" ]] || fail "legacy fallback did not export BACKLOG_REASONING_EFFORT_SOURCE=legacy"
  [[ "$BACKLOG_REASONING_EFFORT_REASON" == "BACKLOG_REASONING_EFFORT_AUTOSIZE=0" ]] || fail "legacy fallback did not export BACKLOG_REASONING_EFFORT_REASON"
}

test_docs_only_target_selects_low
test_mechanical_target_selects_medium
test_high_risk_issue_title_selects_xhigh
test_newest_file_review_defaults_high
test_override_and_legacy_fallback_export_runtime_env
printf 'backlog_reasoning_effort_test: ok\n'
