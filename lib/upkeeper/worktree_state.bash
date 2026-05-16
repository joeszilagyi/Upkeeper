worktree_redaction_key_material() {
  if declare -F upkeeper_redaction_key_material >/dev/null 2>&1; then
    upkeeper_redaction_key_material
  else
    printf '%s' "${UPKEEPER_REDACTION_KEY:-worktree-state-test-key}"
  fi
}

worktree_path_hmac() {
  local value="$1"

  if declare -F upkeeper_path_hmac >/dev/null 2>&1; then
    upkeeper_path_hmac "$value"
    return 0
  fi
  printf 'path-hmac-sha256:%s' "$(python3 - "${UPKEEPER_REDACTION_KEY:-worktree-state-test-key}" "$value" <<'PY' 2>/dev/null || printf 'unknown'
import hashlib
import hmac
import sys

key, value = sys.argv[1:3]
print(hmac.new(key.encode("utf-8", "surrogateescape"), f"path\0{value}".encode("utf-8", "surrogateescape"), hashlib.sha256).hexdigest())
PY
)"
}

refresh_worktree_counts() {
  DIRTY_PATH_COUNT=0
  TRACKED_MODIFIED_PATH_COUNT=0
  UNTRACKED_PATH_COUNT=0

  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    DIRTY_PATH_COUNT=$((DIRTY_PATH_COUNT + 1))
    if [[ "${line:0:2}" == "??" ]]; then
      UNTRACKED_PATH_COUNT=$((UNTRACKED_PATH_COUNT + 1))
    else
      TRACKED_MODIFIED_PATH_COUNT=$((TRACKED_MODIFIED_PATH_COUNT + 1))
    fi
  done < <(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all)
}

write_git_status_snapshot_json() {
  local output_file="$1"
  local hmac_key
  ensure_run_tmp_dir
  hmac_key="$(worktree_redaction_key_material)"
  # Persist redacted path identities because the gate only needs stable joins, not raw filenames.
  python3 - "$ROOT_DIR" "$output_file" "$RUN_TMP_DIR" "$hmac_key" <<'PY'
import hashlib
import hmac
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
output = Path(sys.argv[2])
run_tmp_dir = Path(sys.argv[3]).resolve()
hmac_key = sys.argv[4].encode("utf-8", "surrogateescape")

allowed_exact = {
    "Upkeeper",
    "Upkeeper.conf",
    "README.md",
    "change_notes_2026.md",
    "docs/compatibility.md",
    "docs/dependencies.md",
    "docs/scripts/upkeeper.md",
    "docs/stress-corpus.md",
    "tools/validate_upkeeper.sh",
}
allowed_prefixes = (
    "configurations/",
    "lib/upkeeper/",
    "prompts/",
    "templates/",
    "launcher_examples/",
)


def git(args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.DEVNULL)


def git_text(args):
    try:
        return (
            subprocess.check_output(
                ["git", "-C", str(root), *args],
                stderr=subprocess.DEVNULL,
            )
            .decode("utf-8", "replace")
            .strip()
            or "unknown"
        )
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def validated_output_path(path):
    try:
        resolved = path.resolve(strict=False)
    except OSError as exc:
        fail(f"snapshot output path is unreadable: {path} ({exc})")
    try:
        resolved.relative_to(run_tmp_dir)
    except ValueError:
        fail(f"snapshot output path escapes run temp directory: {path}")

    parent = resolved.parent
    if not parent.is_dir():
        fail(f"snapshot output parent directory is unavailable: {parent}")
    return resolved


def worktree_hash(rel_path):
    path = root / rel_path
    try:
        mode = path.stat().st_mode
    except OSError:
        return "missing"
    if not stat.S_ISREG(mode):
        return "not_regular"
    try:
        return git(["hash-object", "--", rel_path]).decode("utf-8", "replace").strip() or "unknown"
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def hmac_value(namespace, value):
    material = f"{namespace}\0{value}".encode("utf-8", "surrogateescape")
    return hmac.new(hmac_key, material, hashlib.sha256).hexdigest()


def path_hmac(path):
    return "path-hmac-sha256:" + hmac_value("path", path)


def extension_class(path):
    suffix = Path(path).suffix.lower()
    if not suffix:
        return "none"
    if not re.fullmatch(r"[.][a-z0-9_+-]{1,24}", suffix):
        return "other"
    return suffix


def coarse_path_class(path):
    lower = path.lower()
    name = Path(lower).name
    suffix = Path(lower).suffix
    if lower.startswith(".git/"):
        return "git"
    if lower.startswith("runtime/"):
        return "runtime"
    if "test" in lower.split("/"):
        return "test"
    if suffix in {".bash", ".sh", ".py", ".js", ".ts", ".mjs", ".cjs"} or name in {"upkeeper", "chimneysweep", "flameon"}:
        return "script"
    if suffix in {".md", ".rst", ".txt"}:
        return "documentation"
    if suffix in {".conf", ".json", ".yaml", ".yml", ".toml", ".ini"}:
        return "configuration"
    if suffix:
        return "source"
    return "no_extension"


def allowed(path):
    return (
        path in allowed_exact
        or re.fullmatch(r"change_notes_[0-9]{4}\.md", path) is not None
        or any(path.startswith(prefix) for prefix in allowed_prefixes)
    )


def snapshot_record(rel_path, status_code):
    return {
        "status": status_code,
        "hash": worktree_hash(rel_path),
        "allowed": 1 if allowed(rel_path) else 0,
        "path_class": coarse_path_class(rel_path),
        "extension": extension_class(rel_path),
    }


def atomic_write_json(path, payload):
    temp_fd, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=str(path.parent),
    )
    try:
        with os.fdopen(temp_fd, "w", encoding="utf-8", newline="") as handle:
            json.dump(payload, handle, sort_keys=True, separators=(",", ":"))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_name, path)
        try:
            parent_fd = os.open(path.parent, os.O_RDONLY)
        except OSError:
            return
        try:
            os.fsync(parent_fd)
        finally:
            os.close(parent_fd)
    except BaseException:
        try:
            Path(temp_name).unlink()
        except OSError:
            pass
        raise


