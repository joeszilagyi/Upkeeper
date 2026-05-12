# Detached screen fallback supervision.
#
# This module owns the generated `screen` runner used when the primary Codex
# path needs a stronger fallback child that can outlive the visible terminal. It
# writes and reads small state artifacts under the current cycle's postmortem
# directory; callers must treat those artifacts as operational evidence rather
# than trusted shell input.
screen_fallback_exit_code_or_default() {
  local raw_exit="$1"
  local fallback="${2-8}"

  if [[ "$raw_exit" =~ ^[0-9]+$ ]]; then
    raw_exit="${raw_exit#"${raw_exit%%[!0]*}"}"
    raw_exit="${raw_exit:-0}"
    case "$raw_exit" in
      [0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])
        printf '%s' "$raw_exit"
        return 0
        ;;
    esac
  fi

  printf '%s' "$fallback"
}

screen_session_exists() {
  local session_name="$1"
  screen -list | grep -F ".$session_name" >/dev/null 2>&1
}

launch_screen_fallback_loop() {
  local trigger="$1"
  shift
  local detail_text="${*:-none}"
  local loop_details loop_parent_pid loop_parent_comm loop_parent_args using_override
  if ! loop_details="$(parent_shell_details)"; then
    log_line "ERROR" "fallback.screen.start trigger=$trigger failed_to_resolve_loop_parent=1"
    return 8
  fi
  IFS=$'\t' read -r loop_parent_pid loop_parent_comm loop_parent_args using_override <<<"$loop_details"

  local screen_root session_name runner_script transcript_file exit_file done_file last_cycle_exit_file
  local child_id_file child_started_file child_status_file heartbeat_file completed_count_file stop_reason_file
  local prompt_arg_snippet=""
  local self_q model_q effort_q mode_q root_q screen_root_q transcript_q poll_q trigger_q
  local loop_parent_pid_q loop_parent_comm_q loop_parent_args_q primary_model_q prompt_file_q inline_prompt_q
  local continuous_q max_children_q max_seconds_q
  local review_module review_module_q
  local fallback_chain_token
  local contract_path_q

  screen_root="$CODEX_POSTMORTEM_DIR/$CYCLE_ID/screen"
  session_name="upkeeper-${CYCLE_ID//[^A-Za-z0-9]/_}"
  runner_script="$screen_root/run-screen-fallback.sh"
  transcript_file="$screen_root/transcript.log"
  exit_file="$screen_root/final-exit-code.txt"
  done_file="$screen_root/done.txt"
  last_cycle_exit_file="$screen_root/last-cycle-exit-code.txt"
  child_id_file="$screen_root/current-child-cycle-id.txt"
  child_started_file="$screen_root/current-child-started-at.txt"
  child_status_file="$screen_root/current-child-status.txt"
  heartbeat_file="$screen_root/heartbeat.txt"
  completed_count_file="$screen_root/completed-child-count.txt"
  stop_reason_file="$screen_root/stop-reason.txt"

  FALLBACK_SCREEN_SESSION_NAME="$session_name"
  FALLBACK_SCREEN_TRANSCRIPT_PATH="$transcript_file"
  FALLBACK_SCREEN_EXIT_CODE=""
  FALLBACK_SCREEN_TRIGGER="$trigger"

  mkdir -p "$screen_root"

  printf -v root_q '%q' "$ROOT_DIR"
  printf -v self_q '%q' "$SELF_INVOKE_PATH"
  printf -v screen_root_q '%q' "$screen_root"
  printf -v transcript_q '%q' "$transcript_file"
  printf -v poll_q '%q' "$CODEX_FALLBACK_SCREEN_POLL_SECONDS"
  printf -v continuous_q '%q' "$CODEX_FALLBACK_SCREEN_CONTINUOUS"
  printf -v max_children_q '%q' "$CODEX_FALLBACK_SCREEN_MAX_CHILDREN"
  printf -v max_seconds_q '%q' "$CODEX_FALLBACK_SCREEN_MAX_SECONDS"
  printf -v model_q '%q' "$CODEX_FALLBACK_MODEL"
  printf -v effort_q '%q' "$CODEX_FALLBACK_REASONING_EFFORT"
  printf -v mode_q '%q' "$CODEX_FALLBACK_MODE"
  printf -v trigger_q '%q' "$trigger"
  printf -v loop_parent_pid_q '%q' "$loop_parent_pid"
  printf -v loop_parent_comm_q '%q' "$loop_parent_comm"
  printf -v loop_parent_args_q '%q' "$loop_parent_args"
  printf -v primary_model_q '%q' "$CODEX_MODEL"
  printf -v contract_path_q '%q' "${CODEX_FALLBACK_CONTRACT_PATH:-}"
  fallback_chain_token="$(generate_fallback_chain_token)"

  if [[ -n "$PROMPT_FILE" ]]; then
    printf -v prompt_file_q '%q' "$PROMPT_FILE"
    prompt_arg_snippet="--prompt-file $prompt_file_q"
  elif [[ -n "$INLINE_PROMPT" ]]; then
    printf -v inline_prompt_q '%q' "$INLINE_PROMPT"
    prompt_arg_snippet="--prompt $inline_prompt_q"
  fi
  for review_module in "${CODEX_REVIEW_MODULES[@]}"; do
    printf -v review_module_q '%q' "$review_module"
    prompt_arg_snippet="${prompt_arg_snippet:+$prompt_arg_snippet }--review-module=$review_module_q"
  done
  if [[ -n "$CODEX_TARGET_FILE" ]]; then
    local target_file_q
    printf -v target_file_q '%q' "$CODEX_TARGET_FILE"
    prompt_arg_snippet="${prompt_arg_snippet:+$prompt_arg_snippet }--target-file=$target_file_q"
  fi
  if [[ -n "$CODEX_PROMPT_PASS" ]]; then
    local prompt_pass_q
    printf -v prompt_pass_q '%q' "$CODEX_PROMPT_PASS"
    prompt_arg_snippet="${prompt_arg_snippet:+$prompt_arg_snippet }--prompt-pass=$prompt_pass_q"
  fi
  if upkeeper_bug_report_only_enabled; then
    prompt_arg_snippet="${prompt_arg_snippet:+$prompt_arg_snippet }--bug-report-only"
  fi

  cat >"$runner_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Generated screen runner. It may outlive the launching terminal, so it writes
# small state files that the parent can poll and later include in postmortems.
ROOT_DIR=$root_q
SELF_INVOKE_PATH=$self_q
SCREEN_ROOT=$screen_root_q
TRANSCRIPT_FILE=$transcript_q

state_file() {
  printf '%s/%s' "\$SCREEN_ROOT" "\$1"
}

write_state() {
  local name="\$1"
  local value="\$2"
  printf '%s\n' "\$value" > "\$(state_file "\$name")"
}

write_state_datetime() {
  local name="\$1"
  date '+%Y-%m-%dT%H:%M:%S%z' > "\$(state_file "\$name")"
}

fallback_parent_process_start() {
  local pid="\$1"
  local stat_text after_comm
  if [[ -r "/proc/\$pid/stat" ]]; then
    IFS= read -r stat_text <"/proc/\$pid/stat" || true
    after_comm="\${stat_text##*) }"
    set -- \$after_comm
    if [[ \$# -ge 20 && -n "\${20:-}" ]]; then
      printf 'proc_start_ticks=%s' "\${20}"
      return 0
    fi
  fi
  printf 'proc_start_ticks=unknown'
}

cd "\$ROOT_DIR"
continuous=$continuous_q
max_children=$max_children_q
max_seconds=$max_seconds_q
case "\$max_children" in ''|*[!0-9]*) max_children=1 ;; esac
case "\$max_seconds" in ''|*[!0-9]*) max_seconds=0 ;; esac
if [[ "\$max_children" -lt 1 ]]; then
  max_children=1
fi
if [[ "\$continuous" != "1" ]]; then
  max_children=1
fi

# Single-shot is the safe default. Continuous fallback must be explicitly opted
# in because repeated recovery children can spend quota while an incident is in
# progress.
runner_started_epoch=\$(date '+%s')
child_count=0
rc=0
stop_reason=unknown
heartbeat_pid=""
heartbeat_interval=$poll_q
case "\$heartbeat_interval" in ''|*[!0-9]*) heartbeat_interval=30 ;; esac
heartbeat_interval=\$((heartbeat_interval / 2))
if [[ "\$heartbeat_interval" -lt 5 ]]; then
  heartbeat_interval=5
