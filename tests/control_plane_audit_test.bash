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
  assert_json_value '.invariant_registry | map(select(.ident == "KP-001" and .remediation_policy != "")) | length == 1'
  assert_json_value '.closed_loop.observed_anomaly_count == 0'
  assert_json_value '.closed_loop.next_recommended_action == "safe_to_restart_or_exit_clean"'

  run_audit "$repo"
  [[ "$AUDIT_RC" -eq 0 ]] || fail "clean text audit exited $AUDIT_RC"
  assert_text_contains "control_plane_audit: status=clean findings=0"
  assert_text_contains "control_plane_audit: closed_loop observed=0"
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
  assert_json_value '.policy_decisions | map(select(.klass == "tracked_root_scratch_artifact" and .policy_class == "data_integrity_blocker" and .action == "block_before_staging" and .blocks_stage == true and .invariant_id == "KP-001")) | length == 1'
  assert_json_value '.invariant_failures | map(select(.invariant_id == "KP-001" and .message != "")) | length == 1'

  run_audit "$repo"
  [[ "$AUDIT_RC" -eq 2 ]] || fail "tracked db text audit exited $AUDIT_RC"
  assert_text_contains "policy="
  assert_text_contains "invariant=KP-001"
  assert_text_contains "control_plane_audit: invariant id=KP-001"
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
  assert_json_value '.closed_loop.observed_anomaly_count == 2'
  assert_json_value '.closed_loop.auto_remediated_count == 2'
  assert_json_value '.policy_decisions | map(select(.policy_class == "known_safe_cleanup" and .status == "cleaned" and .invariant_id == "KP-002")) | length == 2'
  assert_json_value '.invariant_failures | length == 0'
}

test_before_after_snapshot_delta_resolves_safe_cleanup() {
  local repo="$TEST_TMP_ROOT/snapshot-delta"
  local before_snapshot="$TEST_TMP_ROOT/before.json"
  local after_snapshot="$TEST_TMP_ROOT/after.json"
  make_repo "$repo"
  (
    cd "$repo"
    printf 'scratch\n' >'$db'
  )
  run_audit "$repo" --json --no-runtime --snapshot-label before --snapshot-out "$before_snapshot" --fail-on never
  [[ "$AUDIT_RC" -eq 0 ]] || fail "before snapshot audit exited $AUDIT_RC"
  [[ -s "$before_snapshot" ]] || fail "before snapshot was not written"
  jq -e '.invariant_failures | map(select(.invariant_id == "KP-002")) | length == 1' "$before_snapshot" >/dev/null ||
    fail "before snapshot did not preserve safe-cleanup invariant failure"

  run_audit "$repo" --json --no-runtime --remediate-safe --before-snapshot "$before_snapshot" --snapshot-label after --snapshot-out "$after_snapshot"
  [[ "$AUDIT_RC" -eq 0 ]] || fail "after snapshot audit exited $AUDIT_RC output=$AUDIT_OUT stderr=$AUDIT_ERR"
  [[ -s "$after_snapshot" ]] || fail "after snapshot was not written"
  [[ ! -e "$repo/\$db" ]] || fail "after snapshot remediation did not remove scratch db"
  assert_json_value '.snapshot.invariant_id == "KP-007"'
  assert_json_value '.snapshot_delta.invariant_id == "KP-007"'
  assert_json_value '.snapshot_delta.before_finding_count == 1'
  assert_json_value '.snapshot_delta.after_finding_count == 0'
  assert_json_value '.snapshot_delta.resolved_invariants | index("KP-002")'
  jq -e '.snapshot_delta.resolved_invariants | index("KP-002")' "$after_snapshot" >/dev/null ||
    fail "after snapshot file did not preserve resolved invariant delta"
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
  assert_json_value '.policy_decisions | map(select(.status == "obligation_written" and .blocks_stage == true and .invariant_id == "KP-001")) | length == 1'
  record_count="$(find "$obligation_root/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$record_count" == "1" ]] || fail "control-plane audit wrote $record_count obligations, expected 1"
  record_file="$(find "$obligation_root/open" -maxdepth 1 -type f -name '*.json' | sort | head -n 1)"
  [[ "$(jq -r '.kind' "$record_file")" == "control_plane_policy_blocker" ]] ||
    fail "control-plane obligation kind was not specific"
  [[ "$(jq -r '.policy_class' "$record_file")" == "data_integrity_blocker" ]] ||
    fail "control-plane obligation did not preserve policy class"
  [[ "$(jq -r '.invariant_id' "$record_file")" == "KP-001" ]] ||
    fail "control-plane obligation did not preserve invariant id"
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
  assert_json_value '.policy_decisions | map(select(.policy_class == "unsafe_unknown" and .action == "create_automation_obligation" and .blocks_stage == true and .invariant_id == "KP-003")) | length == 1'
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
  assert_json_value '.policy_decisions | map(select(.klass == "open_automation_obligations" and .policy_class == "known_expected" and .blocks_stage == false and .invariant_id == "KP-004")) | length == 1'
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
  assert_json_value '.policy_decisions | map(select(.invariant_id == "KP-005")) | length == 2'
}

