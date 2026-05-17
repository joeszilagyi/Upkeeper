# Startup-anomaly gate state helpers.
#
# The wrapper writes these local state files when a prior cycle needs the next
# run to inspect Upkeeper itself before normal target selection. State files are
# treated as security-sensitive control inputs; readers ignore untrusted records and
# only trust files that are owned, private, and cryptographically signed.
startup_anomaly_redaction_key_material() {
  if declare -F upkeeper_redaction_key_material >/dev/null 2>&1; then
    upkeeper_redaction_key_material
  elif [[ -n "${UPKEEPER_REDACTION_KEY:-}" ]]; then
    printf '%s' "$UPKEEPER_REDACTION_KEY"
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

startup_anomaly_state_signature() {
  local text="$1"
  local key="${2:-}"

  if [[ -z "$text" || -z "$key" ]]; then
    printf '%s\n' unknown
    return 1
  fi

  python3 - "$key" "$text" <<'PY' 2>/dev/null || printf '%s\n' unknown
import hashlib
import hmac
import sys

key = sys.argv[1].encode("utf-8", "surrogateescape")
text = sys.argv[2] if len(sys.argv) > 2 else ""
material = f"startup_anomaly_state\0{text}".encode("utf-8", "surrogateescape")
print(hmac.new(key, material, hashlib.sha256).hexdigest())
PY
}

startup_anomaly_state_dir_contains_symlink_component() {
  local path="$1"
  local candidate

  candidate="$path"
  while [[ -n "$candidate" && "$candidate" != "/" && "$candidate" != "." ]]; do
    if [[ -L "$candidate" ]]; then
      return 0
    fi
    candidate="$(dirname -- "$candidate")"
  done
  return 1
}

startup_anomaly_validate_private_state_dir() {
  local state_dir="$1"
  local owner mode

  if [[ -z "$state_dir" ]]; then
    return 1
  fi
  if [[ ! -d "$state_dir" ]]; then
    return 1
  fi
  if startup_anomaly_state_dir_contains_symlink_component "$state_dir"; then
    return 1
  fi
  if ! chmod 700 "$state_dir"; then
    return 1
  fi
  owner="$(stat -Lc '%u' -- "$state_dir" 2>/dev/null || printf '')"
  if [[ "$owner" != "$(id -u)" ]]; then
    return 1
  fi
  mode="$(stat -Lc '%a' -- "$state_dir" 2>/dev/null || printf '000')"
  if [[ "$mode" != "700" ]]; then
    return 1
  fi
  return 0
}

startup_anomaly_prepare_private_state_dir() {
  local state_dir="$1"

  if [[ -z "$state_dir" ]]; then
    return 1
  fi
  if ! mkdir -p -- "$state_dir"; then
    return 1
  fi
  startup_anomaly_validate_private_state_dir "$state_dir"
}

write_startup_anomaly_gate_state() {
  local status="$1"
  local detail="${2:-}"
  local state_dir="$CODEX_STARTUP_ANOMALY_GATE_STATE_DIR"
  local state_path tmp_path now_epoch detail_class reasons_class
  local state_payload state_signature hmac_key

  [[ -n "$state_dir" ]] || return 1
  if ! startup_anomaly_prepare_private_state_dir "$state_dir"; then
    log_line "ERROR" "startup_anomaly.gate_state_unwritable dir=$(shell_quote "$state_dir") reason=invalid_private_state_dir"
    return 1
  fi

  STARTUP_ANOMALY_GATE_STATE_FILE="$state_dir/$CYCLE_RUN_HASH.state"
  state_path="$STARTUP_ANOMALY_GATE_STATE_FILE"
  tmp_path="$state_path.tmp.$$"
  now_epoch="$(date '+%s')"
  hmac_key="$(startup_anomaly_redaction_key_material)"

  state_payload="$(
    printf 'active_reasons=%s\n' "${STARTUP_ANOMALY_REASONS:-unknown}"
    printf 'created_epoch=%s\n' "$now_epoch"
    printf 'cycle_id=%s\n' "$CYCLE_ID"
    printf 'detail=%s\n' "${detail:-none}"
    printf 'reason=%s\n' "${detail:-none}"
    printf 'root_dir=%s\n' "$ROOT_DIR"
    printf 'run_hash=%s\n' "$CYCLE_RUN_HASH"
    printf 'self_path=%s\n' "$SELF_PATH"
    printf 'state_path=%s\n' "$state_path"
    printf 'status=%s\n' "$status"
    printf 'updated_epoch=%s\n' "$now_epoch"
  )"
  state_signature="$(startup_anomaly_state_signature "${state_payload}"$'\n' "$hmac_key")"
  if [[ "$state_signature" == "unknown" ]]; then
    log_line "ERROR" "startup_anomaly.gate_state_unwritable path=$(shell_quote "$state_path") reason=signature_failed"
    return 1
  fi

  if ! {
    printf '%s\n' "$state_payload"
    printf 'state_signature=%s\n' "$state_signature"
  } >"$tmp_path"; then
    rm -f "$tmp_path"
    log_line "ERROR" "startup_anomaly.gate_state_unwritable path=$(shell_quote "$state_path") reason=write_failed"
    return 1
  fi
  if ! chmod 600 "$tmp_path"; then
    rm -f "$tmp_path"
    log_line "ERROR" "startup_anomaly.gate_state_unwritable path=$(shell_quote "$state_path") reason=chmod_failed"
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
  local hmac_key

  [[ -d "$state_dir" ]] || return 0
  if ! startup_anomaly_validate_private_state_dir "$state_dir"; then
    return 0
  fi
  hmac_key="$(startup_anomaly_redaction_key_material)"

  python3 - "$state_dir" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$hmac_key" <<'PY' || true
from hashlib import sha256
from hmac import compare_digest, new as hmac_new
from pathlib import Path
import os
import sys
import time

root = Path(sys.argv[1])
cycle_id = sys.argv[2]
run_hash = sys.argv[3]
secret = sys.argv[4].encode("utf-8", "surrogateescape")
now = str(int(time.time()))


def signature_payload(fields):
    return "".join(f"{key}={fields.get(key, '')}\n" for key in sorted(fields) if key != "state_signature")


def compute_signature(fields):
    payload = signature_payload(fields)
    material = f"startup_anomaly_state\0{payload}".encode("utf-8", "surrogateescape")
    return hmac_new(secret, material, sha256).hexdigest()


def valid_signature(fields):
    signature = fields.get("state_signature", "")
    if not signature:
        return False
    return compare_digest(signature, compute_signature(fields))


def read_fields(path):
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        stat = path.stat()
    except OSError:
        return None

    if path.is_symlink():
        return None
    if stat.st_uid != os.getuid():
        return None
    if (stat.st_mode & 0o777) != 0o600:
        return None

    fields = {}
    for line in lines:
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key.strip()] = value.strip()

    if not valid_signature(fields):
        return None
    return fields


