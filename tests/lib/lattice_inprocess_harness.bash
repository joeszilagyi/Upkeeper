#!/usr/bin/env bash

LATTICE_HARNESS_ACTIVE="0"
LATTICE_HARNESS_PID=""
LATTICE_HARNESS_REQUEST_FD=""
LATTICE_HARNESS_RESPONSE_FD=""
LATTICE_HARNESS_RAW_STORAGE="${UPKEEPER_LATTICE_RAW_STORAGE-__UNSET__}"
LATTICE_HARNESS_COMMAND_TIMEOUT_SECONDS="${LATTICE_HARNESS_COMMAND_TIMEOUT_SECONDS:-15}"
LATTICE_HARNESS_TIMEOUT_ARTIFACT="${LATTICE_HARNESS_TIMEOUT_ARTIFACT:-}"

lattice_harness_start() {
  local harness_root="$1"
  local request_fifo="$harness_root/request.fifo"
  local response_fifo="$harness_root/response.fifo"

  [[ "$LATTICE_HARNESS_ACTIVE" == "0" ]] || return 0
  mkdir -p "$harness_root"
  mkfifo "$request_fifo" "$response_fifo"
  exec {LATTICE_HARNESS_REQUEST_FD}<>"$request_fifo"
  exec {LATTICE_HARNESS_RESPONSE_FD}<>"$response_fifo"
  python3 "$ROOT_DIR/tests/lib/lattice_inprocess_server.py" \
    <"$request_fifo" >"$response_fifo" &
  LATTICE_HARNESS_PID="$!"
  LATTICE_HARNESS_ACTIVE="1"
}

lattice_harness_decode() {
  local encoded="$1"
  [[ -n "$encoded" ]] || return 0
  printf '%s' "$encoded" | base64 --decode
}

lattice_harness_abort() {
  local deadline
  [[ "$LATTICE_HARNESS_ACTIVE" == "1" ]] || return 0
  kill -TERM "$LATTICE_HARNESS_PID" 2>/dev/null || true
  deadline=$((SECONDS + 1))
  while kill -0 "$LATTICE_HARNESS_PID" 2>/dev/null && [[ "$SECONDS" -lt "$deadline" ]]; do
    sleep 0.1
  done
  kill -KILL "$LATTICE_HARNESS_PID" 2>/dev/null || true
  wait "$LATTICE_HARNESS_PID" 2>/dev/null || true
  eval "exec ${LATTICE_HARNESS_REQUEST_FD}>&-" 2>/dev/null || true
  eval "exec ${LATTICE_HARNESS_RESPONSE_FD}>&-" 2>/dev/null || true
  LATTICE_HARNESS_PID=""
  LATTICE_HARNESS_ACTIVE="0"
}

lattice_harness_timeout() {
  local response_phase="$1"
  shift
  local artifact="${LATTICE_HARNESS_TIMEOUT_ARTIFACT:-${ROOT_DIR:?ROOT_DIR is required}/runtime/validation-timeouts/lattice-harness-$$.jsonl}"

  lattice_harness_abort
  lattice_command_guard_record_timeout \
    "lattice_inprocess:$response_phase" \
    "$LATTICE_HARNESS_COMMAND_TIMEOUT_SECONDS" \
    "$artifact" \
    harness_process_term_kill \
    "$@"
  return 124
}

lattice_harness_run() {
  local rc_line stdout_line stderr_line end_line rc
  local request_fd="$LATTICE_HARNESS_REQUEST_FD"
  local response_fd="$LATTICE_HARNESS_RESPONSE_FD"

  [[ "$LATTICE_HARNESS_ACTIVE" == "1" ]] || return 70
  printf 'CMD %d\n' "$#" >&"$request_fd"
  local arg
  for arg in "$@"; do
    printf '%s\0' "$arg" >&"$request_fd"
  done

  if ! IFS= read -r -t "$LATTICE_HARNESS_COMMAND_TIMEOUT_SECONDS" rc_line <&"$response_fd"; then
    lattice_harness_timeout response_header "$@"
    return $?
  fi
  if ! IFS= read -r -t 2 stdout_line <&"$response_fd"; then
    lattice_harness_timeout stdout "$@"
    return $?
  fi
  if ! IFS= read -r -t 2 stderr_line <&"$response_fd"; then
    lattice_harness_timeout stderr "$@"
    return $?
  fi
  if ! IFS= read -r -t 2 end_line <&"$response_fd"; then
    lattice_harness_timeout response_end "$@"
    return $?
  fi
  [[ "$rc_line" =~ ^RC[[:space:]]+([0-9]+)$ ]] || return 70
  rc="${BASH_REMATCH[1]}"
  [[ "$stdout_line" == STDOUT_B64\ * ]] || return 70
  [[ "$stderr_line" == STDERR_B64\ * ]] || return 70
  [[ "$end_line" == "END" ]] || return 70
  lattice_harness_decode "${stdout_line#STDOUT_B64 }"
  lattice_harness_decode "${stderr_line#STDERR_B64 }" >&2
  return "$rc"
}

lattice_harness_stop() {
  local ignored

  [[ "$LATTICE_HARNESS_ACTIVE" == "1" ]] || return 0
  printf 'SHUTDOWN\n' >&"$LATTICE_HARNESS_REQUEST_FD" 2>/dev/null || true
  if ! {
    IFS= read -r -t 2 ignored <&"$LATTICE_HARNESS_RESPONSE_FD" 2>/dev/null &&
      IFS= read -r -t 2 ignored <&"$LATTICE_HARNESS_RESPONSE_FD" 2>/dev/null &&
      IFS= read -r -t 2 ignored <&"$LATTICE_HARNESS_RESPONSE_FD" 2>/dev/null &&
      IFS= read -r -t 2 ignored <&"$LATTICE_HARNESS_RESPONSE_FD" 2>/dev/null
  }; then
    kill "$LATTICE_HARNESS_PID" 2>/dev/null || true
  fi
  eval "exec ${LATTICE_HARNESS_REQUEST_FD}>&-" 2>/dev/null || true
  eval "exec ${LATTICE_HARNESS_RESPONSE_FD}>&-" 2>/dev/null || true
  wait "$LATTICE_HARNESS_PID" 2>/dev/null || true
  LATTICE_HARNESS_ACTIVE="0"
}
