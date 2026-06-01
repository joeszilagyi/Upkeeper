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

if ! declare -F upkeeper_preselect_output_field >/dev/null 2>&1; then
  upkeeper_preselect_output_field() {
    local key="$1"
    local raw="$2"

    awk -v prefix="$key=" 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }' <<<"$raw"
  }
fi

tool_failure_queue_active_for_selection() {
  tool_failure_queue_enabled && [[ "${CODEX_TOOL_FAILURE_QUEUE_BYPASS:-0}" != "1" ]]
}

tool_failure_queue_open_custody_log() {
  local level="$1"
  local message="$2"

  [[ "$level" == "WARN" ]] || return 1
  case "$message" in
    tool_failure_queue.open\ action=open*\ unresolved_failures=*\ addressed_by_later_success=0*\ kind=*\ exit_line=*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

upkeeper_tool_failure_queue_open_custody_log() {
  tool_failure_queue_open_custody_log "$@"
}

upkeeper_tool_failure_queue_signing_key_material() {
  local key_file="${UPKEEPER_TOOL_FAILURE_QUEUE_SIGNING_KEY_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/upkeeper/tool-failure-queue.key}"
  local key_dir="" key_value="" token=""

  if [[ -n "${UPKEEPER_TOOL_FAILURE_QUEUE_SIGNING_KEY:-}" ]]; then
    printf '%s' "$UPKEEPER_TOOL_FAILURE_QUEUE_SIGNING_KEY"
    return 0
  fi

  if [[ -r "$key_file" ]]; then
    IFS= read -r key_value <"$key_file" || key_value=""
    if [[ -n "$key_value" ]]; then
      printf '%s' "$key_value"
      return 0
    fi
  fi

  key_dir="$(dirname -- "$key_file")"
  mkdir -p -- "$key_dir" 2>/dev/null || return 1
  chmod 700 "$key_dir" 2>/dev/null || true
  if [[ -r /dev/urandom ]]; then
    token="$(od -An -N 32 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
  fi
  if [[ -z "$token" ]] && command -v python3 >/dev/null 2>&1; then
    token="$(python3 - "$key_file" <<'PY'
import hashlib
import os
import sys
import time

seed = f"{sys.argv[1]}|{os.getpid()}|{time.time_ns()}".encode("utf-8", "surrogateescape")
print(hashlib.sha256(seed).hexdigest())
PY
)"
  fi
  [[ -n "$token" ]] || return 1
  printf '%s\n' "$token" >"$key_file" 2>/dev/null || return 1
  chmod 600 "$key_file" 2>/dev/null || true
  printf '%s' "$token"
}

upkeeper_tool_failure_queue_prepare_secure_dirs() {
  python3 - "$ROOT_DIR" "$CODEX_TOOL_FAILURE_QUEUE_DIR" <<'PY'
import os
import stat
import sys
from pathlib import Path

root, raw_queue_dir = sys.argv[1:3]
queue_dir = Path(raw_queue_dir).expanduser()
if not queue_dir.is_absolute():
    queue_dir = Path(os.path.abspath(Path(root) / queue_dir))
else:
    queue_dir = Path(os.path.abspath(queue_dir))
uid = os.getuid()


def emit(status: str, reason: str = "", path=None) -> None:
    print(f"status={status}")
    if reason:
        print(f"reason={reason}")
    if path is not None:
        print(f"queue_dir={path}")


def ensure_no_symlink_components(path: Path) -> tuple[bool, str]:
    current = Path(path.anchor or os.sep)
    for part in path.parts[1:]:
        current /= part
        try:
            st = os.lstat(current)
        except FileNotFoundError:
            continue
        except OSError as exc:
            return False, f"queue_path_unreadable:{type(exc).__name__}"
        if stat.S_ISLNK(st.st_mode):
            return False, f"queue_path_contains_symlink:{current}"
    return True, ""


def ensure_private_owned_dir(path: Path) -> tuple[bool, str]:
    try:
        path.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        return False, f"queue_dir_create_failed:{type(exc).__name__}"
    try:
        st = os.lstat(path)
    except OSError as exc:
        return False, f"queue_dir_stat_failed:{type(exc).__name__}"
    if not stat.S_ISDIR(st.st_mode):
        return False, "queue_path_not_directory"
    if stat.S_ISLNK(st.st_mode):
        return False, "queue_dir_symlinked"
    if st.st_uid != uid:
        return False, "queue_dir_wrong_owner"
    mode = stat.S_IMODE(st.st_mode)
    if mode != 0o700:
        try:
            os.chmod(path, 0o700)
            st = os.lstat(path)
            mode = stat.S_IMODE(st.st_mode)
        except OSError as exc:
            return False, f"queue_dir_chmod_failed:{type(exc).__name__}"
    if mode != 0o700:
        return False, f"queue_dir_unprotected:{oct(mode)}"
    return True, ""


ok, reason = ensure_no_symlink_components(queue_dir)
if not ok:
    emit("unsafe", reason, queue_dir)
    raise SystemExit(0)

for path in (queue_dir, queue_dir / "open", queue_dir / "resolved"):
    ok, reason = ensure_private_owned_dir(path)
    if not ok:
        emit("unsafe", reason, path)
        raise SystemExit(0)
    ok, reason = ensure_no_symlink_components(path)
    if not ok:
        emit("unsafe", reason, path)
        raise SystemExit(0)

emit("ok", path=queue_dir)
PY
}

