#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-recovery-effort.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

LOG_LINES=()
log_line() {
  LOG_LINES+=("$2")
}

log_line_parts() {
  local level="$1"
  shift
  log_line "$level" "$*"
}

shell_quote() {
  printf '%q' "$1"
}

source "$PROJECT_ROOT/lib/upkeeper/postmortem_context.bash"

assert_selection() {
  local expected_effort="$1"
  local expected_class="$2"
  local phase="$3"
  local trigger="$4"
  local detail="$5"
  local configured="$6"
  local actual

  actual="$(upkeeper_recovery_effort_selection "$phase" "$trigger" "$detail" "$configured")"
  [[ "$actual" == "$expected_effort"$'\t'"$expected_class"$'\t'* ]] ||
    fail "expected $phase/$trigger to select $expected_effort/$expected_class, got $actual"
}

test_selection_matrix() {
  UPKEEPER_FALLBACK_REASONING_EFFORT_EXPLICIT=0
  UPKEEPER_POSTMORTEM_REASONING_EFFORT_EXPLICIT=0

  assert_selection low quota_or_environment fallback primary_quota_before_run none high
  assert_selection low quota_or_environment fallback primary_backend_usage_limit none high
  assert_selection low dirty_no_backend_task fallback dirty_no_backend_task none high
  assert_selection medium blocked_task fallback blocked 'codex_exit=1' high
  assert_selection medium no_output fallback failure 'status_marker=missing' high
  assert_selection high capability_failure fallback failure 'codex_exit=1 status_marker=BLOCKED' high
  assert_selection low incident_report postmortem.report failure none medium
  assert_selection medium incident_hardening postmortem.hardening failure none medium

  UPKEEPER_FALLBACK_REASONING_EFFORT_EXPLICIT=1
  UPKEEPER_POSTMORTEM_REASONING_EFFORT_EXPLICIT=1
  assert_selection xhigh operator_override fallback failure none xhigh
  assert_selection high operator_override postmortem.report failure none high
  assert_selection high operator_override postmortem.hardening failure none high
}

prepare_fallback_fixture() {
  local fake_upkeeper="$TEST_TMP_ROOT/fake-upkeeper.sh"

  cat >"$fake_upkeeper" <<'SH'
#!/usr/bin/env bash
printf 'effort=%s\n' "$CODEX_REASONING_EFFORT" >"$RECOVERY_EFFORT_CAPTURE"
SH
  chmod +x "$fake_upkeeper"

  upkeeper_bug_report_only_enabled() { return 1; }
  codex_bwrap_tmp_write_check() { printf ok; }
  compact_process_args() { cat; }
  fallback_would_rediscover_dirty_block() { return 1; }
  launch_screen_fallback_loop() { return 0; }
  wait_for_screen_fallback_loop() { return 0; }
  fallback_screen_session_teardown() { :; }
  refresh_postmortem_incident_log() { :; }
  generate_fallback_chain_token() { printf 'recovery-policy-token'; }
  process_start_fingerprint() { printf 'recovery-policy-fingerprint'; }

  CYCLE_ID="recovery-policy"
  CYCLE_RUN_HASH="recovery-policy-run"
  RUN_TMP_DIR="$TEST_TMP_ROOT/run"
  CODEX_POSTMORTEM_DIR="$TEST_TMP_ROOT/postmortems"
  CODEX_FALLBACK_SCREEN_ENABLED=0
  CODEX_FALLBACK_MODEL="test-fallback"
  CODEX_FALLBACK_REASONING_EFFORT=high
  CODEX_FALLBACK_MODE="--sandbox workspace-write"
  CODEX_POSTMORTEM_ENABLED=0
  CODEX_TARGET_FILE=""
  RUN_SELECTED_REVIEW_PATH=""
  SELF_INVOKE_PATH="$fake_upkeeper"
  UPKEEPER_DRY_RUN=0
  DIRTY_PATH_COUNT=0
  TRACKED_MODIFIED_PATH_COUNT=0
  CODEX_MODEL="test-primary"
  CODEX_REASONING_EFFORT="xhigh"
  CODEX_MODE="--sandbox workspace-write"
  CODEX_MODE_STRING="--sandbox workspace-write"
  CODEX_BWRAP_TMP_ROOT="$TEST_TMP_ROOT/bwrap"
  POSTMORTEM_SEQUENCE_STATUS="not_run"
  PROMPT_FILE=""
  INLINE_PROMPT=""
  CODEX_PROMPT_PASS=""
  CODEX_REVIEW_MODULES=()
  RECOVERY_EFFORT_CAPTURE="$TEST_TMP_ROOT/fallback-effort.txt"
  export RECOVERY_EFFORT_CAPTURE

  source "$PROJECT_ROOT/lib/upkeeper/fallback_orchestration.bash"
}

assert_fallback_launch_effort() {
  local trigger="$1"
  local detail="$2"
  local expected="$3"

  : >"$RECOVERY_EFFORT_CAPTURE"
  CODEX_FALLBACK_REASONING_EFFORT=high
  run_fallback_cycle "$trigger" "$detail"
  grep -qx "effort=$expected" "$RECOVERY_EFFORT_CAPTURE" ||
    fail "fallback $trigger did not launch with effort $expected"
  [[ "$CODEX_FALLBACK_REASONING_EFFORT" == high ]] ||
    fail "fallback $trigger did not restore configured effort"
}

