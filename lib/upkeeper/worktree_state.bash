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
  python3 - "$ROOT_DIR" "$output_file" <<'PY'
import json
import stat
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
output = Path(sys.argv[2])


def git(args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.DEVNULL)


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


raw = git(["status", "--porcelain=v1", "-z", "--untracked-files=all"])
parts = raw.decode("utf-8", "surrogateescape").split("\0")
items = {}
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
    items[rel_path] = {
        "status": status_code,
        "hash": worktree_hash(rel_path),
    }
    if status_code[0] in {"R", "C"} or status_code[1] in {"R", "C"}:
        if i < len(parts):
            old_path = parts[i]
            i += 1
            if old_path:
                items.setdefault(
                    old_path,
                    {
                        "status": "old",
                        "hash": worktree_hash(old_path),
                    },
                )

output.write_text(json.dumps(items, sort_keys=True, separators=(",", ":")), encoding="utf-8")
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
  python3 - "$before_file" "$after_file" <<'PY'
import json
import sys

before_path, after_path = sys.argv[1:3]

try:
    before = json.load(open(before_path, "r", encoding="utf-8"))
    after = json.load(open(after_path, "r", encoding="utf-8"))
except OSError:
    raise SystemExit(0)

allowed_exact = {
    "Upkeeper",
    "README.md",
    "change_notes.md",
    "docs/compatibility.md",
    "docs/dependencies.md",
    "docs/scripts/upkeeper.md",
    "docs/stress-corpus.md",
    "tools/validate_upkeeper.sh",
}
allowed_prefixes = (
    "lib/upkeeper/",
    "prompts/",
    "templates/",
    "launcher_examples/",
)


def allowed(path):
    return path in allowed_exact or any(path.startswith(prefix) for prefix in allowed_prefixes)


for path in sorted(set(before) | set(after)):
    if allowed(path):
        continue
    if before.get(path) == after.get(path):
        continue
    before_state = before.get(path, {"status": "clean", "hash": "clean"})
    after_state = after.get(path, {"status": "clean", "hash": "clean"})
    print(
        f"changed_path={path!r} before_status={before_state.get('status', 'unknown')} "
        f"before_hash={before_state.get('hash', 'unknown')} "
        f"after_status={after_state.get('status', 'unknown')} "
        f"after_hash={after_state.get('hash', 'unknown')}"
    )
PY
}

enforce_startup_anomaly_changed_paths() {
  local after_file violation_count=0 violation
  [[ "$STARTUP_ANOMALY_GATE" == "1" ]] || return 0
  [[ -n "${STARTUP_ANOMALY_GATE_BASELINE_FILE:-}" && -f "$STARTUP_ANOMALY_GATE_BASELINE_FILE" ]] || return 0

  after_file="$(run_mktemp startup-gate-after)"
  write_git_status_snapshot_json "$after_file"
  while IFS= read -r violation; do
    [[ -n "$violation" ]] || continue
    violation_count=$((violation_count + 1))
    log_line "WARN" "startup_anomaly.gate_violation $violation"
  done < <(startup_anomaly_gate_changed_path_violations "$STARTUP_ANOMALY_GATE_BASELINE_FILE" "$after_file")

  if [[ "$violation_count" -gt 0 ]]; then
    STARTUP_ANOMALY_GATE_CHANGED_PATH_VIOLATION="1"
    append_startup_anomaly_reason "gate_changed_path_violation"
    if ! write_startup_anomaly_gate_state "unresolved" "changed_path_violation"; then
      finish_cycle 7 STARTUP_ANOMALY_STATE_UNWRITABLE ERROR "codex_exec_started=1"
    fi
  else
    log_line "INFO" "startup_anomaly.gate_violation status=none"
  fi
}