upkeeper_tool_failure_queue_validate_selected_marker() {
  local marker_path="$1"
  local signing_key=""

  signing_key="$(upkeeper_tool_failure_queue_signing_key_material)" || signing_key=""

  python3 - "$ROOT_DIR" "$CODEX_TOOL_FAILURE_QUEUE_DIR" "$marker_path" "$signing_key" <<'PY'
import hashlib
import hmac
import json
import os
import re
import stat
import sys
from pathlib import Path

root, raw_queue_dir, raw_marker_path, signing_key = sys.argv[1:5]
root_path = Path(root).resolve()
queue_dir = Path(raw_queue_dir).expanduser()
if not queue_dir.is_absolute():
    queue_dir = Path(os.path.abspath(root_path / queue_dir))
else:
    queue_dir = Path(os.path.abspath(queue_dir))
open_dir = queue_dir / "open"
marker_path = Path(raw_marker_path).expanduser()
if not marker_path.is_absolute():
    marker_path = Path(os.path.abspath(root_path / marker_path))
else:
    marker_path = Path(os.path.abspath(marker_path))
uid = os.getuid()
signing_key_bytes = signing_key.encode("utf-8", "surrogateescape")


def emit(status: str, **fields: str) -> None:
    print(f"status={status}")
    for key, value in fields.items():
        print(f"{key}={value}")


def ensure_no_symlink_components(path: Path) -> tuple[bool, str]:
    current = Path(path.anchor or os.sep)
    for part in path.parts[1:]:
        current /= part
        try:
            st = os.lstat(current)
        except FileNotFoundError:
            continue
        except OSError as exc:
            return False, f"queue_path_unreadable:{type(exc).__name__}"
        if stat.S_ISLNK(st.st_mode):
            return False, f"queue_path_contains_symlink:{current}"
    return True, ""


def ensure_private_owned_dir(path: Path) -> tuple[bool, str]:
    try:
        st = os.lstat(path)
    except OSError as exc:
        return False, f"queue_dir_stat_failed:{type(exc).__name__}"
    if not stat.S_ISDIR(st.st_mode):
        return False, "queue_path_not_directory"
    if stat.S_ISLNK(st.st_mode):
        return False, "queue_dir_symlinked"
    if st.st_uid != uid:
        return False, "queue_dir_wrong_owner"
    mode = stat.S_IMODE(st.st_mode)
    if mode != 0o700:
        return False, f"queue_dir_unprotected:{oct(mode)}"
    return True, ""


def normalize_target(path_value: object) -> str:
    if not isinstance(path_value, str):
        return ""
    value = path_value.strip()
    if not value or "\0" in value or any(ord(char) < 32 for char in value):
        return ""
    if os.path.isabs(value):
        try:
            rel = Path(value).resolve().relative_to(root_path)
        except (OSError, ValueError):
            return ""
        return rel.as_posix()
    normalized = os.path.normpath(value).replace(os.sep, "/")
    if normalized in {".", ""} or normalized.startswith("../") or os.path.isabs(normalized):
        return ""
    return normalized


def marker_id_for(path_value: str) -> str:
    return hashlib.sha1(path_value.encode("utf-8", "surrogateescape")).hexdigest()[:24]


def marker_auth_hmac(data: dict) -> str:
    payload = json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    digest = hmac.new(signing_key_bytes, payload.encode("utf-8", "surrogateescape"), hashlib.sha256).hexdigest()
    return f"hmac-sha256:{digest}"


def display_text(value: object, limit: int = 500) -> str:
    text = str(value if value is not None else "unknown")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > limit:
        text = text[: limit - 15].rstrip() + "...<truncated>"
    return text or "unknown"


for path in (queue_dir, open_dir):
    ok, reason = ensure_no_symlink_components(path)
    if not ok:
        emit("unsafe", reason=reason)
        raise SystemExit(0)
    ok, reason = ensure_private_owned_dir(path)
    if not ok:
        emit("unsafe", reason=reason)
        raise SystemExit(0)

ok, reason = ensure_no_symlink_components(marker_path)
if not ok:
    emit("unsafe", reason=reason)
    raise SystemExit(0)

try:
    marker_relative = marker_path.relative_to(open_dir)
except ValueError:
    emit("unsafe", reason="marker_outside_open_dir")
    raise SystemExit(0)

if marker_relative.parent != Path("."):
    emit("unsafe", reason="marker_nested_path")
    raise SystemExit(0)

try:
    st = os.lstat(marker_path)
except OSError as exc:
    emit("unsafe", reason=f"marker_unreadable:{type(exc).__name__}")
    raise SystemExit(0)

if stat.S_ISLNK(st.st_mode):
    emit("unsafe", reason="marker_symlinked")
    raise SystemExit(0)
if not stat.S_ISREG(st.st_mode):
    emit("unsafe", reason="marker_not_regular")
    raise SystemExit(0)
if st.st_uid != uid:
    emit("unsafe", reason="marker_wrong_owner")
    raise SystemExit(0)

try:
    with marker_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
except (OSError, json.JSONDecodeError) as exc:
    emit("unsafe", reason=f"marker_json_invalid:{type(exc).__name__}")
    raise SystemExit(0)

if not isinstance(data, dict) or data.get("status") not in ("", None, "open"):
    emit("unsafe", reason="marker_status_invalid")
    raise SystemExit(0)

target_path = normalize_target(data.get("target_path"))
if not target_path:
    emit("unsafe", reason="marker_target_invalid")
    raise SystemExit(0)

expected_marker_id = marker_id_for(target_path)
stored_marker_id = str(data.get("marker_id", "") or "")
if stored_marker_id != expected_marker_id:
    emit("unsafe", reason="marker_id_mismatch")
    raise SystemExit(0)
if marker_path.stem != expected_marker_id:
    emit("unsafe", reason="marker_filename_mismatch")
    raise SystemExit(0)
if not signing_key_bytes:
    emit("unsafe", reason="marker_auth_key_unavailable")
    raise SystemExit(0)

stored_auth = data.get("marker_auth_hmac")
if not isinstance(stored_auth, str) or not stored_auth:
    emit("unsafe", reason="marker_auth_missing")
    raise SystemExit(0)

auth_payload = dict(data)
auth_payload.pop("marker_auth_hmac", None)
if stored_auth != marker_auth_hmac(auth_payload):
    emit("unsafe", reason="marker_auth_mismatch")
    raise SystemExit(0)

try:
    first_seen_epoch = int(data.get("first_seen_epoch", data.get("last_seen_epoch", 0)) or 0)
except (TypeError, ValueError):
    first_seen_epoch = 0

try:
    failure_count = int(data.get("failure_count", 0))
    if failure_count < 0:
        raise ValueError
except (TypeError, ValueError):
    failure_count = 0

emit(
    "ok",
    marker_id=expected_marker_id,
    marker_path=str(marker_path),
    target_path=target_path,
    first_seen_epoch=str(first_seen_epoch),
    failure_count=str(failure_count),
    first_failure_kind_json=display_text(data.get("first_failure_kind", "unknown")),
    first_failure_exit_line_json=display_text(data.get("first_failure_exit_line", "unknown")),
)
PY
}

