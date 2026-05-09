# Every terminal path should end through this helper so the log has one obvious
# cycle.exit line with a reason and the exit code the outer loop will observe.
finish_cycle() {
  local exit_code="$1"
  local reason="$2"
  local level="$3"
  shift 3

  stop_terminal_progress_heartbeat "$reason"
  stop_run_mark_heartbeat "$reason"
  local message="cycle.exit exit_code=$exit_code reason=$reason"
  if [[ $# -gt 0 ]]; then
    message="$message $*"
  fi
  local status_marker="" codex_exit="" codex_exec_started="0"
  case "$reason" in
    WORK_DONE)
      status_marker="WORK_DONE"
      ;;
    BLOCKED)
      status_marker="BLOCKED"
      ;;
    NO_BACKEND_TASK|NO_BACKEND_TASK_CONTINUE|NO_BACKEND_TASK_DIRTY_CONTINUE)
      status_marker="NO_BACKEND_TASK"
      ;;
  esac
  if [[ "$message" =~ codex_exit=([-0-9]+) ]]; then
    codex_exit="${BASH_REMATCH[1]}"
  fi
  if [[ "$message" =~ codex_exec_started=([01]) ]]; then
    codex_exec_started="${BASH_REMATCH[1]}"
  elif [[ -n "${RUN_CODEX_STARTED_EPOCH:-}" ]]; then
    codex_exec_started="1"
  fi
  lattice_record_cycle_finish "$exit_code" "$reason" "$level" "$status_marker" "$codex_exit" "$codex_exec_started" "${RUN_SELECTED_REVIEW_PATH:-}" || true
  log_line "$level" "$message"
  finalize_wrapper_health_state "exited"
  release_active_lock
  exit "$exit_code"
}

cleanup_run_temp_files() {
  stop_terminal_progress_heartbeat "cleanup"
  stop_run_mark_heartbeat "cleanup"
  finalize_wrapper_health_state "aborted"
  release_active_lock
  if [[ -n "${RUN_COMPILED_PROMPT_FILE:-}" ]]; then
    rm -f "$RUN_COMPILED_PROMPT_FILE"
  fi
  if [[ -n "${RUN_LAST_MESSAGE_FILE:-}" ]]; then
    rm -f "$RUN_LAST_MESSAGE_FILE"
  fi
  if [[ -n "${RUN_TMP_DIR:-}" && "$RUN_TMP_DIR" == "${TMPDIR:-/tmp}"/upkeeper-* ]]; then
    find "$RUN_TMP_DIR" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
    rmdir "$RUN_TMP_DIR" 2>/dev/null || true
  fi
}

completed_fallback_screen_result_available() {
  local screen_root="$CODEX_POSTMORTEM_DIR/$CYCLE_ID/screen"
  local exit_file="$screen_root/final-exit-code.txt"
  local done_file="$screen_root/done.txt"

  [[ -n "${FALLBACK_SCREEN_SESSION_NAME:-}" ]] || return 1
  [[ -f "$done_file" && -f "$exit_file" ]] || return 1
}

fallback_screen_runner_process_groups() {
  local runner_script="$1"
  local pid pgid args

  [[ -n "$runner_script" ]] || return 0

  ps -eo pid=,pgid=,args= | while read -r pid pgid args; do
    [[ "$pid" =~ ^[0-9]+$ && "$pgid" =~ ^[0-9]+$ ]] || continue
    [[ "${args:-}" == *"$runner_script"* ]] || continue
    [[ "$pid" -eq "$$" ]] && continue
    printf '%s\n' "$pgid"
  done | sort -u
}

fallback_screen_process_group_exists() {
  local pgid="$1"

  [[ "$pgid" =~ ^[0-9]+$ ]] || return 1
  ps -eo pgid= | awk -v target="$pgid" '$1 == target { found = 1; exit } END { exit !found }'
}

terminate_fallback_screen_process_groups() {
  local reason="${1:-manual_teardown}"
  local runner_script="$CODEX_POSTMORTEM_DIR/$CYCLE_ID/screen/run-screen-fallback.sh"
  local pgid
  local -a pgids=()

  mapfile -t pgids < <(fallback_screen_runner_process_groups "$runner_script")
  [[ "${#pgids[@]}" -gt 0 ]] || return 0

  for pgid in "${pgids[@]}"; do
    [[ "$pgid" =~ ^[0-9]+$ ]] || continue
    log_line "WARN" "fallback.screen.stop execution_origin=$CODEX_EXECUTION_ORIGIN reason=$reason action=process_group_term pgid=$pgid runner_script=$(shell_quote "$runner_script")"
    kill -TERM -- "-$pgid" >/dev/null 2>&1 || true
  done

  sleep 1

  for pgid in "${pgids[@]}"; do
    [[ "$pgid" =~ ^[0-9]+$ ]] || continue
    if fallback_screen_process_group_exists "$pgid"; then
      log_line "WARN" "fallback.screen.stop execution_origin=$CODEX_EXECUTION_ORIGIN reason=$reason action=process_group_kill pgid=$pgid runner_script=$(shell_quote "$runner_script")"
      kill -KILL -- "-$pgid" >/dev/null 2>&1 || true
    fi
  done
}

