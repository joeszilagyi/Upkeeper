previous_run_anomaly_lines_impl() {
  local current_boot_id current_boot_id_hash redaction_key

  if [[ ! -s "$LOG_FILE" ]]; then
    return 0
  fi

  current_boot_id="$(system_boot_id)"
  if declare -F upkeeper_value_hmac >/dev/null 2>&1; then
    current_boot_id_hash="$(upkeeper_value_hmac boot_id "$current_boot_id")"
  else
    current_boot_id_hash="$current_boot_id"
  fi
  if declare -F upkeeper_redaction_key_material >/dev/null 2>&1; then
    redaction_key="$(upkeeper_redaction_key_material)"
  else
    redaction_key="${ROOT_DIR:-$PWD}|upkeeper-redaction-fallback"
  fi

  UPKEEPER_PREVIOUS_RUN_REDACTION_KEY="$redaction_key" python3 - \
    "$LOG_FILE" \
    "$CYCLE_ID" \
    "$CODEX_PREVIOUS_RUN_SCAN_MINUTES" \
    "$current_boot_id" \
    "$current_boot_id_hash" <<'PY'
import datetime as dt
import hashlib
import hmac
import os
import re
import sys
import time

log_path, current_cycle, minutes_raw, current_boot_raw, current_boot_protected = sys.argv[1:6]
redaction_key = os.environ.get("UPKEEPER_PREVIOUS_RUN_REDACTION_KEY", "")
try:
    scan_minutes = max(0, int(minutes_raw))
except ValueError:
    scan_minutes = 240
cutoff = time.time() - (scan_minutes * 60)
cycle_re = re.compile(r"\bcycle=([^ \t\r\n]+)")
run_hash_re = re.compile(r"\brun_hash=([^ \t\r\n]+)")
boot_id_re = re.compile(r"\bboot_id=([^ \t\r\n]+)")
structured_log_re = re.compile(
    r"^[^ \t\r\n]+[ \t]+\[[A-Z]+\][ \t]+cycle=[^ \t\r\n]+(?:[ \t]|\r?\n|$)"
)
direct_custody_re = re.compile(
    r"^[^ \t\r\n]+[ \t]+(?:\u2588[ \t]+)?"
    r"(?:(?:--FYI--|[A-Z]+)[ \t]+)?"
    r"(?:\[[A-Z]+\][ \t]+)?"
    r"backlog:[ \t]+anomaly custody:[ \t]"
)
cycles = {}
latest_previous_run_ack_epoch = None
latest_previous_run_ack_reason = "previous_run_anomaly_gate_reviewed"
custody_ack_kinds = {
    "page_error",
    "previous_run_anomaly_summary",
    "startup_anomaly_unresolved",
}

def protected_boot_id(value):
    text = str(value or "unknown")
    if text in {"", "unknown", "none", "missing", "unavailable"}:
        return text or "unknown"
    if text.startswith("value-hmac-sha256:"):
        return text
    material = f"boot_id\0{text}".encode("utf-8", "surrogateescape")
    digest = hmac.new(
        redaction_key.encode("utf-8", "surrogateescape"),
        material,
        hashlib.sha256,
    ).hexdigest()
    return f"value-hmac-sha256:{digest}"


def boot_id_matches_current(value):
    text = str(value or "unknown")
    return text in {
        "",
        "unknown",
        current_boot_raw,
        current_boot_protected,
        protected_boot_id(current_boot_raw),
    }


def redact_boot_ids(text):
    return boot_id_re.sub(lambda match: f"boot_id={protected_boot_id(match.group(1))}", text)


def parsed_epoch(line):
    stamp = line.split(" ", 1)[0]
    for timestamp_format in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S"):
        try:
            parsed = dt.datetime.strptime(stamp, timestamp_format)
        except ValueError:
            continue
        # Backlog loop logs are operator-facing local time and omit the offset.
        # Treat those sanitized stamps as local so custody lines can acknowledge
        # older unresolved-gate evidence from the same log stream.
        if parsed.tzinfo is None:
            parsed = parsed.astimezone()
        return parsed.timestamp()
    return None


def is_structured_log_event(line):
    # Launcher attention rows can quote prior Upkeeper output after their own
    # marker column. Only raw Upkeeper structured events are trusted here.
    return bool(structured_log_re.match(line))


def direct_custody_payload(line):
    # Treat only direct backlog custody records as acknowledgments. A PAGE line
    # whose payload starts with "backlog:" is backlog's own paged custody row.
    # Worker rows use the same direct shape; echoed Upkeeper output includes
    # its own prefix before quoted payload and therefore fails this boundary.
    if not direct_custody_re.match(line):
        return None
    payload = line.split("anomaly custody:", 1)[1]
    return payload.split(" excerpt=", 1)[0]


def custody_field(payload, name):
    match = re.search(rf"(?:^|[ \t]){re.escape(name)}=([^ \t\r\n]+)", payload)
    if not match:
        return ""
    return match.group(1)

try:
    handle = open(log_path, "r", encoding="utf-8", errors="replace")
except OSError:
    raise SystemExit(0)

with handle:
    for line in handle:
        epoch = parsed_epoch(line)
        if epoch is not None and scan_minutes > 0 and epoch < cutoff:
            continue
        # A raw structured event must start with a parseable timestamp. This
        # keeps echoed snippets from spoofing prior-cycle control-plane rows.
        structured_event = epoch is not None and is_structured_log_event(line)
        if structured_event:
            if (
                epoch is not None
                and " startup_anomaly.gate_resolved " in line
                and "reasons=previous_run_anomaly" in line
            ):
                if latest_previous_run_ack_epoch is None or epoch > latest_previous_run_ack_epoch:
                    latest_previous_run_ack_epoch = epoch
                    latest_previous_run_ack_reason = "previous_run_anomaly_gate_reviewed"
        custody_payload = direct_custody_payload(line)
        if custody_payload is not None:
            if (
                epoch is not None
                and custody_field(custody_payload, "target") == "lib/upkeeper/previous_run_anomalies.bash"
                and custody_field(custody_payload, "kind") in custody_ack_kinds
            ):
                if latest_previous_run_ack_epoch is None or epoch > latest_previous_run_ack_epoch:
                    latest_previous_run_ack_epoch = epoch
                    latest_previous_run_ack_reason = "previous_run_anomaly_custody_recorded"
            continue
        if not structured_event:
            continue
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
        if boot_id_matches_current(info.get("last_boot_id", "unknown")):
            reason = "missing_cycle_exit"
        else:
            reason = "probable_reboot_or_power_loss"
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
    last_line = redact_boot_ids(info["last_line"]).replace("\\", "\\\\").replace("\t", " ")[:300]
    print(
        f"previous_cycle={cycle} previous_run_hash={info['run_hash']} "
        f"reason={reason} scan_minutes={scan_minutes} last_epoch={last_epoch} "
        f"previous_boot_id={protected_boot_id(info.get('last_boot_id', 'unknown'))} "
        f"current_boot_id={protected_boot_id(current_boot_raw)} "
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
        f"reason={latest_previous_run_ack_reason}"
    )
PY
}

