timestamp_now() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

epoch_now_fraction() {
  local now
  now="$(date '+%s.%N' 2>/dev/null || true)"
  if [[ "$now" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf '%.5f\n' "$now"
  else
    date '+%s'
  fi
}

system_boot_id() {
  if [[ -r /proc/sys/kernel/random/boot_id ]]; then
    tr -d '[:space:]' </proc/sys/kernel/random/boot_id
  else
    printf 'unknown'
  fi
}

system_uptime_seconds() {
  if [[ -r /proc/uptime ]]; then
    awk '{ printf "%.2f", $1 }' /proc/uptime
  else
    printf 'unknown'
  fi
}

process_start_fingerprint() {
  local pid="$1"
  local stat_text after_comm
  if [[ -r "/proc/$pid/stat" ]]; then
    IFS= read -r stat_text <"/proc/$pid/stat" || true
    after_comm="${stat_text##*) }"
    set -- $after_comm
    if [[ $# -ge 20 && -n "${20:-}" ]]; then
      printf 'proc_start_ticks=%s' "${20}"
      return 0
    fi
  fi
  printf 'proc_start_ticks=unknown'
}

terminal_wants_full_output() {
  case "${CODEX_TERMINAL_VERBOSITY:-summary}" in
    full|verbose|debug|trace|1|yes|true)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_wants_quiet_output() {
  case "${CODEX_TERMINAL_VERBOSITY:-summary}" in
    quiet|none|silent|0|no|false)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_suppresses_progress() {
  case "${CODEX_TERMINAL_VERBOSITY:-summary}" in
    none|silent|0|no|false)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_emit_progress() {
  local message="$*"

  terminal_wants_full_output && return 0
  terminal_suppresses_progress && return 0
  printf '%s Upkeeper: %s\n' "$(timestamp_now)" "$message" >&2
}

terminal_emit_log_line() {
  local level="$1"
  local line="$2"

  if terminal_wants_full_output; then
    printf '%s\n' "$line"
    return 0
  fi
  if terminal_wants_quiet_output; then
    case "$level" in
      WARN|ERROR)
        printf '%s\n' "$line" >&2
        ;;
    esac
    return 0
  fi
  case "$level" in
    WARN|ERROR)
      printf '%s\n' "$line" >&2
      ;;
  esac
}

log_line() {
  local level="$1"
  shift
  local ts line
  ts="$(timestamp_now)"
  line="$(printf '%s [%s] cycle=%s run_hash=%s %s' "$ts" "$level" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$*")"
  printf '%s\n' "$line" >>"$LOG_FILE"
  terminal_emit_log_line "$level" "$line"
}

ensure_log_parent() {
  if [[ -n "$LOG_FILE_DIR" && "$LOG_FILE_DIR" != "." ]]; then
    if ! mkdir -p -- "$LOG_FILE_DIR"; then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s\n' "$(timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" >&2
      exit 3
    fi
  fi
}

ensure_run_tmp_dir() {
  if [[ -n "$RUN_TMP_DIR" ]]; then
    return 0
  fi

  local tmp_base="${TMPDIR:-/tmp}"
  RUN_TMP_DIR="$tmp_base/upkeeper-$CYCLE_RUN_HASH"
  if ! mkdir -p -- "$RUN_TMP_DIR"; then
    die "failed to create run temp directory $RUN_TMP_DIR"
  fi
  chmod 700 "$RUN_TMP_DIR" 2>/dev/null || true
  log_line "INFO" "run.tmp_dir path=$(shell_quote "$RUN_TMP_DIR")" >/dev/null
}

run_mktemp() {
  local label="${1:-tmp}"
  ensure_run_tmp_dir
  mktemp "$RUN_TMP_DIR/${label}.XXXXXX"
}

prune_transcript_artifacts() {
  local transcript_dir="$CODEX_TRANSCRIPT_DIR"
  local keep_hours max_mb

  [[ -n "$transcript_dir" ]] || return 0
  keep_hours="$(sanitize_nonnegative_integer "$CODEX_TRANSCRIPT_KEEP_HOURS" "24")"
  max_mb="$(sanitize_nonnegative_integer "$CODEX_TRANSCRIPT_KEEP_MAX_MB" "200")"

  python3 - "$transcript_dir" "$keep_hours" "$max_mb" <<'PY' || true
from pathlib import Path
import sys
import time

root = Path(sys.argv[1])
keep_hours = int(sys.argv[2])
max_mb = int(sys.argv[3])
try:
    root.mkdir(parents=True, exist_ok=True)
except OSError:
    raise SystemExit(0)
if keep_hours > 0:
    cutoff = time.time() - keep_hours * 3600
    for path in root.glob('*.log'):
        try:
            if path.is_file() and path.stat().st_mtime < cutoff:
                path.unlink()
        except OSError:
            pass
if max_mb <= 0:
    raise SystemExit(0)
max_bytes = max_mb * 1024 * 1024
entries = []
for path in root.glob('*.log'):
    try:
        st = path.stat()
    except OSError:
        continue
    if path.is_file():
        entries.append((st.st_mtime, st.st_size, path))
total = sum(size for _, size, _ in entries)
for _, size, path in sorted(entries):
    if total <= max_bytes:
        break
    try:
        path.unlink()
        total -= size
    except OSError:
        pass
PY
}

new_transcript_file() {
  local label="${1:-codex}"
  local transcript_dir="$CODEX_TRANSCRIPT_DIR"
  label="${label//[^A-Za-z0-9_.-]/_}"
  [[ -n "$transcript_dir" ]] || transcript_dir="$ROOT_DIR/runtime/upkeeper-transcripts"
  if ! mkdir -p -- "$transcript_dir"; then
    die "failed to create transcript directory $transcript_dir"
  fi
  chmod 700 "$transcript_dir" 2>/dev/null || true
  prune_transcript_artifacts
  mktemp "$transcript_dir/$CYCLE_ID.$CYCLE_RUN_HASH.$label.XXXXXX.log"
}

file_blob_hash() {
  local path="$1"
  git hash-object -- "$path" 2>/dev/null || printf 'unknown'
}

hash_text() {
  local value="$1"
  python3 - "$value" <<'PY' 2>/dev/null || printf 'unknown'
import hashlib
import sys

print(hashlib.sha256(sys.argv[1].encode("utf-8", "surrogateescape")).hexdigest()[:24])
PY
}

file_size_bytes() {
  local path="$1"
  if command -v stat >/dev/null 2>&1; then
    stat -c '%s' -- "$path" 2>/dev/null && return 0
  fi
  python3 - "$path" <<'PY' 2>/dev/null || printf 'unknown'
import os
import sys
try:
    print(os.stat(sys.argv[1]).st_size)
except OSError:
    print("unknown")
PY
}

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

wrapper_health_stale_seconds() {
  local interval="$CODEX_MARK_INTERVAL_SECONDS"
  if [[ "$interval" -lt 1 ]]; then
    interval=60
  fi
  local stale=$((interval * 3))
  if [[ "$stale" -lt 180 ]]; then
    stale=180
  fi
  printf '%s' "$stale"
}

wrapper_health_key_fields() {
  local self_path_hash wrapper_blob_hash
  self_path_hash="$(hash_text "$SELF_PATH")"
  wrapper_blob_hash="$(file_blob_hash "$SELF_PATH")"
  printf '%s\t%s\n' "$self_path_hash" "$wrapper_blob_hash"
}

write_wrapper_health_state() {
  local phase="$1"
  local state_dir="$CODEX_WRAPPER_HEALTH_STATE_DIR"
  local self_path_hash wrapper_blob_hash state_file tmp_file now_epoch

  [[ -n "$state_dir" ]] || return 1
  if ! mkdir -p -- "$state_dir"; then
    log_line "ERROR" "central_wrapper.health_state_unwritable dir=$(shell_quote "$state_dir") reason=mkdir_failed"
    return 1
  fi

  IFS=$'\t' read -r self_path_hash wrapper_blob_hash < <(wrapper_health_key_fields)
  if [[ -z "${WRAPPER_HEALTH_STATE_FILE:-}" ]]; then
    WRAPPER_HEALTH_STATE_FILE="$state_dir/$self_path_hash.$wrapper_blob_hash.$CYCLE_RUN_HASH.state"
  fi
  state_file="$WRAPPER_HEALTH_STATE_FILE"
  tmp_file="$state_file.tmp.$$"
  now_epoch="$(date '+%s')"

  if ! {
    printf 'status=%s\n' "$phase"
    printf 'cycle_id=%s\n' "$CYCLE_ID"
    printf 'run_hash=%s\n' "$CYCLE_RUN_HASH"
    printf 'self_path=%s\n' "$SELF_PATH"
    printf 'self_path_hash=%s\n' "$self_path_hash"
    printf 'wrapper_blob_hash=%s\n' "$wrapper_blob_hash"
    printf 'root_dir=%s\n' "$ROOT_DIR"
    printf 'pid=%s\n' "$$"
    printf 'wrapper_start=%s\n' "$(process_start_fingerprint "$$")"
    printf 'boot_id=%s\n' "$(system_boot_id)"
    printf 'last_mark_epoch=%s\n' "$now_epoch"
    printf 'updated_epoch=%s\n' "$now_epoch"
  } >"$tmp_file"; then
    rm -f "$tmp_file"
    log_line "ERROR" "central_wrapper.health_state_unwritable path=$(shell_quote "$state_file") reason=write_failed"
    return 1
  fi
  if ! mv -f -- "$tmp_file" "$state_file"; then
    rm -f "$tmp_file"
    log_line "ERROR" "central_wrapper.health_state_unwritable path=$(shell_quote "$state_file") reason=rename_failed"
    return 1
  fi
  return 0
}

finalize_wrapper_health_state() {
  local phase="${1:-exited}"
  [[ -n "${WRAPPER_HEALTH_STATE_FILE:-}" ]] || return 0
  [[ "${WRAPPER_HEALTH_STATE_FINALIZED:-0}" == "0" ]] || return 0
  write_wrapper_health_state "$phase" || true
  WRAPPER_HEALTH_STATE_FINALIZED="1"
}

scan_wrapper_health_state() {
  local state_dir="$CODEX_WRAPPER_HEALTH_STATE_DIR"
  local self_path_hash wrapper_blob_hash stale_seconds
  [[ -d "$state_dir" ]] || return 0
  IFS=$'\t' read -r self_path_hash wrapper_blob_hash < <(wrapper_health_key_fields)
  stale_seconds="$(wrapper_health_stale_seconds)"

  python3 - "$state_dir" "$self_path_hash" "$wrapper_blob_hash" "$CYCLE_RUN_HASH" "$stale_seconds" "$(system_boot_id)" "$CODEX_WRAPPER_HEALTH_ARCHIVE_DIR" <<'PY'
from pathlib import Path
import os
import sys
import time

state_dir = Path(sys.argv[1])
self_path_hash = sys.argv[2]
wrapper_blob_hash = sys.argv[3]
current_run_hash = sys.argv[4]
stale_seconds = int(sys.argv[5])
current_boot_id = sys.argv[6]
archive_dir_raw = sys.argv[7].strip()
now = int(time.time())
prefix = f"{self_path_hash}.{wrapper_blob_hash}."


def read_fields(path):
    fields = {}
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return fields
    for line in lines:
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key.strip()] = value.strip()
    return fields


def proc_start_ticks(pid):
    try:
        stat_text = Path("/proc", pid, "stat").read_text(encoding="utf-8", errors="replace")
        return f"proc_start_ticks={stat_text.rsplit(') ', 1)[1].split()[19]}"
    except Exception:
        return "proc_start_ticks=unknown"


for path in sorted(state_dir.glob(f"{prefix}*.state")):
    if not path.name.startswith(prefix):
        continue
    fields = read_fields(path)
    if fields.get("run_hash") == current_run_hash:
        continue
    status = fields.get("status", "unknown")
    if status in {"exited", "aborted", "cleanup", "die", "finish", "resolved"}:
        continue
    pid = fields.get("pid", "")
    expected_start = fields.get("wrapper_start", "")
    boot_id = fields.get("boot_id", "unknown")
    cycle_id = fields.get("cycle_id", "unknown")
    run_hash = fields.get("run_hash", "unknown")
    last_mark_raw = fields.get("last_mark_epoch", "0")
    try:
        last_mark = int(float(last_mark_raw))
    except ValueError:
        last_mark = 0
    alive = pid.isdigit() and Path("/proc", pid).exists()
    fingerprint_matches = alive and proc_start_ticks(pid) == expected_start
    boot_matches = boot_id in {"", "unknown"} or current_boot_id in {"", "unknown"} or boot_id == current_boot_id
    fresh = last_mark > 0 and now - last_mark <= stale_seconds
    if alive and fingerprint_matches and boot_matches and fresh:
        print(
            f"status=healthy action=allow peer_cycle={cycle_id} peer_run_hash={run_hash} "
            f"peer_pid={pid} last_mark_age_seconds={now - last_mark} state_file={path}"
        )
        continue
    if not alive and not fresh:
        archive_dir = Path(archive_dir_raw) if archive_dir_raw else None
        archived_path = None
        if archive_dir:
            try:
                archive_dir.mkdir(parents=True, exist_ok=True)
                archived_path = archive_dir / f"{path.stem}-retired-{time.strftime('%Y%m%dT%H%M%S%z')}-{os.getpid()}.state"
                path.replace(archived_path)
            except Exception:
                archived_path = None
        if archived_path is not None:
            print(
                f"status=reclaimed action=archive reason=pid_not_alive peer_cycle={cycle_id} "
                f"peer_run_hash={run_hash} peer_pid={pid or 'unknown'} last_mark_age_seconds={now - last_mark if last_mark else 'unknown'} "
                f"stale_seconds={stale_seconds} state_file={path} archived_state_file={archived_path}"
            )
            continue
    reason = "unknown"
    if not alive:
        reason = "pid_not_alive"
    elif not fingerprint_matches:
        reason = "pid_start_fingerprint_mismatch"
    elif not boot_matches:
        reason = "boot_id_changed"
    elif not fresh:
        reason = "heartbeat_stale"
    print(
        f"status=quarantine action=fail_closed reason={reason} peer_cycle={cycle_id} "
        f"peer_run_hash={run_hash} peer_pid={pid or 'unknown'} last_mark_age_seconds={now - last_mark if last_mark else 'unknown'} "
        f"stale_seconds={stale_seconds} state_file={path}"
    )
PY
}