adopt_completed_fallback_screen_result_on_signal() {
  local signal_name="$1"
  local screen_root="$CODEX_POSTMORTEM_DIR/$CYCLE_ID/screen"
  local exit_file="$screen_root/final-exit-code.txt"
  local child_exit raw_child_exit current_child_id current_child_status completed_count last_cycle_exit stop_reason

  [[ "$CODEX_EXECUTION_ORIGIN" == "primary" ]] || return 1
  [[ "$FALLBACK_SCREEN_WATCH_ACTIVE" == "1" ]] || return 1
  completed_fallback_screen_result_available || return 1

  raw_child_exit="$(tr -d '[:space:]' <"$exit_file")"
  child_exit="$(screen_fallback_exit_code_or_default "$raw_child_exit" "")"
  if [[ -z "$child_exit" ]]; then
    log_line "WARN" "signal.completed_fallback_result invalid_exit_code_artifact=1 signal=$signal_name session_name=${FALLBACK_SCREEN_SESSION_NAME:-none} exit_file=$(shell_quote "$exit_file") raw_exit=$(shell_quote "$raw_child_exit") default_exit=8"
    child_exit="8"
  fi

  FALLBACK_SCREEN_EXIT_CODE="$child_exit"
  FALLBACK_SCREEN_WATCH_ACTIVE="0"
  current_child_id="$(read_artifact_or_unknown "$screen_root/current-child-cycle-id.txt")"
  current_child_status="$(read_artifact_or_unknown "$screen_root/current-child-status.txt")"
  completed_count="$(read_artifact_or_unknown "$screen_root/completed-child-count.txt")"
  last_cycle_exit="$(read_artifact_or_unknown "$screen_root/last-cycle-exit-code.txt")"
  stop_reason="$(read_artifact_or_unknown "$screen_root/stop-reason.txt")"
  log_line "WARN" "signal.completed_fallback_result signal=$signal_name execution_origin=$CODEX_EXECUTION_ORIGIN session_name=${FALLBACK_SCREEN_SESSION_NAME:-none} final_exit=$child_exit current_child_id=$current_child_id current_child_status=$current_child_status completed_children=$completed_count last_cycle_exit=$last_cycle_exit stop_reason=$stop_reason"
  teardown_fallback_screen_session "completed_result_$signal_name"
  finish_cycle "$child_exit" FALLBACK_CHILD_COMPLETED_BEFORE_SIGNAL WARN "signal=$signal_name fallback_screen_session=${FALLBACK_SCREEN_SESSION_NAME:-none} fallback_trigger=${FALLBACK_SCREEN_TRIGGER:-none} transcript=${FALLBACK_SCREEN_TRANSCRIPT_PATH:-none}"
}

# Signals usually mean the human is trying to stop the visible loop. If a
# detached fallback screen is active, leaving it behind would create a ghost
# worker that keeps spending quota, so the visible wrapper owns cleanup.
teardown_fallback_screen_session() {
  local reason="${1:-manual_teardown}"
  local session_name="${FALLBACK_SCREEN_SESSION_NAME:-}"

  if [[ -z "$session_name" ]]; then
    return 0
  fi

  if [[ "$UPKEEPER_DRY_RUN" == "1" ]]; then
    log_line "WARN" "fallback.screen.stop execution_origin=$CODEX_EXECUTION_ORIGIN session_name=$session_name reason=$reason dry_run=1"
    return 0
  fi

  if screen_session_exists "$session_name"; then
    log_line "WARN" "fallback.screen.stop execution_origin=$CODEX_EXECUTION_ORIGIN session_name=$session_name reason=$reason action=screen_quit"
    screen -S "$session_name" -X quit >/dev/null 2>&1 || true
    sleep 1
    terminate_fallback_screen_process_groups "$reason"
    return 0
  fi

  log_line "WARN" "fallback.screen.stop execution_origin=$CODEX_EXECUTION_ORIGIN session_name=$session_name reason=$reason status=already_gone"
  terminate_fallback_screen_process_groups "$reason"
  return 0
}

handle_wrapper_signal() {
  local signal_name="$1"
  trap - INT TERM HUP

  log_line "WARN" "signal.received signal=$signal_name execution_origin=$CODEX_EXECUTION_ORIGIN fallback_screen_session=${FALLBACK_SCREEN_SESSION_NAME:-none} fallback_screen_watch_active=$FALLBACK_SCREEN_WATCH_ACTIVE"

  if [[ "$CODEX_EXECUTION_ORIGIN" == "primary" && -n "${FALLBACK_SCREEN_SESSION_NAME:-}" ]]; then
    adopt_completed_fallback_screen_result_on_signal "$signal_name" || true
    teardown_fallback_screen_session "signal_$signal_name"
  fi

  finish_cycle 130 "SIGNAL_${signal_name}" WARN "execution_origin=$CODEX_EXECUTION_ORIGIN fallback_screen_session=${FALLBACK_SCREEN_SESSION_NAME:-none} fallback_screen_watch_active=$FALLBACK_SCREEN_WATCH_ACTIVE"
}
