# Parent-loop control.
#
# A quota stop must break the shell loop that is repeatedly launching this
# script, not just this child process. Fallback children inherit the original
# parent PID so nested recovery can still stop the real outer loop.
direct_parent_details() {
  local ppid_now
  ppid_now="$(ps -o ppid= -p "$$" | tr -d ' ')"
  [[ -n "$ppid_now" ]] || return 1
  ps -p "$ppid_now" >/dev/null 2>&1 || return 1
  local parent_comm
  local parent_args
  parent_comm="$(ps -o comm= -p "$ppid_now" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  parent_args="$(ps -o args= -p "$ppid_now" | compact_process_args)"
  parent_args="$(truncate_process_args "$parent_args")"
  printf '%s\t%s\t%s\n' "$ppid_now" "$parent_comm" "$parent_args"
}

parent_shell_details() {
  if [[ -n "$CODEX_LOOP_PARENT_PID" ]]; then
    local target_pid target_comm target_args
    target_pid="$CODEX_LOOP_PARENT_PID"
    if ps -p "$target_pid" >/dev/null 2>&1; then
      target_comm="$(ps -o comm= -p "$target_pid" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      target_args="$(ps -o args= -p "$target_pid" | compact_process_args)"
      target_args="$(truncate_process_args "$target_args")"
    else
      target_comm="${CODEX_LOOP_PARENT_COMM:-unknown}"
      target_args="${CODEX_LOOP_PARENT_ARGS:-unknown}"
      target_args="$(truncate_process_args "$target_args")"
    fi
    printf '%s\t%s\t%s\t%s\n' "$target_pid" "$target_comm" "$target_args" "1"
    return 0
  fi

  local direct_details
  direct_details="$(direct_parent_details)" || return 1
  printf '%s\t%s\n' "$direct_details" "0"
}

parent_stop_skip_reason() {
  local parent_comm="$1"
  local parent_args="$2"
  local using_override="$3"

  if [[ "$CODEX_DISABLE_PARENT_STOP" == "1" ]]; then
    printf 'disabled_by_env'
    return 0
  fi

  # Explicit loop-parent overrides are only injected by Upkeeper-supervised
  # children. Trust those because nested fallback/postmortem workers must still
  # be able to stop the original loop controller.
  if [[ "${using_override:-0}" == "1" ]]; then
    return 1
  fi

  # A direct interactive terminal normally appears as parent_comm=bash with
  # parent_args=bash (or another bare shell name). Killing that PID can close the
  # operator's terminal, so treat it as a local one-shot invocation and let this
  # child exit instead.
  case "$parent_args" in
    ""|bash|-bash|/bin/bash|*/bash|sh|-sh|/bin/sh|*/sh|dash|-dash|zsh|-zsh|ksh|-ksh|fish|-fish)
      printf 'interactive_parent_shell'
      return 0
      ;;
  esac

  # Non-interactive launchers such as `bash -lc 'while ./Upkeeper.sh ...'` or
  # `bash -lc 'for ...; do ./Upkeeper.sh; ...'` are safe loop supervisors to
  # stop. Unknown shell commands are fail-closed so a quota guardrail cannot kill
  # an unrelated operator shell just because it is the direct parent.
  case "$parent_args" in
    *Upkeeper*|*upkeeper*|*'while '*|*'for '*|*'; do '*)
      return 1
      ;;
    *)
      printf 'unrecognized_parent_shell_command'
      return 0
      ;;
  esac
}

stop_parent_loop() {
  local details
  if ! details="$(parent_shell_details)"; then
    log_line "ERROR" "could not resolve parent shell details for stop"
    return 1
  fi

  local parent_pid parent_comm parent_args using_override
  IFS=$'\t' read -r parent_pid parent_comm parent_args using_override <<<"$details"

  case "$parent_comm" in
    bash|sh|dash|zsh|ksh|fish)
      ;;
    *)
      log_line "ERROR" "refusing to stop non-shell parent_pid=$parent_pid parent_comm=$parent_comm"
      return 1
      ;;
  esac

  if [[ "${#parent_args}" -gt 240 ]]; then
    parent_args="${parent_args:0:240}..."
  fi

  local skip_reason
  if skip_reason="$(parent_stop_skip_reason "$parent_comm" "$parent_args" "${using_override:-0}")"; then
    PARENT_LOOP_STOP_OUTCOME="skipped_$skip_reason"
    log_line "WARN" "parent loop stop skipped reason=$skip_reason execution_origin=$CODEX_EXECUTION_ORIGIN parent_pid=$parent_pid parent_comm=$parent_comm using_override=${using_override:-0} parent_args=$parent_args"
    return 0
  fi

  if ! kill -0 "$parent_pid" 2>/dev/null; then
    PARENT_LOOP_STOP_OUTCOME="already_exited"
    log_line "INFO" "loop parent already exited; parent_pid=$parent_pid parent_comm=$parent_comm using_override=${using_override:-0}"
    return 0
  fi

  PARENT_LOOP_STOP_OUTCOME="stopping"
  log_line "WARN" "quota guardrail tripped; parent_pid=$parent_pid parent_comm=$parent_comm using_override=${using_override:-0} parent_args=$parent_args"

  if [[ "$UPKEEPER_DRY_RUN" == "1" ]]; then
    PARENT_LOOP_STOP_OUTCOME="dry_run"
    log_line "INFO" "dry-run active; would send SIGTERM to parent_pid=$parent_pid"
    return 0
  fi

  if [[ "${using_override:-0}" != "1" ]]; then
    local ppid_now
    ppid_now="$(ps -o ppid= -p "$$" | tr -d ' ')"
    if [[ "$ppid_now" != "$parent_pid" ]]; then
      log_line "ERROR" "parent PID changed before stop; expected=$parent_pid actual=$ppid_now"
      return 1
    fi
  fi

  kill -TERM "$parent_pid"
  log_line "WARN" "sent SIGTERM to parent_pid=$parent_pid"

  local elapsed=0
  while (( elapsed < CODEX_LOOP_STOP_GRACE_SECONDS * 10 )); do
    if ! kill -0 "$parent_pid" 2>/dev/null; then
      PARENT_LOOP_STOP_OUTCOME="stopped_sigterm"
      log_line "INFO" "confirmed parent_pid=$parent_pid exited after SIGTERM"
      return 0
    fi
    sleep 0.1
    elapsed=$((elapsed + 1))
  done

  log_line "WARN" "parent_pid=$parent_pid still alive after ${CODEX_LOOP_STOP_GRACE_SECONDS}s; sending SIGKILL"
  kill -KILL "$parent_pid"
  sleep 0.2

  if kill -0 "$parent_pid" 2>/dev/null; then
    PARENT_LOOP_STOP_OUTCOME="sigkill_failed"
    log_line "ERROR" "parent_pid=$parent_pid still exists after SIGKILL"
    return 1
  fi

  PARENT_LOOP_STOP_OUTCOME="stopped_sigkill"
  log_line "INFO" "confirmed parent_pid=$parent_pid exited after SIGKILL"
  return 0
}
