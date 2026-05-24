# Auxiliary postmortem/hardening guardrail.
#
# Recovery diagnostics should not make quota exhaustion worse. This check runs
# against the auxiliary model before launching another Codex process; if the
# exact-model snapshot has no current bucket or any current bucket is unsafe,
# the shell writes a minimal report instead.
aux_quota_allows_run() {
  local phase_label="$1"
  local target_model="$2"

  local quota_json quota_error selection snapshot_current stale_after_reset matching_count
  local primary_reset_expired secondary_reset_expired primary_bucket_current secondary_bucket_current
  local source model_hint ts primary_used secondary_used primary_left secondary_left
  local limit_id limit_name expected_quota_identity quota_identity_status
  local projected_primary_delta projected_secondary_delta projected_basis
  local primary_projected_used secondary_projected_used primary_projected_left secondary_projected_left
  local five_hour_threshold week_threshold week_buffer stop_reason=""
  local primary_guardrail_decision="defer" secondary_guardrail_decision="defer"

  five_hour_threshold="$(quota_5h_stop_percent_for_model "$target_model")"
  week_threshold="$(quota_week_stop_percent_for_model "$target_model")"
  week_buffer="$(quota_week_stop_buffer_percent_for_model "$target_model")"

  quota_json="$(quota_state_json "$target_model")"
  eval "$(quota_json_assignments "$quota_json" quota)"
  quota_error="$quota_error"
  if [[ -n "$quota_error" ]]; then
    log_line "WARN" "$phase_label.skip reason=quota_snapshot_unavailable target_model=$target_model error=$quota_error"
    return 1
  fi

  selection="$quota_selection"
  snapshot_current="$quota_snapshot_is_current"
  stale_after_reset="$quota_snapshot_stale_after_reset"
  primary_reset_expired="$quota_primary_reset_expired"
  secondary_reset_expired="$quota_secondary_reset_expired"
  primary_bucket_current="$quota_primary_bucket_current"
  secondary_bucket_current="$quota_secondary_bucket_current"
  matching_count="$quota_matching_snapshot_count"
  source="$quota_source"
  model_hint="$quota_model_hint"
  ts="$quota_ts"
  limit_id="$quota_limit_id"
  limit_name="$quota_limit_name"
  expected_quota_identity="$(quota_expected_identity_for_model "$target_model")"
  quota_identity_status="$(quota_identity_status_for_model "$target_model" "$limit_id" "$limit_name")"
  primary_used="$quota_primary_used"
  secondary_used="$quota_secondary_used"
  projected_primary_delta="$quota_projected_primary_delta"
  projected_secondary_delta="$quota_projected_secondary_delta"
  projected_basis="$quota_projected_basis"

  if [[ -z "$primary_used" || -z "$secondary_used" || -z "$projected_primary_delta" || -z "$projected_secondary_delta" ]]; then
    log_line_parts "WARN" \
      "$phase_label.skip reason=quota_snapshot_incomplete target_model=$target_model" \
      " snapshot_selection=$selection snapshot_current=$snapshot_current" \
      "$(quota_hashed_path_log_field source "$source")" \
      "$(quota_sensitive_log_field source "$source")"
    return 1
  fi

  primary_left="$(awk -v used="$primary_used" 'BEGIN { printf "%.1f", 100 - used }')"
  secondary_left="$(awk -v used="$secondary_used" 'BEGIN { printf "%.1f", 100 - used }')"
  primary_projected_used="$(awk -v current="$primary_used" -v delta="$projected_primary_delta" 'BEGIN { printf "%.1f", current + delta }')"
  secondary_projected_used="$(awk -v current="$secondary_used" -v delta="$projected_secondary_delta" 'BEGIN { printf "%.1f", current + delta }')"
  primary_projected_left="$(awk -v used="$primary_projected_used" 'BEGIN { printf "%.1f", 100 - used }')"
  secondary_projected_left="$(awk -v used="$secondary_projected_used" 'BEGIN { printf "%.1f", 100 - used }')"

  if [[ "$selection" == "exact_model" ]]; then
    primary_guardrail_decision="$(quota_bucket_decision "$primary_bucket_current" "$primary_projected_left" "$five_hour_threshold")"
    secondary_guardrail_decision="$(quota_bucket_decision "$secondary_bucket_current" "$secondary_projected_left" "$week_threshold")"
  fi

  log_line_parts "INFO" \
    "$phase_label.quota target_model=$target_model snapshot_selection=$selection" \
    " snapshot_current=$snapshot_current snapshot_stale_after_reset=$stale_after_reset" \
    " primary_reset_expired=$primary_reset_expired" \
    " secondary_reset_expired=$secondary_reset_expired" \
    " primary_bucket_current=$primary_bucket_current" \
    " secondary_bucket_current=$secondary_bucket_current" \
    " matching_snapshot_count=$matching_count" \
    " expected_quota_identity=$expected_quota_identity" \
    " quota_identity_status=$quota_identity_status" \
    "$(quota_hashed_log_field limit_id "$limit_id")" \
    "$(quota_hashed_log_field limit_name "$limit_name")" \
    "$(quota_hashed_path_log_field source "$source")" \
    " primary_decision=$primary_guardrail_decision" \
    " secondary_decision=$secondary_guardrail_decision" \
    " projection_basis=$projected_basis" \
    "$(quota_sensitive_log_field limit_id "$limit_id")" \
    "$(quota_sensitive_log_field limit_name "$limit_name")" \
    "$(quota_sensitive_log_field source "$source")" \
    "$(quota_sensitive_log_field plan_type "$plan_type")" \
    "$(quota_sensitive_log_field snapshot_model_hint "$model_hint")" \
    "$(quota_sensitive_log_field event_timestamp "$ts")" \
    "$(quota_sensitive_log_field primary_used "${primary_used}%")" \
    "$(quota_sensitive_log_field primary_left "${primary_left}%")" \
    "$(quota_sensitive_log_field secondary_used "${secondary_used}%")" \
    "$(quota_sensitive_log_field secondary_left "${secondary_left}%")" \
    "$(quota_sensitive_log_field projected_primary_delta_used "${projected_primary_delta}%")" \
    "$(quota_sensitive_log_field projected_primary_left "${primary_projected_left}%")" \
    "$(quota_sensitive_log_field projected_secondary_delta_used "${projected_secondary_delta}%")" \
    "$(quota_sensitive_log_field projected_secondary_left "${secondary_projected_left}%")" \
    "$(quota_sensitive_log_field left_thresholds "${five_hour_threshold}%/${week_threshold}%")" \
    "$(quota_sensitive_log_field weekly_base_threshold "${CODEX_WEEK_STOP_PERCENT}%")" \
    "$(quota_sensitive_log_field weekly_buffer "${week_buffer}%")"

  if [[ "${CODEX_QUOTA_GUARDRAIL_BYPASS:-0}" == "1" ]]; then
    log_line "WARN" "$phase_label.quota_bypass target_model=$target_model primary_decision=$primary_guardrail_decision secondary_decision=$secondary_guardrail_decision quota_identity_status=$quota_identity_status"
    return 0
  fi

  if [[ "$selection" != "exact_model" ]]; then
    log_line_parts "WARN" \
      "$phase_label.skip reason=quota_snapshot_not_exact target_model=$target_model" \
      " snapshot_selection=$selection" \
      "$(quota_hashed_path_log_field source "$source")" \
      "$(quota_sensitive_log_field snapshot_model_hint "$model_hint")" \
      "$(quota_sensitive_log_field source "$source")"
    return 1
  fi
  if ! quota_identity_allows_pre_run "$target_model" "$limit_id" "$limit_name"; then
    log_line_parts "WARN" \
      "$phase_label.skip reason=quota_identity_conflict target_model=$target_model" \
      " expected_quota_identity=$expected_quota_identity" \
      " quota_identity_status=$quota_identity_status" \
      "$(quota_hashed_log_field limit_id "$limit_id")" \
      "$(quota_hashed_log_field limit_name "$limit_name")" \
      "$(quota_hashed_path_log_field source "$source")" \
      "$(quota_sensitive_log_field limit_id "$limit_id")" \
      "$(quota_sensitive_log_field limit_name "$limit_name")" \
      "$(quota_sensitive_log_field source "$source")"
    return 1
  fi
  if [[ "$primary_guardrail_decision" == "defer" && "$secondary_guardrail_decision" == "defer" ]]; then
    log_line_parts "WARN" \
      "$phase_label.skip reason=quota_snapshot_stale target_model=$target_model" \
      " snapshot_current=$snapshot_current snapshot_stale_after_reset=$stale_after_reset" \
      " primary_bucket_current=$primary_bucket_current" \
      " secondary_bucket_current=$secondary_bucket_current" \
      "$(quota_hashed_path_log_field source "$source")" \
      "$(quota_sensitive_log_field source "$source")"
    return 1
  fi
  if [[ "$primary_guardrail_decision" == "defer" || "$secondary_guardrail_decision" == "defer" ]]; then
    log_line_parts "WARN" \
      "$phase_label.skip reason=quota_snapshot_partial target_model=$target_model" \
      " primary_decision=$primary_guardrail_decision" \
      " secondary_decision=$secondary_guardrail_decision" \
      " primary_bucket_current=$primary_bucket_current" \
      " secondary_bucket_current=$secondary_bucket_current" \
      " primary_reset_expired=$primary_reset_expired" \
      " secondary_reset_expired=$secondary_reset_expired" \
      "$(quota_hashed_path_log_field source "$source")" \
      "$(quota_sensitive_log_field source "$source")"
    return 1
  fi

  if [[ "$primary_guardrail_decision" == "stop" ]]; then
    stop_reason="projected 5-hour left ${primary_projected_left}% <= ${five_hour_threshold}%"
  fi
  if [[ "$secondary_guardrail_decision" == "stop" ]]; then
    if [[ -n "$stop_reason" ]]; then
      stop_reason="$stop_reason; "
    fi
    stop_reason="${stop_reason}projected weekly left ${secondary_projected_left}% <= ${week_threshold}% (base ${CODEX_WEEK_STOP_PERCENT}% + buffer ${week_buffer}%)"
  fi
  if [[ -n "$stop_reason" ]]; then
    log_line "WARN" "$phase_label.skip reason=quota_guardrail target_model=$target_model detail=\"$stop_reason\""
    return 1
  fi
  return 0
}

