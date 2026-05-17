# Durable local queue for script/tool failures found during Codex runs.
#
# Open markers live under runtime and affect only local target selection. They
# are resolved locally after WORK_DONE when no unaddressed same-target tool
# failure remains in the new transcript or open marker state.
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
  local redaction_key target_path_hmac transcript_path_hmac output rc line

  tool_failure_queue_enabled || return 0
  [[ -n "$target_path" ]] || return 0
  [[ -n "$transcript_file" ]] || return 0
  redaction_key="$(upkeeper_redaction_key_material)"
  target_path_hmac="$(upkeeper_path_hmac "$target_path")"
  transcript_path_hmac="$(upkeeper_path_hmac "$transcript_file")"

  set +e
  output="$(python3 - \
    "$ROOT_DIR" \
    "$CODEX_TOOL_FAILURE_QUEUE_DIR" \
    "$target_path" \
    "$transcript_file" \
    "$codex_exit" \
    "$status_marker" \
    "$CYCLE_ID" \
    "$CYCLE_RUN_HASH" \
    "${RUN_SELECTED_FAILURE_MARKER_PATH:-}" \
    "${CODEX_BUG_REPORT_ONLY:-0}" \
    "$redaction_key" <<'PY'
import hashlib
import hmac
import json
import os
import re
import stat
import sys
import time
from pathlib import Path

root_raw, queue_dir_raw, target_path, transcript_raw, codex_exit, status_marker, cycle_id, run_hash, selected_marker_raw, bug_report_only_raw, redaction_key = sys.argv[1:12]
root_path = Path(root_raw).resolve()
queue_dir = Path(queue_dir_raw).expanduser()
if not queue_dir.is_absolute():
    queue_dir = Path(os.path.abspath(root_path / queue_dir))
else:
    queue_dir = Path(os.path.abspath(queue_dir))
open_dir = queue_dir / "open"
resolved_dir = queue_dir / "resolved"
transcript_path = Path(transcript_raw).expanduser()
if not transcript_path.is_absolute():
    transcript_path = Path(os.path.abspath(root_path / transcript_path))
else:
    transcript_path = Path(os.path.abspath(transcript_path))
bug_report_only = str(bug_report_only_raw).strip().lower() in {"1", "true", "yes", "on"}
redaction_key_bytes = redaction_key.encode("utf-8", "surrogateescape")
uid = os.getuid()


def short(value: str, limit: int = 500) -> str:
    value = re.sub(r"\s+", " ", value.strip())
    if len(value) > limit:
        return value[: limit - 15].rstrip() + "...<truncated>"
    return value


def hmac_hex(namespace: str, value: str) -> str:
    material = f"{namespace}\0{value}".encode("utf-8", "surrogateescape")
    return hmac.new(redaction_key_bytes, material, hashlib.sha256).hexdigest()


def path_hmac(value: str) -> str:
    return f"path-hmac-sha256:{hmac_hex('path', value)}"


def value_hmac(namespace: str, value: str) -> str:
    return f"value-hmac-sha256:{hmac_hex(namespace, value)}"


def transcript_id_for(path: Path) -> str:
    return f"transcript-hmac-sha256:{hmac_hex('transcript', str(path))}"


def scrub_marker_snapshot(data: dict, *, keep_target_path: bool) -> dict:
    cleaned = {}
    for key, value in data.items():
        if key in {
            "first_failure_command",
            "last_failure_command",
            "last_transcript_path",
            "transcript_path",
        }:
            continue
        if key == "target_path" and not keep_target_path:
            continue
        cleaned[key] = value
    return cleaned


def failure_signature(kind: str, command_hash: str, exit_line: str) -> str:
    payload = f"{kind}\0{command_hash}\0{exit_line}"
    return hashlib.sha256(payload.encode("utf-8", "surrogateescape")).hexdigest()


def command_signature(kind: str, command_hash: str) -> str:
    payload = f"{kind}\0{command_hash}"
    return hashlib.sha256(payload.encode("utf-8", "surrogateescape")).hexdigest()