test_fallback_launches_use_selected_effort() {
  UPKEEPER_FALLBACK_REASONING_EFFORT_EXPLICIT=0
  prepare_fallback_fixture
  assert_fallback_launch_effort primary_quota_before_run quota_stop low
  assert_fallback_launch_effort blocked 'codex_exit=1' medium
  assert_fallback_launch_effort failure 'status_marker=missing' medium
  assert_fallback_launch_effort failure 'status_marker=BLOCKED' high
  [[ "${LOG_LINES[*]}" == *"fallback.effort_selection trigger=primary_quota_before_run trigger_class=quota_or_environment effort=low"* ]] ||
    fail "fallback selection log omitted quota trigger class and effort"

  UPKEEPER_FALLBACK_REASONING_EFFORT_EXPLICIT=1
  CODEX_FALLBACK_REASONING_EFFORT=xhigh
  run_fallback_cycle failure 'codex_exit=1'
  grep -qx 'effort=xhigh' "$RECOVERY_EFFORT_CAPTURE" || fail "explicit fallback effort was not preserved"
}

test_dry_run_fallback_retains_non_success_status_without_postmortem() {
  local rc

  prepare_fallback_fixture
  UPKEEPER_DRY_RUN=1
  CODEX_POSTMORTEM_ENABLED=0
  CODEX_FALLBACK_SCREEN_ENABLED=1
  SCREEN_FALLBACK_LAUNCHED=0
  launch_screen_fallback_loop() { SCREEN_FALLBACK_LAUNCHED=1; }
  : >"$RECOVERY_EFFORT_CAPTURE"
  set +e
  run_fallback_cycle primary_quota_before_run quota_stop
  rc=$?
  set -e
  [[ "$rc" -eq 7 ]] ||
    fail "dry-run fallback exited $rc with postmortem disabled, expected 7"
  [[ ! -s "$RECOVERY_EFFORT_CAPTURE" ]] ||
    fail "dry-run fallback unexpectedly launched the child"
  [[ "$SCREEN_FALLBACK_LAUNCHED" -eq 0 ]] ||
    fail "dry-run fallback unexpectedly launched the screen child"
}

prepare_auxiliary_fixture() {
  source "$PROJECT_ROOT/lib/upkeeper/aux_codex.bash"

  aux_quota_allows_run() { return 0; }
  codex_session_store_write_check() { printf ok; }
  codex_arg0_tmp_cleanup_check() { printf ok; }
  codex_bwrap_tmp_write_check() { printf ok; }
  compact_process_args() { cat; }
  new_transcript_file() { printf '%s/transcript.log' "$TEST_TMP_ROOT"; }
  upkeeper_path_hmac() { printf 'path-hmac'; }
  run_codex_exec_capture() {
    printf '%s\n' "$@" >"$TEST_TMP_ROOT/aux-args.txt"
    return 0
  }

  CODEX_HOME_DIR="$TEST_TMP_ROOT/codex-home"
  CODEX_ARG0_TMP_ROOT="$TEST_TMP_ROOT/arg0"
  CODEX_ARG0_TMP_QUARANTINE_ROOT="$TEST_TMP_ROOT/arg0-quarantine"
  CODEX_BWRAP_TMP_ROOT="$TEST_TMP_ROOT/bwrap"
  ROOT_DIR="$TEST_TMP_ROOT"
  UPKEEPER_DRY_RUN=0
}

test_auxiliary_launches_use_selected_effort() {
  local prompt_file="$TEST_TMP_ROOT/prompt.txt"
  local last_message="$TEST_TMP_ROOT/last-message.txt"

  : >"$prompt_file"
  prepare_auxiliary_fixture
  UPKEEPER_POSTMORTEM_REASONING_EFFORT_EXPLICIT=0
  UPKEEPER_RECOVERY_TRIGGER=primary_quota_before_run
  run_aux_codex_exec postmortem.report test-model medium '--sandbox workspace-write' "$prompt_file" "$last_message"
  grep -qx 'model_reasoning_effort=low' "$TEST_TMP_ROOT/aux-args.txt" || fail "report did not use low effort"

  run_aux_codex_exec postmortem.hardening test-model low '--sandbox workspace-write' "$prompt_file" "$last_message"
  grep -qx 'model_reasoning_effort=medium' "$TEST_TMP_ROOT/aux-args.txt" || fail "hardening did not use medium effort"

  UPKEEPER_POSTMORTEM_REASONING_EFFORT_EXPLICIT=1
  run_aux_codex_exec postmortem.report test-model xhigh '--sandbox workspace-write' "$prompt_file" "$last_message"
  grep -qx 'model_reasoning_effort=xhigh' "$TEST_TMP_ROOT/aux-args.txt" || fail "explicit postmortem effort was not preserved"
  [[ "${LOG_LINES[*]}" == *"postmortem.report.effort_selection trigger=primary_quota_before_run trigger_class=operator_override effort=xhigh"* ]] ||
    fail "postmortem selection log omitted explicit override evidence"
}

test_selection_matrix
test_fallback_launches_use_selected_effort
test_dry_run_fallback_retains_non_success_status_without_postmortem
test_auxiliary_launches_use_selected_effort
printf 'recovery_effort_policy_test: ok\n'