fi
if [[ "\$heartbeat_interval" -gt 30 ]]; then
  heartbeat_interval=30
fi
write_state 'completed-child-count.txt' 0
write_state_datetime 'heartbeat.txt'

stop_child_heartbeat() {
  if [[ -n "\${heartbeat_pid:-}" ]]; then
    kill "\$heartbeat_pid" >/dev/null 2>&1 || true
    wait "\$heartbeat_pid" >/dev/null 2>&1 || true
    heartbeat_pid=""
  fi
}

cleanup() {
  stop_child_heartbeat
}
trap cleanup EXIT

start_child_heartbeat() {
  stop_child_heartbeat
  (
    while true; do
      write_state_datetime 'heartbeat.txt'
      sleep "\$heartbeat_interval"
    done
  ) &
  heartbeat_pid=\$!
}

mark_interrupted() {
  # Make operator interrupts visible as data, not just a missing screen session.
  stop_child_heartbeat
  write_state 'current-child-status.txt' interrupted
  write_state_datetime 'heartbeat.txt'
  write_state 'stop-reason.txt' interrupted
  write_state 'last-cycle-exit-code.txt' 130
  write_state 'final-exit-code.txt' 130
  write_state_datetime 'done.txt'
  exit 130
}
trap mark_interrupted INT TERM HUP

