#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-control-plane-audit.XXXXXX")"
trap 'rm -r "$TEST_TMP_ROOT" 2>/dev/null || true' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git checkout -q -B main
    git config user.name "Control Plane Audit Test"
    git config user.email "control-plane-audit@example.invalid"
    printf 'hello\n' >README.md
    printf 'runtime/\nUpkeeper.log\ntranscripts/\npostmortems/\n' >.gitignore
    git add README.md .gitignore
    git commit -q -m init
  )
}

run_audit() {
  local repo="$1"
  shift
  set +e
  "$PROJECT_ROOT/tools/upkeeper_control_plane_audit.py" \
    --root "$repo" \
    --no-default-log \
    "$@" >"$TEST_TMP_ROOT/out.txt" 2>"$TEST_TMP_ROOT/err.txt"
  AUDIT_RC="$?"
  set -e
  AUDIT_OUT="$(cat "$TEST_TMP_ROOT/out.txt")"
  AUDIT_ERR="$(cat "$TEST_TMP_ROOT/err.txt")"
}

assert_json_value() {
  local filter="$1"
  jq -e "$filter" <<<"$AUDIT_OUT" >/dev/null ||
    fail "JSON assertion failed: $filter output=$AUDIT_OUT stderr=$AUDIT_ERR"
}

assert_text_contains() {
  local needle="$1"
  grep -Fq "$needle" <<<"$AUDIT_OUT" ||
    fail "missing text '$needle' in output=$AUDIT_OUT stderr=$AUDIT_ERR"
}

test_clean_repo_is_clean() {
  local repo="$TEST_TMP_ROOT/clean"
  make_repo "$repo"
  run_audit "$repo" --json
  [[ "$AUDIT_RC" -eq 0 ]] || fail "clean audit exited $AUDIT_RC"
  assert_json_value '.status == "clean"'
  assert_json_value '.counts.finding_count == 0'
  assert_json_value '.counts.tracked_change_count == 0'

  run_audit "$repo"
  [[ "$AUDIT_RC" -eq 0 ]] || fail "clean text audit exited $AUDIT_RC"
  assert_text_contains "control_plane_audit: status=clean findings=0"
}

test_tracked_root_db_is_anomaly() {
  local repo="$TEST_TMP_ROOT/tracked-db"
  make_repo "$repo"
  (
    cd "$repo"
    printf 'scratch\n' >'$db'
    git add '$db'
    git commit -q -m "add scratch db"
  )
  run_audit "$repo" --json
  [[ "$AUDIT_RC" -eq 2 ]] || fail "tracked db audit exited $AUDIT_RC"
  assert_json_value '.status == "blocked"'
  assert_json_value '.counts.blocker_count == 1'
  assert_json_value '.findings | map(select(.klass == "tracked_root_scratch_artifact" and .path == "$db")) | length == 1'
  assert_json_value '.policy_decisions | map(select(.klass == "tracked_root_scratch_artifact" and .policy_class == "data_integrity_blocker" and .action == "block_before_staging" and .blocks_stage == true)) | length == 1'

  run_audit "$repo"
  [[ "$AUDIT_RC" -eq 2 ]] || fail "tracked db text audit exited $AUDIT_RC"
  assert_text_contains "policy="
  assert_text_contains "blocks_stage=true"
  assert_text_contains "class=tracked_root_scratch_artifact"
  assert_text_contains 'path=$db'
}

test_tracked_local_evidence_is_anomaly() {
  local repo="$TEST_TMP_ROOT/tracked-evidence"
  make_repo "$repo"
  (
    cd "$repo"
    mkdir -p runtime transcripts postmortems
    printf '{}\n' >runtime/upkeeper-file-manifest.json
    printf 'log\n' >Upkeeper.log
    printf 'transcript\n' >transcripts/session.log
    printf '{}\n' >postmortems/report.json
    git add -f runtime/upkeeper-file-manifest.json Upkeeper.log transcripts/session.log postmortems/report.json
    git commit -q -m "add local evidence"
  )
  run_audit "$repo" --json
  [[ "$AUDIT_RC" -eq 2 ]] || fail "tracked evidence audit exited $AUDIT_RC"
  assert_json_value '.findings | map(select(.klass == "tracked_manifest_artifact")) | length == 1'
  assert_json_value '.findings | map(select(.klass == "tracked_log_artifact")) | length == 1'
  assert_json_value '.findings | map(select(.klass == "tracked_transcript_artifact")) | length == 1'
  assert_json_value '.findings | map(select(.klass == "tracked_postmortem_artifact")) | length == 1'
}

test_untracked_root_scratch_and_runtime_inventory() {
  local repo="$TEST_TMP_ROOT/untracked-runtime"
  make_repo "$repo"
  (
    cd "$repo"
    printf 'scratch\n' >'$db'
    mkdir -p runtime/upkeeper-active.lock runtime/upkeeper-obligations/open
    printf '{"id":"fixture","status":"open"}\n' >runtime/upkeeper-obligations/open/fixture.json
  )
  run_audit "$repo" --json
  [[ "$AUDIT_RC" -eq 2 ]] || fail "runtime inventory audit exited $AUDIT_RC"
  assert_json_value '.status == "blocked"'
  assert_json_value '.findings | map(select(.klass == "untracked_root_scratch_artifact" and .path == "$db")) | length == 1'
  assert_json_value '.findings | map(select(.klass == "active_lock_present")) | length == 1'
  assert_json_value '.findings | map(select(.klass == "open_automation_obligations")) | length == 1'
  assert_json_value '.runtime.active_lock_present == true'
  assert_json_value '.runtime.open_obligation_count == 1'
}

