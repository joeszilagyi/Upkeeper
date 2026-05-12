# Fallback orchestration.
#
# A fallback child is still one cycle, just with stronger defaults and extra
# context. The parent owns the postmortem sequence because incident evidence is
# about the failed handoff as a whole, not only the child run.
run_fallback_cycle() {
  local trigger="$1"
  shift
  local detail_text="${*:-none}"
  local child_exit=0
  local source_model="$CODEX_MODEL"
  local fallback_contract_path
  local bwrap_tmp_detail bwrap_tmp_detail_q
  local fallback_chain_token
  fallback_chain_token="$(generate_fallback_chain_token)"

  fallback_contract_path="${CODEX_POSTMORTEM_DIR:-${ROOT_DIR:-$PWD}/runtime/journals/upkeeper-postmortems}/$CYCLE_ID/fallback-$CYCLE_RUN_HASH.contract"
  if ! mkdir -p -- "$(dirname -- "$fallback_contract_path")"; then
    log_line "ERROR" "fallback.contract_build_failed path=$(shell_quote "$fallback_contract_path")"
    finish_cycle 7 FALLBACK_CONTRACT_BROKEN ERROR "codex_exec_started=1 reason=parent_dir_create_failed"
  fi
  if ! cat >"${fallback_contract_path}.tmp.$$" <<EOF
UPKEEPER_CONFIG_DISABLE=$(printf '%q' "${UPKEEPER_CONFIG_DISABLE:-0}")
UPKEEPER_CONFIG_FILE=$(printf '%q' "${UPKEEPER_CONFIG_FILE:-}")
UPKEEPER_CONFIG_FILE_EXPLICIT=$(printf '%q' "${UPKEEPER_CONFIG_FILE_EXPLICIT:-0}")
UPKEEPER_CONFIG_LOADED=$(printf '%q' "${UPKEEPER_CONFIG_LOADED:-0}")
UPKEEPER_CONFIG_SOURCE=$(printf '%q' "${UPKEEPER_CONFIG_SOURCE:-none}")
CODEX_TARGET_FILE=$(printf '%q' "${CODEX_TARGET_FILE:-}")
CODEX_SELECTION_SOURCE=$(printf '%q' "${CODEX_SELECTION_SOURCE:-}")
CODEX_SELECTION_ORDER=$(printf '%q' "${CODEX_SELECTION_ORDER:-}")
CODEX_FILE_MANIFEST_MODE=$(printf '%q' "${CODEX_FILE_MANIFEST_MODE:-}")
CODEX_FILE_MANIFEST_PATH=$(printf '%q' "${CODEX_FILE_MANIFEST_PATH:-}")
CODEX_TARGET_ROOT=$(printf '%q' "${CODEX_TARGET_ROOT:-}")
CODEX_TARGET_MAX_DEPTH=$(printf '%q' "${CODEX_TARGET_MAX_DEPTH:-}")
CODEX_SELECTION_INCLUDE_GLOBS=$(printf '%q' "${CODEX_SELECTION_INCLUDE_GLOBS:-}")
CODEX_SELECTION_EXCLUDE_GLOBS=$(printf '%q' "${CODEX_SELECTION_EXCLUDE_GLOBS:-}")
CODEX_SELECTION_REVIEW_MODULES=$(printf '%q' "${CODEX_SELECTION_REVIEW_MODULES:-}")
CODEX_SELECTION_RANDOM_SEED=$(printf '%q' "${CODEX_SELECTION_RANDOM_SEED:-}")
CODEX_MAX_COVER_MODE=$(printf '%q' "${CODEX_MAX_COVER_MODE:-0}")
CODEX_ISSUE_FIX_NEXT=$(printf '%q' "${CODEX_ISSUE_FIX_NEXT:-0}")
CODEX_ISSUE_FIX_REQUESTED_NUMBER=$(printf '%q' "${CODEX_ISSUE_FIX_REQUESTED_NUMBER:-}")
CODEX_ISSUE_WORKFLOW_STAGE=$(printf '%q' "${CODEX_ISSUE_WORKFLOW_STAGE:-}")
CODEX_ISSUE_FIX_NUMBER=$(printf '%q' "${CODEX_ISSUE_FIX_NUMBER:-}")
CODEX_ISSUE_FIX_SELECTED_LABEL=$(printf '%q' "${CODEX_ISSUE_FIX_SELECTED_LABEL:-}")
CODEX_ISSUE_FIX_LABELS=$(printf '%q' "${CODEX_ISSUE_FIX_LABELS:-}")
CODEX_ISSUE_FIX_TARGET_FILE=$(printf '%q' "${CODEX_ISSUE_FIX_TARGET_FILE:-}")
CODEX_ISSUE_FIX_TITLE=$(printf '%q' "${CODEX_ISSUE_FIX_TITLE:-}")
CODEX_ISSUE_FIX_URL=$(printf '%q' "${CODEX_ISSUE_FIX_URL:-}")
CODEX_ISSUE_FIX_CREATED_AT=$(printf '%q' "${CODEX_ISSUE_FIX_CREATED_AT:-}")
CODEX_ISSUE_FIX_BODY=$(printf '%q' "${CODEX_ISSUE_FIX_BODY:-}")
CODEX_ISSUE_FIX_COMMENTS_JSON=$(printf '%q' "${CODEX_ISSUE_FIX_COMMENTS_JSON:-[]}")
CODEX_TOOL_FAILURE_QUEUE_DIR=$(printf '%q' "${CODEX_TOOL_FAILURE_QUEUE_DIR:-}")
CODEX_TOOL_FAILURE_QUEUE_BYPASS=$(printf '%q' "${CODEX_TOOL_FAILURE_QUEUE_BYPASS:-0}")
RUN_SELECTED_REVIEW_PATH=$(printf '%q' "${RUN_SELECTED_REVIEW_PATH:-}")
RUN_SELECTED_FROM_FAILURE_QUEUE=$(printf '%q' "${RUN_SELECTED_FROM_FAILURE_QUEUE:-0}")
RUN_SELECTED_FAILURE_MARKER_ID=$(printf '%q' "${RUN_SELECTED_FAILURE_MARKER_ID:-}")
RUN_SELECTED_FAILURE_MARKER_PATH=$(printf '%q' "${RUN_SELECTED_FAILURE_MARKER_PATH:-}")
UPKEEPER_IGNORE_FAILURE_QUEUE=$(printf '%q' "${UPKEEPER_IGNORE_FAILURE_QUEUE:-0}")
EOF
  then
    log_line "ERROR" "fallback.contract_build_failed path=$(shell_quote "$fallback_contract_path")"
    finish_cycle 7 FALLBACK_CONTRACT_BROKEN ERROR "codex_exec_started=1 reason=write_failed"
  fi
  if ! chmod 600 "${fallback_contract_path}.tmp.$$" || ! mv -f "${fallback_contract_path}.tmp.$$" "$fallback_contract_path"; then
    rm -f "${fallback_contract_path}.tmp.$$"
    log_line "ERROR" "fallback.contract_build_failed path=$(shell_quote "$fallback_contract_path")"
    finish_cycle 7 FALLBACK_CONTRACT_BROKEN ERROR "codex_exec_started=1 reason=unwritable_contract"
  fi
  CODEX_FALLBACK_CONTRACT_PATH="$fallback_contract_path"

  if [[ "$UPKEEPER_DRY_RUN" == "1" ]]; then
    bwrap_tmp_detail="ok"
  else
    bwrap_tmp_detail="$(codex_bwrap_tmp_write_check | compact_process_args || true)"
  fi
  if [[ "$bwrap_tmp_detail" != "ok" ]]; then
    bwrap_tmp_detail_q="$(shell_quote "$bwrap_tmp_detail")"
    log_line "WARN" "fallback.skip trigger=$trigger reason=codex_bwrap_tmp_unwritable registry_root=$(shell_quote "$CODEX_BWRAP_TMP_ROOT") detail=$bwrap_tmp_detail_q"
    child_exit=3
  elif fallback_would_rediscover_dirty_block "$trigger"; then
    log_line "WARN" "fallback.skip trigger=$trigger reason=dirty_worktree_predicted_block dirty_paths=$DIRTY_PATH_COUNT tracked_modified_paths=$TRACKED_MODIFIED_PATH_COUNT untracked_paths=$UNTRACKED_PATH_COUNT mode=normal_backend_prompt"
    child_exit=2
  elif [[ "$CODEX_FALLBACK_SCREEN_ENABLED" == "1" ]]; then
    if ! launch_screen_fallback_loop "$trigger" "$detail_text"; then
      log_line "ERROR" "fallback.screen.start failed trigger=$trigger"
      child_exit=8
    else
      wait_for_screen_fallback_loop "$trigger" "$FALLBACK_SCREEN_SESSION_NAME" "$CODEX_POSTMORTEM_DIR/$CYCLE_ID/screen/final-exit-code.txt" "$CODEX_POSTMORTEM_DIR/$CYCLE_ID/screen/done.txt"
      child_exit="${FALLBACK_SCREEN_EXIT_CODE:-8}"
    fi
  else
    log_line "INFO" "fallback.start execution_origin=primary trigger=$trigger mode=direct from_model=$source_model to_model=$CODEX_FALLBACK_MODEL detail=\"$detail_text\""
    if [[ "$UPKEEPER_DRY_RUN" == "1" ]]; then
      log_line "INFO" "dry-run active; skipping direct fallback child exec trigger=$trigger target_model=$CODEX_FALLBACK_MODEL"
      child_exit=0
    else
      local -a child_args=()
      if [[ -n "$PROMPT_FILE" ]]; then
        child_args+=(--prompt-file "$PROMPT_FILE")
      elif [[ -n "$INLINE_PROMPT" ]]; then
        child_args+=(--prompt "$INLINE_PROMPT")
      fi
      local review_module
      for review_module in "${CODEX_REVIEW_MODULES[@]}"; do
        child_args+=("--review-module=$review_module")
      done
      if [[ -n "$CODEX_TARGET_FILE" ]]; then
        child_args+=("--target-file=$CODEX_TARGET_FILE")
      elif [[ -n "$RUN_SELECTED_REVIEW_PATH" ]]; then
        child_args+=("--target-file=$RUN_SELECTED_REVIEW_PATH")
      fi
      if [[ -n "$CODEX_PROMPT_PASS" ]]; then
        child_args+=("--prompt-pass=$CODEX_PROMPT_PASS")
      fi
      if upkeeper_bug_report_only_enabled; then
        child_args+=("--bug-report-only")
      fi
      set +e
      CODEX_MODEL="$CODEX_FALLBACK_MODEL" \
      CODEX_REASONING_EFFORT="$CODEX_FALLBACK_REASONING_EFFORT" \
      CODEX_MODE="$CODEX_FALLBACK_MODE" \
      CODEX_FALLBACK_ENABLED=0 \
      CODEX_FALLBACK_CHAIN_ACTIVE=1 \
      CODEX_FALLBACK_PARENT_PID="$$" \
      CODEX_FALLBACK_PARENT_START="$(process_start_fingerprint "$$")" \
      CODEX_ATTEMPT_ROLE=fallback \
      CODEX_PRIMARY_MODEL_CONTEXT="$source_model" \
      CODEX_FALLBACK_TRIGGER="$trigger" \
      CODEX_PARENT_CYCLE_ID="$CYCLE_ID" \
      CODEX_FALLBACK_CONTRACT_PATH="$CODEX_FALLBACK_CONTRACT_PATH" \
      CODEX_FALLBACK_CHAIN_TOKEN_FD=9 \
      9<<<"$fallback_chain_token" \
      CODEX_POSTMORTEM_ENABLED=0 \
      CODEX_DISABLE_PARENT_STOP=1 \
      CODEX_GUARDRAIL_STOP_EXIT_CODE=9 \
      CODEX_EXECUTION_ORIGIN=direct_fallback \
      "$SELF_INVOKE_PATH" "${child_args[@]}"
      child_exit=$?
      set -e
    fi
  fi

  local final_exit="$child_exit"
  if [[ "$CODEX_POSTMORTEM_ENABLED" == "1" ]]; then
    set +e
    run_postmortem_sequence "$trigger" "$detail_text" "$child_exit"
    final_exit=$?
    set -e
  fi

  log_line "INFO" "fallback.finish trigger=$trigger child_exit=$child_exit final_exit=$final_exit child_model=$CODEX_FALLBACK_MODEL child_effort=$CODEX_FALLBACK_REASONING_EFFORT parent_cycle_id=$CYCLE_ID execution_origin=$([[ "$CODEX_FALLBACK_SCREEN_ENABLED" == "1" ]] && printf screen || printf direct_fallback) postmortem_status=$POSTMORTEM_SEQUENCE_STATUS report_path=${POSTMORTEM_REPORT_PATH:-none} screen_session=${FALLBACK_SCREEN_SESSION_NAME:-none}"
  refresh_postmortem_incident_log "${POSTMORTEM_INCIDENT_LOG_PATH:-}"
  return "$final_exit"
}
