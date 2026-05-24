# Local operator status commands.
#
# These commands summarize existing wrapper evidence and never launch backend
# Codex, acquire the active run lock, or mutate runtime state.

upkeeper_operator_status_json() {
  local quota_json

  quota_json="$(quota_state_json "$CODEX_MODEL" 2>/dev/null || printf '{"error":"quota_state_failed"}')"
  python3 - \
    "$ROOT_DIR" \
    "$SELF_PATH" \
    "$SCRIPT_NAME" \
    "$UPKEEPER_VERSION" \
    "$CODEX_MODEL" \
    "$CODEX_REASONING_EFFORT" \
    "$CODEX_MODE" \
    "$UPKEEPER_CONFIG_LOADED" \
    "${UPKEEPER_CONFIG_SOURCE:-}" \
    "$LOG_FILE" \
    "$CODEX_ACTIVE_LOCK_DIR" \
    "$CODEX_TOOL_FAILURE_QUEUE_DIR" \
    "$UPKEEPER_OBLIGATION_DIR" \
    "$CODEX_HOME_DIR" \
    "$CODEX_WRAPPER_HEALTH_STATE_DIR" \
    "$quota_json" <<'PY'
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

(
    root_raw,
    self_path,
    script_name,
    version,
    model,
    effort,
    mode,
    config_loaded,
    config_source,
    log_file_raw,
    active_lock_raw,
    failure_queue_raw,
    obligation_root_raw,
    codex_home_raw,
    wrapper_health_raw,
    quota_json_raw,
) = sys.argv[1:17]

root = Path(root_raw).resolve()
log_file = Path(log_file_raw).expanduser()
active_lock = Path(active_lock_raw).expanduser()
failure_queue = Path(failure_queue_raw).expanduser()
obligation_root = Path(obligation_root_raw).expanduser()
codex_home = Path(codex_home_raw).expanduser()
wrapper_health = Path(wrapper_health_raw).expanduser()


def run_git(args):
    try:
        return subprocess.check_output(["git", *args], cwd=root, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""


def git_status():
    branch = run_git(["branch", "--show-current"]) or run_git(["rev-parse", "--abbrev-ref", "HEAD"]) or "unknown"
    head = run_git(["rev-parse", "--short=12", "HEAD"]) or "unknown"
    porcelain = run_git(["status", "--porcelain=v1"])
    dirty_paths = [line for line in porcelain.splitlines() if line.strip()]
    upstream = run_git(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]) or ""
    return {
        "root": str(root),
        "branch": branch,
        "head_sha": head,
        "upstream": upstream,
        "dirty": bool(dirty_paths),
        "dirty_path_count": len(dirty_paths),
    }


FIELD_RE = re.compile(r"(?:^| )([A-Za-z_][A-Za-z0-9_.-]*)=(?:'([^']*)'|\"([^\"]*)\"|([^ ]+))")


def fields_from_line(line):
    fields = {}
    for match in FIELD_RE.finditer(line):
        key = match.group(1)
        value = next((part for part in match.groups()[1:] if part is not None), "")
        fields[key] = value
    return fields


def read_log_tail(path, max_bytes=1024 * 1024):
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - max_bytes))
            data = handle.read()
    except OSError:
        return []
    text = data.decode("utf-8", errors="replace")
    lines = text.splitlines()
    if size > max_bytes and lines:
        lines = lines[1:]
    return lines


def last_run_from_log(path):
    lines = read_log_tail(path)
    selected = ""
    selected_re = re.compile(r"Upkeeper: selected file (.+?) \(")
    result = {
        "source": "missing",
        "timestamp": "",
        "cycle_id": "",
        "run_hash": "",
        "status_marker": "",
        "codex_exit": None,
        "exit_code": None,
        "finish_reason": "",
        "selected_target": "",
        "summary_line": "",
    }
    for line in lines:
        match = selected_re.search(line)
        if match:
            selected = match.group(1).strip()
        if "cycle.summary " in line or "cycle.exit " in line or "run.finish " in line:
            fields = fields_from_line(line)
            result["source"] = "log"
            result["timestamp"] = line.split(" ", 1)[0] if " " in line else ""
            result["cycle_id"] = fields.get("cycle", result["cycle_id"])
            result["run_hash"] = fields.get("run_hash", result["run_hash"])
            result["status_marker"] = fields.get("status_marker", result["status_marker"])
            result["finish_reason"] = fields.get("reason", fields.get("finish_reason", result["finish_reason"]))
            if "codex_exit" in fields:
                try:
                    result["codex_exit"] = int(fields["codex_exit"])
                except ValueError:
                    result["codex_exit"] = fields["codex_exit"]
            if "exit_code" in fields:
                try:
                    result["exit_code"] = int(fields["exit_code"])
                except ValueError:
                    result["exit_code"] = fields["exit_code"]
            result["summary_line"] = line[-500:]
    if selected:
        result["selected_target"] = selected
    return result


