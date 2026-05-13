# Startup-anomaly gate state helpers.
#
# The wrapper writes these local state files when a prior cycle needs the next
# run to inspect Upkeeper itself before normal target selection. The reader keeps
# malformed or operator-edited state files from corrupting parseable log fields.
startup_anomaly_redaction_key_material() {
  if declare -F upkeeper_redaction_key_material >/dev/null 2>&1; then
    upkeeper_redaction_key_material
  else
    printf '%s' "${UPKEEPER_REDACTION_KEY:-startup-anomaly-test-key}"
  fi
}

startup_anomaly_path_hmac() {
  local value="$1"

  if declare -F upkeeper_path_hmac >/dev/null 2>&1; then
    upkeeper_path_hmac "$value"
    return 0
  fi
  printf 'path-hmac-sha256:%s' "$(python3 - "${UPKEEPER_REDACTION_KEY:-startup-anomaly-test-key}" "$value" <<'PY' 2>/dev/null || printf 'unknown'
import hashlib
import hmac
import sys

key, value = sys.argv[1:3]
print(hmac.new(key.encode("utf-8", "surrogateescape"), f"path\0{value}".encode("utf-8", "surrogateescape"), hashlib.sha256).hexdigest())
PY
)"
}

write_startup_anomaly_gate_state() {
  local status="$1"
  local detail="${2:-}"
  local state_dir="$CODEX_STARTUP_ANOMALY_GATE_STATE_DIR"
  local state_path tmp_path now_epoch detail_class reasons_class

  [[ -n "$state_dir" ]] || return 1
  if ! mkdir -p -- "$state_dir"; then
    log_line "ERROR" "startup_anomaly.gate_state_unwritable dir=$(shell_quote "$state_dir") reason=mkdir_failed"
    return 1
  fi

  STARTUP_ANOMALY_GATE_STATE_FILE="$state_dir/$CYCLE_RUN_HASH.state"
  state_path="$STARTUP_ANOMALY_GATE_STATE_FILE"
  tmp_path="$state_path.tmp.$$"
  now_epoch="$(date '+%s')"

  if ! {
    printf 'cycle_id=%s\n' "$CYCLE_ID"
    printf 'run_hash=%s\n' "$CYCLE_RUN_HASH"
    printf 'self_path=%s\n' "$SELF_PATH"
    printf 'root_dir=%s\n' "$ROOT_DIR"
    printf 'status=%s\n' "$status"
    printf 'reason=%s\n' "${detail:-none}"
    printf 'active_reasons=%s\n' "${STARTUP_ANOMALY_REASONS:-unknown}"
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

  detail_class="${detail:-none}"
  detail_class="${detail_class//[^A-Za-z0-9_.-]/_}"
  reasons_class="${STARTUP_ANOMALY_REASONS:-unknown}"
  reasons_class="${reasons_class//[^A-Za-z0-9_.-,]/_}"
  log_line "INFO" "startup_anomaly.gate_state status=$status path_hmac=$(startup_anomaly_path_hmac "$state_path") reasons_class=$(shell_quote "$reasons_class") detail_class=$(shell_quote "$detail_class") detail_redacted=1"
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
  local hmac_key
  [[ -d "$state_dir" ]] || return 0

  hmac_key="$(startup_anomaly_redaction_key_material)"
  python3 - "$state_dir" "$hmac_key" <<'PY'
from pathlib import Path
import hashlib
import hmac
import string
import sys

root = Path(sys.argv[1])
hmac_key = sys.argv[2].encode("utf-8", "surrogateescape")
items = []

LOG_FIELD_SAFE = set(string.ascii_letters + string.digits + "/._-:@%+=,")


def log_field(value, fallback="unknown", max_len=200):
    text = "" if value is None else str(value)
    text = " ".join(text.strip().split())
    if not text:
        text = fallback
    text = text[:max_len]
    return "".join(ch if ch in LOG_FIELD_SAFE else "\\" + ch for ch in text)


def normalized_epoch(value, fallback):
    text = "" if value is None else str(value).strip()
    if text.isdecimal() and len(text) <= 16:
        return int(text), text
    fallback_epoch = int(fallback)
    return fallback_epoch, str(fallback_epoch)


def hmac_value(namespace, value):
    material = f"{namespace}\0{value}".encode("utf-8", "surrogateescape")
    return hmac.new(hmac_key, material, hashlib.sha256).hexdigest()


def reason_class(value):
    text = "" if value is None else str(value).strip().lower()
    text = "".join(ch if ch in string.ascii_lowercase + string.digits + "_-" else "_" for ch in text)
    text = "_".join(token for token in text.split("_") if token)
    return text[:80] or "unknown"


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
    created_sort, created = normalized_epoch(fields.get("created_epoch"), stat.st_mtime)
    _, updated = normalized_epoch(fields.get("updated_epoch"), stat.st_mtime)
    state_id = "state-hmac-sha256:" + hmac_value("startup_state", path.name)
    state_file_hmac = "path-hmac-sha256:" + hmac_value("path", str(path))
    reason = reason_class(fields.get("reason") or fields.get("active_reasons"))
    items.append((created_sort, created, updated, state_id, state_file_hmac, reason))

for _, created, updated, state_id, state_file_hmac, reason in sorted(items, reverse=True)[:10]:
    print(
        f"reason=startup_anomaly_gate_unresolved_state state_id={state_id} "
        f"reason_class={reason} created_epoch={created} updated_epoch={updated} "
        f"state_file_hmac={state_file_hmac} detail_redacted=1"
    )
PY
}

startup_anomaly_gate_has_unresolved_state() {
  local state_dir="$CODEX_STARTUP_ANOMALY_GATE_STATE_DIR"
  local reasons_csv="$1"
  local reasons_py output

  [[ -d "$state_dir" ]] || return 1
  [[ -n "$reasons_csv" ]] || reasons_csv="unknown"

  reasons_py="$(printf '%s' "$reasons_csv")"
  output="$(python3 - "$state_dir" "$reasons_py" <<'PY'
import sys
from pathlib import Path


root = Path(sys.argv[1])
raw_reasons = (sys.argv[2] or "").strip()
target_reasons = {token for token in raw_reasons.split(",") if token}

for path in root.glob("*.state"):
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        continue
    fields = {}
    for line in lines:
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key.strip()] = value.strip()
    if fields.get("status") != "unresolved":
        continue
    if not target_reasons:
        print("1")
        raise SystemExit(0)
    reasons = {token for token in str(fields.get("active_reasons", fields.get("reason", ""))).split(",") if token}
    if reasons.intersection(target_reasons):
        print("1")
        raise SystemExit(0)

print("0")
PY
)"

  if [[ "$output" == "1" ]]; then
    return 0
  fi
  return 1
}
