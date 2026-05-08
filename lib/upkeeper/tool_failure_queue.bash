# Durable local queue for script/tool failures found during Codex runs.
#
# Open markers live under runtime and affect only local target selection. They
# are resolved locally after WORK_DONE when no unaddressed same-target tool
# failure remains in the new transcript.
tool_failure_queue_open_dir() {
  printf '%s/open' "$CODEX_TOOL_FAILURE_QUEUE_DIR"
}

tool_failure_queue_resolved_dir() {
  printf '%s/resolved' "$CODEX_TOOL_FAILURE_QUEUE_DIR"
}

tool_failure_queue_enabled() {
  [[ "${CODEX_TOOL_FAILURE_QUEUE_ENABLED:-1}" == "1" ]]
}

tool_failure_queue_active_for_selection() {
  tool_failure_queue_enabled && [[ "${CODEX_TOOL_FAILURE_QUEUE_BYPASS:-0}" != "1" ]]
}

tool_failure_queue_finalize_run() {
  local target_path="$1"
  local transcript_file="$2"
  local codex_exit="$3"
  local status_marker="$4"
  local output rc line

  tool_failure_queue_enabled || return 0
  [[ -n "$target_path" ]] || return 0
  [[ -n "$transcript_file" ]] || return 0

  set +e
  output="$(python3 - \
    "$CODEX_TOOL_FAILURE_QUEUE_DIR" \
    "$target_path" \
    "$transcript_file" \
    "$codex_exit" \
    "$status_marker" \
    "$CYCLE_ID" \
    "$CYCLE_RUN_HASH" \
    "${RUN_SELECTED_FAILURE_MARKER_PATH:-}" <<'PY'
import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path

queue_dir_raw, target_path, transcript_raw, codex_exit, status_marker, cycle_id, run_hash, selected_marker_raw = sys.argv[1:9]
queue_dir = Path(queue_dir_raw)
open_dir = queue_dir / "open"
resolved_dir = queue_dir / "resolved"
transcript_path = Path(transcript_raw)


def short(value: str, limit: int = 500) -> str:
    value = re.sub(r"\s+", " ", value.strip())
    if len(value) > limit:
        return value[: limit - 15].rstrip() + "...<truncated>"
    return value


def field(value: str) -> str:
    return short(str(value)).replace(" ", "\\ ")


def marker_id_for(path: str) -> str:
    return hashlib.sha1(path.encode("utf-8", "surrogateescape")).hexdigest()[:24]


def command_kind(line: str) -> str:
    lowered = line.lower()
    if re.search(r"\bbash\s+-n\b|\bdiff\s+--check\b|git\s+diff\s+--check|\bshellcheck\b|\bruff\b|\bmypy\b", lowered):
        return "check"
    if re.search(r"\btools/validate_[a-z0-9_.-]+(?:\.sh)?\b|validate_upkeeper\.sh", lowered):
        return "validation"
    if re.search(r"\b(pytest|bats)\b|\bpython[0-9.]*\s+-m\s+pytest\b|\bgo\s+test\b|\bcargo\s+test\b|\b(?:npm|pnpm|yarn)\s+(?:run\s+)?test\b|\bmake\s+(?:[^;&|]*\s+)?test\b", lowered):
        return "tests"
    if re.search(r"\b(npm|pnpm|yarn|node|make|cargo|go)\b", lowered):
        return "build"
    if re.search(r"\bcommand -v\s+", lowered):
        return "command"
    if re.search(r"\b(rg|grep|find|cat)\b|\bgit\s+(?:grep|ls-files|diff|show|status|log)\b|\bnl\s+-ba\b|\bsed\s+-n\b", lowered):
        return "search"
    if re.search(r"\bgit\b", lowered):
        return "git"
    return "command"


def interesting_failure_kind(kind: str) -> bool:
    return kind in {"tests", "validation", "check", "build"}


def strip_initial_prompt_echo(raw_lines: list[str]) -> list[str]:
    filtered = []
    in_user_echo = False
    saw_codex_marker = False
    for item in raw_lines:
        stripped = item.strip()
        if not saw_codex_marker:
            if in_user_echo:
                if stripped == "codex":
                    in_user_echo = False
                    saw_codex_marker = True
                continue
            if stripped == "user":
                in_user_echo = True
                continue
        filtered.append(item)
    return filtered


def transcript_failure_state(path: Path) -> tuple[list[dict[str, str]], bool]:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return [], False

    failures = []
    last_failure_kind = ""
    addressed_by_later_success = False
    expecting_command = False
    current_command = ""
    current_kind = "command"
    in_diff_block = False
    for line in strip_initial_prompt_echo(lines):
        stripped = line.strip()
        if stripped == "codex" or stripped.startswith("tokens used"):
            expecting_command = False
            current_command = ""
            current_kind = "command"
            in_diff_block = False
            continue
        if stripped == "exec":
            expecting_command = True
            current_command = ""
            current_kind = "command"
            in_diff_block = False
            continue
        if line.startswith("diff --git "):
            in_diff_block = True
            continue
        if in_diff_block:
            continue
        if expecting_command and stripped:
            expecting_command = False
            current_command = stripped
            current_kind = command_kind(stripped)
            continue
        if re.match(r"succeeded in [0-9]+", stripped) and interesting_failure_kind(current_kind):
            if last_failure_kind == current_kind:
                addressed_by_later_success = True
            continue
        if re.match(r"exited [1-9][0-9]* in ", stripped) and interesting_failure_kind(current_kind):
            last_failure_kind = current_kind
            addressed_by_later_success = False
            failures.append(
                {
                    "kind": current_kind,
                    "command": short(current_command),
                    "exit_line": short(stripped),
                }
            )
    return failures, addressed_by_later_success


def read_json(path: Path) -> dict:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
            if isinstance(data, dict):
                return data
    except OSError:
        return {}
    except json.JSONDecodeError:
        return {}
    return {}


def write_json_atomic(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".tmp.{os.getpid()}")
    with tmp.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)