while true; do
  child_count=\$((child_count + 1))
  child_cycle_id="\$(date '+%Y%m%dT%H%M%S%z')-screen-child-\$child_count"
  write_state 'current-child-cycle-id.txt' "\$child_cycle_id"
  write_state_datetime 'current-child-started-at.txt'
  write_state 'current-child-status.txt' running
  write_state_datetime 'heartbeat.txt'
  start_child_heartbeat
  set +e
  fallback_parent_pid="\$\$"
  fallback_parent_start="\$(fallback_parent_process_start "\$fallback_parent_pid")"
  CODEX_MODEL=$model_q \
  CODEX_REASONING_EFFORT=$effort_q \
  CODEX_MODE=$mode_q \
  CODEX_FALLBACK_ENABLED=0 \
  CODEX_FALLBACK_CHAIN_ACTIVE=1 \
  CODEX_FALLBACK_PARENT_PID="\$fallback_parent_pid" \
  CODEX_FALLBACK_PARENT_START="\$fallback_parent_start" \
  CODEX_FALLBACK_CHAIN_TOKEN_FD=9 \
  CODEX_FALLBACK_SCREEN_CONTINUOUS=$continuous_q \
  CODEX_FALLBACK_SCREEN_MAX_CHILDREN=$max_children_q \
  CODEX_FALLBACK_SCREEN_MAX_SECONDS=$max_seconds_q \
  CODEX_ATTEMPT_ROLE=fallback \
  CODEX_PRIMARY_MODEL_CONTEXT=$primary_model_q \
  CODEX_FALLBACK_TRIGGER=$trigger_q \
  CODEX_PARENT_CYCLE_ID=$(shell_quote "$CYCLE_ID") \
  CODEX_FALLBACK_CONTRACT_PATH=$contract_path_q \
  CODEX_SCREEN_FALLBACK_CHILD_ID="\$child_cycle_id" \
  CODEX_LOOP_PARENT_PID=$loop_parent_pid_q \
  CODEX_LOOP_PARENT_COMM=$loop_parent_comm_q \
  CODEX_LOOP_PARENT_ARGS=$loop_parent_args_q \
  CODEX_POSTMORTEM_ENABLED=0 \
  CODEX_DISABLE_PARENT_STOP=1 \
  CODEX_GUARDRAIL_STOP_EXIT_CODE=9 \
  CODEX_EXECUTION_ORIGIN=screen \
  "\$SELF_INVOKE_PATH" $prompt_arg_snippet >>"\$TRANSCRIPT_FILE" 2>&1
  rc=\$?
  stop_child_heartbeat
  set -e
  write_state 'last-cycle-exit-code.txt' "\$rc"
  write_state 'completed-child-count.txt' "\$child_count"
  write_state 'current-child-status.txt' finished
  write_state_datetime 'heartbeat.txt'
  if [[ "\$rc" -ne 0 ]]; then
    stop_reason=child_exit_nonzero
    break
  fi
  if [[ "\$child_count" -ge "\$max_children" ]]; then
    stop_reason=child_limit_reached
    break
  fi
  if [[ "\$max_seconds" -gt 0 ]]; then
    now_epoch=\$(date '+%s')
    if (( now_epoch - runner_started_epoch >= max_seconds )); then
      stop_reason=wall_clock_limit_reached
      break
    fi
  fi
  sleep $poll_q