upkeeper_tool_failure_queue_normalize_target() {
  local target_path="${1:-}"

  python3 - "$ROOT_DIR" "$target_path" <<'PY'
import os
import sys
from pathlib import Path

root, raw_target = sys.argv[1:3]
value = (raw_target or "").strip()
if not value or "\0" in value or any(ord(char) < 32 for char in value):
    raise SystemExit(1)

root_path = Path(root).resolve()
if os.path.isabs(value):
    try:
        print(Path(value).resolve().relative_to(root_path).as_posix())
    except (OSError, ValueError):
        raise SystemExit(1)
    raise SystemExit(0)

normalized = os.path.normpath(value).replace(os.sep, "/")
if normalized in {".", ""} or normalized.startswith("../") or os.path.isabs(normalized):
    raise SystemExit(1)
print(normalized)
PY
}

upkeeper_tool_failure_queue_sign_open_marker() {
  local target_path="$1"
  local signing_key=""

  signing_key="$(upkeeper_tool_failure_queue_signing_key_material)" || return 1

  python3 - "$ROOT_DIR" "$CODEX_TOOL_FAILURE_QUEUE_DIR" "$target_path" "$signing_key" <<'PY'
import hashlib
import hmac
import json
import os
import sys
from pathlib import Path

root, raw_queue_dir, target_path, signing_key = sys.argv[1:5]
root_path = Path(root).resolve()
queue_dir = Path(raw_queue_dir).expanduser()
if not queue_dir.is_absolute():
    queue_dir = Path(os.path.abspath(root_path / queue_dir))
else:
    queue_dir = Path(os.path.abspath(queue_dir))
open_dir = queue_dir / "open"
signing_key_bytes = signing_key.encode("utf-8", "surrogateescape")


def marker_id_for(path_value: str) -> str:
    return hashlib.sha1(path_value.encode("utf-8", "surrogateescape")).hexdigest()[:24]


def marker_auth_hmac(data: dict) -> str:
    payload = json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    digest = hmac.new(signing_key_bytes, payload.encode("utf-8", "surrogateescape"), hashlib.sha256).hexdigest()
    return f"hmac-sha256:{digest}"


def write_json_atomic(path: Path, data: dict) -> None:
    tmp = path.with_name(path.name + f".tmp.{os.getpid()}")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(tmp, path)
        os.chmod(path, 0o600)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


marker_path = open_dir / f"{marker_id_for(target_path)}.json"
if not marker_path.exists():
    print("status=missing")
    raise SystemExit(0)

with marker_path.open("r", encoding="utf-8") as handle:
    data = json.load(handle)
if not isinstance(data, dict):
    print("status=invalid")
    raise SystemExit(0)

data.pop("marker_auth_hmac", None)
data["marker_auth_hmac"] = marker_auth_hmac(data)
write_json_atomic(marker_path, data)
print("status=signed")
PY
}

