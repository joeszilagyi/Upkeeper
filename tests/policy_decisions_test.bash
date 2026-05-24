#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "$ROOT_DIR/lib/upkeeper/policy_decisions.bash"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_valid_decision() {
  local decision_json="$1"

  upkeeper_policy_decision_validate_json "$decision_json" ||
    fail "expected policy decision to validate: $decision_json"
}

assert_invalid_decision() {
  local decision_json="$1"

  if upkeeper_policy_decision_validate_json "$decision_json"; then
    fail "expected policy decision to be rejected: $decision_json"
  fi
}

test_policy_decision_emitter_outputs_schema_v1_json() {
  local decision_json

  decision_json="$(
    upkeeper_policy_decision_emit \
      selected-target-precontact \
      wrapper-local-control-plane \
      precontact \
      tools/example.py \
      true \
      true \
      false \
      false \
      false \
      false \
      tools/example.py \
      retarget,restore_backup,file_issue \
      selected_target_backed_up,quota_guardrail_allowed \
      Upkeeper.log
  )" || fail "policy decision emitter failed"

  assert_valid_decision "$decision_json"
  [[ "$(jq -r '.schema_version' <<<"$decision_json")" == "1" ]] ||
    fail "schema_version was not 1"
  [[ "$(jq -r '.capability_profile' <<<"$decision_json")" == "wrapper-local-control-plane" ]] ||
    fail "capability_profile was not preserved"
  [[ "$(jq -r '.may_retarget' <<<"$decision_json")" == "false" ]] ||
    fail "may_retarget was not a false boolean"
  [[ "$(jq -r '.denied_actions | join(",")' <<<"$decision_json")" == "retarget,restore_backup,file_issue" ]] ||
    fail "denied_actions were not preserved"
  [[ "$(jq -r '.reasons | length' <<<"$decision_json")" == "2" ]] ||
    fail "reasons were not split into two entries"
}

test_policy_decision_validator_rejects_prompt_like_or_incomplete_records() {
  local valid_base

  valid_base='{
    "schema_version": 1,
    "decision_id": "issue-comment-readonly",
    "capability_profile": "backend-codex-issue-comment",
    "mode": "issue-comment",
    "selected_target": "none",
    "may_contact_backend": true,
    "may_write_source": false,
    "may_retarget": false,
    "may_restore_backup": false,
    "may_use_network": false,
    "may_file_issue": false,
    "allowed_writes": [],
    "denied_actions": ["write_source", "file_issue"],
    "reasons": ["comment_stage_is_read_only"],
    "evidence": ["source_fingerprint_before_launch"]
  }'

  assert_valid_decision "$valid_base"
  assert_invalid_decision "$(jq '.may_contact_backend = "true"' <<<"$valid_base")"
  assert_invalid_decision "$(jq 'del(.reasons)' <<<"$valid_base")"
  assert_invalid_decision "$(jq '.reasons = []' <<<"$valid_base")"
  assert_invalid_decision "$(jq '.capability_profile = "model-said-ok"' <<<"$valid_base")"
  assert_invalid_decision "$(jq '.denied_actions = ["bad action"]' <<<"$valid_base")"
  assert_invalid_decision "$(jq '.schema_version = 2' <<<"$valid_base")"
}

test_policy_decision_emitter_rejects_bad_scalars() {
  local output rc

  set +e
  output="$(
    upkeeper_policy_decision_emit \
      bad-profile \
      unknown-profile \
      mode \
      none \
      true \
      false \
      false \
      false \
      false \
      false \
      "" \
      retarget \
      reason 2>&1
  )"
  rc=$?
  set -e
  [[ "$rc" -eq 2 ]] || fail "unknown profile exited $rc, expected 2"
  grep -Fq "unknown policy decision capability profile" <<<"$output" ||
    fail "unknown profile rejection was not clear: $output"

  set +e
  output="$(
    upkeeper_policy_decision_emit \
      bad-bool \
      operator \
      mode \
      none \
      yes \
      false \
      false \
      false \
      false \
      false \
      "" \
      retarget \
      reason 2>&1
  )"
  rc=$?
  set -e
  [[ "$rc" -eq 2 ]] || fail "bad boolean exited $rc, expected 2"
  grep -Fq "boolean must be true or false" <<<"$output" ||
    fail "bad boolean rejection was not clear: $output"
}

test_policy_decision_emitter_outputs_schema_v1_json
test_policy_decision_validator_rejects_prompt_like_or_incomplete_records
test_policy_decision_emitter_rejects_bad_scalars
printf 'ok - policy_decisions\n'
