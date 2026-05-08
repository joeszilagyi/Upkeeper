postmortem_incident_classification() {
  local trigger="$1"
  local child_exit="$2"
  local fallback_marker="$3"

  if [[ "$trigger" == "primary_quota_before_run" && "$child_exit" == "0" && "$fallback_marker" == "WORK_DONE" ]]; then
    printf 'CONTROLLED_QUOTA_HANDOFF'
  else
    printf 'INCIDENT_REVIEW'
  fi
}

refresh_postmortem_incident_log() {
  local incident_log_path="$1"
  [[ -n "$incident_log_path" ]] || return 0
  grep "cycle=$CYCLE_ID " "$LOG_FILE" >"$incident_log_path" || true
}

# Postmortem evidence writers.
#
# These files are intentionally plain text and redundant with the log. During an
# incident the operator should not need to remember which command reconstructs
# context; the evidence directory should be readable on its own.
write_postmortem_context() {
  local context_path="$1"
  local trigger="$2"
  local detail_text="$3"
  local child_exit="$4"
  local incident_log_path="$5"
  local primary_last_message_copy="$6"
  local primary_exec_started="1"
  local pre_run_guardrail_stop="0"
  local primary_stop_phase="after_run"
  local primary_stop_reason="$trigger"
  local primary_status_marker_expectation="required_after_primary_exec"
  local primary_before_session_end_state
  local screen_root fallback_current_child_id fallback_current_child_started_at fallback_current_child_status
  local fallback_completed_child_count fallback_last_cycle_exit fallback_runner_stop_reason fallback_heartbeat
  local fallback_marker_analysis fallback_child_status_marker fallback_child_status_marker_source
  local fallback_child_status_marker_candidate fallback_child_status_marker_candidate_reason
  local incident_classification

  if [[ "$trigger" == "primary_quota_before_run" ]]; then
    primary_exec_started="0"
    pre_run_guardrail_stop="1"
    primary_stop_phase="before_run"
    primary_stop_reason="quota_guardrail"
    primary_status_marker_expectation="missing_expected_no_primary_exec"
  elif [[ "$trigger" == "primary_quota_after_run" ]]; then
    primary_stop_reason="quota_guardrail"
  fi

  primary_before_session_end_state="$(parse_session_end_state "${before_source:-}")"
  screen_root="$CODEX_POSTMORTEM_DIR/$CYCLE_ID/screen"
  fallback_current_child_id="$(read_artifact_or_unknown "$screen_root/current-child-cycle-id.txt")"
  fallback_current_child_started_at="$(read_artifact_or_unknown "$screen_root/current-child-started-at.txt")"
  fallback_current_child_status="$(read_artifact_or_unknown "$screen_root/current-child-status.txt")"
  fallback_completed_child_count="$(read_artifact_or_unknown "$screen_root/completed-child-count.txt")"
  fallback_last_cycle_exit="$(read_artifact_or_unknown "$screen_root/last-cycle-exit-code.txt")"
  fallback_runner_stop_reason="$(read_artifact_or_unknown "$screen_root/stop-reason.txt")"
  fallback_heartbeat="$(read_artifact_or_unknown "$screen_root/heartbeat.txt")"
  fallback_marker_analysis="$(while_marker_analysis_json "${FALLBACK_SCREEN_TRANSCRIPT_PATH:-}")"
  fallback_child_status_marker="$(json_field "$fallback_marker_analysis" '.accepted_marker')"
  fallback_child_status_marker_candidate="$(json_field "$fallback_marker_analysis" '.candidate_marker')"
  fallback_child_status_marker_candidate_reason="$(json_field "$fallback_marker_analysis" '.candidate_rejection_reason')"
  if [[ -n "$fallback_child_status_marker" ]]; then
    fallback_child_status_marker_source="exact"
  elif [[ -n "$fallback_child_status_marker_candidate" && "$fallback_child_status_marker_candidate_reason" != "decorated_marker" ]]; then
    fallback_child_status_marker="$fallback_child_status_marker_candidate"
    fallback_child_status_marker_source="recovered_malformed_candidate"
  else
    fallback_child_status_marker="missing"
    fallback_child_status_marker_source="missing"
  fi
  incident_classification="$(postmortem_incident_classification "$trigger" "$child_exit" "$fallback_child_status_marker")"

  cat >"$context_path" <<EOF
incident_cycle_id: $CYCLE_ID
incident_trigger: $trigger
incident_detail: $detail_text
incident_classification: $incident_classification
attempt_role: $CODEX_ATTEMPT_ROLE
primary_model: $CODEX_MODEL
primary_reasoning_effort: $CODEX_REASONING_EFFORT
fallback_model: $CODEX_FALLBACK_MODEL
fallback_reasoning_effort: $CODEX_FALLBACK_REASONING_EFFORT
postmortem_model: $CODEX_POSTMORTEM_MODEL
fallback_child_exit: $child_exit
fallback_screen_session: ${FALLBACK_SCREEN_SESSION_NAME:-none}
fallback_screen_transcript: ${FALLBACK_SCREEN_TRANSCRIPT_PATH:-none}
fallback_screen_exit_code: ${FALLBACK_SCREEN_EXIT_CODE:-unknown}
fallback_completed_child_count: $fallback_completed_child_count
fallback_current_child_cycle_id: $fallback_current_child_id
fallback_current_child_started_at: $fallback_current_child_started_at
fallback_current_child_status: $fallback_current_child_status
fallback_child_status_marker: $fallback_child_status_marker
fallback_child_status_marker_source: $fallback_child_status_marker_source
fallback_last_cycle_exit_code: $fallback_last_cycle_exit
fallback_runner_stop_reason: $fallback_runner_stop_reason
fallback_heartbeat: $fallback_heartbeat
primary_failure_classification: ${primary_failure_classification:-none}
primary_exec_started: $primary_exec_started
pre_run_guardrail_stop: $pre_run_guardrail_stop
primary_stop_phase: $primary_stop_phase
primary_stop_reason: $primary_stop_reason
primary_status_marker_expectation: $primary_status_marker_expectation
primary_status_marker: ${status_marker:-missing}
primary_status_marker_source: ${status_marker_source:-unknown}
primary_status_marker_candidate: ${status_marker_candidate:-none}
primary_status_marker_candidate_rejection_reason: ${status_marker_candidate_rejection_reason:-none}
primary_codex_exit: ${codex_exit:-unknown}
primary_session_end_state: ${session_end_state:-none}
primary_session_agent_message_count: ${primary_session_agent_message_count:-unknown}
primary_session_tool_call_count: ${primary_session_tool_call_count:-unknown}
primary_session_tool_result_count: ${primary_session_tool_result_count:-unknown}
primary_session_task_complete_last_agent_message: ${primary_session_task_complete_last_agent_message:-unknown}
primary_session_last_rate_limit_reached_type: ${primary_session_last_rate_limit_reached_type:-unknown}
primary_session_last_rate_limit_limit_id: ${primary_session_last_rate_limit_limit_id:-unknown}
primary_session_last_rate_limit_limit_name: ${primary_session_last_rate_limit_limit_name:-unknown}
primary_session_last_rate_limit_plan_type: ${primary_session_last_rate_limit_plan_type:-unknown}
primary_session_last_rate_limit_primary_used_percent: ${primary_session_last_rate_limit_primary_used_percent:-unknown}
primary_session_last_rate_limit_secondary_used_percent: ${primary_session_last_rate_limit_secondary_used_percent:-unknown}
quota_snapshot_identity_changed: $(quota_identity_changed_flag "${limit_id:-unknown}" "${limit_name:-unknown}" "${after_limit_id:-unknown}" "${after_limit_name:-unknown}")
quota_session_identity_changed: $(quota_identity_changed_flag "${limit_id:-unknown}" "${limit_name:-unknown}" "${primary_session_last_rate_limit_limit_id:-unknown}" "${primary_session_last_rate_limit_limit_name:-unknown}")
dirty_paths: $DIRTY_PATH_COUNT
tracked_modified_paths: $TRACKED_MODIFIED_PATH_COUNT
untracked_paths: $UNTRACKED_PATH_COUNT
primary_before_limit_id: ${limit_id:-unknown}
primary_before_limit_name: ${limit_name:-unknown}
primary_before_snapshot_source: ${before_source:-unknown}
primary_before_snapshot_model_hint: ${before_model_hint:-unknown}
primary_before_snapshot_current: ${before_snapshot_is_current:-unknown}
primary_before_snapshot_event_timestamp: ${before_ts:-unknown}
primary_before_snapshot_age_seconds: ${before_snapshot_age_seconds:-unknown}
primary_before_primary_reset: $(format_epoch_local "${primary_reset:-}")
primary_before_primary_reset_age_seconds: ${before_primary_reset_age_seconds:-unknown}
primary_before_primary_reset_expired: ${before_primary_reset_expired:-unknown}
primary_before_primary_bucket_current: ${before_primary_bucket_current:-unknown}
primary_before_secondary_reset: $(format_epoch_local "${secondary_reset:-}")
primary_before_secondary_reset_age_seconds: ${before_secondary_reset_age_seconds:-unknown}
primary_before_secondary_reset_expired: ${before_secondary_reset_expired:-unknown}
primary_before_secondary_bucket_current: ${before_secondary_bucket_current:-unknown}
primary_before_snapshot_stale_after_reset: ${before_snapshot_stale_after_reset:-unknown}
primary_before_session_end_state: $primary_before_session_end_state
primary_after_limit_id: ${after_limit_id:-unknown}
primary_after_limit_name: ${after_limit_name:-unknown}
primary_after_snapshot_source: ${after_source:-unknown}
primary_after_snapshot_model_hint: ${after_model_hint:-unknown}
primary_after_snapshot_current: ${after_snapshot_is_current:-unknown}
primary_after_snapshot_event_timestamp: ${after_ts:-unknown}
primary_after_snapshot_age_seconds: ${after_snapshot_age_seconds:-unknown}
primary_after_primary_reset: $(format_epoch_local "${after_primary_reset:-}")
primary_after_primary_reset_age_seconds: ${after_primary_reset_age_seconds:-unknown}
primary_after_primary_reset_expired: ${after_primary_reset_expired:-unknown}
primary_after_primary_bucket_current: ${after_primary_bucket_current:-unknown}
primary_after_secondary_reset: $(format_epoch_local "${after_secondary_reset:-}")
primary_after_secondary_reset_age_seconds: ${after_secondary_reset_age_seconds:-unknown}
primary_after_secondary_reset_expired: ${after_secondary_reset_expired:-unknown}
primary_after_secondary_bucket_current: ${after_secondary_bucket_current:-unknown}
primary_after_snapshot_stale_after_reset: ${after_snapshot_stale_after_reset:-unknown}
primary_before_used_left: primary_used=${primary_used:-unknown}% primary_left=${primary_left:-unknown}% secondary_used=${secondary_used:-unknown}% secondary_left=${secondary_left:-unknown}%
primary_after_used_left: primary_used=${after_primary:-unknown}% primary_left=${after_primary_left:-unknown}% secondary_used=${after_secondary:-unknown}% secondary_left=${after_secondary_left:-unknown}%
incident_log_path: $incident_log_path
primary_last_message_copy: $primary_last_message_copy
repo_root: $ROOT_DIR
loop_log: $LOG_FILE
EOF
}

