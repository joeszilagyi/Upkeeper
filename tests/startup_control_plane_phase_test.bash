#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-startup-phase.XXXXXX")"
EVENTS="$TEST_ROOT/events"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'startup_control_plane_phase_test: FAIL: %s\n' "$*" >&2
  exit 1
}

record() {
  printf '%s\n' "$1" >>"$EVENTS"
}

assert_before() {
  local earlier="$1" later="$2" earlier_line later_line
  earlier_line="$(awk -v value="$earlier" '$0 == value { print NR; exit }' "$EVENTS")"
  later_line="$(awk -v value="$later" '$0 == value { print NR; exit }' "$EVENTS")"
  [[ -n "$earlier_line" && -n "$later_line" && "$earlier_line" -lt "$later_line" ]] ||
    fail "expected $earlier before $later; events=$(tr '\n' ' ' <"$EVENTS")"
}

# shellcheck source=/dev/null
source "$PROJECT_ROOT/Upkeeper"

normalize_guardrail_thresholds() { record normalize_guardrails; }
check_central_wrapper_health_or_exit() { record wrapper_health; }
prepare_fallback_chain_token() { record fallback_token; }
acquire_active_lock_or_exit() { record active_lock; }
upkeeper_fast_path_timing_reset() { record timing_reset; }
upkeeper_fast_path_timing_start() { record "timing_start:$1"; }
upkeeper_fast_path_timing_finish() { record "timing_finish:$1"; }
ensure_operator_guide() { record operator_guide; }
resolve_prompt_file() { record prompt_file; }
scan_previous_run_anomalies() { record anomaly_scan; }
rotate_wrapper_log_if_needed() { record log_rotation; }
refresh_worktree_counts() { record worktree_counts; }
direct_parent_details() { printf '1\tbash\tfixture-parent\n'; }
parent_shell_details() { printf '2\tbash\tfixture-loop\t0\n'; }
process_start_fingerprint() { printf 'fingerprint-%s\n' "$1"; }
cycle_start_log_message() { record cycle_start_message; printf 'cycle.start fixture\n'; }
log_line_parts() { record cycle_start_log; }
automation_record_cycle_start() { record automation_start; }
upkeeper_precontact_backup_hmac_key_material() { record backup_key; printf 'fixture-key\n'; }
precontact_backup_machine_preflight_or_exit() { record backup_preflight; }
resolve_issue_fix_next_or_exit() { record issue_resolution; }
upkeeper_bind_issue_fix_obligation_context() { record obligation_binding; }
run_issue_docs_contract_checks() { record issue_docs; }
enforce_breadcrumb_gate_or_exit() { record breadcrumb_gate; }
upkeeper_preflight_explicit_target_or_exit() { record explicit_target; }
lattice_init_and_doctor_or_exit() { record lattice_init; }
lattice_record_cycle_start() { record lattice_cycle_start; }
start_run_mark_heartbeat() { record heartbeat; }
check_disk_space_preflight() { record disk_preflight; }
enforce_primary_quota_block_marker() { record quota_marker; }
ensure_file_manifest_for_selection() { record file_manifest; }

STARTUP_ANOMALY_GATE=0
upkeeper_run_startup_control_plane_preflight

assert_before normalize_guardrails active_lock
assert_before active_lock timing_reset
assert_before timing_start:operator_guide operator_guide
assert_before operator_guide timing_finish:operator_guide
assert_before timing_finish:startup_anomaly_scan cycle_start_log
assert_before cycle_start_log automation_start
assert_before timing_start:backup_preflight backup_key
assert_before backup_preflight timing_finish:backup_preflight
assert_before timing_finish:backup_preflight timing_start:issue_and_target_preflight
assert_before issue_resolution obligation_binding
assert_before obligation_binding issue_docs
assert_before issue_docs breadcrumb_gate
assert_before explicit_target timing_finish:issue_and_target_preflight
assert_before timing_finish:issue_and_target_preflight timing_start:lattice_startup
assert_before lattice_init timing_finish:lattice_startup
assert_before timing_finish:lattice_startup timing_start:lattice_cycle_start
assert_before lattice_cycle_start heartbeat
assert_before disk_preflight quota_marker
assert_before quota_marker timing_start:file_manifest
assert_before timing_start:file_manifest file_manifest
assert_before file_manifest timing_finish:file_manifest

printf 'startup_control_plane_phase_test: ok\n'