def normalize_failure_item(kind: object, command_hash: object, exit_line: object) -> dict[str, str] | None:
    if not isinstance(kind, str) or not kind:
        return None
    if not isinstance(command_hash, str) or not command_hash:
        return None
    if not isinstance(exit_line, str) or not exit_line:
        return None
    return {
        "kind": kind,
        "command_hash": command_hash,
        "command_signature": command_signature(kind, command_hash),
        "exit_line": exit_line,
        "signature": failure_signature(kind, command_hash, exit_line),
    }


def field(value: str) -> str:
    return short(str(value)).replace(" ", "\\ ")


def marker_id_for(path: str) -> str:
    return hashlib.sha1(path.encode("utf-8", "surrogateescape")).hexdigest()[:24]


def normalize_target_path(value: object) -> str:
    if not isinstance(value, str):
        return ""
    path = value.strip()
    if not path or "\0" in path or any(ord(char) < 32 for char in path):
        return ""
    if os.path.isabs(path):
        try:
            rel = Path(path).resolve().relative_to(root_path)
        except (OSError, ValueError):
            return ""
        return rel.as_posix()
    normalized = os.path.normpath(path).replace(os.sep, "/")
    if normalized in {".", ""} or normalized.startswith("../") or os.path.isabs(normalized):
        return ""
    return normalized


def normalize_open_marker_path(value: object) -> Path | None:
    if not isinstance(value, str):
        return None
    raw = value.strip()
    if not raw or "\0" in raw or any(ord(char) < 32 for char in raw):
        return None
    path = Path(raw).expanduser()
    if not path.is_absolute():
        path = Path(os.path.abspath(root_path / path))
    else:
        path = Path(os.path.abspath(path))
    try:
        relative = path.relative_to(open_dir)
    except ValueError:
        return None
    if relative.parent != Path("."):
        return None
    return path


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


def transcript_failure_state(path: Path) -> tuple[list[dict[str, str]], list[dict[str, str]], set[str]]:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return [], [], set()

    failures = []
    unresolved_failures = []
    successful_command_signatures = set()
    expecting_command = False
    current_command = ""
    current_command_hash = ""
    current_kind = "command"
    in_diff_block = False
    for line in strip_initial_prompt_echo(lines):
        stripped = line.strip()
        if stripped == "codex" or stripped.startswith("tokens used"):
            expecting_command = False
            current_command = ""
            current_command_hash = ""
            current_kind = "command"
            in_diff_block = False
            continue
        if stripped == "exec":
            expecting_command = True
            current_command = ""
            current_command_hash = ""
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
            current_command_hash = value_hmac("command", short(current_command))
            continue
        if re.match(r"succeeded in [0-9]+", stripped) and interesting_failure_kind(current_kind):
            if current_command_hash:
                current_command_signature = command_signature(current_kind, current_command_hash)
                successful_command_signatures.add(current_command_signature)
                unresolved_failures = [
                    item for item in unresolved_failures if item["command_signature"] != current_command_signature
                ]
            continue
        if re.match(r"exited [1-9][0-9]* in ", stripped) and interesting_failure_kind(current_kind):
            failure = normalize_failure_item(current_kind, current_command_hash, short(stripped))
            if failure is not None:
                failures.append(failure)
                unresolved_failures.append(failure)
    return failures, unresolved_failures, successful_command_signatures


def marker_unresolved_failures(data: dict) -> list[dict[str, str]]:
    collected = []
    seen = set()

    def add(kind: object, command_hash: object, exit_line: object) -> None:
        failure = normalize_failure_item(kind, command_hash, exit_line)
        if failure is None or failure["signature"] in seen:
            return
        seen.add(failure["signature"])
        collected.append(failure)

    unresolved = data.get("unresolved_failures")
    if isinstance(unresolved, list):
        for item in unresolved:
            if not isinstance(item, dict):
                continue
            add(item.get("kind"), item.get("command_hash"), item.get("exit_line"))
        if collected:
            return collected

    samples = data.get("failure_samples")
    if isinstance(samples, list):
        for item in samples:
            if not isinstance(item, dict):
                continue
            add(item.get("kind"), item.get("command_hash"), item.get("exit_line"))

    add(data.get("first_failure_kind"), data.get("first_failure_command_hash"), data.get("first_failure_exit_line"))
    add(data.get("last_failure_kind"), data.get("last_failure_command_hash"), data.get("last_failure_exit_line"))
    return collected