check_central_wrapper_health_or_exit() {
  local line saw_quarantine=0 saw_healthy=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ "$line" == status=quarantine* ]]; then
      saw_quarantine=1
      log_line "WARN" "central_wrapper.health $line"
    elif [[ "$line" == status=healthy* ]]; then
      saw_healthy=1
      log_line "INFO" "central_wrapper.health $line"
    else
      log_line "INFO" "central_wrapper.health $line"
    fi
  done < <(scan_wrapper_health_state || true)

  if [[ "$saw_quarantine" == "1" ]]; then
    if ! write_wrapper_health_state "quarantined"; then
      finish_cycle 7 CENTRAL_WRAPPER_HEALTH_STATE_UNWRITABLE ERROR "codex_exec_started=0 implementation=$(shell_quote "$SELF_PATH")"
    fi
    finish_cycle 7 CENTRAL_WRAPPER_HEALTH_QUARANTINE WARN "codex_exec_started=0 implementation=$(shell_quote "$SELF_PATH")"
  fi

  if ! write_wrapper_health_state "starting"; then
    finish_cycle 7 CENTRAL_WRAPPER_HEALTH_STATE_UNWRITABLE ERROR "codex_exec_started=0 implementation=$(shell_quote "$SELF_PATH")"
  fi
  log_line "INFO" "central_wrapper.health_state status=starting state_file=$(shell_quote "$WRAPPER_HEALTH_STATE_FILE") healthy_peers=$saw_healthy"
}