done
write_state 'stop-reason.txt' "\$stop_reason"
write_state 'final-exit-code.txt' "\$rc"
write_state_datetime 'done.txt'
exit "\${rc:-0}"
EOF
  chmod +x "$runner_script"

  if [[ "$UPKEEPER_DRY_RUN" == "1" ]]; then
    log_line "INFO" "fallback.screen.start execution_origin=screen trigger=$trigger session_name=$session_name dry_run=1 detail=\"$detail_text\""
    cat >"$transcript_file" <<EOF
dry-run screen fallback transcript for cycle $CYCLE_ID trigger $trigger
EOF
    printf '0\n' >"$last_cycle_exit_file"
    printf 'dry-run-child\n' >"$child_id_file"
    date '+%Y-%m-%dT%H:%M:%S%z' >"$child_started_file"
    printf 'finished\n' >"$child_status_file"
    date '+%Y-%m-%dT%H:%M:%S%z' >"$heartbeat_file"
    printf '1\n' >"$completed_count_file"
    printf 'dry_run\n' >"$stop_reason_file"
    printf '0\n' >"$exit_file"
    date '+%Y-%m-%dT%H:%M:%S%z' >"$done_file"
    return 0
  fi

  local launch_started_at launch_returned_at launch_rc launch_verified launch_probe_attempts
  launch_started_at="$(timestamp_now)"
  log_line "INFO" "fallback.screen.launch execution_origin=screen trigger=$trigger session_name=$session_name command=screen_-dmS launch_started_at=$launch_started_at"
  set +e
  CODEX_FALLBACK_CHAIN_TOKEN_FD=9 \
  9<<<"$fallback_chain_token" \
  screen -dmS "$session_name" bash "$runner_script"
  launch_rc=$?
  set -e
  launch_returned_at="$(timestamp_now)"
  if [[ "$launch_rc" -ne 0 ]]; then
    log_line "ERROR" "fallback.screen.launch_return execution_origin=screen trigger=$trigger session_name=$session_name launch_failed=1 launch_rc=$launch_rc launch_started_at=$launch_started_at launch_returned_at=$launch_returned_at"
    return 8
  fi
  log_line "INFO" "fallback.screen.launch_return execution_origin=screen trigger=$trigger session_name=$session_name launch_rc=$launch_rc launch_started_at=$launch_started_at launch_returned_at=$launch_returned_at"
  launch_verified=0
  launch_probe_attempts=0
  while (( launch_probe_attempts < 50 )); do
    if screen_session_exists "$session_name" || [[ -f "$heartbeat_file" || -f "$done_file" ]]; then
      launch_verified=1
      break
    fi
    sleep 0.1
    launch_probe_attempts=$((launch_probe_attempts + 1))
  done
  if [[ "$launch_verified" != "1" ]]; then
    log_line "ERROR" "fallback.screen.launch_verify execution_origin=screen trigger=$trigger session_name=$session_name launch_unverified=1 launch_rc=$launch_rc heartbeat_missing=1 done_file_missing=1 probe_attempts=$launch_probe_attempts"
    return 8
  fi
  log_line "INFO" "fallback.screen.launch_verify execution_origin=screen trigger=$trigger session_name=$session_name launch_verified=1 probe_attempts=$launch_probe_attempts"
  log_line "INFO" "fallback.screen.start execution_origin=screen trigger=$trigger session_name=$session_name detail=\"$detail_text\" transcript=$transcript_file poll_seconds=$CODEX_FALLBACK_SCREEN_POLL_SECONDS continuous=$CODEX_FALLBACK_SCREEN_CONTINUOUS max_children=$CODEX_FALLBACK_SCREEN_MAX_CHILDREN max_seconds=$CODEX_FALLBACK_SCREEN_MAX_SECONDS"
  return 0
}

screen_fallback_interruptible_poll_sleep() {
  local session_name="$1"
  local done_file="$2"
  local requested_seconds="$3"
  local remaining

  remaining="$(sanitize_nonnegative_integer "$requested_seconds" 60)"
  if [[ "$remaining" -lt 1 ]]; then
    remaining=1
  fi

  while (( remaining > 0 )); do
    [[ -f "$done_file" ]] && return 0
    screen_session_exists "$session_name" || return 0
    sleep 1
    remaining=$((remaining - 1))
  done
}

