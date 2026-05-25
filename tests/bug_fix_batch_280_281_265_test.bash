#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-bug-fix-280-281-265.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

write_message_file() {
  local path="$1"
  cat >"$path"
}

source "$PROJECT_ROOT/lib/upkeeper/runtime_format_json.bash"
source "$PROJECT_ROOT/lib/upkeeper/report_analysis.bash"
source "$PROJECT_ROOT/lib/upkeeper/status_session.bash"

test_status_marker_final_line_is_authoritative() {
  local messages="$TEST_TMP_ROOT/final-line.txt"

  write_message_file "$messages" <<'EOF'
UPKEEPER_STATUS: WORK_DONE
Intro text that should not count.
UPKEEPER_STATUS: BLOCKED
EOF

  analysis="$(while_marker_analysis_json "$messages")"
  accepted="$(json_field "$analysis" '.accepted_marker')"
  [[ "$accepted" == "BLOCKED" ]] || fail "expected final marker to win, got accepted=$accepted"
  [[ -z "$(json_field "$analysis" '.candidate_marker')" ]] || fail "did not expect candidate for exact final marker"
}

test_marker_analysis_missing_args_is_nonfatal() {
  local messages="$TEST_TMP_ROOT/missing-args.txt"
  local analysis accepted reason

  write_message_file "$messages" <<'EOF'
UPKEEPER_STATUS: WORK_DONE
EOF

  analysis="$(marker_analysis_json "$messages")"
  accepted="$(json_field "$analysis" '.accepted_marker')"
  reason="$(json_field "$analysis" '.candidate_rejection_reason')"
  [[ -z "$accepted" ]] || fail "expected missing parser args to avoid accepting a marker, got $accepted"
  [[ "$reason" == "invalid_marker_analysis_args" ]] || fail "expected invalid_marker_analysis_args, got $reason"
}

test_entrypoint_status_marker_override_uses_status_contract() {
  local messages="$TEST_TMP_ROOT/entrypoint-duplicate-marker.txt"
  local analysis accepted

  write_message_file "$messages" <<'EOF'
UPKEEPER_STATUS: WORK_DONE
Summary line after first marker.
`UPKEEPER_STATUS: BLOCKED`
Trailing human note after the final marker.
EOF

  analysis="$(
    UPKEEPER_CONFIG_DISABLE=1 UPKEEPER_LOCAL_ENV_DISABLE=1 CODEX_LOG_FILE="$TEST_TMP_ROOT/source-upkeeper.log" \
      bash -lc 'cd "$1"; source ./Upkeeper; while_marker_analysis_json "$2"' bash "$PROJECT_ROOT" "$messages"
  )"
  accepted="$(json_field "$analysis" '.accepted_marker')"
  [[ "$accepted" == "BLOCKED" ]] || fail "expected entrypoint override to recover final marker, got analysis=$analysis"
}

test_status_marker_ignores_non_final_markers_and_code_fence() {
  local messages="$TEST_TMP_ROOT/ignore-middle.txt"
  write_message_file "$messages" <<'EOF'
```
UPKEEPER_STATUS: WORK_DONE
```
Progress update
Trailing explanation.
EOF

  analysis="$(while_marker_analysis_json "$messages")"
  accepted="$(json_field "$analysis" '.accepted_marker')"
  candidate="$(json_field "$analysis" '.candidate_marker')"
  [[ -z "$accepted" ]] || fail "expected no accepted final status marker, got $accepted"
  [[ -z "$candidate" ]] || fail "expected no candidate status marker when final non-status line present, got $candidate"
}

test_status_marker_rejects_malformed_final_marker_and_keeps_reason() {
  local messages="$TEST_TMP_ROOT/malformed-final.txt"
  write_message_file "$messages" <<'EOF'
UPKEEPER_STATUS: WORK_DONE
Summary: done.
UPKEEPER_STATUS: WORK_DONE please follow up with the model
EOF

  analysis="$(while_marker_analysis_json "$messages")"
  accepted="$(json_field "$analysis" '.accepted_marker')"
  candidate="$(json_field "$analysis" '.candidate_marker')"
  reason="$(json_field "$analysis" '.candidate_rejection_reason')"
  [[ -z "$accepted" ]] || fail "expected malformed final marker to be rejected, got accepted=$accepted"
  [[ "$candidate" == "WORK_DONE" ]] || fail "expected malformed marker recorded as candidate, got candidate=$candidate"
  [[ -n "$reason" ]] || fail "expected malformed marker rejection reason"
}