ensure_log_writable_or_exit() {
  local phase="${1:-startup}"
  local marker line last_line

  ensure_log_parent
  marker="upkeeper-log-probe-$CYCLE_ID-$CYCLE_RUN_HASH-$$"
  line="$(timestamp_now) [INFO] cycle=$CYCLE_ID run_hash=$CYCLE_RUN_HASH log.write_preflight phase=$phase marker=$marker"
  if ! printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null; then
    printf '%s [ERROR] cycle=%s run_hash=%s log.write_preflight_failed phase=%s path=%s reason=append_failed\n' "$(timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$phase" "$LOG_FILE" >&2
    exit 3
  fi
  last_line="$(tail -n 1 "$LOG_FILE" 2>/dev/null || true)"
  if [[ "$last_line" != "$line" ]]; then
    printf '%s [ERROR] cycle=%s run_hash=%s log.write_preflight_failed phase=%s path=%s reason=verify_failed\n' "$(timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$phase" "$LOG_FILE" >&2
    exit 3
  fi
}

die() {
  ensure_log_parent
  if ! log_line "ERROR" "$*"; then
    printf '%s [ERROR] cycle=%s %s\n' "$(timestamp_now)" "$CYCLE_ID" "$*" >&2
  fi
  stop_run_mark_heartbeat "die"
  finalize_wrapper_health_state "die"
  release_active_lock
  exit 3
}

emit_run_mark() {
  local phase="${1:-heartbeat}"
  log_line "INFO" "--MARK-- phase=$phase epoch=$(epoch_now_fraction) boot_id=$(system_boot_id) uptime_seconds=$(system_uptime_seconds)"
  if [[ -n "${WRAPPER_HEALTH_STATE_FILE:-}" && "${WRAPPER_HEALTH_STATE_FINALIZED:-0}" == "0" ]]; then
    write_wrapper_health_state "$phase" || log_line "WARN" "central_wrapper.health_state_update_failed phase=$phase state_file=$(shell_quote "$WRAPPER_HEALTH_STATE_FILE")"
  fi
}

stop_terminal_progress_heartbeat() {
  local reason="${1:-stop}"

  if [[ -n "${RUN_TERMINAL_PROGRESS_PID:-}" ]]; then
    kill "$RUN_TERMINAL_PROGRESS_PID" >/dev/null 2>&1 || true
    wait "$RUN_TERMINAL_PROGRESS_PID" 2>/dev/null || true
    RUN_TERMINAL_PROGRESS_PID=""
    log_line "INFO" "terminal_progress.stop reason=$reason"
  fi
}

