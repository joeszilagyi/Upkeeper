# Owns the local active-run lock for one Upkeeper checkout. The lock directory
# serializes wrapper cycles before Codex starts so quota, runtime evidence, and
# fallback state are not mutated by two primary runs at once.
append_startup_anomaly_reason() {
  local reason="$1"
  [[ -n "$reason" ]] || return 0
  if [[ ",$STARTUP_ANOMALY_REASONS," == *",$reason,"* ]]; then
    return 0
  fi
  STARTUP_ANOMALY_REASONS="${STARTUP_ANOMALY_REASONS}${STARTUP_ANOMALY_REASONS:+,}$reason"
}

active_lock_field() {
  local key="$1"
  local file="$CODEX_ACTIVE_LOCK_DIR/state"
  [[ -f "$file" ]] || return 1
  sed -n "s/^${key}=//p" "$file" | sed -n '1p'
}

fallback_chain_token_hash() {
  local token="${1:-}"

  python3 - "$token" <<'PY'
import hashlib
import sys

print(hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest())
PY
}

active_lock_age_seconds() {
  local path="$1"
  python3 - "$path" <<'PY'
import os
import sys
import time

try:
    age = int(time.time() - os.stat(sys.argv[1]).st_mtime)
except OSError:
    sys.exit(1)
print(max(age, 0))
PY
}

process_fingerprint_alive() {
  local pid="$1"
  local expected_start="$2"
  local expected_boot="$3"
  local current_start current_boot

  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1 || return 1
  current_boot="$(system_boot_id)"
  if [[ -n "$expected_boot" && "$expected_boot" != "unknown" && "$current_boot" != "$expected_boot" ]]; then
    return 1
  fi
  current_start="$(process_start_fingerprint "$pid")"
  [[ "$current_start" == "$expected_start" ]]
}

release_active_lock() {
  [[ "${ACTIVE_LOCK_ACQUIRED:-0}" == "1" ]] || return 0
  [[ -n "$CODEX_ACTIVE_LOCK_DIR" ]] || return 0
  rm -f -- "$CODEX_ACTIVE_LOCK_DIR/state.tmp.$$" 2>/dev/null || true
  rm -f -- "$CODEX_ACTIVE_LOCK_DIR/state" 2>/dev/null || true
  rmdir -- "$CODEX_ACTIVE_LOCK_DIR" 2>/dev/null || true
  ACTIVE_LOCK_ACQUIRED="0"
}

