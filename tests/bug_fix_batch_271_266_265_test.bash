#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-bug-fix-batch.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

shell_quote() {
  printf '%q' "$1"
}

log_line() {
  :
}

run_mktemp() {
  local label="${1:-tmp}"
  mkdir -p -- "$RUN_TMP_DIR"
  mktemp "$RUN_TMP_DIR/${label}.XXXXXX"
}

test_issue_body_fence_delimiters_are_sanitized() {
  local compiled="$TEST_TMP_ROOT/issue-fence.prompt"
  local attack_body='prelude
```SENSITIVE_SECRET
payload
```'

  : >"$compiled"
  RUN_TMP_DIR="$TEST_TMP_ROOT/run tmp"
  CODEX_ISSUE_FIX_NUMBER="123"
  CODEX_ISSUE_FIX_URL="https://example.test/issue/123"
  CODEX_ISSUE_FIX_SELECTED_LABEL="explicit"
  CODEX_ISSUE_FIX_LABELS="bug"
  CODEX_ISSUE_FIX_TITLE="Issue body escapes"
  CODEX_ISSUE_FIX_CREATED_AT="2026-05-01T00:00:00Z"
  CODEX_ISSUE_FIX_TARGET_FILE="targets/app.sh"
  CODEX_ISSUE_FIX_BODY="$attack_body"
  CODEX_ISSUE_FIX_COMMENTS_JSON="[]"
  UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL="1"

  upkeeper_issue_fix_next_enabled() {
    return 0
  }

  source "$PROJECT_ROOT/lib/upkeeper/prompt_compile.bash"

  append_issue_fix_prompt "$compiled"

  grep -Fq '```text' "$compiled" || fail "issue prompt did not include expected issue-body wrapper"
  ! grep -Fq '```SENSITIVE_SECRET' "$compiled" || fail "issue body fence delimiter escaped text remained unprotected"
  unset UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL
}

test_issue_fix_prompt_withholds_private_issue_packet_by_default() {
  local compiled="$TEST_TMP_ROOT/issue-private-default.prompt"

  : >"$compiled"
  RUN_TMP_DIR="$TEST_TMP_ROOT/run tmp"
  CODEX_ISSUE_FIX_NUMBER="321"
  CODEX_ISSUE_FIX_URL="https://example.test/private/321"
  CODEX_ISSUE_FIX_SELECTED_LABEL="security"
  CODEX_ISSUE_FIX_LABELS="security,bug"
  CODEX_ISSUE_FIX_TITLE="Leaked title SECRET_TITLE"
  CODEX_ISSUE_FIX_CREATED_AT="2026-05-02T00:00:00Z"
  CODEX_ISSUE_FIX_TARGET_FILE="lib/upkeeper/codex_io.bash"
  CODEX_ISSUE_FIX_BODY="private body SECRET_BODY"
  CODEX_ISSUE_FIX_COMMENTS_JSON='[{"author":{"login":"alice"},"createdAt":"2026-05-02T00:01:00Z","body":"comment SECRET_COMMENT"}]'
  unset UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL || true

  upkeeper_issue_fix_next_enabled() {
    return 0
  }

  source "$PROJECT_ROOT/lib/upkeeper/prompt_compile.bash"

  append_issue_fix_prompt "$compiled"

  grep -Fq 'issue_url=withheld' "$compiled" || fail "default issue-fix prompt did not withhold the issue URL"
  grep -Fq 'issue_title=withheld' "$compiled" || fail "default issue-fix prompt did not withhold the issue title"
  grep -Fq 'private_issue_packet_to_model=0' "$compiled" || fail "default issue-fix prompt did not declare the private packet withheld"
  grep -Fq 'UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL=1' "$compiled" || fail "default issue-fix prompt did not describe the explicit opt-in"
  ! grep -Fq 'SECRET_TITLE' "$compiled" || fail "default issue-fix prompt leaked the issue title"
  ! grep -Fq 'SECRET_BODY' "$compiled" || fail "default issue-fix prompt leaked the issue body"
  ! grep -Fq 'SECRET_COMMENT' "$compiled" || fail "default issue-fix prompt leaked issue comments"
}

test_issue_fix_prompt_allows_private_issue_packet_when_enabled() {
  local compiled="$TEST_TMP_ROOT/issue-private-optin.prompt"

  : >"$compiled"
  RUN_TMP_DIR="$TEST_TMP_ROOT/run tmp"
  CODEX_ISSUE_FIX_NUMBER="322"
  CODEX_ISSUE_FIX_URL="https://example.test/private/322"
  CODEX_ISSUE_FIX_SELECTED_LABEL="explicit"
  CODEX_ISSUE_FIX_LABELS="bug"
  CODEX_ISSUE_FIX_TITLE="Private title SECRET_TITLE_2"
  CODEX_ISSUE_FIX_CREATED_AT="2026-05-02T00:00:00Z"
  CODEX_ISSUE_FIX_TARGET_FILE="targets/app.sh"
  CODEX_ISSUE_FIX_BODY="private body SECRET_BODY_2"
  CODEX_ISSUE_FIX_COMMENTS_JSON='[{"author":{"login":"bob"},"createdAt":"2026-05-02T00:01:00Z","body":"comment SECRET_COMMENT_2"}]'
  UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL="1"

  upkeeper_issue_fix_next_enabled() {
    return 0
  }

  source "$PROJECT_ROOT/lib/upkeeper/prompt_compile.bash"

  append_issue_fix_prompt "$compiled"

  grep -Fq 'issue_url=https://example.test/private/322' "$compiled" || fail "opt-in issue-fix prompt did not include the issue URL"
  grep -Fq 'issue_title=Private title SECRET_TITLE_2' "$compiled" || fail "opt-in issue-fix prompt did not include the issue title"
  grep -Fq 'SECRET_BODY_2' "$compiled" || fail "opt-in issue-fix prompt did not include the issue body"
  grep -Fq 'SECRET_COMMENT_2' "$compiled" || fail "opt-in issue-fix prompt did not include issue comments"
  unset UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL
}