start_terminal_progress_heartbeat() {
  local label="$1"
  local transcript_file="$2"
  local started_epoch="$3"
  local target="$4"
  local interval

  terminal_wants_full_output && return 0
  terminal_suppresses_progress && return 0
  interval="$(sanitize_nonnegative_integer "${CODEX_TERMINAL_PROGRESS_INTERVAL_SECONDS:-$CODEX_MARK_INTERVAL_SECONDS}" "$CODEX_MARK_INTERVAL_SECONDS")"
  if [[ "$interval" -le 0 ]]; then
    return 0
  fi

  stop_terminal_progress_heartbeat "restart"
  (
    progress_sleep_pid=""
    trap '[[ -n "$progress_sleep_pid" ]] && kill "$progress_sleep_pid" >/dev/null 2>&1 || true; exit 0' INT TERM HUP
    while true; do
      sleep "$interval" &
      progress_sleep_pid="$!"
      wait "$progress_sleep_pid" || exit 0
      progress_sleep_pid=""

      now_epoch="$(date '+%s')"
      if [[ "$started_epoch" =~ ^[0-9]+$ && "$now_epoch" =~ ^[0-9]+$ ]]; then
        elapsed_seconds=$((now_epoch - started_epoch))
      else
        elapsed_seconds="unknown"
      fi
      if [[ -f "$transcript_file" ]]; then
        transcript_lines="$(wc -l <"$transcript_file" 2>/dev/null || printf 'unknown')"
        transcript_bytes="$(file_size_bytes "$transcript_file")"
        transcript_updated="$(date -r "$transcript_file" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf 'unknown')"
      else
        transcript_lines="missing"
        transcript_bytes="missing"
        transcript_updated="missing"
      fi
      printf '%s Upkeeper: %s still running target=%s elapsed=%ss transcript_lines=%s transcript_bytes=%s last_update=%s\n' \
        "$(timestamp_now)" \
        "$label" \
        "${target:-unknown}" \
        "$elapsed_seconds" \
        "$transcript_lines" \
        "$transcript_bytes" \
        "$transcript_updated" >&2
    done
  ) &
  RUN_TERMINAL_PROGRESS_PID="$!"
  log_line "INFO" "terminal_progress.start pid=$RUN_TERMINAL_PROGRESS_PID label=$label interval_seconds=$interval target=$(shell_quote "${target:-unknown}") transcript=$(shell_quote "$transcript_file")"
}

start_run_mark_heartbeat() {
  local interval="$CODEX_MARK_INTERVAL_SECONDS"
  if [[ "$interval" -le 0 ]]; then
    return 0
  fi
  emit_run_mark "start"
  RUN_MARK_HEARTBEAT_STARTED="1"
  (
    mark_sleep_pid=""
    trap '[[ -n "$mark_sleep_pid" ]] && kill "$mark_sleep_pid" >/dev/null 2>&1 || true; exit 0' INT TERM HUP
    while true; do
      sleep "$interval" &
      mark_sleep_pid="$!"
      wait "$mark_sleep_pid" || exit 0
      mark_sleep_pid=""
      emit_run_mark "heartbeat" >/dev/null
    done
  ) >/dev/null 2>&1 &
  RUN_MARK_HEARTBEAT_PID="$!"
  log_line "INFO" "mark_heartbeat.start pid=$RUN_MARK_HEARTBEAT_PID interval_seconds=$interval"
}

stop_run_mark_heartbeat() {
  local reason="${1:-stop}"
  if [[ "${RUN_MARK_HEARTBEAT_STARTED:-0}" != "1" ]]; then
    return 0
  fi
  if [[ "${RUN_MARK_HEARTBEAT_STOPPED:-0}" == "1" ]]; then
    return 0
  fi
  RUN_MARK_HEARTBEAT_STOPPED="1"
  if [[ -n "${RUN_MARK_HEARTBEAT_PID:-}" ]]; then
    kill "$RUN_MARK_HEARTBEAT_PID" >/dev/null 2>&1 || true
    wait "$RUN_MARK_HEARTBEAT_PID" 2>/dev/null || true
    RUN_MARK_HEARTBEAT_PID=""
    log_line "INFO" "mark_heartbeat.stop reason=$reason"
  fi
  emit_run_mark "finish"
}

write_startup_anomaly_gate_state() {
  local status="$1"
  local detail="${2:-}"
  local state_dir="$CODEX_STARTUP_ANOMALY_GATE_STATE_DIR"
  local state_path tmp_path now_epoch

  [[ -n "$state_dir" ]] || return 1
  if ! mkdir -p -- "$state_dir"; then
    log_line "ERROR" "startup_anomaly.gate_state_unwritable dir=$(shell_quote "$state_dir") reason=mkdir_failed"
    return 1
  fi

  if [[ -z "${STARTUP_ANOMALY_GATE_STATE_FILE:-}" ]]; then
    STARTUP_ANOMALY_GATE_STATE_FILE="$state_dir/$CYCLE_RUN_HASH.state"
  fi
  state_path="$STARTUP_ANOMALY_GATE_STATE_FILE"
  tmp_path="$state_path.tmp.$$"
  now_epoch="$(date '+%s')"

  if ! {
    printf 'cycle_id=%s\n' "$CYCLE_ID"
    printf 'run_hash=%s\n' "$CYCLE_RUN_HASH"
    printf 'self_path=%s\n' "$SELF_PATH"
    printf 'root_dir=%s\n' "$ROOT_DIR"
    printf 'reason=%s\n' "${STARTUP_ANOMALY_REASONS:-unknown}"
    printf 'status=%s\n' "$status"
    printf 'detail=%s\n' "${detail:-none}"
    printf 'created_epoch=%s\n' "$now_epoch"
    printf 'updated_epoch=%s\n' "$now_epoch"
  } >"$tmp_path"; then
    rm -f "$tmp_path"
    log_line "ERROR" "startup_anomaly.gate_state_unwritable path=$(shell_quote "$state_path") reason=write_failed"
    return 1
  fi
  if ! mv -f -- "$tmp_path" "$state_path"; then
    rm -f "$tmp_path"
    log_line "ERROR" "startup_anomaly.gate_state_unwritable path=$(shell_quote "$state_path") reason=rename_failed"
    return 1
  fi

  log_line "INFO" "startup_anomaly.gate_state status=$status path=$(shell_quote "$state_path") reasons=$(shell_quote "${STARTUP_ANOMALY_REASONS:-unknown}") detail=$(shell_quote "${detail:-none}")"
  return 0
}

