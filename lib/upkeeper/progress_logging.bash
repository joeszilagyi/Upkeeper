ensure_log_writable_or_exit() {
  local phase="${1:-startup}"
  local marker line

  ensure_log_parent
  marker="upkeeper-log-probe-$CYCLE_ID-$CYCLE_RUN_HASH-$$"
  line="$(timestamp_now) [INFO] cycle=$CYCLE_ID run_hash=$CYCLE_RUN_HASH log.write_preflight phase=$phase marker=$marker"
  if ! append_log_line_secure "$line" "write_preflight"; then
    exit 3
  fi
}

die() {
  ensure_log_parent
  if ! log_line "ERROR" "$*"; then
    printf '%s [ERROR] cycle=%s %s\n' "$(terminal_timestamp_now)" "$CYCLE_ID" "$*" >&2
  fi
  stop_run_mark_heartbeat "die"
  finalize_wrapper_health_state "die"
  release_active_lock
  exit 3
}

emit_run_mark() {
  local phase="${1:-heartbeat}"
  log_line "INFO" "--MARK-- phase=$phase epoch=$(epoch_now_fraction) boot_id=$(system_boot_id) uptime_seconds=$(system_uptime_seconds)"
  if [[ -n "${WRAPPER_HEALTH_STATE_FILE:-}" && "${WRAPPER_HEALTH_STATE_FINALIZED:-0}" == "0" ]]; then
    write_wrapper_health_state "$phase" || log_line "WARN" "central_wrapper.health_state_update_failed phase=$phase state_file=$(shell_quote "$WRAPPER_HEALTH_STATE_FILE")"
  fi
}

stop_terminal_progress_heartbeat() {
  local reason="${1:-stop}"

  if [[ -n "${RUN_TERMINAL_PROGRESS_PID:-}" ]]; then
    kill "$RUN_TERMINAL_PROGRESS_PID" >/dev/null 2>&1 || true
    wait "$RUN_TERMINAL_PROGRESS_PID" 2>/dev/null || true
    RUN_TERMINAL_PROGRESS_PID=""
    log_line "INFO" "terminal_progress.stop reason=$reason"
  fi
}

start_terminal_progress_heartbeat() {
  local label="$1"
  local transcript_file="$2"
  local started_epoch="$3"
  local target="$4"
  local interval

  terminal_wants_full_output && return 0
  terminal_suppresses_heartbeat && return 0
  interval="$(sanitize_nonnegative_integer "${CODEX_TERMINAL_PROGRESS_INTERVAL_SECONDS:-$CODEX_MARK_INTERVAL_SECONDS}" "$CODEX_MARK_INTERVAL_SECONDS")"
  if [[ "$interval" -le 0 ]]; then
    return 0
  fi

  stop_terminal_progress_heartbeat "restart"
  (
    progress_sleep_pid=""
    trap '[[ -n "$progress_sleep_pid" ]] && kill "$progress_sleep_pid" >/dev/null 2>&1 || true; exit 0' INT TERM HUP
    while true; do
      sleep "$interval" &
      progress_sleep_pid="$!"
      wait "$progress_sleep_pid" || exit 0
      progress_sleep_pid=""

      now_epoch="$(date '+%s')"
      if [[ "$started_epoch" =~ ^[0-9]+$ && "$now_epoch" =~ ^[0-9]+$ ]]; then
        elapsed_seconds=$((now_epoch - started_epoch))
      else
        elapsed_seconds="unknown"
      fi
      if [[ -f "$transcript_file" ]]; then
        transcript_lines="$(wc -l <"$transcript_file" 2>/dev/null || printf 'unknown')"
        transcript_bytes="$(file_size_bytes "$transcript_file")"
        transcript_updated="$(date -r "$transcript_file" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf 'unknown')"
      else
        transcript_lines="missing"
        transcript_bytes="missing"
        transcript_updated="missing"
      fi
      printf '%s [INFO] Upkeeper: wait plane=llm waiting_for=codex_backend_review phase=%s target=%s elapsed=%ss transcript_lines=%s transcript_bytes=%s last_update=%s\n' \
        "$(terminal_timestamp_now)" \
        "$label" \
        "${target:-unknown}" \
        "$elapsed_seconds" \
        "$transcript_lines" \
        "$transcript_bytes" \
        "$transcript_updated" >&2
    done
  ) &
  RUN_TERMINAL_PROGRESS_PID="$!"
  log_line "INFO" "terminal_progress.start plane=llm waiting_for=codex_backend_review pid=$RUN_TERMINAL_PROGRESS_PID label=$label interval_seconds=$interval target=$(shell_quote "$(upkeeper_redact_model_text "${target:-unknown}" 240)") transcript=$(shell_quote "$(upkeeper_path_hmac "$transcript_file")") path_redacted=1"
}

start_run_mark_heartbeat() {
  local interval="$CODEX_MARK_INTERVAL_SECONDS"
  if [[ "$interval" -le 0 ]]; then
    return 0
  fi
  emit_run_mark "start"
  RUN_MARK_HEARTBEAT_STARTED="1"
  (
    mark_sleep_pid=""
    trap '[[ -n "$mark_sleep_pid" ]] && kill "$mark_sleep_pid" >/dev/null 2>&1 || true; exit 0' INT TERM HUP
    while true; do
      sleep "$interval" &
      mark_sleep_pid="$!"
      wait "$mark_sleep_pid" || exit 0
      mark_sleep_pid=""
      emit_run_mark "heartbeat" >/dev/null
    done
  ) >/dev/null 2>&1 &
  RUN_MARK_HEARTBEAT_PID="$!"
  log_line "INFO" "mark_heartbeat.start pid=$RUN_MARK_HEARTBEAT_PID interval_seconds=$interval"
}

stop_run_mark_heartbeat() {
  local reason="${1:-stop}"
  if [[ "${RUN_MARK_HEARTBEAT_STARTED:-0}" != "1" ]]; then
    return 0
  fi
  if [[ "${RUN_MARK_HEARTBEAT_STOPPED:-0}" == "1" ]]; then
    return 0
  fi
  RUN_MARK_HEARTBEAT_STOPPED="1"
  if [[ -n "${RUN_MARK_HEARTBEAT_PID:-}" ]]; then
    kill "$RUN_MARK_HEARTBEAT_PID" >/dev/null 2>&1 || true
    wait "$RUN_MARK_HEARTBEAT_PID" 2>/dev/null || true
    RUN_MARK_HEARTBEAT_PID=""
    log_line "INFO" "mark_heartbeat.stop reason=$reason"
  fi
  emit_run_mark "finish"
}
