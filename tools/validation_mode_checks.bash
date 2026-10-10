#!/usr/bin/env bash
# Validation-mode dispatch for tools/validate_upkeeper.sh.
#
# This module deliberately owns only the selection and ordering of checks.  The
# validator remains responsible for its timeout runner, timing evidence, and
# check implementations; callers must provide run_bounded_check and
# validation_timing_record_skip.

run_validation_integration_checks() {
  run_bounded_check review_module_flags "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_review_module_flags
  run_bounded_check config_file_support "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_config_file_support
  run_bounded_check gitignore_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_gitignore_contract
  run_bounded_check force_added_gitignored_target_selection "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_force_added_gitignored_target_selection
  run_bounded_check symlink_target_selection_guard "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_symlink_target_selection_guard
  run_bounded_check cycle_start_log_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_cycle_start_log_contract
  run_bounded_check log_path_symlink_guard "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_log_path_symlink_guard
  run_bounded_check custom_log_path_rotation_boundary "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_custom_log_path_rotation_boundary
  run_bounded_check disk_preflight_log_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_disk_preflight_log_contract
  run_bounded_check disk_preflight_prompt_note_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_disk_preflight_prompt_note_contract
  run_bounded_check arg0_tmp_cleanup_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_arg0_tmp_cleanup_contract
  run_bounded_check automation_obligation_framework "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_automation_obligation_framework
  run_bounded_check session_store_preflight_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_session_store_preflight_contract
  run_bounded_check bwrap_tmp_preflight_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_bwrap_tmp_preflight_contract
  run_bounded_check wrapper_health_log_quoting "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_wrapper_health_log_quoting
  run_bounded_check operator_guide_bootstrap_race "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_operator_guide_bootstrap_race
  run_bounded_check active_lock_incomplete_guard "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_active_lock_incomplete_guard
  run_bounded_check quota_fallback_exit_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_quota_fallback_exit_contract
  run_bounded_check file_manifest_selection "$VALIDATION_FILE_MANIFEST_TIMEOUT_SECONDS" check_file_manifest_selection
  run_bounded_check issue_workflow_comment_relay "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_issue_workflow_comment_relay
  run_bounded_check issue_workflow_backend_mode_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_issue_workflow_backend_mode_contract
  run_bounded_check genie_protocol_backend_boundary "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_genie_protocol_backend_boundary
  run_bounded_check prompt_pass_coverage_enforcement "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_prompt_pass_coverage_enforcement
  run_bounded_check log_self_review_target_boundary "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_log_self_review_target_boundary
  run_bounded_check tool_failure_queue "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_tool_failure_queue
  run_bounded_check lattice_contract "$VALIDATION_FULL_TIMEOUT_SECONDS" check_lattice_contract
  run_bounded_check fallback_artifact_helpers "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_fallback_artifact_helpers
}

run_validation_full_only_checks() {
  run_bounded_check central_dry_runs "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_central_dry_runs
  run_bounded_check symlinked_client "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_symlinked_client
  run_bounded_check missing_module_failure "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_missing_module_failure
  run_bounded_check missing_prompt_failure "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_missing_prompt_failure
  run_bounded_check empty_transcript_failure "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_empty_transcript_failure
  run_bounded_check fault_injection_first_scenarios "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_fault_injection_first_scenarios
  run_bounded_check stress_corpus_harness "$VALIDATION_FULL_TIMEOUT_SECONDS" check_stress_corpus_harness
}

run_validation_mode_checks() {
  local mode="$1"

  case "$mode" in
    quick)
      validation_timing_record_skip integration_checks mode_quick tools/validate_upkeeper.sh --full
      ;;
    full)
      run_validation_integration_checks
      run_validation_full_only_checks
      ;;
    *)
      printf 'validation_mode_checks: unsupported mode: %s\n' "$mode" >&2
      return 2
      ;;
  esac
}
