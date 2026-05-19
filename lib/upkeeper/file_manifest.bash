# File manifest cache for deterministic target selection.
#
# The manifest is local runtime state: it records source-visible files with
# repo-relative paths, mtimes, sizes, and a hashed repo-root identifier so
# selection can work from a ready sorted list without leaking checkout-local
# absolute paths or asking the backend model to rediscover repository shape.

resolve_upkeeper_manifest_path() {
  local raw_path="$1"

  if [[ "$raw_path" == /* ]]; then
    printf '%s' "$raw_path"
  else
    printf '%s/%s' "$ROOT_DIR" "$raw_path"
  fi
}

ensure_file_manifest_for_selection() {
  local manifest_path manifest_dir output rc

  manifest_path="$(resolve_upkeeper_manifest_path "$CODEX_FILE_MANIFEST_PATH")"
  CODEX_FILE_MANIFEST_PATH="$manifest_path"

  if [[ "$CODEX_FILE_MANIFEST_MODE" == "off" ]]; then
    log_line "INFO" "file_manifest.skip reason=manifest_mode_off source=$CODEX_SELECTION_SOURCE mode=$CODEX_FILE_MANIFEST_MODE path=$(shell_quote "$manifest_path")"
    CODEX_SELECTION_SOURCE="enumerate"
    return 0
  fi

  if [[ "$CODEX_SELECTION_SOURCE" != "manifest" ]]; then
    log_line "INFO" "file_manifest.skip reason=selection_source_disabled source=$CODEX_SELECTION_SOURCE mode=$CODEX_FILE_MANIFEST_MODE path=$(shell_quote "$manifest_path")"
    return 0
  fi

  manifest_dir="$(dirname -- "$manifest_path")"
  if ! mkdir -p "$manifest_dir"; then
    log_line "WARN" "file_manifest.skip reason=manifest_dir_unwritable path=$(shell_quote "$manifest_path") action=fall_back_to_enumerate"
    CODEX_SELECTION_SOURCE="enumerate"
    return 0
  fi
  if ! chmod 700 "$manifest_dir"; then
    log_line "WARN" "file_manifest.skip reason=manifest_dir_unprotected path=$(shell_quote "$manifest_path") action=fall_back_to_enumerate"
    CODEX_SELECTION_SOURCE="enumerate"
    return 0
  fi

  set +e
  output="$(python3 - "$ROOT_DIR" "$manifest_path" "$CODEX_FILE_MANIFEST_MODE" "$CODEX_FILE_MANIFEST_MAX_AGE_SECONDS" "$CODEX_UPKEEPER_IGNORE_FILE" <<'PY'
import fnmatch
import hashlib
import json
import os
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

root = Path(os.path.expanduser(sys.argv[1]))
if not root.is_absolute():
    root = Path.cwd() / root
root = root.absolute()

manifest_path = Path(os.path.expanduser(sys.argv[2]))
if not manifest_path.is_absolute():
    manifest_path = Path.cwd() / manifest_path
mode = sys.argv[3]
ignore_file = Path(sys.argv[5]).expanduser()
if not ignore_file.is_absolute():
    ignore_file = root / ignore_file


def ensure_not_symlink(path: Path, *, context: str) -> None:
    try:
        if stat.S_ISLNK(path.lstat().st_mode):
            raise ValueError(f"refuse_manifest_input_symlink {context}={path}")
    except FileNotFoundError:
        return


ensure_not_symlink(root, context="root")
if ignore_file.exists():
    ensure_not_symlink(ignore_file, context="ignore_file")
try:
    max_age_seconds = max(0, int(sys.argv[4]))
except ValueError:
    max_age_seconds = 300

root_hash = hashlib.sha256(str(root).encode("utf-8", "surrogateescape")).hexdigest()


def emit(**fields: object) -> None:
    for key, value in fields.items():
        print(f"{key}={str(value).replace(chr(10), ' ')}")


def git(args: list[str]) -> bytes:
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.DEVNULL)


def inside_git_repo() -> bool:
    try:
        return git(["rev-parse", "--is-inside-work-tree"]).strip() == b"true"
    except (OSError, subprocess.CalledProcessError):
        return False


def root_relative(path: Path) -> str:
    try:
        rel = path.relative_to(root)
    except ValueError:
        return ""
    return rel.as_posix()


def validate_manifest_rel_path(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    if not value or "\x00" in value or any(ord(char) < 32 for char in value):
        return None
    if "/" in value or "\\" in value:
        parts = value.split("/")
        if value.startswith("/"):
            return None
        if any(part in (".", "..", "") for part in parts):
            return None
    else:
        if value in (".", "..", ""):
            return None

    normalized = os.path.normpath(value)
    if normalized in (".", "") or os.path.isabs(normalized):
        return None
    if normalized.startswith(".."):
        return None
    if any(part in (".", "..", "") for part in normalized.split(os.sep)):
        return None

    candidate = (root / normalized).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        return None

    return normalized.replace(os.sep, "/")


def load_upkeeperignore_patterns() -> list[tuple[bool, str]]:
    patterns: list[tuple[bool, str]] = []
    try:
        lines = ignore_file.read_text(encoding="utf-8").splitlines()
    except OSError:
        return patterns
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        negated = line.startswith("!")
        if negated:
            line = line[1:].strip()
            if not line:
                continue
        patterns.append((negated, line.replace("\\", "/")))
    return patterns


upkeeperignore_patterns = load_upkeeperignore_patterns()


def upkeeperignore_pattern_matches(path: str, pattern: str) -> bool:
    pattern = pattern.strip()
    if not pattern:
        return False
    anchored = pattern.startswith("/")
    if anchored:
        pattern = pattern.lstrip("/")
    directory_only = pattern.endswith("/")
    if directory_only:
        pattern = pattern.rstrip("/")
    if not pattern:
        return False

    if directory_only:
        if "/" in pattern or anchored:
            return path == pattern or path.startswith(pattern + "/")
        return pattern in path.split("/")

    name = os.path.basename(path)
    if anchored or "/" in pattern:
        return fnmatch.fnmatch(path, pattern)
    return fnmatch.fnmatch(name, pattern) or any(fnmatch.fnmatch(part, pattern) for part in path.split("/"))


def upkeeper_path_ignored(path: str) -> bool:
    ignored = False
    for negated, pattern in upkeeperignore_patterns:
        if upkeeperignore_pattern_matches(path, pattern):
            ignored = not negated
    return ignored


def compute_files_fingerprint(source: str, files: list[dict[str, object]]) -> str:
    parts: list[str] = []
    for entry in files:
        try:
            parts.append(
                f"{entry['rel_path']}\t{entry['mtime_ns']}\t{entry['size']}\t{entry['mode']}"
            )
        except KeyError:
            continue
    return hashlib.sha256((f"{source}\n" + "\n".join(sorted(parts))).encode("utf-8", "surrogateescape")).hexdigest()


def git_paths() -> list[str]:
    raw = git(["ls-files", "-co", "--exclude-standard", "-z"])
    return sorted(path for path in raw.decode("utf-8", "surrogateescape").split("\0") if path)


def git_ignored_paths(paths: list[str]) -> set[str]:
    if not paths:
        return set()
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "check-ignore", "-z", "--no-index", "--stdin"],
            input=("\0".join(paths) + "\0").encode("utf-8", "surrogateescape"),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        return set()
    if result.returncode not in (0, 1):
        return set()
    return set(path for path in result.stdout.decode("utf-8", "surrogateescape").split("\0") if path)


def local_paths() -> list[str]:
    paths: list[str] = []
    excluded_dirs = {".git", "runtime"}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [name for name in dirnames if name not in excluded_dirs]
        for filename in filenames:
            rel = root_relative(Path(dirpath) / filename)
            if rel:
                paths.append(rel)
    return sorted(paths)


def file_entry(rel_path: str) -> dict[str, object] | None:
    path = root / rel_path
    try:
        st = path.lstat()
    except OSError:
        return None
    if stat.S_ISLNK(st.st_mode):
        return None
    if not stat.S_ISREG(st.st_mode):
        return None
    return {
        "rel_path": rel_path,
        "mtime": int(st.st_mtime),
        "mtime_ns": int(st.st_mtime_ns),
        "size": int(st.st_size),
        "mode": format(stat.S_IMODE(st.st_mode), "04o"),
    }


def build_payload() -> tuple[dict[str, object], str]:
    source = "git" if inside_git_repo() else "find"
    raw_paths = git_paths() if source == "git" else local_paths()
    git_ignored = git_ignored_paths(raw_paths) if source == "git" else set()
    entries = [
        entry
        for rel in raw_paths
        if rel not in git_ignored and not upkeeper_path_ignored(rel) and (entry := file_entry(rel)) is not None
    ]
    entries.sort(key=lambda item: (int(item["mtime_ns"]), str(item["rel_path"])))

    fingerprint = compute_files_fingerprint(source, entries)

    git_head = "none"
    git_status_hash = "none"
    if source == "git":
        try:
            git_head = git(["rev-parse", "--verify", "HEAD"]).decode("utf-8", "replace").strip() or "none"
        except (OSError, subprocess.CalledProcessError):
            git_head = "none"
        try:
            status_raw = git(["status", "--porcelain=v1", "-z", "--untracked-files=all"])
            git_status_hash = hashlib.sha256(status_raw).hexdigest()
        except (OSError, subprocess.CalledProcessError):
            git_status_hash = "unknown"

    payload = {
        "schema_version": 2,
        "generated_epoch": int(time.time()),
        "root_hash": root_hash,
        "source": source,
        "fingerprint": fingerprint,
        "git_head": git_head,
        "git_status_hash": git_status_hash,
        "files": entries,
    }

    payload["files_fingerprint"] = fingerprint
    return payload, source


def existing_payload() -> dict[str, object] | None:
    try:
        with manifest_path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict):
        return None
    if (
        payload.get("schema_version") != 2
        or payload.get("root_hash") != root_hash
        or "root" in payload
    ):
        return None
    if not isinstance(payload.get("files"), list):
        return None

    existing_files = payload.get("files") or []
    if isinstance(existing_files, list):
        # Rebuild legacy manifests that persisted raw checkout roots or per-file
        # absolute paths. The manifest consumer only needs repo-relative paths
        # plus metadata, so those fields are retained nowhere in fresh payloads.
        if any(isinstance(entry, dict) and "abs_path" in entry for entry in existing_files):
            return None
        try:
            # Verify that existing payload entries still hash back to their own
            # fingerprint. This protects against model- or attacker-written
            # manifest tampering while preserving legacy file layout.
            payload_source = str(payload.get("source", "git"))
            payload_entries = [
                {
                    "rel_path": rel_path,
                    "mtime_ns": entry.get("mtime_ns"),
                    "size": entry.get("size"),
                    "mode": entry.get("mode"),
                }
                for entry in existing_files
                for rel_path in [validate_manifest_rel_path(entry.get("rel_path", ""))]
                if isinstance(entry, dict)
                and rel_path is not None
                and isinstance(entry.get("mtime_ns"), (int, float))
                and isinstance(entry.get("size"), (int, float))
                and isinstance(entry.get("mode"), str)
            ]
            if isinstance(payload.get("files_fingerprint"), str) is False:
                return None
            computed = compute_files_fingerprint(payload_source, payload_entries)
            payload_files_fingerprint = payload.get("files_fingerprint")
            if payload_files_fingerprint != computed:
                return None
        except Exception:
            return None
    return payload


def write_payload(payload: dict[str, object]) -> None:
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(manifest_path.parent, 0o700)
    fd, temp_name = tempfile.mkstemp(prefix=f".{manifest_path.name}.", suffix=".tmp", dir=str(manifest_path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, sort_keys=True, separators=(",", ":"))
            handle.write("\n")
        os.replace(temp_name, manifest_path)
    finally:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass


current_payload, source = build_payload()
existing = existing_payload()
now = int(time.time())
reason = "missing"
action = "rebuilt"

if mode == "refresh":
    reason = "forced_refresh"
elif existing is None:
    reason = "missing_or_invalid"
elif existing.get("files_fingerprint") != current_payload["files_fingerprint"]:
    reason = "files_fingerprint_changed"
elif existing.get("fingerprint") != current_payload["fingerprint"]:
    reason = "fingerprint_changed"
elif max_age_seconds and now - int(existing.get("generated_epoch", 0) or 0) > max_age_seconds:
    reason = "max_age_exceeded"
else:
    action = "reused"
    reason = "current"

if action == "rebuilt":
    write_payload(current_payload)
    payload = current_payload
else:
    payload = existing or current_payload

emit(
    action=action,
    reason=reason,
    source=payload.get("source", source),
    count=len(payload.get("files", [])),
    path=str(manifest_path),
    fingerprint=str(payload.get("fingerprint", "unknown"))[:16],
)
PY
)"
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    log_line "WARN" "file_manifest.skip reason=manifest_update_failed path=$(shell_quote "$manifest_path") action=fall_back_to_enumerate detail=$(shell_quote "$output")"
    CODEX_SELECTION_SOURCE="enumerate"
    return 0
  fi

  local action reason source count fingerprint
  action="$(sed -n 's/^action=//p' <<<"$output" | tail -1)"
  reason="$(sed -n 's/^reason=//p' <<<"$output" | tail -1)"
  source="$(sed -n 's/^source=//p' <<<"$output" | tail -1)"
  count="$(sed -n 's/^count=//p' <<<"$output" | tail -1)"
  fingerprint="$(sed -n 's/^fingerprint=//p' <<<"$output" | tail -1)"

  log_line "INFO" "file_manifest.ready action=${action:-unknown} reason=${reason:-unknown} source=${source:-unknown} count=${count:-unknown} path=$(shell_quote "$manifest_path") fingerprint=${fingerprint:-unknown}"
}
