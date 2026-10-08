#!/usr/bin/env bash

LATTICE_HARNESS_ACTIVE="0"
LATTICE_HARNESS_PID=""
LATTICE_HARNESS_REQUEST_FD=""
LATTICE_HARNESS_RESPONSE_FD=""
LATTICE_HARNESS_RAW_STORAGE="${UPKEEPER_LATTICE_RAW_STORAGE-__UNSET__}"

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

  IFS= read -r -t 15 rc_line <&"$response_fd" || return 70
  IFS= read -r -t 2 stdout_line <&"$response_fd" || return 70
  IFS= read -r -t 2 stderr_line <&"$response_fd" || return 70
  IFS= read -r -t 2 end_line <&"$response_fd" || return 70
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
