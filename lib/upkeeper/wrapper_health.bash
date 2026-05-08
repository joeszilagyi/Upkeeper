# Tracks active central-wrapper runs before the active lock is acquired. These
# state files let a later run distinguish a healthy peer from stale crash
# evidence without touching client repositories or spending backend quota.
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
import shlex
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


def log_value(value):
    return shlex.quote(str(value))


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
            f"status=healthy action=allow peer_cycle={log_value(cycle_id)} peer_run_hash={log_value(run_hash)} "
            f"peer_pid={log_value(pid)} last_mark_age_seconds={now - last_mark} state_file={log_value(path)}"
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
                f"status=reclaimed action=archive reason=pid_not_alive peer_cycle={log_value(cycle_id)} "
                f"peer_run_hash={log_value(run_hash)} peer_pid={log_value(pid or 'unknown')} last_mark_age_seconds={now - last_mark if last_mark else 'unknown'} "
                f"stale_seconds={stale_seconds} state_file={log_value(path)} archived_state_file={log_value(archived_path)}"
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
        f"status=quarantine action=fail_closed reason={reason} peer_cycle={log_value(cycle_id)} "
        f"peer_run_hash={log_value(run_hash)} peer_pid={log_value(pid or 'unknown')} last_mark_age_seconds={now - last_mark if last_mark else 'unknown'} "
        f"stale_seconds={stale_seconds} state_file={log_value(path)}"
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