raw = git(["status", "--porcelain=v1", "-z", "--untracked-files=all"])
output = validated_output_path(output)
parts = raw.decode("utf-8", "surrogateescape").split("\0")
items = {
    "__meta__": {
        "head": git_text(["rev-parse", "--verify", "HEAD"]),
        "branch": git_text(["symbolic-ref", "--short", "-q", "HEAD"]),
        "index_tree": git_text(["write-tree"]),
        "status_lines": str(len(raw)),
    },
    "__paths__": {},
}
i = 0
while i < len(parts):
    entry = parts[i]
    i += 1
    if not entry or len(entry) < 4:
        continue
    status_code = entry[:2]
    rel_path = entry[3:]
    if not rel_path:
        continue
    items["__paths__"][path_hmac(rel_path)] = snapshot_record(rel_path, status_code)
    if status_code[0] in {"R", "C"} or status_code[1] in {"R", "C"}:
        if i < len(parts):
            old_path = parts[i]
            i += 1
            if old_path:
                items["__paths__"].setdefault(path_hmac(old_path), snapshot_record(old_path, "old"))

atomic_write_json(output, items)
PY
}

capture_startup_anomaly_gate_baseline() {
  [[ "$STARTUP_ANOMALY_GATE" == "1" ]] || return 0
  STARTUP_ANOMALY_GATE_BASELINE_FILE="$(run_mktemp startup-gate-baseline)"
  write_git_status_snapshot_json "$STARTUP_ANOMALY_GATE_BASELINE_FILE"
  log_line "INFO" "startup_anomaly.gate_baseline path=$(shell_quote "$STARTUP_ANOMALY_GATE_BASELINE_FILE")"
}

