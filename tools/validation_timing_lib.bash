#!/usr/bin/env bash

# Shared timing and bounded-check helpers for tools/validate_upkeeper.sh.
# The caller owns shell strictness and the final EXIT trap.

VALIDATION_TIMING_INITIALIZED="0"
VALIDATION_TIMING_FILE=""
VALIDATION_TIMING_MODE="unknown"
VALIDATION_TIMING_PROFILE="0"
VALIDATION_TIMING_GIT_HEAD="unknown"
VALIDATION_TIMING_GIT_TREE="unknown"
VALIDATION_TIMING_GIT_DIRTY="unknown"
VALIDATION_TIMING_ENVIRONMENT="local"
VALIDATION_TIMING_RUN_ID=""
VALIDATION_TIMING_SUMMARY_ROWS=()

validation_timing_now_us() {
  local now="${EPOCHREALTIME:-}"
  if [[ -n "$now" ]]; then
    printf '%s\n' "${now/./}"
    return 0
  fi
  date +%s%6N
}

validation_timing_json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

validation_timing_command_display() {
  local arg rendered=""
  for arg in "$@"; do
    printf -v arg '%q' "$arg"
    rendered+="${rendered:+ }$arg"
  done
  printf '%s' "$rendered"
}

validation_timing_initialize() {
  local mode="$1"
  local root_dir="$2"
  local requested_file="${3:-}"
  local profile="${4:-0}"
  local short_head timing_dir

  VALIDATION_TIMING_MODE="$mode"
  VALIDATION_TIMING_PROFILE="$profile"
  VALIDATION_TIMING_GIT_HEAD="$(git -C "$root_dir" rev-parse HEAD 2>/dev/null || printf unknown)"
  VALIDATION_TIMING_GIT_TREE="$(git -C "$root_dir" rev-parse 'HEAD^{tree}' 2>/dev/null || printf unknown)"
  if git -C "$root_dir" diff --quiet --ignore-submodules -- 2>/dev/null && \
      git -C "$root_dir" diff --cached --quiet --ignore-submodules -- 2>/dev/null && \
      [[ -z "$(git -C "$root_dir" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
    VALIDATION_TIMING_GIT_DIRTY="false"
  else
    VALIDATION_TIMING_GIT_DIRTY="true"
  fi
  if [[ -n "${CI:-}" ]]; then
    VALIDATION_TIMING_ENVIRONMENT="ci"
  fi
  VALIDATION_TIMING_RUN_ID="${GITHUB_RUN_ID:-local}-$$"

  if [[ -n "$requested_file" ]]; then
    VALIDATION_TIMING_FILE="$requested_file"
  else
    short_head="${VALIDATION_TIMING_GIT_HEAD:0:12}"
    timing_dir="$root_dir/runtime/validation-timing"
    VALIDATION_TIMING_FILE="$timing_dir/${mode}-${short_head}-$$.jsonl"
  fi
  mkdir -p "$(dirname -- "$VALIDATION_TIMING_FILE")"
  (umask 077; : >"$VALIDATION_TIMING_FILE")
  VALIDATION_TIMING_SUMMARY_ROWS=()
  VALIDATION_TIMING_INITIALIZED="1"
  printf 'validate_upkeeper: timing artifact=%s\n' "$VALIDATION_TIMING_FILE"
}

validation_timing_record() {
  local check_name="$1"
  local command_text="$2"
  local status="$3"
  local exit_code="$4"
  local duration_ms="$5"
  local timeout_seconds="$6"
  local cleanup="$7"
  local reason="${8:-}"
  local escaped_mode escaped_head escaped_tree escaped_check escaped_command
  local escaped_status escaped_cleanup escaped_reason escaped_environment escaped_run_id

  [[ "$VALIDATION_TIMING_INITIALIZED" == "1" ]] || return 0
  escaped_mode="$(validation_timing_json_escape "$VALIDATION_TIMING_MODE")"
  escaped_head="$(validation_timing_json_escape "$VALIDATION_TIMING_GIT_HEAD")"
  escaped_tree="$(validation_timing_json_escape "$VALIDATION_TIMING_GIT_TREE")"
  escaped_check="$(validation_timing_json_escape "$check_name")"
  escaped_command="$(validation_timing_json_escape "$command_text")"
  escaped_status="$(validation_timing_json_escape "$status")"
  escaped_cleanup="$(validation_timing_json_escape "$cleanup")"
  escaped_reason="$(validation_timing_json_escape "$reason")"
  escaped_environment="$(validation_timing_json_escape "$VALIDATION_TIMING_ENVIRONMENT")"
  escaped_run_id="$(validation_timing_json_escape "$VALIDATION_TIMING_RUN_ID")"

  printf '{"schema":"upkeeper.validation-timing.v1","run_id":"%s","environment":"%s","mode":"%s","git_head":"%s","git_tree":"%s","git_dirty":%s,"check":"%s","command":"%s","status":"%s","exit_code":%d,"duration_ms":%d,"timeout_seconds":%d,"cleanup":"%s","reason":"%s"}\n' \
    "$escaped_run_id" "$escaped_environment" "$escaped_mode" "$escaped_head" \
    "$escaped_tree" "$VALIDATION_TIMING_GIT_DIRTY" "$escaped_check" \
    "$escaped_command" "$escaped_status" "$exit_code" "$duration_ms" \
    "$timeout_seconds" "$escaped_cleanup" "$escaped_reason" \
    >>"$VALIDATION_TIMING_FILE"
  if [[ "$check_name" != "__run__" ]]; then
    VALIDATION_TIMING_SUMMARY_ROWS+=("$duration_ms"$'\t'"$check_name"$'\t'"$status")
  fi
}

validation_timing_descendant_pids() {
  local root_pid="$1"
  local table parent child found
  local -a frontier=("$root_pid")
  local -a descendants=()

  table="$(ps -eo pid=,ppid= 2>/dev/null || true)"
  while [[ "${#frontier[@]}" -gt 0 ]]; do
    parent="${frontier[0]}"
    frontier=("${frontier[@]:1}")
    while read -r child found; do
      [[ -n "$child" && "$found" == "$parent" ]] || continue
      descendants+=("$child")
      frontier+=("$child")
    done <<<"$table"
  done
  printf '%s\n' "${descendants[@]}"
}

validation_timing_terminate_process_tree() {
  local root_pid="$1"
  local pid index
  local -a descendants=()

  mapfile -t descendants < <(validation_timing_descendant_pids "$root_pid")
  for ((index=${#descendants[@]} - 1; index >= 0; index--)); do
    pid="${descendants[$index]}"
    [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
  done
  kill -TERM "$root_pid" 2>/dev/null || true
  sleep 1
  for ((index=${#descendants[@]} - 1; index >= 0; index--)); do
    pid="${descendants[$index]}"
    [[ -n "$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
  done
  kill -KILL "$root_pid" 2>/dev/null || true
}

validation_run_check() {
  local name="$1"
  local timeout_seconds="$2"
  shift 2
  local start_us end_us duration_us duration_ms deadline_us now_us
  local pid rc status cleanup="none" reason="" command_text

  command_text="$(validation_timing_command_display "$@")"
  start_us="$(validation_timing_now_us)"
  (
    trap - EXIT
    "$@"
  ) &
  pid=$!

  if [[ "$timeout_seconds" =~ ^[0-9]+$ && "$timeout_seconds" -gt 0 ]]; then
    deadline_us=$((start_us + timeout_seconds * 1000000))
    while kill -0 "$pid" 2>/dev/null; do
      now_us="$(validation_timing_now_us)"
      if ((now_us >= deadline_us)); then
        cleanup="process_tree_term_kill"
        reason="timeout"
        validation_timing_terminate_process_tree "$pid"
        wait "$pid" 2>/dev/null || true
        rc=124
        break
      fi
      sleep 0.1
    done
  fi

  if [[ -z "${rc+x}" ]]; then
    if wait "$pid"; then
      rc=0
    else
      rc=$?
    fi
  fi
  end_us="$(validation_timing_now_us)"
  duration_us=$((end_us - start_us))
  duration_ms=$((duration_us / 1000))

  if [[ "$rc" -eq 0 ]]; then
    status="pass"
  elif [[ "$rc" -eq 124 ]]; then
    status="timeout"
  else
    status="fail"
  fi
  validation_timing_record "$name" "$command_text" "$status" "$rc" \
    "$duration_ms" "$timeout_seconds" "$cleanup" "$reason"

  if [[ "$VALIDATION_TIMING_PROFILE" == "1" ]]; then
    printf 'validate_upkeeper: timing check=%s status=%s elapsed=%d.%03ds timeout=%ss cleanup=%s\n' \
      "$name" "$status" "$((duration_ms / 1000))" "$((duration_ms % 1000))" \
      "$timeout_seconds" "$cleanup"
  fi
  if [[ "$status" == "timeout" ]]; then
    printf 'validate_upkeeper: ERROR: check %s exceeded %ss timeout; command=%s cleanup=%s artifact=%s\n' \
      "$name" "$timeout_seconds" "$command_text" "$cleanup" "$VALIDATION_TIMING_FILE" >&2
  fi
  return "$rc"
}

validation_timing_record_skip() {
  local name="$1"
  local reason="$2"
  shift 2
  validation_timing_record "$name" "$(validation_timing_command_display "$@")" \
    "skipped" 0 0 0 "none" "$reason"
  if [[ "$VALIDATION_TIMING_PROFILE" == "1" ]]; then
    printf 'validate_upkeeper: timing check=%s status=skipped elapsed=0.000s timeout=0s cleanup=none reason=%s\n' \
      "$name" "$reason"
  fi
}

validation_timing_finish() {
  local exit_code="$1"
  local status="pass"
  [[ "$exit_code" -eq 0 ]] || status="fail"
  validation_timing_record "__run__" "tools/validate_upkeeper.sh" "$status" \
    "$exit_code" 0 0 "none" "run_exit"
}

validation_timing_print_summary() {
  local limit="${1:-10}"
  local row duration_ms name status count=0
  [[ "$VALIDATION_TIMING_INITIALIZED" == "1" ]] || return 0
  [[ "${#VALIDATION_TIMING_SUMMARY_ROWS[@]}" -gt 0 ]] || return 0

  printf 'validate_upkeeper: slowest checks (mode=%s, artifact=%s)\n' \
    "$VALIDATION_TIMING_MODE" "$VALIDATION_TIMING_FILE"
  while IFS=$'\t' read -r duration_ms name status; do
    printf 'validate_upkeeper: slow check=%s status=%s elapsed=%d.%03ds\n' \
      "$name" "$status" "$((duration_ms / 1000))" "$((duration_ms % 1000))"
    count=$((count + 1))
    [[ "$count" -ge "$limit" ]] && break
  done < <(printf '%s\n' "${VALIDATION_TIMING_SUMMARY_ROWS[@]}" | sort -t $'\t' -k1,1nr)
}