def ensure_private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    st = os.lstat(path)
    if not stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode):
        raise PermissionError(f"queue_path_not_private_dir:{path}")
    if st.st_uid != uid:
        raise PermissionError(f"queue_dir_wrong_owner:{path}")
    os.chmod(path, 0o700)
    st = os.lstat(path)
    if stat.S_IMODE(st.st_mode) != 0o700:
        raise PermissionError(f"queue_dir_unprotected:{path}")


def ensure_private_regular_file(path: Path) -> None:
    st = os.lstat(path)
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode):
        raise PermissionError(f"queue_marker_not_regular:{path}")
    if st.st_uid != uid:
        raise PermissionError(f"queue_marker_wrong_owner:{path}")
    os.chmod(path, 0o600)
    st = os.lstat(path)
    if stat.S_IMODE(st.st_mode) != 0o600:
        raise PermissionError(f"queue_marker_unprotected:{path}")


def read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    ensure_private_regular_file(path)
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
            if isinstance(data, dict):
                return data
    except json.JSONDecodeError:
        return {}
    return {}


def write_json_atomic(path: Path, data: dict) -> None:
    ensure_private_dir(path.parent)
    tmp = path.with_name(path.name + f".tmp.{os.getpid()}")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(tmp, path)
        ensure_private_regular_file(path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def resolve_marker(path: Path, reason: str) -> Path:
    data = read_json(path)
    now = int(time.time())
    data = scrub_marker_snapshot(data, keep_target_path=False)
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
    ensure_private_dir(resolved_dir)
    resolved_path = resolved_dir / f"{path.stem}.{cycle_id}.json"
    write_json_atomic(resolved_path, data)
    try:
        path.unlink()
    except OSError:
        pass
    return resolved_path


def main() -> None:
    normalized_target_path = normalize_target_path(target_path)
    if not normalized_target_path:
        raise ValueError("target_path_invalid")
    marker_id = marker_id_for(normalized_target_path)
    marker_path = open_dir / f"{marker_id}.json"
    selected_marker_path = normalize_open_marker_path(selected_marker_raw) or marker_path
    now = int(time.time())
    failures, unresolved_failures, successful_command_signatures = transcript_failure_state(transcript_path)
    ensure_private_dir(queue_dir)
    ensure_private_dir(open_dir)
    ensure_private_dir(resolved_dir)

    if failures:
        if marker_path.exists():
            existing = read_json(marker_path)
        elif selected_marker_path and selected_marker_path.exists():
            existing = read_json(selected_marker_path)
        else:
            existing = {}
        existing = scrub_marker_snapshot(existing, keep_target_path=True)
        first = failures[0]
        remaining_existing_unresolved = [
            item
            for item in marker_unresolved_failures(existing)
            if item["command_signature"] not in successful_command_signatures
        ]
        existing_signatures = existing.get("failure_signatures", [])
        if not isinstance(existing_signatures, list):
            existing_signatures = []
        existing_signatures = [str(item) for item in existing_signatures if isinstance(item, str)]

        existing_signature_lookup = set(existing_signatures)
        unique_failures = []
        for item in failures:
            if item["signature"] not in existing_signature_lookup:
                unique_failures.append(item)
                existing_signature_lookup.add(item["signature"])

        first_failure = existing.get("first_failure_kind")
        first_failure_command_hash = existing.get("first_failure_command_hash")
        if not isinstance(first_failure_command_hash, str) or not first_failure_command_hash:
            first_failure_command_hash = ""
        first_failure_exit_line = existing.get("first_failure_exit_line")
        if not (first_failure and first_failure_command_hash and first_failure_exit_line):
            first_failure = first["kind"]
            first_failure_command_hash = first["command_hash"]
            first_failure_exit_line = first["exit_line"]

        last_failure = failures[-1]
        failure_count = int(existing.get("failure_count", 0) or 0) + len(unique_failures)
        signatures = existing_signatures.copy()
        for item in unique_failures:
            signatures.append(item["signature"])
        unresolved_signature_lookup = set()
        unresolved_combined = []
        for item in remaining_existing_unresolved + unresolved_failures:
            if item["signature"] in unresolved_signature_lookup:
                continue
            unresolved_signature_lookup.add(item["signature"])
            unresolved_combined.append(item)
        addressed_by_later_success = bool(failures) and not unresolved_combined
        data = {
            "version": 2,
            "status": "open",
            "marker_id": marker_id,
            "target_path": normalized_target_path,
            "target_path_hmac": path_hmac(normalized_target_path),
            "first_seen_epoch": int(existing.get("first_seen_epoch", now) or now),
            "first_seen_cycle": existing.get("first_seen_cycle", cycle_id),
            "first_seen_run_hash": existing.get("first_seen_run_hash", run_hash),
            "last_seen_epoch": now,
            "last_seen_cycle": cycle_id,
            "last_seen_run_hash": run_hash,
            "last_transcript_id": transcript_id_for(transcript_path),
            "last_transcript_path_hmac": path_hmac(str(transcript_path)),
            "last_codex_exit": codex_exit,
            "last_status_marker": status_marker,
            "failure_count": failure_count,
            "failure_signatures": signatures,
            "first_failure_kind": first_failure,
            "first_failure_command_hash": first_failure_command_hash,
            "first_failure_exit_line": first_failure_exit_line,
            "last_failure_kind": last_failure["kind"],
            "last_failure_command_hash": last_failure["command_hash"],
            "last_failure_exit_line": last_failure["exit_line"],
            "failure_samples": failures[:5],
            "unresolved_failure_count": len(unresolved_combined),
            "unresolved_failures": unresolved_combined,
            "addressed_by_later_success": addressed_by_later_success,
        }
        write_json_atomic(marker_path, data)
        if addressed_by_later_success and not bug_report_only:
            reason = "work_done_after_detected_failure" if status_marker == "WORK_DONE" else "later_success_after_detected_failure"
            resolved_path = resolve_marker(marker_path, reason)
            print(f"action=resolved_same_run marker_id={field(marker_id)} marker_path_hmac={field(path_hmac(str(resolved_path)))} target_path_hmac={field(path_hmac(normalized_target_path))} path_redacted=1 failures={len(failures)} unresolved_failures=0 addressed_by_later_success=1")
        else:
            print(f"action=open marker_id={field(marker_id)} marker_path_hmac={field(path_hmac(str(marker_path)))} target_path_hmac={field(path_hmac(normalized_target_path))} path_redacted=1 failures={len(failures)} unresolved_failures={len(unresolved_combined)} addressed_by_later_success={1 if addressed_by_later_success else 0} kind={field(last_failure['kind'])} exit_line={field(last_failure['exit_line'])}")
        raise SystemExit(0)

    if status_marker == "WORK_DONE" and selected_marker_path.exists() and bug_report_only:
        print(f"action=preserved_report_only marker_id={field(marker_id)} marker_path_hmac={field(path_hmac(str(selected_marker_path)))} target_path_hmac={field(path_hmac(normalized_target_path))} path_redacted=1 failures=0")
    elif status_marker == "WORK_DONE" and selected_marker_path.exists():
        resolved_path = resolve_marker(selected_marker_path, "work_done_without_new_tool_failure")
        print(f"action=resolved marker_id={field(marker_id)} marker_path_hmac={field(path_hmac(str(resolved_path)))} target_path_hmac={field(path_hmac(normalized_target_path))} path_redacted=1 failures=0")
    else:
        print(f"action=none marker_id={field(marker_id)} target_path_hmac={field(path_hmac(normalized_target_path))} path_redacted=1 failures=0")


try:
    main()
except SystemExit:
    raise
except Exception as exc:
    print(f"action=error error_class={field(type(exc).__name__)} path_redacted=1")
    raise SystemExit(1)
PY
  )"
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    log_line "WARN" "tool_failure_queue.update_failed target_hmac=$target_path_hmac transcript_hmac=$transcript_path_hmac path_redacted=1 detail=$(shell_quote "$output")"
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
      action=preserved_report_only*)
        log_line "INFO" "tool_failure_queue.preserved $line"
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