acquire_active_lock_or_exit() {
  local lock_age_seconds lock_parent owner_pid owner_start owner_boot owner_cycle owner_run_hash owner_token fallback_inherit_fail state_file state_tmp
  local fallback_parent_pid fallback_parent_start token_fd child_token child_token_hash
  local incomplete_lock_grace_seconds="30"
  if [[ -z "$CODEX_ACTIVE_LOCK_DIR" || "$CODEX_ACTIVE_LOCK_DIR" == "/" ]]; then
    log_line "ERROR" "active_lock.failed path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") reason=unsafe_lock_path"
    finish_cycle 7 UPKEEPER_ACTIVE_LOCK_FAILED ERROR "codex_exec_started=0 reason=unsafe_lock_path"
  fi
  lock_parent="$(dirname -- "$CODEX_ACTIVE_LOCK_DIR")"
  if ! mkdir -p -- "$lock_parent"; then
    log_line "ERROR" "active_lock.failed path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") reason=parent_mkdir_failed"
    finish_cycle 7 UPKEEPER_ACTIVE_LOCK_FAILED ERROR "codex_exec_started=0 reason=parent_mkdir_failed"
  fi

  if mkdir -- "$CODEX_ACTIVE_LOCK_DIR" 2>/dev/null; then
    ACTIVE_LOCK_ACQUIRED="1"
  else
    owner_pid="$(active_lock_field pid || true)"
    owner_start="$(active_lock_field wrapper_start || true)"
    owner_boot="$(active_lock_field boot_id || true)"
    owner_cycle="$(active_lock_field cycle_id || true)"
    owner_run_hash="$(active_lock_field run_hash || true)"
    owner_token="$(active_lock_field fallback_chain_token || true)"
    if process_fingerprint_alive "$owner_pid" "$owner_start" "$owner_boot"; then
      if [[ "${CODEX_FALLBACK_CHAIN_ACTIVE:-0}" == "1" && "${CODEX_ATTEMPT_ROLE:-}" == "fallback" ]]; then
        fallback_inherit_fail=""
        child_token="${CODEX_FALLBACK_CHAIN_TOKEN:-}"
        if [[ -z "$child_token" ]]; then
          if ! [[ "${CODEX_FALLBACK_CHAIN_TOKEN_FD:-}" =~ ^[0-9]+$ ]]; then
            fallback_inherit_fail="missing_fallback_chain_token_fd"
          elif ! IFS= read -r child_token <&"${CODEX_FALLBACK_CHAIN_TOKEN_FD}"; then
            fallback_inherit_fail="missing_fallback_chain_token_read"
          fi
        fi
        if [[ -z "${CODEX_PARENT_CYCLE_ID:-}" ]]; then
          fallback_inherit_fail="missing_parent_cycle"
        elif [[ -z "$owner_token" ]]; then
          fallback_inherit_fail="missing_state_fallback_chain_token"
        elif [[ -z "$child_token" ]]; then
          fallback_inherit_fail="missing_fallback_chain_token_read"
        elif [[ "$owner_cycle" != "$CODEX_PARENT_CYCLE_ID" ]]; then
          fallback_inherit_fail="parent_cycle_mismatch"
        elif ! [[ "${CODEX_FALLBACK_PARENT_PID:-}" =~ ^[0-9]+$ ]]; then
          fallback_inherit_fail="missing_fallback_parent_pid"
        elif ! [[ "${CODEX_FALLBACK_PARENT_START:-}" ]]; then
          fallback_inherit_fail="missing_fallback_parent_start"
        elif [[ "$PPID" != "${CODEX_FALLBACK_PARENT_PID:-}" ]]; then
          fallback_inherit_fail="parent_pid_mismatch"
        elif ! process_fingerprint_alive "${CODEX_FALLBACK_PARENT_PID:-}" "${CODEX_FALLBACK_PARENT_START:-}" "$owner_boot"; then
          fallback_inherit_fail="fallback_parent_process_fingerprint_mismatch"
        else
          child_token_hash="$(fallback_chain_token_hash "$child_token")"
          if [[ "$owner_token" != "$child_token_hash" && "$owner_token" != "$child_token" ]]; then
            fallback_inherit_fail="fallback_chain_token_mismatch"
          fi
        fi
        token_fd="${CODEX_FALLBACK_CHAIN_TOKEN_FD:-}"
        [[ -n "$token_fd" ]] && eval "exec ${token_fd}<&-" 2>/dev/null || true
        fallback_parent_pid="${CODEX_FALLBACK_PARENT_PID:-}"
        fallback_parent_start="${CODEX_FALLBACK_PARENT_START:-}"

        if [[ -n "$fallback_inherit_fail" ]]; then
          log_line "WARN" "active_lock.fallback_inherit_rejected path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") owner_pid=${owner_pid:-unknown} owner_cycle=${owner_cycle:-unknown} reason=$fallback_inherit_fail child_cycle=$CYCLE_ID"
          log_line "WARN" "active_lock.held path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") owner_pid=${owner_pid:-unknown} owner_cycle=${owner_cycle:-unknown} owner_run_hash=${owner_run_hash:-unknown} action=exit reason=$fallback_inherit_fail"
          finish_cycle 7 UPKEEPER_ACTIVE_LOCK_HELD WARN "codex_exec_started=0 owner_pid=${owner_pid:-unknown} owner_cycle=${owner_cycle:-unknown} owner_run_hash=${owner_run_hash:-unknown} requested_parent_cycle=${CODEX_PARENT_CYCLE_ID:-unknown} reason=$fallback_inherit_fail"
        fi
        log_line "INFO" "active_lock.inherited path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") owner_pid=${owner_pid:-unknown} owner_cycle=${owner_cycle:-unknown} owner_run_hash=${owner_run_hash:-unknown} child_cycle=$CYCLE_ID"
        ACTIVE_LOCK_ACQUIRED="0"
        return 0
      fi
      log_line "WARN" "active_lock.held path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") owner_pid=${owner_pid:-unknown} owner_cycle=${owner_cycle:-unknown} owner_run_hash=${owner_run_hash:-unknown} action=exit"
      finish_cycle 7 UPKEEPER_ACTIVE_LOCK_HELD WARN "codex_exec_started=0 owner_pid=${owner_pid:-unknown} owner_cycle=${owner_cycle:-unknown} owner_run_hash=${owner_run_hash:-unknown}"
    fi
    lock_age_seconds="$(active_lock_age_seconds "$CODEX_ACTIVE_LOCK_DIR" 2>/dev/null || printf 'unknown')"
    # A newly-created lock with no trusted state can be another wrapper between
    # mkdir and atomic state publish. Fail closed briefly instead of reclaiming it.
    if [[ "$lock_age_seconds" =~ ^[0-9]+$ && "$lock_age_seconds" -lt "$incomplete_lock_grace_seconds" ]]; then
      log_line "WARN" "active_lock.incomplete path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") owner_pid=${owner_pid:-unknown} owner_cycle=${owner_cycle:-unknown} lock_age_seconds=$lock_age_seconds grace_seconds=$incomplete_lock_grace_seconds action=exit"
      finish_cycle 7 UPKEEPER_ACTIVE_LOCK_HELD WARN "codex_exec_started=0 reason=incomplete_recent_lock owner_pid=${owner_pid:-unknown} owner_cycle=${owner_cycle:-unknown} lock_age_seconds=$lock_age_seconds grace_seconds=$incomplete_lock_grace_seconds"
    fi
    log_line "WARN" "active_lock.stale path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") owner_pid=${owner_pid:-unknown} owner_cycle=${owner_cycle:-unknown} owner_run_hash=${owner_run_hash:-unknown} action=reclaim"
    rm -f -- "$CODEX_ACTIVE_LOCK_DIR/state" 2>/dev/null || true
    rm -f -- "$CODEX_ACTIVE_LOCK_DIR"/state.tmp.* 2>/dev/null || true
    if ! rmdir -- "$CODEX_ACTIVE_LOCK_DIR" 2>/dev/null; then
      log_line "ERROR" "active_lock.failed path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") reason=stale_lock_not_empty"
      finish_cycle 7 UPKEEPER_ACTIVE_LOCK_FAILED ERROR "codex_exec_started=0 reason=stale_lock_not_empty"
    fi
    if ! mkdir -- "$CODEX_ACTIVE_LOCK_DIR" 2>/dev/null; then
      log_line "ERROR" "active_lock.failed path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") reason=reclaim_mkdir_failed"
      finish_cycle 7 UPKEEPER_ACTIVE_LOCK_FAILED ERROR "codex_exec_started=0 reason=reclaim_mkdir_failed"
    fi
    ACTIVE_LOCK_ACQUIRED="1"
  fi

  state_file="$CODEX_ACTIVE_LOCK_DIR/state"
  state_tmp="$CODEX_ACTIVE_LOCK_DIR/state.tmp.$$"
  if ! {
    printf 'cycle_id=%s\n' "$CYCLE_ID"
    printf 'run_hash=%s\n' "$CYCLE_RUN_HASH"
    printf 'pid=%s\n' "$$"
    printf 'wrapper_start=%s\n' "$(process_start_fingerprint "$$")"
    printf 'boot_id=%s\n' "$(system_boot_id)"
    printf 'root_dir=%s\n' "$ROOT_DIR"
    printf 'self_path=%s\n' "${SELF_PATH:-}"
    printf 'fallback_chain_token=%s\n' "$(fallback_chain_token_hash "${CODEX_FALLBACK_CHAIN_TOKEN:-}")"
    printf 'created_epoch=%s\n' "$(date '+%s')"
  } >"$state_tmp"; then
    rm -f -- "$state_tmp" 2>/dev/null || true
    release_active_lock
    log_line "ERROR" "active_lock.failed path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") reason=state_write_failed"
    finish_cycle 7 UPKEEPER_ACTIVE_LOCK_FAILED ERROR "codex_exec_started=0 reason=state_write_failed"
  fi
  if ! mv -f -- "$state_tmp" "$state_file"; then
    rm -f -- "$state_tmp" 2>/dev/null || true
    release_active_lock
    log_line "ERROR" "active_lock.failed path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") reason=state_rename_failed"
    finish_cycle 7 UPKEEPER_ACTIVE_LOCK_FAILED ERROR "codex_exec_started=0 reason=state_rename_failed"
  fi

  log_line "INFO" "active_lock.acquired path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR")"
}
