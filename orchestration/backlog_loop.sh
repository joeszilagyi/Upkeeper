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

main() {
  local state_root log_file sleep_seconds status

  state_root="$(backlog_state_root)"
  log_file="${BACKLOG_LOOP_LOG_FILE:-$state_root/loop.log}"
  sleep_seconds="${BACKLOG_LOOP_SLEEP_SECONDS:-60}"

  mkdir -p -- "$state_root" "$(dirname -- "$log_file")"
  chmod 700 "$state_root" "$(dirname -- "$log_file")" 2>/dev/null || true

  printf '%s # backlog-loop: writing output to %s\n' "$(backlog_loop_timestamp)" "$log_file" >&2
  while "$ROOT_DIR/orchestration/backlog.sh" </dev/null > >(backlog_loop_timestamp_stream >>"$log_file") 2>&1; do
    sleep "$sleep_seconds"
  done
  status="$?"
  printf '%s # backlog-loop: stopped exit=%s log=%s\n' "$(backlog_loop_timestamp)" "$status" "$log_file" >&2
  return "$status"
}

main "$@"
