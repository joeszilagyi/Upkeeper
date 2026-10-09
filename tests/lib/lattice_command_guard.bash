#!/usr/bin/env bash

# Sourceable command-level timeout custody for direct Lattice validation probes.

lattice_command_guard_json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

lattice_command_guard_display() {
  local arg rendered=""
  for arg in "$@"; do
    printf -v arg '%q' "$arg"
    rendered+="${rendered:+ }$arg"
  done
  printf '%s' "$rendered"
}

lattice_command_guard_record_timeout() {
  local phase="$1"
  local timeout_seconds="$2"
  local artifact="$3"
  local cleanup="$4"
  shift 4
  local command_text escaped_phase escaped_command escaped_cleanup
  local log_fd="${LATTICE_COMMAND_GUARD_LOG_FD:-2}"

  command_text="$(lattice_command_guard_display "$@")"
  escaped_phase="$(lattice_command_guard_json_escape "$phase")"
  escaped_command="$(lattice_command_guard_json_escape "$command_text")"
  escaped_cleanup="$(lattice_command_guard_json_escape "$cleanup")"
  mkdir -p "$(dirname -- "$artifact")"
  (
    umask 077
    printf '{"schema":"upkeeper.lattice-validation-timeout.v1","phase":"%s","command":"%s","status":"timeout","exit_code":124,"timeout_seconds":%d,"cleanup":"%s","recorded_at":"%s"}\n' \
      "$escaped_phase" "$escaped_command" "$timeout_seconds" "$escaped_cleanup" \
      "$(date '+%Y-%m-%dT%H:%M:%S%z')" >>"$artifact"
  )
  printf 'lattice_validation: ERROR phase=%s command=%s timeout=%ss cleanup=%s artifact=%s\n' \
    "$phase" "$command_text" "$timeout_seconds" "$cleanup" "$artifact" >&"$log_fd"
}

lattice_command_guard_run() {
  local phase="$1"
  local timeout_seconds="$2"
  local artifact="$3"
  shift 3
  local command_text rc=0
  local log_fd="${LATTICE_COMMAND_GUARD_LOG_FD:-2}"

  [[ "$timeout_seconds" =~ ^[0-9]+$ && "$timeout_seconds" -ge 1 ]] || {
    printf 'lattice_validation: ERROR invalid timeout for phase=%s: %s\n' "$phase" "$timeout_seconds" >&2
    return 2
  }
  [[ "$#" -gt 0 ]] || {
    printf 'lattice_validation: ERROR missing command for phase=%s\n' "$phase" >&2
    return 2
  }
  command_text="$(lattice_command_guard_display "$@")"
  printf 'lattice_validation: command phase=%s timeout=%ss artifact=%s command=%s\n' \
    "$phase" "$timeout_seconds" "$artifact" "$command_text" >&"$log_fd"
  timeout --kill-after=5s "$timeout_seconds" "$@" || rc="$?"
  if [[ "$rc" -eq 124 ]]; then
    lattice_command_guard_record_timeout \
      "$phase" "$timeout_seconds" "$artifact" process_group_term_kill "$@"
  fi
  return "$rc"
}