mark_startup_anomaly_gate_states_resolved() {
  local state_dir="$CODEX_STARTUP_ANOMALY_GATE_STATE_DIR"
  [[ -d "$state_dir" ]] || return 0

  python3 - "$state_dir" "$CYCLE_ID" "$CYCLE_RUN_HASH" <<'PY' || true
from pathlib import Path
import sys
import time

root = Path(sys.argv[1])
cycle_id = sys.argv[2]
run_hash = sys.argv[3]
now = str(int(time.time()))

for path in root.glob("*.state"):
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        continue
    fields = {}
    order = []
    for line in lines:
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key not in fields:
            order.append(key)
        fields[key] = value
    if fields.get("status") != "unresolved":
        continue
    fields["status"] = "resolved"
    fields["resolved_by_cycle_id"] = cycle_id
    fields["resolved_by_run_hash"] = run_hash
    fields["updated_epoch"] = now
    for key in ("status", "resolved_by_cycle_id", "resolved_by_run_hash", "updated_epoch"):
        if key not in order:
            order.append(key)
    tmp = path.with_name(path.name + f".tmp.{run_hash}")
    try:
        tmp.write_text("".join(f"{key}={fields.get(key, '')}\n" for key in order), encoding="utf-8")
        tmp.replace(path)
    except OSError:
        try:
            tmp.unlink()
        except OSError:
            pass
PY
}

startup_anomaly_state_lines() {
  local state_dir="$CODEX_STARTUP_ANOMALY_GATE_STATE_DIR"
  [[ -d "$state_dir" ]] || return 0

  python3 - "$state_dir" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
items = []
for path in root.glob("*.state"):
    fields = {}
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        stat = path.stat()
    except OSError:
        continue
    for line in lines:
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key.strip()] = value.strip()
    if fields.get("status") != "unresolved":
        continue
    created = fields.get("created_epoch") or str(int(stat.st_mtime))
    cycle = fields.get("cycle_id") or "unknown"
    run_hash = fields.get("run_hash") or "unknown"
    reason = (fields.get("reason") or "unknown").replace("\t", " ")[:200]
    items.append((created, path, cycle, run_hash, reason))

for created, path, cycle, run_hash, reason in sorted(items, reverse=True)[:10]:
    print(
        f"previous_cycle={cycle} previous_run_hash={run_hash} "
        f"reason=startup_anomaly_gate_unresolved_state created_epoch={created} "
        f"state_file={path} state_reason={reason!r}"
    )
PY
}

# Create the tracked operator guide only when it is missing.
#
# The guide is meant to become repo- and operator-specific over time, so this
# function must never regenerate or "fix" an existing file. That avoids turning
# useful human notes into generated churn.
ensure_operator_guide() {
  [[ "$CODEX_OPERATOR_GUIDE_BOOTSTRAP" == "1" ]] || return 0

  local guide_path guide_dir tmp_file
  guide_path="$(resolved_operator_guide_path)"
  if [[ -e "$guide_path" ]]; then
    check_existing_operator_guide "$guide_path"
    return 0
  fi

  if operator_guide_is_ignored "$guide_path"; then
    log_line "INFO" "operator_guide.local_missing path=$guide_path current_version=$UPKEEPER_VERSION action=ignored_no_bootstrap"
    return 0
  fi

  guide_dir="${guide_path%/*}"
  if ! mkdir -p "$guide_dir"; then
    die "failed to create operator guide directory $guide_dir"
  fi
  if ! tmp_file="$(mktemp "$guide_dir/.upkeeper-guide.XXXXXX")"; then
    die "failed to create temporary operator guide under $guide_dir"
  fi
  {
    printf '# %s\n\n' "$SCRIPT_NAME"
    printf '> Bootstrap-generated by `%s` because `%s` was missing.\n\n' "$SCRIPT_NAME" "$guide_path"
    printf 'Keep this file as the repo-local living operator guide. The wrapper only creates it when missing; it does not overwrite future edits.\n\n'
    printf '## Script Help Snapshot\n\n'
    printf '```text\n'
    show_help
    printf '```\n\n'
    printf '## Repo-Local Living Notes\n\n'
    printf -- '- Record local relaunch conventions, recurring incident lessons, and environment-specific guardrail decisions here.\n'
    printf -- '- Keep transient run logs and generated postmortems under `runtime/`; promote only durable operating rules into this guide.\n'
  } >"$tmp_file"
  mv "$tmp_file" "$guide_path"
  log_line "INFO" "operator_guide.bootstrap path=$guide_path source=show_help"
}

