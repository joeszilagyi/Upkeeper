#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

backlog_state_root() {
  printf '%s\n' "${BACKLOG_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/upkeeper/backlog}"
}

main() {
  local state_root log_file sleep_seconds status

  state_root="$(backlog_state_root)"
  log_file="${BACKLOG_LOOP_LOG_FILE:-$state_root/loop.log}"
  sleep_seconds="${BACKLOG_LOOP_SLEEP_SECONDS:-60}"

  mkdir -p -- "$state_root" "$(dirname -- "$log_file")"
  chmod 700 "$state_root" "$(dirname -- "$log_file")" 2>/dev/null || true

  printf '# backlog-loop: writing output to %s\n' "$log_file" >&2
  while "$ROOT_DIR/orchestration/backlog.sh" </dev/null >>"$log_file" 2>&1; do
    sleep "$sleep_seconds"
  done
  status="$?"
  printf '# backlog-loop: stopped exit=%s log=%s\n' "$status" "$log_file" >&2
  return "$status"
}

main "$@"
