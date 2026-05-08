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