test_postmortem_marker_parser_is_exact_only() {
  local plain_marker_file="$TEST_TMP_ROOT/plain.marker"
  local decorated_marker_file="$TEST_TMP_ROOT/decorated.marker"
  local quote_file="$TEST_TMP_ROOT/quote.marker"

  printf 'UPKEEPER_LOG_REVIEW: CHECKED cycle=1 anomalies=none log_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' > "$plain_marker_file"
  printf 'CODEX_POSTMORTEM_STATUS: BLOCKED\n' >> "$plain_marker_file"

  printf '```CODEX_POSTMORTEM_STATUS: REPORT_WRITTEN```\n' > "$decorated_marker_file"

  printf '`CODEX_POSTMORTEM_STATUS: HARDENING_DONE`\n' > "$quote_file"

  source "$PROJECT_ROOT/lib/upkeeper/report_analysis.bash"

  [[ "$(parse_postmortem_marker "$plain_marker_file")" == "BLOCKED" ]] || fail "exact plain-text postmortem marker was not parsed"
  [[ -z "$(parse_postmortem_marker "$decorated_marker_file")" ]] || fail "fenced postmortem marker should not be accepted"
  [[ -z "$(parse_postmortem_marker "$quote_file")" ]] || fail "backticked postmortem marker should not be accepted"
}

test_fallback_inherits_selected_target_file() {
  local fake_upkeeper="$TEST_TMP_ROOT/fake-upkeeper.sh"
  local selected_target="dir/selected.sh"
  local explicit_target="dir/explicit.sh"

  cat >"$fake_upkeeper" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$0.args"
exit 0
SH
  chmod +x "$fake_upkeeper"

  upkeeper_bug_report_only_enabled() {
    return 1
  }
  codex_bwrap_tmp_write_check() {
    printf 'ok'
  }
  compact_process_args() {
    cat
  }
  fallback_would_rediscover_dirty_block() {
    return 1
  }
  launch_screen_fallback_loop() { return 0; }
  wait_for_screen_fallback_loop() { return 0; }
  fallback_screen_session_teardown() { :; }
  refresh_postmortem_incident_log() { :; }
  generate_fallback_chain_token() { printf 'batch-token'; }
  process_start_fingerprint() { printf 'fingerprint'; }

  LOG_DIR="$TEST_TMP_ROOT"
  CYCLE_ID="cycle-fallback"
  RUN_TMP_DIR="$TEST_TMP_ROOT/run tmp"
  CYCLE_RUN_HASH="batch-1"
  CODEX_FALLBACK_SCREEN_ENABLED="0"
  CODEX_FALLBACK_MODEL="model-fallback"
  CODEX_FALLBACK_REASONING_EFFORT="medium"
  CODEX_FALLBACK_MODE="batch"
  CODEX_GUARDRAIL_STOP_EXIT_CODE="9"
  CODEX_DISABLE_PARENT_STOP="1"
  CODEX_POSTMORTEM_ENABLED="0"
  CODEX_TARGET_FILE=""
  RUN_SELECTED_REVIEW_PATH="$selected_target"
  SELF_INVOKE_PATH="$fake_upkeeper"
  CODEX_EXECUTION_ORIGIN="test"
  UPKEEPER_DRY_RUN="0"
  DIRTY_PATH_COUNT=0
  TRACKED_MODIFIED_PATH_COUNT=0
  UNTRACKED_PATH_COUNT=0
  CODEX_FALLBACK_CHAIN_TOKEN_FD=9
  CODEX_PRIMARY_MODEL_CONTEXT="primary"
  CODEX_FALLBACK_TRIGGER="test"
  CODEX_PARENT_CYCLE_ID=""
  CODEX_ATTEMPT_ROLE="fallback"
  CODEX_REASONING_EFFORT="batch-effort"
  CODEX_MODEL="parent-model"
  CODEX_EXECUTION_ORIGIN="direct_fallback"
  CODEX_BWRAP_TMP_ROOT="$TEST_TMP_ROOT/bwrap"
  POSTMORTEM_SEQUENCE_STATUS="n/a"
  PROMPT_FILE=""
  INLINE_PROMPT=""
  CODEX_PROMPT_PASS=""
  source "$PROJECT_ROOT/lib/upkeeper/fallback_orchestration.bash"

  run_fallback_cycle "test-trigger" "none"
  local selected_arg="$(awk -F= '/^--target-file=/ {print $2}' <"${fake_upkeeper}.args" | sed '1q')"
  [[ "$selected_arg" == "$selected_target" ]] || fail "fallback did not inherit selected target path"

  CODEX_TARGET_FILE="$explicit_target"
  RUN_SELECTED_REVIEW_PATH="$selected_target"
  : >"${fake_upkeeper}.args"
  run_fallback_cycle "test-trigger" "none"
  selected_arg="$(awk -F= '/^--target-file=/ {print $2}' <"${fake_upkeeper}.args" | sed '1q')"
  [[ "$selected_arg" == "$explicit_target" ]] || fail "fallback did not preserve explicit target-file override"
}

test_issue_body_fence_delimiters_are_sanitized
test_issue_fix_prompt_withholds_private_issue_packet_by_default
test_issue_fix_prompt_allows_private_issue_packet_when_enabled
test_postmortem_marker_parser_is_exact_only
test_fallback_inherits_selected_target_file

printf 'bug_fix_batch_271_266_265_test: ok\n'