startup_anomaly_gate_changed_path_violations() {
  local before_file="$1"
  local after_file="$2"
  local diagnostics_file="${3:-}"
  local hmac_key

  hmac_key="$(worktree_redaction_key_material)"
  python3 - "$before_file" "$after_file" "$diagnostics_file" "$hmac_key" <<'PY'
import hashlib
import hmac
import json
from pathlib import Path
import re
import sys

before_path, after_path, diagnostics_path, hmac_key_text = sys.argv[1:5]
hmac_key = hmac_key_text.encode("utf-8", "surrogateescape")

try:
    before = json.load(open(before_path, "r", encoding="utf-8"))
    after = json.load(open(after_path, "r", encoding="utf-8"))
except OSError:
    raise SystemExit(0)

allowed_exact = {
    "Upkeeper",
    "Upkeeper.conf",
    "README.md",
    "change_notes_2026.md",
    "docs/compatibility.md",
    "docs/dependencies.md",
    "docs/scripts/upkeeper.md",
    "docs/stress-corpus.md",
    "tools/validate_upkeeper.sh",
}
allowed_prefixes = (
    "configurations/",
    "lib/upkeeper/",
    "prompts/",
    "templates/",
    "launcher_examples/",
)


def allowed(path):
    return (
        path in allowed_exact
        or re.fullmatch(r"change_notes_[0-9]{4}\.md", path) is not None
        or any(path.startswith(prefix) for prefix in allowed_prefixes)
    )


def hmac_value(namespace, value):
    material = f"{namespace}\0{value}".encode("utf-8", "surrogateescape")
    return hmac.new(hmac_key, material, hashlib.sha256).hexdigest()


def path_hmac(path):
    return "path-hmac-sha256:" + hmac_value("path", path)


def extension_class(path):
    suffix = Path(path).suffix.lower()
    if not suffix:
        return "none"
    if not re.fullmatch(r"[.][a-z0-9_+-]{1,24}", suffix):
        return "other"
    return suffix


def coarse_path_class(path):
    lower = path.lower()
    name = Path(lower).name
    suffix = Path(lower).suffix
    if lower.startswith(".git/"):
        return "git"
    if lower.startswith("runtime/"):
        return "runtime"
    if "test" in lower.split("/"):
        return "test"
    if suffix in {".bash", ".sh", ".py", ".js", ".ts", ".mjs", ".cjs"} or name in {"upkeeper", "chimneysweep", "flameon"}:
        return "script"
    if suffix in {".md", ".rst", ".txt"}:
        return "documentation"
    if suffix in {".conf", ".json", ".yaml", ".yml", ".toml", ".ini"}:
        return "configuration"
    if suffix:
        return "source"
    return "no_extension"


diagnostics = []


def record_diagnostic(kind, payload):
    diagnostics.append({"kind": kind, **payload})


def normalize_snapshot(snapshot):
    if not isinstance(snapshot, dict):
        return {}, {}
    meta = snapshot.get("__meta__", {})
    meta = meta if isinstance(meta, dict) else {}
    redacted_paths = snapshot.get("__paths__")
    if isinstance(redacted_paths, dict):
        normalized = {}
        for key, value in redacted_paths.items():
            if isinstance(value, dict):
                normalized[str(key)] = dict(value)
        return meta, normalized

    normalized = {}
    for path, value in snapshot.items():
        if path == "__meta__" or not isinstance(value, dict):
            continue
        normalized[path_hmac(path)] = {
            "status": value.get("status", "unknown"),
            "hash": value.get("hash", "unknown"),
            "allowed": 1 if allowed(path) else 0,
            "path_class": coarse_path_class(path),
            "extension": extension_class(path),
            "legacy_path": path,
        }
    return meta, normalized


def emit_control_change(key, before_value, after_value):
    record_diagnostic("control_state_changed", {"key": key, "before": before_value, "after": after_value})
    print(f"control_state_changed key={key!r} changed=1 values_redacted=1")


def emit_path_change(path_key, before_state, after_state):
    before_status = before_state.get("status", "unknown")
    after_status = after_state.get("status", "unknown")
    before_hash = before_state.get("hash", "unknown")
    after_hash = after_state.get("hash", "unknown")
    path_token = before_state.get("path_hmac") or after_state.get("path_hmac") or path_key
    path_class = before_state.get("path_class") or after_state.get("path_class") or "unknown"
    extension = before_state.get("extension") or after_state.get("extension") or "unknown"
    content_changed = 1 if before_hash != after_hash else 0
    status_changed = 1 if before_status != after_status else 0
    diagnostic = {
        "before_status": before_status,
        "before_hash": before_hash,
        "after_status": after_status,
        "after_hash": after_hash,
        "content_changed": content_changed,
        "status_changed": status_changed,
    }
    raw_path = before_state.get("legacy_path") or after_state.get("legacy_path")
    if raw_path:
        diagnostic["path"] = raw_path
    else:
        diagnostic["path_hmac"] = path_token
        diagnostic["path_class"] = path_class
        diagnostic["extension"] = extension
    record_diagnostic("changed_path", diagnostic)
    print(
        f"changed_path path_hmac={path_token} "
        f"path_class={path_class} extension={extension} "
        f"before_status={before_status} after_status={after_status} "
        f"content_changed={content_changed} status_changed={status_changed}"
    )


before_meta, before_paths = normalize_snapshot(before)
after_meta, after_paths = normalize_snapshot(after)
for key in sorted(set(before_meta) | set(after_meta)):
    if before_meta.get(key) == after_meta.get(key):
        continue
    emit_control_change(key, before_meta.get(key, "missing"), after_meta.get(key, "missing"))


for path_key in sorted(set(before_paths) | set(after_paths)):
    before_state = before_paths.get(path_key, {"status": "clean", "hash": "clean"})
    after_state = after_paths.get(path_key, {"status": "clean", "hash": "clean"})
    if before_state == after_state:
        continue
    if before_state.get("allowed") == 1 or after_state.get("allowed") == 1:
        continue
    emit_path_change(path_key, before_state, after_state)

if diagnostics_path and diagnostics:
    try:
        with open(diagnostics_path, "w", encoding="utf-8") as handle:
            for item in diagnostics:
                handle.write(json.dumps(item, sort_keys=True, separators=(",", ":")) + "\n")
    except OSError:
        pass
PY
}