for path in root.glob("*.state"):
    fields = read_fields(path)
    if not fields:
        continue
    if fields.get("status") != "unresolved":
        continue
    fields["status"] = "resolved"
    fields["resolved_by_cycle_id"] = cycle_id
    fields["resolved_by_run_hash"] = run_hash
    fields["updated_epoch"] = now
    fields["state_signature"] = compute_signature(fields)

    payload = "".join(f"{key}={fields.get(key, '')}\n" for key in sorted(fields))
    tmp = path.with_name(path.name + f".tmp.{run_hash}")
    try:
        tmp.write_text(payload, encoding="utf-8")
        tmp.chmod(0o600)
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
  if ! startup_anomaly_validate_private_state_dir "$state_dir"; then
    return 0
  fi

  hmac_key="$(startup_anomaly_redaction_key_material)"
  python3 - "$state_dir" "$hmac_key" <<'PY'
from hashlib import sha256
from hmac import compare_digest, new as hmac_new
from pathlib import Path
import os
import string
import sys

root = Path(sys.argv[1])
secret = sys.argv[2].encode("utf-8", "surrogateescape")
items = []


def normalized_epoch(value, fallback):
    text = "" if value is None else str(value).strip()
    if text.isdecimal() and len(text) <= 16:
        return int(text), text
    fallback_epoch = int(fallback)
    return fallback_epoch, str(fallback_epoch)


