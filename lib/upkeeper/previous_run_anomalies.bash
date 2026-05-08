previous_run_anomaly_lines() {
  if [[ ! -s "$LOG_FILE" ]]; then
    return 0
  fi

  python3 - "$LOG_FILE" "$CYCLE_ID" "$CODEX_PREVIOUS_RUN_SCAN_MINUTES" "$(system_boot_id)" <<'PY'
import datetime as dt
import re
import sys
import time

log_path, current_cycle, minutes_raw, current_boot_id = sys.argv[1:5]
try:
    scan_minutes = max(0, int(minutes_raw))
except ValueError:
    scan_minutes = 240
cutoff = time.time() - (scan_minutes * 60)
cycle_re = re.compile(r"\bcycle=([^ ]+)")
run_hash_re = re.compile(r"\brun_hash=([^ ]+)")
boot_id_re = re.compile(r"\bboot_id=([^ ]+)")
cycles = {}
latest_previous_run_ack_epoch = None

def parsed_epoch(line):
    stamp = line.split(" ", 1)[0]
    try:
        return dt.datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%S%z").timestamp()
    except ValueError:
        return None

try:
    handle = open(log_path, "r", encoding="utf-8", errors="replace")
except OSError:
    raise SystemExit(0)

with handle:
    for line in handle:
        epoch = parsed_epoch(line)
        if epoch is not None and scan_minutes > 0 and epoch < cutoff:
            continue
        if (
            epoch is not None
            and " startup_anomaly.gate_resolved " in line
            and "reasons=previous_run_anomaly" in line
        ):
            if latest_previous_run_ack_epoch is None or epoch > latest_previous_run_ack_epoch:
                latest_previous_run_ack_epoch = epoch
        cycle_match = cycle_re.search(line)
        if not cycle_match:
            continue
        cycle = cycle_match.group(1)
        if cycle == current_cycle:
            continue
        info = cycles.setdefault(
            cycle,
            {
                "run_hash": "unknown",
                "start": False,
                "exit": False,
                "run_start": False,
                "run_finish": False,
                "gate_unresolved": False,
                "gate_resolved": False,
                "watchdog_anomaly": False,
                "last_boot_id": "unknown",
                "last_epoch": epoch,
                "last_line": line.strip(),
            },
        )
        hash_match = run_hash_re.search(line)
        if hash_match:
            info["run_hash"] = hash_match.group(1)
        boot_id_match = boot_id_re.search(line)
        if boot_id_match:
            info["last_boot_id"] = boot_id_match.group(1)
        if " cycle.start " in line:
            info["start"] = True
        if " cycle.exit " in line:
            info["exit"] = True
        if " run.start " in line:
            info["run_start"] = True
        if " run.finish " in line:
            info["run_finish"] = True
        if " startup_anomaly.gate_unresolved " in line:
            info["gate_unresolved"] = True
        if " startup_anomaly.gate_resolved " in line:
            info["gate_resolved"] = True
        if " watchdog.anomaly " in line:
            info["watchdog_anomaly"] = True
        info["last_epoch"] = epoch
        info["last_line"] = line.strip()

printed = 0
acknowledged = 0
for cycle, info in sorted(cycles.items(), key=lambda item: item[1]["last_epoch"] or 0, reverse=True):
    reason = ""
    if info["start"] and not info["exit"]:
        if (
            info.get("last_boot_id", "unknown") not in {"", "unknown"}
            and current_boot_id not in {"", "unknown"}
            and info["last_boot_id"] != current_boot_id
        ):
            reason = "probable_reboot_or_power_loss"
        else:
            reason = "missing_cycle_exit"
    elif info["run_start"] and not info["run_finish"] and not info["exit"]:
        reason = "missing_run_finish"
    elif info["watchdog_anomaly"]:
        reason = "watchdog_anomaly"
    elif info["gate_unresolved"] and not info["gate_resolved"]:
        reason = "startup_anomaly_gate_unresolved"
    if not reason:
        continue
    if (
        latest_previous_run_ack_epoch is not None
        and info["last_epoch"] is not None
        and info["last_epoch"] <= latest_previous_run_ack_epoch
    ):
        acknowledged += 1
        continue
    last_epoch = "unknown" if info["last_epoch"] is None else str(int(info["last_epoch"]))
    last_line = info["last_line"].replace("\\", "\\\\").replace("\t", " ")[:300]
    print(
        f"previous_cycle={cycle} previous_run_hash={info['run_hash']} "
        f"reason={reason} scan_minutes={scan_minutes} last_epoch={last_epoch} "
        f"previous_boot_id={info.get('last_boot_id', 'unknown')} current_boot_id={current_boot_id} "
        f"last_line={last_line!r}"
    )
    printed += 1
    if printed >= 10:
        break
if acknowledged:
    print(
        "__ACK__ "
        f"suppressed={acknowledged} "
        f"ack_epoch={int(latest_previous_run_ack_epoch)} "
        "reason=previous_run_anomaly_gate_reviewed"
    )
PY
}

scan_previous_run_anomalies() {
  local -a anomalies=()
  local -a state_anomalies=()
  local anomaly
  PREVIOUS_RUN_ANOMALIES=""
  mapfile -t anomalies < <(previous_run_anomaly_lines || true)
  mapfile -t state_anomalies < <(startup_anomaly_state_lines || true)
  anomalies+=("${state_anomalies[@]}")
  local -a active_anomalies=()
  for anomaly in "${anomalies[@]}"; do
    [[ -n "$anomaly" ]] || continue
    if [[ "$anomaly" == "__ACK__ "* ]]; then
      log_line "INFO" "previous_run.acknowledged ${anomaly#__ACK__ } boot_id=$(system_boot_id) uptime_seconds=$(system_uptime_seconds)"
      continue
    fi
    active_anomalies+=("$anomaly")
  done
  anomalies=("${active_anomalies[@]}")
  if [[ "${#anomalies[@]}" -eq 0 ]]; then
    log_line "INFO" "previous_run.scan status=clean scan_minutes=$CODEX_PREVIOUS_RUN_SCAN_MINUTES boot_id=$(system_boot_id) uptime_seconds=$(system_uptime_seconds)"
    return 0
  fi

  for anomaly in "${anomalies[@]}"; do
    [[ -n "$anomaly" ]] || continue
    log_line "WARN" "previous_run.anomaly $anomaly boot_id=$(system_boot_id) uptime_seconds=$(system_uptime_seconds)"
    PREVIOUS_RUN_ANOMALIES+="- $anomaly"$'\n'
  done
  STARTUP_ANOMALY_GATE="1"
  append_startup_anomaly_reason "previous_run_anomaly"
}