selected_target_scope_violations() {
  local before_file="$1"
  local after_file="$2"
  local selected_path="$3"
  local hmac_key

  [[ -n "$before_file" && -f "$before_file" ]] || return 0
  [[ -n "$after_file" && -f "$after_file" ]] || return 0

  hmac_key="$(worktree_redaction_key_material)"
  python3 - "$before_file" "$after_file" "$selected_path" "$hmac_key" <<'PY'
import hashlib
import hmac
import json
from pathlib import Path
import sys

before_path, after_path, selected_path, hmac_key_text = sys.argv[1:5]
hmac_key = hmac_key_text.encode("utf-8", "surrogateescape")

if not selected_path:
    raise SystemExit(0)

try:
    before = json.load(open(before_path, 'r', encoding='utf-8'))
    after = json.load(open(after_path, 'r', encoding='utf-8'))
except OSError:
    raise SystemExit(0)

if not isinstance(before, dict) or not isinstance(after, dict):
    raise SystemExit(0)


def hmac_value(namespace, value):
    material = f"{namespace}\0{value}".encode("utf-8", "surrogateescape")
    return hmac.new(hmac_key, material, hashlib.sha256).hexdigest()


def path_hmac(path):
    return "path-hmac-sha256:" + hmac_value("path", path)


def extension_class(path):
    suffix = Path(path).suffix.lower()
    return suffix if suffix else "none"


def normalize_snapshot(snapshot):
    if not isinstance(snapshot, dict):
        return {}
    redacted_paths = snapshot.get("__paths__")
    if isinstance(redacted_paths, dict):
        normalized = {}
        for key, value in redacted_paths.items():
            if isinstance(value, dict):
                normalized[str(key)] = dict(value)
        return normalized

    normalized = {}
    for path, value in snapshot.items():
        if path == "__meta__" or not isinstance(value, dict):
            continue
        normalized[path_hmac(path)] = {
            "status": value.get("status", "unknown"),
            "hash": value.get("hash", "unknown"),
            "extension": extension_class(path),
        }
    return normalized


before_paths = normalize_snapshot(before)
after_paths = normalize_snapshot(after)
selected_path_hmac = path_hmac(selected_path)

for path_key in sorted(set(before_paths) | set(after_paths)):
    if before_paths.get(path_key) == after_paths.get(path_key):
        continue
    if path_key != selected_path_hmac:
        before_state = before_paths.get(path_key, {"status": "clean", "hash": "clean"})
        after_state = after_paths.get(path_key, {"status": "clean", "hash": "clean"})
        before_hash = before_state.get("hash", "unknown")
        after_hash = after_state.get("hash", "unknown")
        extension = before_state.get("extension") or after_state.get("extension") or "none"
        print(
            f"changed_path path_hmac={path_key} extension={extension} "
            f"before_status={before_state.get('status', 'unknown')} "
            f"after_status={after_state.get('status', 'unknown')} "
            f"content_changed={1 if before_hash != after_hash else 0}"
        )
PY
}