test_unknown_finding_requires_promotion_and_persistent_lineage() {
  local repo="$TEST_TMP_ROOT/unknown-finding"
  local finding_json="$TEST_TMP_ROOT/unknown-finding.json"
  local lineage_root="$TEST_TMP_ROOT/unknown-lineage"
  local obligation_root="$TEST_TMP_ROOT/unknown-obligations"
  local record_file obligation_file
  make_repo "$repo"
  cat >"$finding_json" <<'JSON'
{
  "ident": "future-signal-fixture",
  "klass": "future_control_plane_signal",
  "severity": "high",
  "path": "runtime/future-signal.json",
  "source": "fixture",
  "summary": "future control-plane signal appeared without a classifier",
  "remediation": "add a classifier, invariant, and deterministic fixture"
}
JSON
  run_audit "$repo" --json --no-runtime --finding-json "$finding_json" \
    --write-lineage --lineage-root "$lineage_root" \
    --write-obligations --obligation-root "$obligation_root" --fail-on blockers
  [[ "$AUDIT_RC" -eq 2 ]] || fail "unknown finding audit exited $AUDIT_RC"
  assert_json_value '.closed_loop.unknown_class_count == 1'
  assert_json_value '.closed_loop.next_recommended_action == "add_classifier_invariant_and_fixture"'
  assert_json_value '.policy_decisions | map(select(.klass == "future_control_plane_signal" and .unknown_class == true and .invariant_id == "KP-008" and .status == "obligation_written")) | length == 1'
  assert_json_value '.lineage.record_count == 1'

  record_file="$(find "$lineage_root/records" -maxdepth 1 -type f -name '*.json' | sort | head -n 1)"
  [[ -n "$record_file" ]] || fail "unknown finding did not write lineage record"
  jq -e '
    .unknown_class == true
    and .classifier_version != ""
    and .invariant_id == "KP-008"
    and .resolution_state == "promotion_required"
    and .promotion_required.fixture != ""
  ' "$record_file" >/dev/null || fail "unknown lineage record did not require promotion"
  obligation_file="$(find "$obligation_root/open" -maxdepth 1 -type f -name '*.json' | sort | head -n 1)"
  [[ -n "$obligation_file" ]] || fail "unknown finding did not write an obligation"
  jq -e '.unknown_class == true and .invariant_id == "KP-008" and .classifier_version != ""' "$obligation_file" >/dev/null ||
    fail "unknown obligation did not preserve promotion metadata"

  run_audit "$repo" --json --no-runtime --write-lineage --lineage-root "$lineage_root" --resolve-missing-lineage --fail-on never
  [[ "$AUDIT_RC" -eq 0 ]] || fail "clean resolve-missing audit exited $AUDIT_RC"
  jq -e '.resolution_state == "promotion_required"' "$record_file" >/dev/null ||
    fail "unknown lineage was resolved without classifier promotion"
}

test_clean_repo_is_clean
test_tracked_root_db_is_anomaly
test_tracked_local_evidence_is_anomaly
test_untracked_root_scratch_and_runtime_inventory
test_remediate_safe_cleans_only_safe_artifacts
test_before_after_snapshot_delta_resolves_safe_cleanup
test_blocker_writes_obligation_before_stage
test_unknown_root_artifact_is_unsafe_unknown
test_existing_obligations_do_not_block_pre_staging_policy
test_recent_log_nonzero_and_page_errors_are_anomalies
test_unknown_finding_requires_promotion_and_persistent_lineage
printf 'control_plane_audit_test: ok\n'