def reason_class(value):
    text = "" if value is None else str(value).strip().lower()
    text = "".join(ch if ch in string.ascii_lowercase + string.digits + "_-" else "_" for ch in text)
    text = "_".join(token for token in text.split("_") if token)
    return text[:80] or "unknown"


def signature_payload(fields):
    return "".join(f"{key}={fields.get(key, '')}\n" for key in sorted(fields) if key != "state_signature")


def compute_signature(fields):
    payload = signature_payload(fields)
    material = f"startup_anomaly_state\0{payload}".encode("utf-8", "surrogateescape")
    return hmac_new(secret, material, sha256).hexdigest()


def read_fields(path):
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        stat = path.stat()
    except OSError:
        return None

    if path.is_symlink():
        return None
    if stat.st_uid != os.getuid():
        return None
    if (stat.st_mode & 0o777) != 0o600:
        return None

    fields = {}
    for line in lines:
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key.strip()] = value.strip()
    signature = fields.get("state_signature", "")
    if not signature:
        return None
    if not compare_digest(signature, compute_signature(fields)):
        return None
    return fields, stat


for path in root.glob("*.state"):
    result = read_fields(path)
    if not result:
        continue
    fields, stat = result
    if fields.get("status") != "unresolved":
        continue
    created_sort, created = normalized_epoch(fields.get("created_epoch"), stat.st_mtime)
    _, updated = normalized_epoch(fields.get("updated_epoch"), stat.st_mtime)
    state_id = "state-hmac-sha256:" + hmac_new(secret, f"startup_state\0{path.name}".encode("utf-8", "surrogateescape"), sha256).hexdigest()
    state_file_hmac = "path-hmac-sha256:" + hmac_new(secret, f"path\0{path}".encode("utf-8", "surrogateescape"), sha256).hexdigest()
    reason = reason_class(fields.get("reason") or fields.get("active_reasons"))
    items.append((created_sort, created, updated, state_id, state_file_hmac, reason, fields.get("state_signature", "")))

for _, created, updated, state_id, state_file_hmac, reason, _ in sorted(items, reverse=True)[:10]:
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
  local reasons_py output hmac_key

  [[ -d "$state_dir" ]] || return 1
  if ! startup_anomaly_validate_private_state_dir "$state_dir"; then
    return 1
  fi
  [[ -n "$reasons_csv" ]] || reasons_csv="unknown"

  reasons_py="$(printf '%s' "$reasons_csv")"
  hmac_key="$(startup_anomaly_redaction_key_material)"
  output="$(python3 - "$state_dir" "$reasons_py" "$hmac_key" <<'PY'
from hashlib import sha256
from hmac import compare_digest, new as hmac_new
from pathlib import Path
from os import getuid
import os
import sys


root = Path(sys.argv[1])
raw_reasons = (sys.argv[2] or "").strip()
secret = sys.argv[3].encode("utf-8", "surrogateescape")
target_reasons = {token for token in raw_reasons.split(",") if token}


def signature_payload(fields):
    return "".join(f"{key}={fields.get(key, '')}\n" for key in sorted(fields) if key != "state_signature")


def compute_signature(fields):
    payload = signature_payload(fields)
    material = f"startup_anomaly_state\0{payload}".encode("utf-8", "surrogateescape")
    return hmac_new(secret, material, sha256).hexdigest()


def read_fields(path):
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        stat = path.stat()
    except OSError:
        return None

    if path.is_symlink():
        return None
    if stat.st_uid != getuid():
        return None
    if (stat.st_mode & 0o777) != 0o600:
        return None

    fields = {}
    for line in lines:
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key.strip()] = value.strip()
    signature = fields.get("state_signature", "")
    if not signature:
        return None
    if not compare_digest(signature, compute_signature(fields)):
        return None
    return fields


for path in root.glob("*.state"):
    fields = read_fields(path)
    if not fields:
        continue
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