enforce_selected_target_scope() {
  local before_file="$1"
  local selected_path="$2"
  local after_file violation_count=0 violation

  [[ -n "$selected_path" ]] || return 0

  after_file="$(run_mktemp selected-scope-after)"
  write_git_status_snapshot_json "$after_file"
  while IFS= read -r violation; do
    [[ -n "$violation" ]] || continue
    violation_count=$((violation_count + 1))
    log_line "WARN" "selected_target_scope.violation selected_path_hmac=$(worktree_path_hmac "$selected_path") path_redacted=1 $violation"
  done < <(selected_target_scope_violations "$before_file" "$after_file" "$selected_path")

  if [[ "$violation_count" -gt 0 ]]; then
    return 1
  fi

  return 0
}

enforce_startup_anomaly_changed_paths() {
  local after_file diagnostics_file violation_count=0 violation
  [[ "$STARTUP_ANOMALY_GATE" == "1" ]] || return 0
  [[ -n "${STARTUP_ANOMALY_GATE_BASELINE_FILE:-}" && -f "$STARTUP_ANOMALY_GATE_BASELINE_FILE" ]] || return 0

  after_file="$(run_mktemp startup-gate-after)"
  write_git_status_snapshot_json "$after_file"
  diagnostics_file="$CODEX_STARTUP_ANOMALY_GATE_STATE_DIR/$CYCLE_RUN_HASH.changed-path-diagnostics.jsonl"
  mkdir -p -- "$CODEX_STARTUP_ANOMALY_GATE_STATE_DIR" 2>/dev/null || true
  chmod 700 "$CODEX_STARTUP_ANOMALY_GATE_STATE_DIR" 2>/dev/null || true
  : >"$diagnostics_file" 2>/dev/null || diagnostics_file=""
  [[ -n "$diagnostics_file" ]] && chmod 600 "$diagnostics_file" 2>/dev/null || true
  while IFS= read -r violation; do
    [[ -n "$violation" ]] || continue
    violation_count=$((violation_count + 1))
    log_line "WARN" "startup_anomaly.gate_violation $violation"
  done < <(startup_anomaly_gate_changed_path_violations "$STARTUP_ANOMALY_GATE_BASELINE_FILE" "$after_file" "$diagnostics_file")

  if [[ "$violation_count" -gt 0 ]]; then
    log_line "WARN" "startup_anomaly.gate_violation_summary count=$violation_count diagnostics=protected_local diagnostics_path_hmac=$(worktree_path_hmac "$diagnostics_file")"
    STARTUP_ANOMALY_GATE_CHANGED_PATH_VIOLATION="1"
    append_startup_anomaly_reason "gate_changed_path_violation"
    if ! write_startup_anomaly_gate_state "unresolved" "changed_path_violation"; then
      finish_cycle 7 STARTUP_ANOMALY_STATE_UNWRITABLE ERROR "codex_exec_started=1"
    fi
  else
    log_line "INFO" "startup_anomaly.gate_violation status=none"
  fi
}