# Every terminal path should end through this helper so the log has one obvious
# cycle.exit line with a reason and the exit code the outer loop will observe.
finish_cycle() {
  local exit_code="$1"
  local reason="$2"
  local level="$3"
  shift 3

  stop_terminal_progress_heartbeat "$reason"
  stop_run_mark_heartbeat "$reason"
  local message="cycle.exit exit_code=$exit_code reason=$reason"
  if [[ $# -gt 0 ]]; then
    message="$message $*"
  fi
  log_line "$level" "$message"
  finalize_wrapper_health_state "exited"
  release_active_lock
  exit "$exit_code"
}

cleanup_run_temp_files() {
  stop_terminal_progress_heartbeat "cleanup"
  stop_run_mark_heartbeat "cleanup"
  finalize_wrapper_health_state "aborted"
  release_active_lock
  if [[ -n "${RUN_COMPILED_PROMPT_FILE:-}" ]]; then
    rm -f "$RUN_COMPILED_PROMPT_FILE"
  fi
  if [[ -n "${RUN_LAST_MESSAGE_FILE:-}" ]]; then
    rm -f "$RUN_LAST_MESSAGE_FILE"
  fi
  if [[ -n "${RUN_TMP_DIR:-}" && "$RUN_TMP_DIR" == "${TMPDIR:-/tmp}"/upkeeper-* ]]; then
    find "$RUN_TMP_DIR" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
    rmdir "$RUN_TMP_DIR" 2>/dev/null || true
  fi
}

completed_fallback_screen_result_available() {
  local screen_root="$CODEX_POSTMORTEM_DIR/$CYCLE_ID/screen"
  local exit_file="$screen_root/final-exit-code.txt"
  local done_file="$screen_root/done.txt"

  [[ -n "${FALLBACK_SCREEN_SESSION_NAME:-}" ]] || return 1
  [[ -f "$done_file" && -f "$exit_file" ]] || return 1
}

fallback_screen_runner_process_groups() {
  local runner_script="$1"
  local pid pgid args

  [[ -n "$runner_script" ]] || return 0

  ps -eo pid=,pgid=,args= | while read -r pid pgid args; do
    [[ "$pid" =~ ^[0-9]+$ && "$pgid" =~ ^[0-9]+$ ]] || continue
    [[ "${args:-}" == *"$runner_script"* ]] || continue
    [[ "$pid" -eq "$$" ]] && continue
    printf '%s\n' "$pgid"
  done | sort -u
}

fallback_screen_process_group_exists() {
  local pgid="$1"

  [[ "$pgid" =~ ^[0-9]+$ ]] || return 1
  ps -eo pgid= | awk -v target="$pgid" '$1 == target { found = 1; exit } END { exit !found }'
}

terminate_fallback_screen_process_groups() {
  local reason="${1:-manual_teardown}"
  local runner_script="$CODEX_POSTMORTEM_DIR/$CYCLE_ID/screen/run-screen-fallback.sh"
  local pgid
  local -a pgids=()

  mapfile -t pgids < <(fallback_screen_runner_process_groups "$runner_script")
  [[ "${#pgids[@]}" -gt 0 ]] || return 0

  for pgid in "${pgids[@]}"; do
    [[ "$pgid" =~ ^[0-9]+$ ]] || continue
    log_line "WARN" "fallback.screen.stop execution_origin=$CODEX_EXECUTION_ORIGIN reason=$reason action=process_group_term pgid=$pgid runner_script=$(shell_quote "$runner_script")"
    kill -TERM -- "-$pgid" >/dev/null 2>&1 || true
  done

  sleep 1

  for pgid in "${pgids[@]}"; do
    [[ "$pgid" =~ ^[0-9]+$ ]] || continue
    if fallback_screen_process_group_exists "$pgid"; then
      log_line "WARN" "fallback.screen.stop execution_origin=$CODEX_EXECUTION_ORIGIN reason=$reason action=process_group_kill pgid=$pgid runner_script=$(shell_quote "$runner_script")"
      kill -KILL -- "-$pgid" >/dev/null 2>&1 || true
    fi
  done
}

adopt_completed_fallback_screen_result_on_signal() {
  local signal_name="$1"
  local screen_root="$CODEX_POSTMORTEM_DIR/$CYCLE_ID/screen"
  local exit_file="$screen_root/final-exit-code.txt"
  local child_exit current_child_id current_child_status completed_count last_cycle_exit stop_reason

  [[ "$CODEX_EXECUTION_ORIGIN" == "primary" ]] || return 1
  [[ "$FALLBACK_SCREEN_WATCH_ACTIVE" == "1" ]] || return 1
  completed_fallback_screen_result_available || return 1

  child_exit="$(tr -d '[:space:]' <"$exit_file")"
  case "$child_exit" in
    ''|*[!0-9]*)
      child_exit="8"
      ;;
  esac

  FALLBACK_SCREEN_EXIT_CODE="$child_exit"
  FALLBACK_SCREEN_WATCH_ACTIVE="0"
  current_child_id="$(read_artifact_or_unknown "$screen_root/current-child-cycle-id.txt")"
  current_child_status="$(read_artifact_or_unknown "$screen_root/current-child-status.txt")"
  completed_count="$(read_artifact_or_unknown "$screen_root/completed-child-count.txt")"
  last_cycle_exit="$(read_artifact_or_unknown "$screen_root/last-cycle-exit-code.txt")"
  stop_reason="$(read_artifact_or_unknown "$screen_root/stop-reason.txt")"
  log_line "WARN" "signal.completed_fallback_result signal=$signal_name execution_origin=$CODEX_EXECUTION_ORIGIN session_name=${FALLBACK_SCREEN_SESSION_NAME:-none} final_exit=$child_exit current_child_id=$current_child_id current_child_status=$current_child_status completed_children=$completed_count last_cycle_exit=$last_cycle_exit stop_reason=$stop_reason"
  teardown_fallback_screen_session "completed_result_$signal_name"
  finish_cycle "$child_exit" FALLBACK_CHILD_COMPLETED_BEFORE_SIGNAL WARN "signal=$signal_name fallback_screen_session=${FALLBACK_SCREEN_SESSION_NAME:-none} fallback_trigger=${FALLBACK_SCREEN_TRIGGER:-none} transcript=${FALLBACK_SCREEN_TRANSCRIPT_PATH:-none}"
}

# Signals usually mean the human is trying to stop the visible loop. If a
# detached fallback screen is active, leaving it behind would create a ghost
# worker that keeps spending quota, so the visible wrapper owns cleanup.
teardown_fallback_screen_session() {
  local reason="${1:-manual_teardown}"
  local session_name="${FALLBACK_SCREEN_SESSION_NAME:-}"

  if [[ -z "$session_name" ]]; then
    return 0
  fi

  if [[ "$UPKEEPER_DRY_RUN" == "1" ]]; then
    log_line "WARN" "fallback.screen.stop execution_origin=$CODEX_EXECUTION_ORIGIN session_name=$session_name reason=$reason dry_run=1"
    return 0
  fi

  if screen_session_exists "$session_name"; then
    log_line "WARN" "fallback.screen.stop execution_origin=$CODEX_EXECUTION_ORIGIN session_name=$session_name reason=$reason action=screen_quit"
    screen -S "$session_name" -X quit >/dev/null 2>&1 || true
    sleep 1
    terminate_fallback_screen_process_groups "$reason"
    return 0
  fi

  log_line "WARN" "fallback.screen.stop execution_origin=$CODEX_EXECUTION_ORIGIN session_name=$session_name reason=$reason status=already_gone"
  terminate_fallback_screen_process_groups "$reason"
  return 0
}

handle_wrapper_signal() {
  local signal_name="$1"
  trap - INT TERM HUP

  log_line "WARN" "signal.received signal=$signal_name execution_origin=$CODEX_EXECUTION_ORIGIN fallback_screen_session=${FALLBACK_SCREEN_SESSION_NAME:-none} fallback_screen_watch_active=$FALLBACK_SCREEN_WATCH_ACTIVE"

  if [[ "$CODEX_EXECUTION_ORIGIN" == "primary" && -n "${FALLBACK_SCREEN_SESSION_NAME:-}" ]]; then
    adopt_completed_fallback_screen_result_on_signal "$signal_name" || true
    teardown_fallback_screen_session "signal_$signal_name"
  fi

  finish_cycle 130 "SIGNAL_${signal_name}" WARN "execution_origin=$CODEX_EXECUTION_ORIGIN fallback_screen_session=${FALLBACK_SCREEN_SESSION_NAME:-none} fallback_screen_watch_active=$FALLBACK_SCREEN_WATCH_ACTIVE"
}

format_epoch_local() {
  local epoch="$1"
  if [[ -z "$epoch" || "$epoch" == "null" ]]; then
    printf 'unknown'
    return 0
  fi
  if [[ "$epoch" =~ ^[0-9]+([.][0-9]+)?$ ]] && date -d "@$epoch" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null; then
    return 0
  fi
  python3 - "$epoch" <<'PY' 2>/dev/null || printf '%s' "$epoch"
from datetime import datetime
import sys

try:
    epoch = int(float(sys.argv[1]))
except ValueError:
    raise SystemExit(1)

print(datetime.fromtimestamp(epoch).astimezone().strftime("%Y-%m-%dT%H:%M:%S%z"))
PY
}

json_field() {
  local json="$1"
  local path="$2"

  jq -r "$path // empty" <<<"$json" 2>/dev/null
}

emit_codex_transcript_summary() {
  local label="$1"
  local transcript_file="$2"
  local codex_exit="$3"
  local signal_lines="${CODEX_TRANSCRIPT_SIGNAL_LINES:-80}"
  local error_tail_lines="${CODEX_TRANSCRIPT_ERROR_TAIL_LINES:-120}"

  terminal_wants_full_output && return 0
  [[ -n "$transcript_file" && -f "$transcript_file" ]] || return 0

  python3 - "$label" "$transcript_file" "$codex_exit" "$signal_lines" "$error_tail_lines" "$LOG_FILE" "$CYCLE_ID" "$CYCLE_RUN_HASH" <<'PY'
from datetime import datetime, timezone
from pathlib import Path
import re
import sys

label, path_raw, exit_raw, signal_raw, tail_raw, log_raw, cycle_id, run_hash = sys.argv[1:9]
path = Path(path_raw)
log_path = Path(log_raw)
try:
    signal_limit = max(0, int(signal_raw))
except ValueError:
    signal_limit = 80
try:
    tail_limit = max(0, int(tail_raw))
except ValueError:
    tail_limit = 120
try:
    text = path.read_text(encoding='utf-8', errors='replace')
except OSError:
    print(f'Upkeeper: {label} transcript unavailable path={path}', file=sys.stderr)
    raise SystemExit(0)
lines = text.splitlines()

def ts():
    return datetime.now(timezone.utc).astimezone().strftime('%Y-%m-%dT%H:%M:%S%z')

def short(value: str, limit: int = 300) -> str:
    value = re.sub(r'\s+', ' ', value.strip())
    if len(value) > limit:
        return value[: limit - 15].rstrip() + '...<truncated>'
    return value

def field_value(value: str) -> str:
    return short(value).replace(' ', '\\ ')

promptish = re.compile(r'^(WRAPPER_|ABSOLUTE RULE|Background Review Prompt Repertoire|Summary Table|P\d+ - |-{8,}$|workdir: |model: |provider: |approval: |sandbox: |reasoning effort: |session id: |user$|hook: )')
contractish = re.compile(
    r'^(?:[-*] |\d+[.] |[|] ).*(UPKEEPER_STATUS|UPKEEPER_LOG_REVIEW|REVIEWED_AND_FIXED|REVIEWED_CLEAN|STOPPED_ON_BLOCKER|RUN_RESULT|rate limit|quota|failed)'
    r'|^(REVIEWED_AND_FIXED|REVIEWED_CLEAN|STOPPED_ON_BLOCKER|failed)$'
    r'|^RUN_RESULT=\{\{'
)
boilerplateish = re.compile(
    r'^(Check for wrapper/prompt/logging defects|If no anomalies were found|If anomalies were found|Report the review outcome|'
    r'If the review outcome|The literal final line|Do not emit UPKEEPER_STATUS|Wrapper control marker compatibility|'
    r'Current-cycle log self-review|Current-cycle Upkeeper log review found no anomalies|'
    r'The current-cycle log lines show .*no ERROR/WARN)'
)
diff_count = sum(1 for line in lines if line.startswith('diff --git '))
hook_count = sum(1 for line in lines if line.startswith('hook: '))
prompt_count = sum(1 for line in lines if promptish.search(line))

def is_prompt_or_contract(line: str) -> bool:
    stripped = line.strip()
    normalized = re.sub(r'^\s*(?:[-*]|\d+[.])\s+', '', stripped)
    if promptish.search(stripped) or contractish.search(stripped) or boilerplateish.search(normalized):
        return True
    if re.search(r'\bno ERROR/WARN\b|\bno ERROR\b|\bno WARN\b', normalized, re.I):
        return True
    return False

def is_signal(line: str) -> bool:
    if line.startswith(('UPKEEPER_STATUS:', 'UPKEEPER_LOG_REVIEW:')):
        return True
    if is_prompt_or_contract(line):
        return False
    if re.search(r'\[(WARN|ERROR)\]', line):
        return True
    if re.search(r'\b(cycle\.exit|cycle\.summary|status_marker|signal\.received)\b', line):
        return True
    if re.search(r'\b(Command blocked by PreToolUse hook|HTTP request failed|rmcp::|KeyboardInterrupt|interrupted)\b', line):
        return True
    if re.search(r'\bERROR\b', line) and not re.search(r'\b(add_error|JSON_PARSE_ERROR|INPUT_DECODE_ERROR|EXPORT_JSON_PARSE_ERROR)\b', line):
        return True
    if re.search(r'exited [1-9][0-9]* in ', line):
        return True
    if re.search(r'\bRate limit\b|\brate limit reached\b', line):
        return True
    return False

signals = [short(line) for line in lines if is_signal(line)]
summary = (
    f'codex.transcript.summary label={label} path={path} exit={exit_raw} lines={len(lines)} '
    f'diff_blocks={diff_count} hook_lines={hook_count} prompt_like_lines={prompt_count} signal_lines={len(signals)}'
)
log_lines = [f'{ts()} [INFO] cycle={cycle_id} run_hash={run_hash} {summary}']
for item in signals[-signal_limit:]:
    log_lines.append(f'{ts()} [INFO] cycle={cycle_id} run_hash={run_hash} codex.transcript.signal label={label} text={field_value(item)}')
try:
    with log_path.open('a', encoding='utf-8') as handle:
        for item in log_lines:
            handle.write(item + '\n')
except OSError:
    pass
print(f'Upkeeper: {label} transcript captured path={path} exit={exit_raw} lines={len(lines)} diff_blocks={diff_count} hook_lines={hook_count} prompt_like_lines={prompt_count}', file=sys.stderr)
if signals and signal_limit:
    print(f'Upkeeper: {label} high-signal transcript tail (last {min(signal_limit, len(signals))}):', file=sys.stderr)
    for line in signals[-signal_limit:]:
        print(f'  {line}', file=sys.stderr)
if exit_raw not in {'0', ''} and tail_limit:
    print(f'Upkeeper: {label} failure transcript tail (last {min(tail_limit, len(lines))} lines):', file=sys.stderr)
    for line in lines[-tail_limit:]:
        print(f'  {short(line)}', file=sys.stderr)
PY
}

codex_live_output_filter() {
  local label="$1"

  python3 - "$label" <<'PY'
from datetime import datetime, timezone
import os
import re
import sys

label = sys.argv[1]
verbosity = os.environ.get("CODEX_TERMINAL_VERBOSITY", "summary").lower()
silent = verbosity in {"none", "silent", "0", "no", "false"}

promptish = re.compile(
    r"^(WRAPPER_|ABSOLUTE RULE|Background Review Prompt Repertoire|Summary Table|P\d+ - |-{8,}$|"
    r"workdir: |model: |provider: |approval: |sandbox: |reasoning effort: |session id: |user$|hook: )"
)
boilerplateish = re.compile(
    r"^(Check for wrapper/prompt/logging defects|If no anomalies were found|If anomalies were found|Report the review outcome|"
    r"If the review outcome|The literal final line|Do not emit UPKEEPER_STATUS|Wrapper control marker compatibility|"
    r"Current-cycle log self-review|Current-cycle Upkeeper log review found no anomalies|"
    r"The current-cycle log lines show .*no ERROR/WARN)"
)
contractish = re.compile(
    r"^(?:[-*] |\d+[.] |[|] ).*(UPKEEPER_STATUS|UPKEEPER_LOG_REVIEW|REVIEWED_AND_FIXED|REVIEWED_CLEAN|STOPPED_ON_BLOCKER|RUN_RESULT|rate limit|quota|failed)"
    r"|^RUN_RESULT=\{\{"
)


def ts() -> str:
    return datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def short(value: str, limit: int = 260) -> str:
    value = re.sub(r"\s+", " ", value.strip())
    if len(value) > limit:
        return value[: limit - 15].rstrip() + "...<truncated>"
    return value


def is_prompt_or_contract(line: str) -> bool:
    stripped = line.strip()
    normalized = re.sub(r"^\s*(?:[-*]|\d+[.])\s+", "", stripped)
    if promptish.search(stripped) or contractish.search(stripped) or boilerplateish.search(normalized):
        return True
    if re.search(r"\bno ERROR/WARN\b|\bno ERROR\b|\bno WARN\b", normalized, re.I):
        return True
    return False


def is_error_line(line: str) -> bool:
    if not line or is_prompt_or_contract(line):
        return False
    patterns = (
        r"\[(?:WARN|ERROR)\]",
        r"\bERROR\b",
        r"\bWARN(?:ING)?\b",
        r"\bError:",
        r"\berror:",
        r"\berror=",
        r"\bfailed\b",
        r"\bTraceback\b",
        r"\bException\b",
        r"\bpanic\b",
        r"HTTP request failed",
        r"Command blocked by PreToolUse hook",
        r"rmcp::",
        r"exited [1-9][0-9]* in ",
        r"KeyboardInterrupt",
        r"interrupted",
    )
    if any(re.search(pattern, line) for pattern in patterns):
        if re.search(r"\b(add_error|JSON_PARSE_ERROR|INPUT_DECODE_ERROR|EXPORT_JSON_PARSE_ERROR)\b", line):
            return False
        return True
    return False


def command_kind(line: str) -> str:
    lowered = line.lower()
    if "pytest" in lowered or " test" in lowered or "/test" in lowered:
        return "tests"
    if "bash -n" in lowered or "--check" in lowered or "diff --check" in lowered:
        return "check"
    return "command"


def is_interesting_command(line: str) -> bool:
    lowered = line.lower()
    return any(
        token in lowered
        for token in (
            "pytest",
            " test",
            "/test",
            "bash -n",
            "--check",
            "diff --check",
            "python",
            "node",
            "npm",
            "make",
            "cargo",
            "go test",
            "ruff",
            "mypy",
            "shellcheck",
        )
    )


expecting_command = False
last_kind = "command"

for raw in sys.stdin:
    line = raw.rstrip("\r\n")
    stripped = line.strip()

    if stripped == "exec":
        expecting_command = True
        continue

    if expecting_command and stripped:
        expecting_command = False
        last_kind = command_kind(stripped)
        if not silent and is_interesting_command(stripped):
            print(f"{ts()} Upkeeper: {label} running {last_kind}: {short(stripped)}", file=sys.stderr, flush=True)
        continue

    if re.match(r"succeeded in [0-9]+", stripped):
        if not silent:
            print(f"{ts()} Upkeeper: {label} {last_kind} completed: {short(stripped)}", file=sys.stderr, flush=True)
        continue

    if re.match(r"exited [1-9][0-9]* in ", stripped):
        print(f"{ts()} Upkeeper: {label} ERROR {last_kind} failed: {short(stripped)}", file=sys.stderr, flush=True)
        continue

    if stripped.startswith(("UPKEEPER_STATUS:", "UPKEEPER_LOG_REVIEW:")):
        if not silent:
            print(f"{ts()} Upkeeper: {label} status: {short(stripped)}", file=sys.stderr, flush=True)
        continue

    if is_error_line(stripped):
        print(f"{ts()} Upkeeper: {label} ERROR: {short(stripped)}", file=sys.stderr, flush=True)
PY
}

