#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

backlog_state_root() {
  printf '%s\n' "${BACKLOG_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/upkeeper/backlog}"
}

backlog_loop_timestamp() {
  date '+%Y-%m-%dT%H:%M:%S'
}

backlog_loop_line_starts_with_timestamp() {
  local line="$1"

  case "$line" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

backlog_loop_timestamp_stream() {
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    if backlog_loop_line_starts_with_timestamp "$line"; then
      printf '%s\n' "$line"
    else
      printf '%s %s\n' "$(backlog_loop_timestamp)" "$line"
    fi
  done
}

backlog_loop_nonnegative_integer() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

backlog_loop_positive_integer_or_default() {
  local value="$1"
  local default_value="$2"

  if backlog_loop_nonnegative_integer "$value" && [[ "$value" -gt 0 ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

backlog_loop_disposition_field() {
  local path="$1"
  local key="$2"

  [[ -f "$path" ]] || return 1
  awk -F '\t' -v key="$key" '$1 == key { print $2; found = 1; exit } END { exit !found }' "$path"
}

backlog_loop_sleep_plan() {
  local disposition_file="$1"
  local idle_sleep busy_sleep blocked_sleep quota_sleep disposition reason sleep_seconds

  idle_sleep="$(backlog_loop_positive_integer_or_default "${BACKLOG_LOOP_SLEEP_SECONDS:-60}" 60)"
  busy_sleep="${BACKLOG_LOOP_BUSY_SLEEP_SECONDS:-5}"
  blocked_sleep="$(backlog_loop_positive_integer_or_default "${BACKLOG_LOOP_BLOCKED_SLEEP_SECONDS:-$idle_sleep}" "$idle_sleep")"
  quota_sleep="$(backlog_loop_positive_integer_or_default "${BACKLOG_LOOP_QUOTA_SLEEP_SECONDS:-$idle_sleep}" "$idle_sleep")"
  if ! backlog_loop_nonnegative_integer "$busy_sleep"; then
    busy_sleep=5
  fi

  disposition="$(backlog_loop_disposition_field "$disposition_file" disposition 2>/dev/null || printf 'no_disposition')"
  reason="$(backlog_loop_disposition_field "$disposition_file" reason 2>/dev/null || printf 'missing_disposition')"

  case "$disposition" in
    work_done)
      sleep_seconds="$busy_sleep"
      ;;
    blocked_external|no_work|no_disposition)
      sleep_seconds="$idle_sleep"
      ;;
    quota_wait)
      sleep_seconds="$quota_sleep"
      ;;
    *)
      sleep_seconds="$blocked_sleep"
      ;;
  esac

  printf '%s\t%s\t%s\n' "$sleep_seconds" "$disposition" "$reason"
}

main() {
  local state_root log_file disposition_file sleep_plan sleep_seconds disposition reason status

  state_root="$(backlog_state_root)"
  log_file="${BACKLOG_LOOP_LOG_FILE:-$state_root/loop.log}"
  disposition_file="${BACKLOG_LOOP_DISPOSITION_FILE:-$state_root/last-cycle-disposition.tsv}"
  export BACKLOG_LOOP_DISPOSITION_FILE="$disposition_file"

  mkdir -p -- "$state_root" "$(dirname -- "$log_file")" "$(dirname -- "$disposition_file")"
  chmod 700 "$state_root" "$(dirname -- "$log_file")" "$(dirname -- "$disposition_file")" 2>/dev/null || true

  printf '%s # backlog-loop: writing output to %s\n' "$(backlog_loop_timestamp)" "$log_file" >&2
  while "$ROOT_DIR/orchestration/backlog.sh" </dev/null > >(backlog_loop_timestamp_stream >>"$log_file") 2>&1; do
    sleep_plan="$(backlog_loop_sleep_plan "$disposition_file")"
    IFS=$'\t' read -r sleep_seconds disposition reason <<<"$sleep_plan"
    if [[ "$sleep_seconds" -gt 0 ]]; then
      printf '%s # backlog-loop: sleeping %ss disposition=%s reason=%s\n' "$(backlog_loop_timestamp)" "$sleep_seconds" "$disposition" "$reason" >&2
      sleep "$sleep_seconds"
    else
      printf '%s # backlog-loop: continuing immediately disposition=%s reason=%s\n' "$(backlog_loop_timestamp)" "$disposition" "$reason" >&2
    fi
  done
  status="$?"
  printf '%s # backlog-loop: stopped exit=%s log=%s\n' "$(backlog_loop_timestamp)" "$status" "$log_file" >&2
  return "$status"
}

if [[ "${BACKLOG_LOOP_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