test_status_marker_recovers_inline_backtick_final_marker() {
  local messages="$TEST_TMP_ROOT/inline-backtick-final.txt"
  local analysis resolved source
  write_message_file "$messages" <<'EOF'
Review complete.
`UPKEEPER_STATUS: WORK_DONE`
EOF

  analysis="$(while_marker_analysis_json "$messages")"
  source="$(json_field "$analysis" '.candidate_rejection_reason')"
  resolved="$(resolved_status_marker_from_analysis "$analysis" 0 present)"
  [[ "$source" == "markdown_backticks" ]] || fail "expected markdown_backticks candidate reason, got $source"
  [[ "$resolved" == "WORK_DONE" ]] || fail "expected inline backtick marker to resolve to WORK_DONE, got $resolved"
}

test_status_alias_no_changes_resolves_to_work_done() {
  local messages="$TEST_TMP_ROOT/no-changes.txt"
  write_message_file "$messages" <<'EOF'
UPKEEPER_STATUS: NO_CHANGES
EOF

  analysis="$(while_marker_analysis_json "$messages")"
  resolved="$(resolved_status_marker_from_analysis "$analysis" 0 present)"
  [[ "$resolved" == "WORK_DONE" ]] || fail "expected NO_CHANGES marker to resolve to WORK_DONE, got $resolved"
}

test_status_marker_rejects_multiple_markers_in_final_line() {
  local messages="$TEST_TMP_ROOT/multiple-final.txt"
  write_message_file "$messages" <<'EOF'
UPKEEPER_STATUS: WORK_DONE UPKEEPER_STATUS: BLOCKED
EOF

  analysis="$(while_marker_analysis_json "$messages")"
  accepted="$(json_field "$analysis" '.accepted_marker')"
  candidate="$(json_field "$analysis" '.candidate_marker')"
  reason="$(json_field "$analysis" '.candidate_rejection_reason')"
  [[ -z "$accepted" ]] || fail "expected multiple final markers to be rejected, got accepted=$accepted"
  [[ "$reason" == "multiple_markers" ]] || fail "expected multiple_markers reason for malformed final line, got reason=$reason"
  [[ "$candidate" == "WORK_DONE" || "$candidate" == "BLOCKED" ]] || fail "expected a candidate marker for malformed final line, got candidate=$candidate"
}

test_postmortem_status_parser_enforces_final_exact_contract() {
  local messages="$TEST_TMP_ROOT/postmortem-final.txt"
  write_message_file "$messages" <<'EOF'
Some recovery text
CODEX_POSTMORTEM_STATUS: REPORT_WRITTEN
EOF

  marker="$(parse_postmortem_marker "$messages")"
  [[ "$marker" == "REPORT_WRITTEN" ]] || fail "expected exact final postmortem marker, got $marker"

  write_message_file "$messages" <<'EOF'
```
CODEX_POSTMORTEM_STATUS: REPORT_WRITTEN
```
EOF
  marker="$(parse_postmortem_marker "$messages")"
  [[ -z "$marker" ]] || fail "expected fenced postmortem marker to be rejected, got $marker"
}

test_status_marker_final_line_is_authoritative
test_marker_analysis_missing_args_is_nonfatal
test_entrypoint_status_marker_override_uses_status_contract
test_status_marker_ignores_non_final_markers_and_code_fence
test_status_marker_rejects_malformed_final_marker_and_keeps_reason
test_status_marker_recovers_inline_backtick_final_marker
test_status_alias_no_changes_resolves_to_work_done
test_status_marker_rejects_multiple_markers_in_final_line
test_postmortem_status_parser_enforces_final_exact_contract

printf 'bug_fix_batch_280_281_265_test: ok\n'
