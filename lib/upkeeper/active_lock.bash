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
  rm -f -- "$CODEX_ACTIVE_LOCK_DIR/state" 2>/dev/null || true
  rmdir -- "$CODEX_ACTIVE_LOCK_DIR" 2>/dev/null || true
  ACTIVE_LOCK_ACQUIRED="0"
}

acquire_active_lock_or_exit() {
  local lock_parent owner_pid owner_start owner_boot owner_cycle owner_run_hash state_file
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
    if process_fingerprint_alive "$owner_pid" "$owner_start" "$owner_boot"; then
      if [[ "${CODEX_FALLBACK_CHAIN_ACTIVE:-0}" == "1" && "${CODEX_ATTEMPT_ROLE:-}" == "fallback" && -n "${CODEX_PARENT_CYCLE_ID:-}" && "$owner_cycle" == "$CODEX_PARENT_CYCLE_ID" ]]; then
        log_line "INFO" "active_lock.inherited path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") owner_pid=${owner_pid:-unknown} owner_cycle=${owner_cycle:-unknown} owner_run_hash=${owner_run_hash:-unknown} child_cycle=$CYCLE_ID"
        ACTIVE_LOCK_ACQUIRED="0"
        return 0
      fi
      log_line "WARN" "active_lock.held path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") owner_pid=${owner_pid:-unknown} owner_cycle=${owner_cycle:-unknown} owner_run_hash=${owner_run_hash:-unknown} action=exit"
      finish_cycle 7 UPKEEPER_ACTIVE_LOCK_HELD WARN "codex_exec_started=0 owner_pid=${owner_pid:-unknown} owner_cycle=${owner_cycle:-unknown} owner_run_hash=${owner_run_hash:-unknown}"
    fi
    log_line "WARN" "active_lock.stale path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") owner_pid=${owner_pid:-unknown} owner_cycle=${owner_cycle:-unknown} owner_run_hash=${owner_run_hash:-unknown} action=reclaim"
    rm -f -- "$CODEX_ACTIVE_LOCK_DIR/state" 2>/dev/null || true
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
  if ! {
    printf 'cycle_id=%s\n' "$CYCLE_ID"
    printf 'run_hash=%s\n' "$CYCLE_RUN_HASH"
    printf 'pid=%s\n' "$$"
    printf 'wrapper_start=%s\n' "$(process_start_fingerprint "$$")"
    printf 'boot_id=%s\n' "$(system_boot_id)"
    printf 'root_dir=%s\n' "$ROOT_DIR"
    printf 'self_path=%s\n' "$SELF_PATH"
    printf 'created_epoch=%s\n' "$(date '+%s')"
  } >"$state_file"; then
    release_active_lock
    log_line "ERROR" "active_lock.failed path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR") reason=state_write_failed"
    finish_cycle 7 UPKEEPER_ACTIVE_LOCK_FAILED ERROR "codex_exec_started=0 reason=state_write_failed"
  fi

  log_line "INFO" "active_lock.acquired path=$(shell_quote "$CODEX_ACTIVE_LOCK_DIR")"
}