def count_json_files(path):
    try:
        return sum(1 for item in path.glob("*.json") if item.is_file())
    except OSError:
        return 0


def read_key_values(path):
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


def active_lock_status(path):
    state_file = path / "state"
    fields = read_key_values(state_file)
    pid = fields.get("pid", "")
    alive = pid.isdigit() and Path("/proc", pid).exists()
    return {
        "path": str(path),
        "present": path.exists(),
        "state_file_present": state_file.exists(),
        "status": fields.get("status", ""),
        "cycle_id": fields.get("cycle_id", ""),
        "run_hash": fields.get("run_hash", ""),
        "pid": pid,
        "pid_alive": alive,
    }


def quota_status(raw):
    def to_float(value):
        if value is None:
            return None
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {"target_model": model, "snapshot": "unavailable", "error": "invalid_quota_json"}
    if data.get("error"):
        return {"target_model": model, "snapshot": "missing", "error": data.get("error")}
    snapshot = data.get("snapshot") if isinstance(data.get("snapshot"), dict) else {}
    primary_used = snapshot.get("primary_used_percent")
    secondary_used = snapshot.get("secondary_used_percent")
    primary_used_float = to_float(primary_used)
    secondary_used_float = to_float(secondary_used)
    primary_left = None if primary_used_float is None else round(max(0.0, 100.0 - primary_used_float), 4)
    secondary_left = None if secondary_used_float is None else round(max(0.0, 100.0 - secondary_used_float), 4)
    return {
        "target_model": data.get("target_model", model),
        "snapshot": "found",
        "snapshot_selection": data.get("snapshot_selection", ""),
        "snapshot_current": data.get("snapshot_is_current"),
        "matching_snapshot_count": data.get("matching_snapshot_count"),
        "primary_used_percent": primary_used,
        "primary_left_percent": primary_left,
        "primary_window_minutes": snapshot.get("primary_window_minutes"),
        "primary_resets_at": snapshot.get("primary_resets_at"),
        "secondary_used_percent": secondary_used,
        "secondary_left_percent": secondary_left,
        "secondary_window_minutes": snapshot.get("secondary_window_minutes"),
        "secondary_resets_at": snapshot.get("secondary_resets_at"),
        "projection_basis": (data.get("projection") or {}).get("basis"),
        "source_path_sha256": hashlib.sha256(str(snapshot.get("source_path", "")).encode()).hexdigest()
        if snapshot.get("source_path")
        else "",
    }


def dependency_status():
    names = ("bash", "cat", "date", "git", "jq", "python3", "sed", "tail", "tee", "codex", "gh")
    return {name: "present" if shutil.which(name) else "missing" for name in names}


def backend_mode_status(raw):
    parts = raw.split()
    if parts == ["--sandbox", "workspace-write"] or parts == ["--sandbox", "read-only"]:
        return {"status": "ok", "sandbox": parts[1], "reason": ""}
    if any(part in ("danger-full-access", "--dangerously-bypass-approvals-and-sandbox") for part in parts):
        return {"status": "invalid", "sandbox": "", "reason": "unsafe_backend_sandbox"}
    return {"status": "invalid", "sandbox": "", "reason": "unsupported_backend_mode"}


tool_open = count_json_files(failure_queue / "open")
obligation_open = count_json_files(obligation_root / "open")
dependencies = dependency_status()
quota = quota_status(quota_json_raw)
lock = active_lock_status(active_lock)
backend_mode = backend_mode_status(mode)
findings = []
if dependencies.get("python3") != "present":
    findings.append("missing_python3")
if dependencies.get("jq") != "present":
    findings.append("missing_jq")
if dependencies.get("codex") != "present":
    findings.append("missing_codex")
if tool_open:
    findings.append("open_tool_failures")
if obligation_open:
    findings.append("open_automation_obligations")
if quota.get("snapshot") == "missing":
    findings.append("quota_snapshot_missing")
if backend_mode.get("status") != "ok":
    findings.append("invalid_backend_mode")

status = {
    "schema": "upkeeper.status.v1",
    "generated_epoch": int(time.time()),
    "wrapper": {
        "script_name": script_name,
        "version": version,
        "self_path": self_path,
        "model": model,
        "reasoning_effort": effort,
        "mode": mode,
        "backend_mode_status": backend_mode,
    },
    "repo": git_status(),
    "config": {
        "loaded": config_loaded == "1",
        "source": config_source or "none",
    },
    "runtime": {
        "log_file": str(log_file),
        "codex_home": str(codex_home),
        "session_store": str(codex_home / "sessions"),
        "wrapper_health_state_dir": str(wrapper_health),
        "active_lock": lock,
    },
    "last_run": last_run_from_log(log_file),
    "open_failures": {
        "tool_failure_count": tool_open,
        "automation_obligation_count": obligation_open,
        "total": tool_open + obligation_open,
    },
    "quota": quota,
    "dependencies": dependencies,
    "doctor": {
        "status": "degraded" if findings else "ok",
        "findings": findings,
    },
}
print(json.dumps(status, sort_keys=True, separators=(",", ":")))
PY
}