test_remediate_safe_cleans_only_safe_artifacts() {
  local repo="$TEST_TMP_ROOT/remediate-safe"
  make_repo "$repo"
  (
    cd "$repo"
    printf 'scratch\n' >'$db'
    mkdir -p tools/__pycache__
    printf 'bytecode\n' >tools/__pycache__/fixture.pyc
  )
  run_audit "$repo" --json --remediate-safe
  [[ "$AUDIT_RC" -eq 0 ]] || fail "safe remediation audit exited $AUDIT_RC output=$AUDIT_OUT stderr=$AUDIT_ERR"
  [[ ! -e "$repo/\$db" ]] || fail "safe remediation did not remove root scratch db"
  [[ ! -e "$repo/tools/__pycache__/fixture.pyc" ]] || fail "safe remediation did not remove bytecode cache"
  assert_json_value '.status == "clean"'
  assert_json_value '.counts.finding_count == 0'
  assert_json_value '.counts.cleaned_count == 2'
  assert_json_value '.policy_decisions | map(select(.policy_class == "known_safe_cleanup" and .status == "cleaned")) | length == 2'
}

test_blocker_writes_obligation_before_stage() {
  local repo="$TEST_TMP_ROOT/write-obligation"
  local obligation_root="$TEST_TMP_ROOT/write-obligation-state"
  local record_count record_file
  make_repo "$repo"
  (
    cd "$repo"
    printf 'scratch\n' >'$db'
    git add '$db'
    git commit -q -m "add scratch db"
  )
  run_audit "$repo" --json --write-obligations --obligation-root "$obligation_root" --stage pre-staging --fail-on blockers --no-runtime
  [[ "$AUDIT_RC" -eq 2 ]] || fail "blocker obligation audit exited $AUDIT_RC"
  assert_json_value '.counts.blocker_count == 1'
  assert_json_value '.counts.obligation_written_count == 1'
  assert_json_value '.policy_decisions | map(select(.status == "obligation_written" and .blocks_stage == true)) | length == 1'
  record_count="$(find "$obligation_root/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$record_count" == "1" ]] || fail "control-plane audit wrote $record_count obligations, expected 1"
  record_file="$(find "$obligation_root/open" -maxdepth 1 -type f -name '*.json' | sort | head -n 1)"
  [[ "$(jq -r '.kind' "$record_file")" == "control_plane_policy_blocker" ]] ||
    fail "control-plane obligation kind was not specific"
  [[ "$(jq -r '.policy_class' "$record_file")" == "data_integrity_blocker" ]] ||
    fail "control-plane obligation did not preserve policy class"
  [[ "$(jq -r '.repair_target_file' "$record_file")" == "orchestration/backlog.sh" ]] ||
    fail "control-plane obligation did not preserve repair target"
}

test_unknown_root_artifact_is_unsafe_unknown() {
  local repo="$TEST_TMP_ROOT/unknown-root"
  make_repo "$repo"
  (
    cd "$repo"
    printf 'debug\n' >debug.log
  )
  run_audit "$repo" --json --no-runtime
  [[ "$AUDIT_RC" -eq 2 ]] || fail "unknown root audit exited $AUDIT_RC"
  assert_json_value '.status == "blocked"'
  assert_json_value '.findings | map(select(.klass == "unsafe_unknown_root_artifact" and .path == "debug.log")) | length == 1'
  assert_json_value '.policy_decisions | map(select(.policy_class == "unsafe_unknown" and .action == "create_automation_obligation" and .blocks_stage == true)) | length == 1'
}

test_existing_obligations_do_not_block_pre_staging_policy() {
  local repo="$TEST_TMP_ROOT/open-obligations"
  make_repo "$repo"
  (
    cd "$repo"
    mkdir -p runtime/upkeeper-obligations/open
    printf '{"id":"fixture","status":"open"}\n' >runtime/upkeeper-obligations/open/fixture.json
  )
  run_audit "$repo" --json --fail-on blockers
  [[ "$AUDIT_RC" -eq 0 ]] || fail "open-obligation report-only audit exited $AUDIT_RC"
  assert_json_value '.findings | map(select(.klass == "open_automation_obligations")) | length == 1'
  assert_json_value '.counts.blocker_count == 0'
  assert_json_value '.policy_decisions | map(select(.klass == "open_automation_obligations" and .policy_class == "known_expected" and .blocks_stage == false)) | length == 1'
}

test_recent_log_nonzero_and_page_errors_are_anomalies() {
  local repo="$TEST_TMP_ROOT/log"
  local log_file="$TEST_TMP_ROOT/loop.log"
  make_repo "$repo"
  cat >"$log_file" <<'LOG'
2026-05-26T00:00:00 INFO cycle.exit exit_code=2 reason=BLOCKED
2026-05-26T00:00:01 █ PAGE [ERROR] Upkeeper: primary: unexpected
LOG
  run_audit "$repo" --json --log "$log_file"
  [[ "$AUDIT_RC" -eq 2 ]] || fail "log audit exited $AUDIT_RC"
  assert_json_value '.recent_log.nonzero_cycle_exit_count == 1'
  assert_json_value '.recent_log.page_error_count == 1'
  assert_json_value '.findings | map(select(.klass == "recent_nonzero_cycle_exit")) | length == 1'
  assert_json_value '.findings | map(select(.klass == "recent_page_error")) | length == 1'
}

test_clean_repo_is_clean
test_tracked_root_db_is_anomaly
test_tracked_local_evidence_is_anomaly
test_untracked_root_scratch_and_runtime_inventory
test_remediate_safe_cleans_only_safe_artifacts
test_blocker_writes_obligation_before_stage
test_unknown_root_artifact_is_unsafe_unknown
test_existing_obligations_do_not_block_pre_staging_policy
test_recent_log_nonzero_and_page_errors_are_anomalies
printf 'control_plane_audit_test: ok\n'