wait_for_screen_fallback_loop() {
  local trigger="$1"
  local session_name="$2"
  local exit_file="$3"
  local done_file="$4"
  local child_exit="" raw_child_exit=""
  local screen_root current_child_id current_child_status heartbeat completed_count last_cycle_exit stop_reason
  local status_file exit_file_present=0

  screen_root="$(dirname "$exit_file")"
  status_file="$screen_root/current-child-status.txt"

  FALLBACK_SCREEN_WATCH_ACTIVE="1"
  while true; do
    if [[ -f "$done_file" ]]; then
      break
    fi
    if screen_session_exists "$session_name"; then
      current_child_id="$(read_artifact_or_unknown "$screen_root/current-child-cycle-id.txt")"
      current_child_status="$(read_artifact_or_unknown "$status_file")"
      heartbeat="$(read_artifact_or_unknown "$screen_root/heartbeat.txt")"
      completed_count="$(read_artifact_or_unknown "$screen_root/completed-child-count.txt")"
      log_line "INFO" "fallback.screen.wait execution_origin=screen trigger=$trigger session_name=$session_name status=running current_child_id=$current_child_id current_child_status=$current_child_status completed_children=$completed_count heartbeat=$heartbeat next_poll_seconds=$CODEX_FALLBACK_SCREEN_POLL_SECONDS"
      screen_fallback_interruptible_poll_sleep "$session_name" "$done_file" "$CODEX_FALLBACK_SCREEN_POLL_SECONDS"
      continue
    fi
    current_child_id="$(read_artifact_or_unknown "$screen_root/current-child-cycle-id.txt")"
    current_child_status="$(read_artifact_or_unknown "$status_file")"
    heartbeat="$(read_artifact_or_unknown "$screen_root/heartbeat.txt")"
    completed_count="$(read_artifact_or_unknown "$screen_root/completed-child-count.txt")"
    last_cycle_exit="$(read_artifact_or_unknown "$screen_root/last-cycle-exit-code.txt")"
    stop_reason="$(read_artifact_or_unknown "$screen_root/stop-reason.txt")"
    local missing_status="missing_session"
    if [[ "$completed_count" =~ ^[0-9]+$ && "$completed_count" -gt 0 && "$last_cycle_exit" == "0" ]]; then
      missing_status="fallback_interrupted_after_successful_cycles"
    fi
    if [[ "$current_child_status" == "running" ]]; then
      printf 'interrupted\n' >"$status_file"
      current_child_status="interrupted"
    fi
    log_line "WARN" "fallback.screen.wait execution_origin=screen trigger=$trigger session_name=$session_name status=$missing_status done_file_missing=1 current_child_id=$current_child_id current_child_status=$current_child_status completed_children=$completed_count last_cycle_exit=$last_cycle_exit stop_reason=$stop_reason heartbeat=$heartbeat"
    break
  done
  FALLBACK_SCREEN_WATCH_ACTIVE="0"

  teardown_fallback_screen_session "wait_complete_$trigger"

  if [[ -f "$exit_file" ]]; then
    exit_file_present=1
    raw_child_exit="$(tr -d '[:space:]' <"$exit_file")"
    child_exit="$(screen_fallback_exit_code_or_default "$raw_child_exit" "")"
  fi
  if [[ -z "$child_exit" ]]; then
    if [[ "$exit_file_present" == "1" ]]; then
      log_line "WARN" "fallback.screen.finish invalid_exit_code_artifact=1 trigger=$trigger session_name=$session_name exit_file=$(shell_quote "$exit_file") raw_exit=$(shell_quote "$raw_child_exit") default_exit=8"
    fi
    child_exit="8"
  fi

  FALLBACK_SCREEN_EXIT_CODE="$child_exit"
  current_child_id="$(read_artifact_or_unknown "$screen_root/current-child-cycle-id.txt")"
  current_child_status="$(read_artifact_or_unknown "$status_file")"
  completed_count="$(read_artifact_or_unknown "$screen_root/completed-child-count.txt")"
  last_cycle_exit="$(read_artifact_or_unknown "$screen_root/last-cycle-exit-code.txt")"
  stop_reason="$(read_artifact_or_unknown "$screen_root/stop-reason.txt")"
  log_line "INFO" "fallback.screen.finish execution_origin=screen trigger=$trigger session_name=$session_name final_exit=$child_exit completed_children=$completed_count current_child_id=$current_child_id current_child_status=$current_child_status last_cycle_exit=$last_cycle_exit stop_reason=$stop_reason transcript=${FALLBACK_SCREEN_TRANSCRIPT_PATH:-none}"
  return 0
}