write_postmortem_bug_record() {
  local bug_record_path="$1"
  local trigger="$2"
  local detail_text="$3"
  local child_exit="$4"
  local sequence_status="$5"
  local report_path="$6"
  local context_path="$7"
  local incident_log_path="$8"
  local screen_root fallback_completed_child_count fallback_current_child_id fallback_current_child_status fallback_runner_stop_reason
  local fallback_marker_analysis fallback_child_status_marker incident_classification

  screen_root="$CODEX_POSTMORTEM_DIR/$CYCLE_ID/screen"
  fallback_completed_child_count="$(read_artifact_or_unknown "$screen_root/completed-child-count.txt")"
  fallback_current_child_id="$(read_artifact_or_unknown "$screen_root/current-child-cycle-id.txt")"
  fallback_current_child_status="$(read_artifact_or_unknown "$screen_root/current-child-status.txt")"
  fallback_runner_stop_reason="$(read_artifact_or_unknown "$screen_root/stop-reason.txt")"
  fallback_marker_analysis="$(while_marker_analysis_json "${FALLBACK_SCREEN_TRANSCRIPT_PATH:-}")"
  fallback_child_status_marker="$(json_field "$fallback_marker_analysis" '.accepted_marker')"
  if [[ -z "$fallback_child_status_marker" ]]; then
    fallback_child_status_marker="missing"
  fi
  incident_classification="$(postmortem_incident_classification "$trigger" "$child_exit" "$fallback_child_status_marker")"

  cat >"$bug_record_path" <<EOF
# Upkeeper Incident Bug Record

## Suggested Title
Upkeeper incident: $trigger in cycle $CYCLE_ID

## Current Status
- sequence_status: $sequence_status
- trigger: $trigger
- incident_classification: $incident_classification
- detail: $detail_text
- child_exit: $child_exit

## Primary Context
- cycle_id: $CYCLE_ID
- primary_model: $CODEX_MODEL
- primary_reasoning_effort: $CODEX_REASONING_EFFORT
- primary_status_marker: ${status_marker:-missing}
- primary_codex_exit: ${codex_exit:-unknown}
- primary_session_end_state: ${session_end_state:-none}
- execution_origin: $CODEX_EXECUTION_ORIGIN

## Recovery Context
- fallback_model: $CODEX_FALLBACK_MODEL
- fallback_reasoning_effort: $CODEX_FALLBACK_REASONING_EFFORT
- fallback_screen_session: ${FALLBACK_SCREEN_SESSION_NAME:-none}
- fallback_screen_transcript: ${FALLBACK_SCREEN_TRANSCRIPT_PATH:-none}
- fallback_screen_exit_code: ${FALLBACK_SCREEN_EXIT_CODE:-unknown}
- fallback_completed_child_count: $fallback_completed_child_count
- fallback_current_child_cycle_id: $fallback_current_child_id
- fallback_current_child_status: $fallback_current_child_status
- fallback_child_status_marker: $fallback_child_status_marker
- fallback_runner_stop_reason: $fallback_runner_stop_reason

## Repo State Snapshot
- repo_root: $ROOT_DIR
- dirty_paths: $DIRTY_PATH_COUNT
- tracked_modified_paths: $TRACKED_MODIFIED_PATH_COUNT
- untracked_paths: $UNTRACKED_PATH_COUNT

## Evidence Paths
- context: $context_path
- incident_log: $incident_log_path
- report: $report_path
- loop_log: $LOG_FILE

## Suggested Labels
- bug
- upkeeper
- wrapper
- ${trigger}

## Filing Note
This artifact is shell-generated so there is always a human-readable bug stub
even if the later LLM post-mortem or hardening phases fail.
EOF
}