def resolve_marker(path: Path, reason: str) -> Path:
    data = read_json(path)
    now = int(time.time())
    data.update(
        {
            "status": "resolved",
            "resolved_epoch": now,
            "resolved_cycle": cycle_id,
            "resolved_run_hash": run_hash,
            "resolved_reason": reason,
            "last_status_marker": status_marker,
        }
    )
    resolved_dir.mkdir(parents=True, exist_ok=True)
    resolved_path = resolved_dir / f"{path.stem}.{cycle_id}.json"
    write_json_atomic(resolved_path, data)
    try:
        path.unlink()
    except OSError:
        pass
    return resolved_path


marker_id = marker_id_for(target_path)
marker_path = open_dir / f"{marker_id}.json"
selected_marker_path = Path(selected_marker_raw) if selected_marker_raw else marker_path
now = int(time.time())
failures, addressed_by_later_success = transcript_failure_state(transcript_path)

if failures:
    existing = read_json(marker_path)
    first = failures[0]
    failure_count = int(existing.get("failure_count", 0) or 0) + len(failures)
    data = {
        "version": 1,
        "status": "open",
        "marker_id": marker_id,
        "target_path": target_path,
        "first_seen_epoch": int(existing.get("first_seen_epoch", now) or now),
        "first_seen_cycle": existing.get("first_seen_cycle", cycle_id),
        "first_seen_run_hash": existing.get("first_seen_run_hash", run_hash),
        "last_seen_epoch": now,
        "last_seen_cycle": cycle_id,
        "last_seen_run_hash": run_hash,
        "last_transcript": str(transcript_path),
        "last_codex_exit": codex_exit,
        "last_status_marker": status_marker,
        "failure_count": failure_count,
        "first_failure_kind": existing.get("first_failure_kind", first["kind"]),
        "first_failure_command": existing.get("first_failure_command", first["command"]),
        "first_failure_exit_line": existing.get("first_failure_exit_line", first["exit_line"]),
        "last_failure_kind": first["kind"],
        "last_failure_command": first["command"],
        "last_failure_exit_line": first["exit_line"],
        "failure_samples": failures[:5],
        "addressed_by_later_success": addressed_by_later_success,
    }
    write_json_atomic(marker_path, data)
    if status_marker == "WORK_DONE" and addressed_by_later_success:
        resolved_path = resolve_marker(marker_path, "work_done_after_detected_failure")
        print(f"action=resolved_same_run marker_id={field(marker_id)} marker_path={field(str(resolved_path))} target_path={field(target_path)} failures={len(failures)} addressed_by_later_success=1")
    else:
        print(f"action=open marker_id={field(marker_id)} marker_path={field(str(marker_path))} target_path={field(target_path)} failures={len(failures)} addressed_by_later_success=0 kind={field(first['kind'])} exit_line={field(first['exit_line'])}")
    raise SystemExit(0)

if status_marker == "WORK_DONE" and selected_marker_path.exists():
    resolved_path = resolve_marker(selected_marker_path, "work_done_without_new_tool_failure")
    print(f"action=resolved marker_id={field(marker_id)} marker_path={field(str(resolved_path))} target_path={field(target_path)} failures=0")
else:
    print(f"action=none marker_id={field(marker_id)} target_path={field(target_path)} failures=0")
PY
  )"
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    log_line "WARN" "tool_failure_queue.update_failed target=$(shell_quote "$target_path") transcript=$(shell_quote "$transcript_file") detail=$(shell_quote "$output")"
    return 0
  fi

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      action=open*)
        log_line "WARN" "tool_failure_queue.open $line"
        ;;
      action=resolved*|action=resolved_same_run*)
        log_line "INFO" "tool_failure_queue.resolved $line"
        ;;
      action=none*)
        log_line "INFO" "tool_failure_queue.clean $line"
        ;;
      *)
        log_line "INFO" "tool_failure_queue.result $(shell_quote "$line")"
        ;;
    esac
  done <<<"$output"
}