upkeeper_operator_status_print() {
  local command="$1"
  local status_json="$2"

  if [[ "$command" == "json-status" ]]; then
    printf '%s\n' "$status_json"
    return 0
  fi

  UPKEEPER_OPERATOR_STATUS_JSON="$status_json" python3 - "$command" <<'PY'
import json
import os
import sys
from datetime import datetime

command = sys.argv[1]
data = json.loads(os.environ["UPKEEPER_OPERATOR_STATUS_JSON"])


def fmt_epoch(value):
    if value in (None, "", "null"):
        return "unknown"
    try:
        return datetime.fromtimestamp(int(float(value))).astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")
    except Exception:
        return str(value)


def print_last_run():
    last = data["last_run"]
    print("Last run")
    print(f"  source: {last.get('source') or 'missing'}")
    print(f"  timestamp: {last.get('timestamp') or 'unknown'}")
    print(f"  cycle: {last.get('cycle_id') or 'unknown'}")
    print(f"  run hash: {last.get('run_hash') or 'unknown'}")
    print(f"  status marker: {last.get('status_marker') or 'unknown'}")
    print(f"  codex exit: {last.get('codex_exit') if last.get('codex_exit') is not None else 'unknown'}")
    print(f"  wrapper exit: {last.get('exit_code') if last.get('exit_code') is not None else 'unknown'}")
    print(f"  reason: {last.get('finish_reason') or 'unknown'}")
    print(f"  selected target: {last.get('selected_target') or 'unknown'}")


def print_open_failures():
    open_failures = data["open_failures"]
    print("Open local failures")
    print(f"  tool failure markers: {open_failures['tool_failure_count']}")
    print(f"  automation obligations: {open_failures['automation_obligation_count']}")
    print(f"  total: {open_failures['total']}")


def print_quota():
    quota = data["quota"]
    print("Quota")
    print(f"  target model: {quota.get('target_model') or 'unknown'}")
    print(f"  snapshot: {quota.get('snapshot') or 'unknown'}")
    if quota.get("error"):
        print(f"  error: {quota['error']}")
        return
    print(f"  snapshot current: {quota.get('snapshot_current')}")
    print(f"  matching snapshots: {quota.get('matching_snapshot_count')}")
    print(f"  primary used/left: {quota.get('primary_used_percent')}% / {quota.get('primary_left_percent')}%")
    print(f"  primary resets: {fmt_epoch(quota.get('primary_resets_at'))}")
    print(f"  secondary used/left: {quota.get('secondary_used_percent')}% / {quota.get('secondary_left_percent')}%")
    print(f"  secondary resets: {fmt_epoch(quota.get('secondary_resets_at'))}")
    print(f"  projection basis: {quota.get('projection_basis') or 'unknown'}")


def print_doctor():
    doctor = data["doctor"]
    deps = data["dependencies"]
    lock = data["runtime"]["active_lock"]
    print("Doctor")
    print(f"  status: {doctor['status']}")
    print(f"  findings: {', '.join(doctor['findings']) if doctor['findings'] else 'none'}")
    print(f"  active lock: {'present' if lock.get('present') else 'absent'}")
    if lock.get("present"):
        print(f"  active lock owner: pid={lock.get('pid') or 'unknown'} alive={lock.get('pid_alive')}")
    print("  dependencies:")
    for key in sorted(deps):
        print(f"    {key}: {deps[key]}")


def print_status():
    repo = data["repo"]
    wrapper = data["wrapper"]
    config = data["config"]
    print("Upkeeper status")
    print(f"  version: {wrapper['version']}")
    print(f"  model: {wrapper['model']} / {wrapper['reasoning_effort']}")
    print(f"  repo: {repo['branch']} {repo['head_sha']} dirty={repo['dirty']} dirty_paths={repo['dirty_path_count']}")
    print(f"  config: {'loaded' if config['loaded'] else 'not loaded'} ({config['source']})")
    print_last_run()
    print_open_failures()
    print_quota()
    print_doctor()


if command == "last-run":
    print_last_run()
elif command == "open-failures":
    print_open_failures()
elif command == "quota-status":
    print_quota()
elif command == "doctor":
    print_doctor()
else:
    print_status()
PY
}

upkeeper_operator_status_dispatch() {
  local command="$1"
  local status_json

  status_json="$(upkeeper_operator_status_json)"
  upkeeper_operator_status_print "$command" "$status_json"
}