upkeeper_tool_failure_queue_backfill_legacy_signatures() {
  local target_path="$1"
  local transcript_file="$2"
  local selected_marker_path="${3:-}"
  local redaction_key

  redaction_key="$(upkeeper_redaction_key_material)"

  python3 - "$ROOT_DIR" "$CODEX_TOOL_FAILURE_QUEUE_DIR" "$target_path" "$transcript_file" "$selected_marker_path" "$redaction_key" <<'PY'
import hashlib
import hmac
import json
import os
import re
import sys
from pathlib import Path

root, raw_queue_dir, target_path, transcript_raw, selected_marker_raw, redaction_key = sys.argv[1:7]
root_path = Path(root).resolve()
queue_dir = Path(raw_queue_dir).expanduser()
if not queue_dir.is_absolute():
    queue_dir = Path(os.path.abspath(root_path / queue_dir))
else:
    queue_dir = Path(os.path.abspath(queue_dir))
open_dir = queue_dir / "open"
transcript_path = Path(transcript_raw)
redaction_key_bytes = redaction_key.encode("utf-8", "surrogateescape")


def emit(action: str, **fields: str) -> None:
    print(f"action={action}")
    for key, value in fields.items():
        print(f"{key}={value}")


def short(value: str, limit: int = 500) -> str:
    value = re.sub(r"\s+", " ", value.strip())
    if len(value) > limit:
        return value[: limit - 15].rstrip() + "...<truncated>"
    return value


def hmac_hex(namespace: str, value: str) -> str:
    material = f"{namespace}\0{value}".encode("utf-8", "surrogateescape")
    return hmac.new(redaction_key_bytes, material, hashlib.sha256).hexdigest()


def value_hmac(namespace: str, value: str) -> str:
    return f"value-hmac-sha256:{hmac_hex(namespace, value)}"


def failure_signature(kind: str, command_hash: str, exit_line: str) -> str:
    payload = f"{kind}\0{command_hash}\0{exit_line}"
    return hashlib.sha256(payload.encode("utf-8", "surrogateescape")).hexdigest()


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


def transcript_failures(path: Path) -> list[dict[str, str]]:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []

    failures = []
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
        if re.match(r"exited [1-9][0-9]* in ", stripped) and interesting_failure_kind(current_kind):
            failures.append(
                {
                    "kind": current_kind,
                    "command_hash": value_hmac("command", short(current_command)),
                    "exit_line": short(stripped),
                }
            )
    return failures


def normalize_candidate(path_value: str) -> Path | None:
    if not path_value:
        return None
    candidate = Path(path_value).expanduser()
    if not candidate.is_absolute():
        candidate = Path(os.path.abspath(root_path / candidate))
    else:
        candidate = Path(os.path.abspath(candidate))
    try:
        candidate.relative_to(queue_dir)
    except ValueError:
        return None
    return candidate


def marker_id_for(path_value: str) -> str:
    return hashlib.sha1(path_value.encode("utf-8", "surrogateescape")).hexdigest()[:24]


def read_json(path: Path) -> dict:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def write_json_atomic(path: Path, data: dict) -> None:
    tmp = path.with_name(path.name + f".tmp.{os.getpid()}")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(tmp, path)
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def candidate_signatures(data: dict) -> list[str]:
    values: list[str] = []
    seen: set[str] = set()

    def add(kind: object, command_hash: object, exit_line: object) -> None:
        if not isinstance(kind, str) or not kind:
            return
        if not isinstance(exit_line, str) or not exit_line:
            return
        normalized_hash = ""
        if isinstance(command_hash, str) and command_hash:
            normalized_hash = command_hash
        if not normalized_hash:
            return
        signature = failure_signature(kind, normalized_hash, exit_line)
        if signature not in seen:
            seen.add(signature)
            values.append(signature)

    samples = data.get("failure_samples")
    if isinstance(samples, list):
        for sample in samples:
            if not isinstance(sample, dict):
                continue
            command_hash = sample.get("command_hash")
            if not command_hash and isinstance(sample.get("command"), str):
                command_hash = value_hmac("command", short(sample["command"]))
            add(sample.get("kind"), command_hash, sample.get("exit_line"))

    first_command_hash = data.get("first_failure_command_hash")
    if not first_command_hash and isinstance(data.get("first_failure_command"), str):
        first_command_hash = value_hmac("command", short(data["first_failure_command"]))
    add(data.get("first_failure_kind"), first_command_hash, data.get("first_failure_exit_line"))

    last_command_hash = data.get("last_failure_command_hash")
    if not last_command_hash and isinstance(data.get("last_failure_command"), str):
        last_command_hash = value_hmac("command", short(data["last_failure_command"]))
    add(data.get("last_failure_kind"), last_command_hash, data.get("last_failure_exit_line"))
    return values


def main() -> None:
    marker_path = open_dir / f"{marker_id_for(target_path)}.json"
    candidates = [marker_path]
    selected_marker_path = normalize_candidate(selected_marker_raw)
    if selected_marker_path is not None and selected_marker_path != marker_path:
        candidates.append(selected_marker_path)

    existing_path = next((path for path in candidates if path.exists()), None)
    if existing_path is None:
        emit("none", reason="marker_missing")
        return

    data = read_json(existing_path)
    if not data:
        emit("none", reason="marker_invalid")
        return

    existing_signatures = data.get("failure_signatures")
    if isinstance(existing_signatures, list) and any(isinstance(item, str) and item for item in existing_signatures):
        emit("present", marker_path=str(existing_path), signature_count=str(len(existing_signatures)))
        return

    failure_count = data.get("failure_count", 0)
    try:
        failure_count = int(failure_count)
    except (TypeError, ValueError):
        emit("none", reason="failure_count_invalid")
        return
    if failure_count <= 0:
        emit("none", reason="failure_count_not_positive")
        return

    transcript_signature_values = [
        failure_signature(item["kind"], item["command_hash"], item["exit_line"])
        for item in transcript_failures(transcript_path)
    ]
    if len(transcript_signature_values) != failure_count:
        emit(
            "none",
            reason="transcript_failure_count_mismatch",
            marker_count=str(failure_count),
            transcript_count=str(len(transcript_signature_values)),
        )
        return

    known_signatures = candidate_signatures(data)
    if known_signatures and not set(known_signatures).issubset(set(transcript_signature_values)):
        emit("none", reason="transcript_signature_mismatch", marker_signatures=str(len(known_signatures)))
        return

    data["failure_signatures"] = transcript_signature_values
    write_json_atomic(existing_path, data)
    emit("backfilled", marker_path=str(existing_path), signature_count=str(len(transcript_signature_values)))


try:
    main()
except Exception as exc:
    emit("error", error_class=type(exc).__name__)
PY
}