write_aux_quota_blocked_marker() {
  local phase_label="$1"
  local target_model="$2"
  local last_message_file="$3"

  cat >"$last_message_file" <<EOF
Auxiliary Codex execution skipped before launch.

phase: $phase_label
model: $target_model
reason: quota guardrail, missing exact-model quota snapshot, or no current bucket

CODEX_POSTMORTEM_STATUS: BLOCKED
EOF
}

write_aux_environment_blocked_marker() {
  local phase_label="$1"
  local target_model="$2"
  local last_message_file="$3"
  local detail="$4"
  local reason="${5:-Codex local runtime is not writable}"

  cat >"$last_message_file" <<EOF
Auxiliary Codex execution skipped before launch.

phase: $phase_label
model: $target_model
reason: $reason
code_home: $CODEX_HOME_DIR
session_store: $CODEX_HOME_DIR/sessions
arg0_tmp_root: $CODEX_ARG0_TMP_ROOT
arg0_quarantine_root: $CODEX_ARG0_TMP_QUARANTINE_ROOT
bwrap_tmp_root: $CODEX_BWRAP_TMP_ROOT
detail: $detail

CODEX_POSTMORTEM_STATUS: BLOCKED
EOF
}

run_aux_codex_exec() {
  local phase_label="$1"
  local model="$2"
  local effort="$3"
  local mode_string="$4"
  local prompt_file="$5"
  local last_message_file="$6"
  local session_store_detail session_store_detail_q arg0_tmp_detail arg0_tmp_detail_q bwrap_tmp_detail bwrap_tmp_detail_q
  local first_mode_token first_mode_token_q
  local sandbox_mode extra_mode_token

  local -a aux_mode_args=()
  first_mode_token="${aux_mode_args[0]:-}"
  if [[ -n "${mode_string:-}" ]]; then
    read -r -a aux_mode_args <<<"$mode_string"
    first_mode_token="${aux_mode_args[0]:-}"
    sandbox_mode="${aux_mode_args[1]:-}"
    extra_mode_token="${aux_mode_args[2]:-}"
    if [[ "$first_mode_token" != --* || "$first_mode_token" == ---* ]]; then
      first_mode_token_q="$(shell_quote "$first_mode_token")"
      write_aux_environment_blocked_marker "$phase_label" "$model" "$last_message_file" "invalid first mode token $first_mode_token_q; expected a Codex option beginning with --" "Codex auxiliary mode is invalid"
      log_line "WARN" "$phase_label.finish exit_code=87 model=$model reason=invalid_aux_mode first_token=$first_mode_token_q mode=$(shell_quote "$mode_string")"
      return 87
    fi
    case "$first_mode_token" in
      danger-full-access|--dangerously-bypass-approvals-and-sandbox)
        first_mode_token_q="$(shell_quote --dangerously-bypass-approvals-and-sandbox)"
        write_aux_environment_blocked_marker "$phase_label" "$model" "$last_message_file" "invalid auxiliary mode token $first_mode_token_q; expected a sandboxed mode" "Codex auxiliary mode is invalid"
        log_line "WARN" "$phase_label.finish exit_code=87 model=$model reason=invalid_aux_mode first_token=$first_mode_token_q mode=$(shell_quote "$mode_string")"
        return 87
        ;;
      --sandbox)
        ;;
      *)
        first_mode_token_q="$(shell_quote "$first_mode_token")"
        write_aux_environment_blocked_marker "$phase_label" "$model" "$last_message_file" "invalid auxiliary mode token $first_mode_token_q; expected first token --sandbox" "Codex auxiliary mode is invalid"
        log_line "WARN" "$phase_label.finish exit_code=87 model=$model reason=invalid_aux_mode first_token=$first_mode_token_q mode=$(shell_quote "$mode_string")"
        return 87
        ;;
    esac

    if [[ -z "$sandbox_mode" ]]; then
      write_aux_environment_blocked_marker "$phase_label" "$model" "$last_message_file" "invalid auxiliary mode token $(shell_quote --sandbox); expected a sandbox mode argument" "Codex auxiliary mode is invalid"
      log_line "WARN" "$phase_label.finish exit_code=87 model=$model reason=invalid_aux_mode first_token=$(shell_quote --sandbox) mode=$(shell_quote "$mode_string")"
      return 87
    fi
    if [[ "$sandbox_mode" != workspace-write && "$sandbox_mode" != read-only ]]; then
      if [[ "$sandbox_mode" == danger-full-access || "$sandbox_mode" == --dangerously-bypass-approvals-and-sandbox ]]; then
        first_mode_token_q="$(shell_quote --dangerously-bypass-approvals-and-sandbox)"
        write_aux_environment_blocked_marker "$phase_label" "$model" "$last_message_file" "invalid auxiliary mode token $first_mode_token_q; expected a sandboxed mode" "Codex auxiliary mode is invalid"
        log_line "WARN" "$phase_label.finish exit_code=87 model=$model reason=invalid_aux_mode first_token=$first_mode_token_q mode=$(shell_quote "$mode_string")"
        return 87
      fi
      first_mode_token_q="$(shell_quote "$sandbox_mode")"
      write_aux_environment_blocked_marker "$phase_label" "$model" "$last_message_file" "invalid auxiliary mode token $first_mode_token_q; expected a sandbox mode argument" "Codex auxiliary mode is invalid"
      log_line "WARN" "$phase_label.finish exit_code=87 model=$model reason=invalid_aux_mode first_token=$first_mode_token_q mode=$(shell_quote "$mode_string")"
      return 87
    fi
    if [[ -n "$extra_mode_token" ]]; then
      if [[ "$extra_mode_token" == danger-full-access || "$extra_mode_token" == --dangerously-bypass-approvals-and-sandbox ]]; then
        first_mode_token_q="$(shell_quote --dangerously-bypass-approvals-and-sandbox)"
        write_aux_environment_blocked_marker "$phase_label" "$model" "$last_message_file" "invalid auxiliary mode token $first_mode_token_q; expected a sandboxed mode" "Codex auxiliary mode is invalid"
        log_line "WARN" "$phase_label.finish exit_code=87 model=$model reason=invalid_aux_mode first_token=$first_mode_token_q mode=$(shell_quote "$mode_string")"
        return 87
      fi
      first_mode_token_q="$(shell_quote "$extra_mode_token")"
      write_aux_environment_blocked_marker "$phase_label" "$model" "$last_message_file" "invalid auxiliary mode token $first_mode_token_q; auxiliary mode only supports --sandbox workspace-write or --sandbox read-only" "Codex auxiliary mode is invalid"
      log_line "WARN" "$phase_label.finish exit_code=87 model=$model reason=invalid_aux_mode first_token=$first_mode_token_q mode=$(shell_quote "$mode_string")"
      return 87
    fi

    aux_mode_args=(--sandbox "$sandbox_mode")
  fi

  log_line "INFO" "$phase_label.start model=$model effort=$effort mode=$mode_string prompt=$prompt_file output=$last_message_file"

  if [[ "$UPKEEPER_DRY_RUN" == "1" ]]; then
    log_line "INFO" "$phase_label.skip dry_run=1 model=$model"
    return 0
  fi

  if ! aux_quota_allows_run "$phase_label" "$model"; then
    write_aux_quota_blocked_marker "$phase_label" "$model" "$last_message_file"
    log_line "WARN" "$phase_label.finish exit_code=86 model=$model reason=quota_guardrail"
    return 86
  fi

  session_store_detail="$(codex_session_store_write_check | compact_process_args || true)"
  if [[ "$session_store_detail" != "ok" ]]; then
    write_aux_environment_blocked_marker "$phase_label" "$model" "$last_message_file" "$session_store_detail"
    log_line "WARN" "$phase_label.finish exit_code=87 model=$model reason=codex_session_store_unwritable detail_redacted=1"
    return 87
  fi

  arg0_tmp_detail="$(codex_arg0_tmp_cleanup_check | compact_process_args || true)"
  if [[ "$arg0_tmp_detail" != "ok" && "$arg0_tmp_detail" != ok\ * ]]; then
    write_aux_environment_blocked_marker "$phase_label" "$model" "$last_message_file" "$arg0_tmp_detail" "Codex arg0 temp directory contains uncleanable stale entries"
    log_line "WARN" "$phase_label.finish exit_code=87 model=$model reason=codex_arg0_tmp_uncleanable detail_redacted=1"
    return 87
  fi
  if [[ "$arg0_tmp_detail" == ok\ * ]]; then
    log_line "INFO" "$phase_label.arg0_tmp_cleanup model=$model detail_redacted=1"
  fi

  if [[ "$UPKEEPER_DRY_RUN" == "1" ]]; then
    bwrap_tmp_detail="ok"
  else
    bwrap_tmp_detail="$(codex_bwrap_tmp_write_check | compact_process_args || true)"
  fi
  if [[ "$bwrap_tmp_detail" != "ok" ]]; then
    write_aux_environment_blocked_marker "$phase_label" "$model" "$last_message_file" "$bwrap_tmp_detail" "Codex bubblewrap temp registry is not writable"
    log_line "WARN" "$phase_label.finish exit_code=87 model=$model reason=codex_bwrap_tmp_unwritable detail_redacted=1"
    return 87
  fi

  local aux_transcript_file
  aux_transcript_file="$(new_transcript_file "$phase_label")"
  log_line "INFO" "$phase_label.transcript path=$(shell_quote "$aux_transcript_file")"

  set +e
  run_codex_exec_capture "$phase_label" "$aux_transcript_file" "$prompt_file" \
    codex exec \
    "${aux_mode_args[@]}" \
    -C "$ROOT_DIR" \
    -m "$model" \
    -c "model_reasoning_effort="$effort"" \
    -o "$last_message_file"
  local aux_exit=$?
  set -e

  if [[ "$aux_exit" -eq 0 ]]; then
    log_line "INFO" "$phase_label.finish exit_code=$aux_exit model=$model transcript=$(shell_quote "$(upkeeper_path_hmac "$aux_transcript_file")") path_redacted=1"
  else
    log_line "ERROR" "$phase_label.finish exit_code=$aux_exit model=$model transcript=$(shell_quote "$(upkeeper_path_hmac "$aux_transcript_file")") path_redacted=1"
  fi
  return "$aux_exit"

}