previous_run_anomaly_lines() {
  previous_run_anomaly_lines_impl
}

previous_run_anomaly_details_enabled() {
  if declare -F terminal_wants_verbose_output >/dev/null 2>&1 && terminal_wants_verbose_output; then
    return 0
  fi
  if declare -F terminal_wants_full_output >/dev/null 2>&1 && terminal_wants_full_output; then
    return 0
  fi
  return 1
}

previous_run_anomaly_summary_line() {
  local anomaly_input
  anomaly_input="$(cat)"
  UPKEEPER_PREVIOUS_RUN_ANOMALY_INPUT="$anomaly_input" python3 - <<'PY'
import collections
import os
import re

lines = [line.rstrip("\n") for line in os.environ.get("UPKEEPER_PREVIOUS_RUN_ANOMALY_INPUT", "").splitlines() if line.strip()]


def field(line, name):
    match = re.search(rf"(?:^| ){re.escape(name)}=([^ ]+)", line)
    if not match:
        return ""
    return match.group(1)


def safe(value, fallback="unknown"):
    text = str(value or fallback)
    text = re.sub(r"[^A-Za-z0-9_.:@%+=,-]", "_", text)
    return text[:200] or fallback


cycle_count = 0
state_count = 0
reason_counts = collections.Counter()
epochs = []

for line in lines:
    is_state = "reason=startup_anomaly_gate_unresolved_state" in line or bool(field(line, "state_id"))
    if is_state:
        state_count += 1
        reason = field(line, "reason_class") or field(line, "reason") or "unknown"
        epoch = field(line, "updated_epoch") or field(line, "created_epoch")
    else:
        cycle_count += 1
        reason = field(line, "reason") or "unknown"
        epoch = field(line, "last_epoch")
    reason_counts[safe(reason)] += 1
    if epoch.isdecimal():
        epochs.append(int(epoch))

reason_text = ",".join(f"{key}={reason_counts[key]}" for key in sorted(reason_counts)) or "none"
oldest = str(min(epochs)) if epochs else "unknown"
newest = str(max(epochs)) if epochs else "unknown"
print(
    f"listed_total={len(lines)} "
    f"prior_cycle_count={cycle_count} "
    f"state_count={state_count} "
    f"reason_counts={reason_text} "
    f"oldest_epoch={oldest} "
    f"newest_epoch={newest} "
    "details=local_log_state_and_prompt "
    "action=force_upkeeper_self_review"
)
PY
}

scan_previous_run_anomalies() {
  local -a anomalies=()
  local -a state_anomalies=()
  local anomaly
  local detail_level summary_line
  PREVIOUS_RUN_ANOMALIES=""
  # Keep the scan path bound to this module's structured-line trust boundary.
  mapfile -t anomalies < <(previous_run_anomaly_lines_impl || true)
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

  summary_line="$(printf '%s\n' "${anomalies[@]}" | previous_run_anomaly_summary_line)"
  log_line "WARN" "previous_run.anomaly_summary scan_minutes=$CODEX_PREVIOUS_RUN_SCAN_MINUTES $summary_line boot_id=$(system_boot_id) uptime_seconds=$(system_uptime_seconds)"
  detail_level="INFO"
  if previous_run_anomaly_details_enabled; then
    detail_level="WARN"
  fi
  for anomaly in "${anomalies[@]}"; do
    [[ -n "$anomaly" ]] || continue
    log_line "$detail_level" "previous_run.anomaly_detail $anomaly boot_id=$(system_boot_id) uptime_seconds=$(system_uptime_seconds)"
    PREVIOUS_RUN_ANOMALIES+="- $anomaly"$'\n'
  done
  STARTUP_ANOMALY_GATE="1"
  append_startup_anomaly_reason "previous_run_anomaly"
}