tool_failure_queue_finalize_run_core() {
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
command_hash_re = re.compile(r"^value-hmac-sha256:[0-9a-f]{64}$")


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

    for key in ("failure_samples", "unresolved_failures"):
        raw_list = data.get(key)
        if not isinstance(raw_list, list):
            cleaned.pop(key, None)
            continue
        cleaned_list = []
        for item in raw_list:
            failure_item = scrub_failure_item(item)
            if failure_item is not None:
                cleaned_list.append(failure_item)
        if cleaned_list:
            cleaned[key] = cleaned_list
        elif key in cleaned:
            del cleaned[key]
    return cleaned


def scrub_failure_item(item: dict) -> dict | None:
    kind = item.get("kind")
    command_hash = normalize_failure_command_hash(item.get("command_hash"), item.get("command"))
    exit_line = item.get("exit_line")
    if not isinstance(kind, str) or not kind:
        return None
    if not command_hash:
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


def normalize_failure_command_hash(command_hash: object, command_text: object = None) -> str:
    if isinstance(command_hash, str):
        candidate = command_hash.strip()
        if command_hash_re.match(candidate):
            return candidate
        if candidate:
            # Legacy data may have persisted raw commands in command_hash fields.
            return value_hmac("command", short(candidate))
    if isinstance(command_text, str):
        command_value = command_text.strip()
        if command_value:
            # Legacy records may keep command text in a sibling field.
            return value_hmac("command", short(command_value))
    return ""


def failure_signature(kind: str, command_hash: str, exit_line: str) -> str:
    payload = f"{kind}\0{command_hash}\0{exit_line}"
    return hashlib.sha256(payload.encode("utf-8", "surrogateescape")).hexdigest()


def command_signature(kind: str, command_hash: str) -> str:
    payload = f"{kind}\0{command_hash}"
    return hashlib.sha256(payload.encode("utf-8", "surrogateescape")).hexdigest()


def normalize_failure_item(
    kind: object,
    command_hash: object,
    exit_line: object,
    *,
    command_text: object = None,
) -> dict[str, str] | None:
    if not isinstance(kind, str) or not kind:
        return None
    command_hash = normalize_failure_command_hash(command_hash, command_text)
    if not command_hash:
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
        normalized = path.resolve().relative_to(open_dir.resolve())
    except ValueError:
        return None
    except OSError:
        return None
    if path.suffix != ".json":
        return None
    if normalized.parent != Path("."):
        return None
    return path


def selected_marker_path_matches_target(path: Path, expected_target_path: str) -> bool:
    if path.suffix != ".json":
        return False
    data = read_json(path)
    if not isinstance(data, dict):
        return False
    marker_target = normalize_target_path(data.get("target_path"))
    return marker_target == expected_target_path


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

    def add(
        kind: object,
        command_hash: object,
        exit_line: object,
        *,
        command_text: object = None,
    ) -> None:
        failure = normalize_failure_item(
            kind,
            command_hash,
            exit_line,
            command_text=command_text,
        )
        if failure is None or failure["signature"] in seen:
            return
        seen.add(failure["signature"])
        collected.append(failure)

    unresolved = data.get("unresolved_failures")
    if isinstance(unresolved, list):
        for item in unresolved:
            if not isinstance(item, dict):
                continue
            add(item.get("kind"), item.get("command_hash"), item.get("exit_line"), command_text=item.get("command"))
        if collected:
            return collected

    samples = data.get("failure_samples")
    if isinstance(samples, list):
        for item in samples:
            if not isinstance(item, dict):
                continue
            add(item.get("kind"), item.get("command_hash"), item.get("exit_line"), command_text=item.get("command"))

    add(
        data.get("first_failure_kind"),
        data.get("first_failure_command_hash"),
        data.get("first_failure_exit_line"),
        command_text=data.get("first_failure_command"),
    )
    add(
        data.get("last_failure_kind"),
        data.get("last_failure_command_hash"),
        data.get("last_failure_exit_line"),
        command_text=data.get("last_failure_command"),
    )
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
    selected_marker_path = normalize_open_marker_path(selected_marker_raw)
    if (
        not selected_marker_path
        or not selected_marker_path.exists()
        or not selected_marker_path_matches_target(selected_marker_path, normalized_target_path)
    ):
        selected_marker_path = marker_path
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

tool_failure_queue_finalize_run() {
  local target_path="$1"
  local transcript_file="$2"
  local codex_exit="$3"
  local status_marker="$4"
  local secure_queue_result secure_queue_status secure_queue_reason normalized_target_path
  local backfill_result backfill_action marker_sign_result marker_sign_status

  tool_failure_queue_enabled || return 0

  secure_queue_result="$(upkeeper_tool_failure_queue_prepare_secure_dirs)"
  secure_queue_status="$(upkeeper_preselect_output_field status "$secure_queue_result")"
  if [[ "$secure_queue_status" != "ok" ]]; then
    secure_queue_reason="$(upkeeper_preselect_output_field reason "$secure_queue_result")"
    log_line "WARN" "tool_failure_queue.update_skipped reason=$(shell_quote "${secure_queue_reason:-unknown}") queue_dir=$(shell_quote "$CODEX_TOOL_FAILURE_QUEUE_DIR")"
    return 0
  fi

  if ! normalized_target_path="$(upkeeper_tool_failure_queue_normalize_target "$target_path")"; then
    normalized_target_path=""
  fi
  if [[ -z "$normalized_target_path" ]]; then
    log_line "WARN" "tool_failure_queue.update_skipped reason=target_path_invalid target_path=$(shell_quote "${target_path:-unknown}")"
    return 0
  fi

  backfill_result="$(upkeeper_tool_failure_queue_backfill_legacy_signatures "$normalized_target_path" "$transcript_file" "${RUN_SELECTED_FAILURE_MARKER_PATH:-}")"
  backfill_action="$(upkeeper_preselect_output_field action "$backfill_result")"
  if [[ "$backfill_action" == "backfilled" ]]; then
    log_line "INFO" "tool_failure_queue.legacy_signatures_repaired signature_count=$(shell_quote "$(upkeeper_preselect_output_field signature_count "$backfill_result")") path_redacted=1"
  elif [[ "$backfill_action" == "error" ]]; then
    log_line "WARN" "tool_failure_queue.legacy_signatures_repair_failed error_class=$(shell_quote "$(upkeeper_preselect_output_field error_class "$backfill_result")") path_redacted=1"
  fi

  tool_failure_queue_finalize_run_core "$normalized_target_path" "$transcript_file" "$codex_exit" "$status_marker"

  if marker_sign_result="$(upkeeper_tool_failure_queue_sign_open_marker "$normalized_target_path")"; then
    marker_sign_status="$(upkeeper_preselect_output_field status "$marker_sign_result")"
    if [[ "$marker_sign_status" == "signed" ]]; then
      log_line "INFO" "tool_failure_queue.marker_auth_signed path_redacted=1"
    fi
  else
    log_line "WARN" "tool_failure_queue.marker_auth_sign_failed reason=signing_key_unavailable path_redacted=1"
  fi
}
