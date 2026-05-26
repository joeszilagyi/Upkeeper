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
  assert_json_value '.status == "findings"'
  assert_json_value '.findings | map(select(.klass == "tracked_root_scratch_artifact" and .path == "$db")) | length == 1'

  run_audit "$repo"
  [[ "$AUDIT_RC" -eq 2 ]] || fail "tracked db text audit exited $AUDIT_RC"
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
  assert_json_value '.findings | map(select(.klass == "untracked_root_scratch_artifact" and .path == "$db")) | length == 1'
  assert_json_value '.findings | map(select(.klass == "active_lock_present")) | length == 1'
  assert_json_value '.findings | map(select(.klass == "open_automation_obligations")) | length == 1'
  assert_json_value '.runtime.active_lock_present == true'
  assert_json_value '.runtime.open_obligation_count == 1'
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
test_recent_log_nonzero_and_page_errors_are_anomalies
printf 'control_plane_audit_test: ok\n'
