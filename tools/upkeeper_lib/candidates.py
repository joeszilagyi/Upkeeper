"""Shared helpers for deterministic Upkeeper candidate selection."""

from __future__ import annotations

import fnmatch
import hashlib
import json
import os
import re
import stat
import subprocess
from pathlib import Path
from typing import Any, Iterable

BUILD_NAMES = {
    "Dockerfile",
    "Justfile",
    "Makefile",
    "Rakefile",
    "dockerfile",
    "justfile",
    "makefile",
}

SCRIPT_EXTS = {
    ".awk",
    ".bash",
    ".cjs",
    ".fish",
    ".go",
    ".js",
    ".jsx",
    ".ksh",
    ".lua",
    ".mjs",
    ".pl",
    ".ps1",
    ".psm1",
    ".py",
    ".rb",
    ".rs",
    ".sh",
    ".ts",
    ".tsx",
    ".zsh",
}

TEST_DIRS = {"__tests__", "test", "tests"}
TEXT_SAMPLE_SIZE = 4096
EXCLUDED_PREFIXES = (".git/", "runtime/")
EXCLUDED_EXACT = {"Upkeeper.log"}
SOURCE_SAFETY_REASON_CODES = {
    "target path is outside the repository": "outside_repo",
    "target path resolves outside the repository": "outside_repo",
    "target path is missing or unreadable": "missing_at_stat",
    "target path is a symlink": "symlink",
    "target path is not a regular file": "not_regular_file",
    "target path appears to be binary": "binary_or_unreadable",
}


def normalize_rel_path(path: str) -> str:
    path = path.strip()
    if not path:
        return ""
    if re.match(r"^[A-Za-z]:[\\/]", path):
        return ""
    path = path.replace("\\", "/")
    path = re.sub(r"^\./+", "", path)
    parts: list[str] = []
    for part in path.split("/"):
        if not part or part == ".":
            continue
        if part == "..":
            return ""
        parts.append(part)
    return "/".join(parts)


def has_surrogate_codepoint(raw: str) -> bool:
    return any(0xD800 <= ord(ch) <= 0xDFFF for ch in raw)


def encode_path_text(raw: str) -> str:
    pieces: list[str] = []
    for ch in raw:
        codepoint = ord(ch)
        if ch == "\\":
            pieces.append("\\\\")
        elif 0xDC80 <= codepoint <= 0xDCFF:
            pieces.append(f"\\x{codepoint - 0xDC00:02x}")
        elif codepoint < 0x20 or codepoint == 0x7F:
            pieces.append(f"\\x{codepoint:02x}")
        else:
            pieces.append(ch)
    return "".join(pieces)


def decode_path_text(raw: str) -> str:
    decoded = bytearray()
    i = 0
    while i < len(raw):
        ch = raw[i]
        if ch != "\\":
            decoded.extend(ch.encode("utf-8", "surrogateescape"))
            i += 1
            continue
        if i + 1 >= len(raw):
            decoded.append(ord("\\"))
            i += 1
            continue
        nxt = raw[i + 1]
        if nxt == "\\":
            decoded.append(ord("\\"))
            i += 2
            continue
        if nxt == "x" and i + 3 < len(raw):
            hex_pair = raw[i + 2 : i + 4]
            if re.fullmatch(r"[0-9A-Fa-f]{2}", hex_pair):
                decoded.append(int(hex_pair, 16))
                i += 4
                continue
        decoded.append(ord("\\"))
        i += 1
    return decoded.decode("utf-8", "surrogateescape")


def stored_rel_path(path: str) -> str:
    normalized = normalize_rel_path(path)
    return encode_path_text(normalized) if normalized else ""


def operational_rel_path(path: str) -> str:
    return normalize_rel_path(decode_path_text(path))


def decode_git_output(raw: bytes) -> str:
    return raw.decode("utf-8", "surrogateescape")


def repo_relative_parts(path: str) -> list[str] | None:
    normalized = operational_rel_path(path)
    if has_surrogate_codepoint(normalized):
        return None
    if not normalized or normalized == "." or normalized.startswith("../") or Path(normalized).is_absolute():
        return None
    parts = normalized.split("/")
    if any(part in ("", ".", "..") for part in parts):
        return None
    return parts


def repo_rel_path(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return ""


def normalize_upkeeper_ignore_file(root: Path, raw: str | None = None) -> Path:
    raw = raw or os.environ.get("CODEX_UPKEEPER_IGNORE_FILE") or os.environ.get("UPKEEPER_IGNORE_FILE") or ".upkeeperignore"
    path = Path(raw).expanduser()
    return path.resolve() if path.is_absolute() else (root / path).resolve()


def load_upkeeperignore_patterns(root: Path, raw: str | None = None) -> list[tuple[bool, str]]:
    ignore_file = normalize_upkeeper_ignore_file(root, raw)
    patterns: list[tuple[bool, str]] = []
    try:
        lines = ignore_file.read_text(encoding="utf-8").splitlines()
    except OSError:
        return patterns
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        negated = line.startswith("!")
        if negated:
            line = line[1:].strip()
            if not line:
                continue
        patterns.append((negated, line.replace("\\", "/")))
    return patterns


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

    name = Path(path).name
    if anchored or "/" in pattern:
        return fnmatch.fnmatch(path, pattern)
    return fnmatch.fnmatch(name, pattern) or any(fnmatch.fnmatch(part, pattern) for part in path.split("/"))


def upkeeper_path_ignored(path: str, patterns: list[tuple[bool, str]]) -> bool:
    ignored = False
    for negated, pattern in patterns:
        if upkeeperignore_pattern_matches(path, pattern):
            ignored = not negated
    return ignored


def git_output(root: Path, args: list[str], default: str = "") -> str:
    try:
        return subprocess.check_output(["git", "-C", str(root), *args], text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError, UnicodeEncodeError, UnicodeError, ValueError):
        return default


def git_path_ignored(root: Path, path: Path) -> bool:
    rel = repo_rel_path(root, path)
    if not rel:
        return False
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "check-ignore", "-q", "--no-index", "--", rel],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return result.returncode == 0
    except (FileNotFoundError, UnicodeEncodeError, UnicodeError, ValueError, OSError):
        return False


def git_path_tracked(root: Path, path: Path) -> bool:
    rel = repo_rel_path(root, path)
    if not rel:
        return False
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "--error-unmatch", "--", rel],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return result.returncode == 0
    except (FileNotFoundError, UnicodeEncodeError, UnicodeError, ValueError, OSError):
        return False


def git_ignored_paths(root: Path, paths: list[str]) -> set[str]:
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
    return set(path for path in decode_git_output(result.stdout).split("\0") if path)


def source_safe_real_path(root: Path, rel_path: str) -> Path | None:
    rel_path = operational_rel_path(rel_path)
    try:
        real = (root / rel_path).resolve(strict=True)
        real.relative_to(root.resolve())
        return real
    except (OSError, ValueError, UnicodeEncodeError, UnicodeError):
        return None


def read_fd_sample(file_fd: int, sample_size: int) -> bytes:
    return os.read(file_fd, sample_size)


def read_sample_no_follow(root: Path, parts: list[str], sample_size: int = TEXT_SAMPLE_SIZE) -> bytes | None:
    if sample_size <= 0:
        return b""
    if not parts:
        return b""
    try:
        current = root.resolve()
        current_mode = None
        for index, part in enumerate(parts):
            current = current / part
            st = current.lstat()
            if stat.S_ISLNK(st.st_mode):
                return None
            current_mode = st.st_mode
            if index < len(parts) - 1 and not stat.S_ISDIR(st.st_mode):
                return None
        if not stat.S_ISREG(current_mode or 0):
            return None
        with current.open("rb") as handle:
            return read_fd_sample(handle.fileno(), sample_size)
    except OSError:
        return None


def source_safe_file_stat(root: Path, rel_path: str, *, require_text: bool = False) -> tuple[os.stat_result | None, str]:
    rel_path = operational_rel_path(rel_path)
    parts = repo_relative_parts(rel_path)
    if parts is None:
        return None, "target path is outside the repository"
    path = root / rel_path
    try:
        st = path.lstat()
    except OSError:
        return None, "target path is missing or unreadable"
    if stat.S_ISLNK(st.st_mode):
        return None, "target path is a symlink"
    if source_safe_real_path(root, rel_path) is None:
        return None, "target path resolves outside the repository"
    if not stat.S_ISREG(st.st_mode):
        return None, "target path is not a regular file"
    if require_text:
        sample = read_sample_no_follow(root, parts)
        if sample is None or b"\0" in sample:
            return None, "target path appears to be binary"
    return st, ""


def canonicalize_source_safety_reason(reason: str) -> str:
    return SOURCE_SAFETY_REASON_CODES.get(reason, reason)


def executable_text_candidate(root: Path, rel_path: str) -> bool:
    _, error = source_safe_file_stat(root, rel_path, require_text=True)
    return not error


def is_test_path(path: str) -> bool:
    parts = path.split("/")
    name = parts[-1]
    return any(part in TEST_DIRS for part in parts) or name.startswith("test_") or name.endswith("_test.py")


def parse_git_porcelain_v1_z_entries(raw: bytes) -> list[tuple[str, str, str | None]]:
    if not raw:
        return []
    parts = raw.split(b"\0")
    entries: list[tuple[str, str, str | None]] = []
    i = 0
    while i < len(parts):
        item = parts[i]
        i += 1
        if not item:
            continue
        if len(item) < 4 or item[2:3] != b" ":
            continue
        status_code = decode_git_output(item[:2])
        path = decode_git_output(item[3:])
        old_path = None
        if status_code[0] in {"R", "C"} or status_code[1] in {"R", "C"}:
            if i < len(parts):
                old_path = decode_git_output(parts[i]) or None
                i += 1
        entries.append((status_code, path, old_path))
    return entries


def parse_git_porcelain_status_map(raw: bytes) -> dict[str, str]:
    status_by_path: dict[str, str] = {}
    for status_code, path, old_path in parse_git_porcelain_v1_z_entries(raw):
        if path:
            status_by_path[path] = status_code
        if old_path:
            status_by_path[old_path] = status_code
    return status_by_path


def git_porcelain_status_map(root: Path) -> dict[str, str]:
    try:
        raw = subprocess.check_output(
            ["git", "-C", str(root), "status", "--porcelain=v1", "-z"],
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError, UnicodeEncodeError, UnicodeError, ValueError):
        return {}
    return parse_git_porcelain_status_map(raw)


def parse_git_ls_files_s_map(raw: bytes, *, wanted: set[str] | None = None) -> dict[str, str]:
    wanted_set = wanted if wanted is None else set(wanted)
    head_by_path: dict[str, str] = {}
    for item in raw.split(b"\0"):
        if not item:
            continue
        try:
            meta, path_raw = item.split(b"\t", 1)
        except ValueError:
            continue
        parts = meta.split()
        if len(parts) < 2:
            continue
        path = decode_git_output(path_raw)
        if wanted_set is not None and path not in wanted_set:
            continue
        head_by_path[path] = parts[1].decode("utf-8", "surrogateescape")
    return head_by_path


def git_head_blob_map(root: Path, paths: Iterable[str]) -> dict[str, str]:
    if not paths:
        return {}
    wanted = set(paths)
    try:
        raw = subprocess.check_output(["git", "-C", str(root), "ls-files", "-s", "-z"], stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError, UnicodeEncodeError, UnicodeError, ValueError):
        return {}
    return parse_git_ls_files_s_map(raw, wanted=wanted)


def git_porcelain_status_for_path(root: Path, rel_path: str) -> str:
    rel_path = operational_rel_path(rel_path)
    if has_surrogate_codepoint(rel_path):
        return ""
    try:
        raw = subprocess.check_output(
            ["git", "-C", str(root), "status", "--porcelain=v1", "-z", "--", rel_path],
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError, UnicodeEncodeError, UnicodeError, ValueError):
        return ""
    entries = parse_git_porcelain_v1_z_entries(raw)
    return entries[0][0] if entries else ""


def stored_git_status_code(status_code: str) -> str:
    if len(status_code) < 2:
        return "clean"
    return status_code[:2].replace(" ", "_")


def inside_git_repo(root: Path) -> bool:
    return git_output(root, ["rev-parse", "--is-inside-work-tree"]) == "true"


def selected_git_metadata(
    root: Path,
    rel_path: str,
    *,
    git_status: str | None = None,
    head_blob: str | None = None,
    include_worktree_hash: bool = True,
) -> dict[str, str]:
    rel_path = operational_rel_path(rel_path)
    meta: dict[str, str] = {}
    if has_surrogate_codepoint(rel_path):
        return {
            "git_status": "unreadable",
            "content_state": "unreadable",
            "head_blob": "unavailable",
            "worktree_hash": "unavailable",
        }
    status = git_status if git_status is not None else git_porcelain_status_for_path(root, rel_path)
    meta["git_status"] = stored_git_status_code(status) if status else "clean"
    if include_worktree_hash:
        raw_worktree_hash = git_output(root, ["hash-object", "--", rel_path], "missing")
    else:
        raw_worktree_hash = "unavailable"
    if head_blob is not None:
        raw_head_blob = head_blob
    elif status == "??":
        raw_head_blob = "none"
    else:
        raw_head_blob = git_output(root, ["rev-parse", f"HEAD:{rel_path}"], "none")
    if raw_head_blob == "none":
        content_state = "untracked"
    elif not include_worktree_hash:
        content_state = "unknown"
    elif raw_head_blob == raw_worktree_hash:
        content_state = "matches_head"
    else:
        content_state = "differs_from_head"
    meta["content_state"] = content_state
    meta["head_blob"] = raw_head_blob
    meta["worktree_hash"] = raw_worktree_hash
    return meta


def split_csv(raw: str) -> list[str]:
    return [item.strip() for item in raw.split(",") if item.strip()]


def path_matches_any(path: str, patterns: list[str]) -> bool:
    if not patterns:
        return True
    name = Path(path).name
    return any(fnmatch.fnmatch(path, pattern) or fnmatch.fnmatch(name, pattern) for pattern in patterns)


def path_excluded(path: str, patterns: list[str]) -> bool:
    if not patterns:
        return False
    name = Path(path).name
    return any(fnmatch.fnmatch(path, pattern) or fnmatch.fnmatch(name, pattern) for pattern in patterns)


def normalized_repo_target(root: Path, path: str) -> str:
    if not path:
        return ""
    expanded = path.strip()
    if not expanded:
        return ""
    if any(ord(char) < 32 for char in expanded) or "\0" in expanded:
        return ""
    expanded = expanded.strip().strip("`'\"()[]{}<>.,;")
    expanded = re.sub(r"(?::L?\d+(?:-L?\d+)?)$", "", expanded, flags=re.IGNORECASE)
    expanded = re.sub(r"#L?\d+(?:-L?\d+)?$", "", expanded, flags=re.IGNORECASE)
    expanded = expanded.strip().strip("`'\"()[]{}<>.,;")
    if not expanded:
        return ""
    expanded = os.path.expanduser(expanded)
    if os.path.isabs(expanded):
        try:
            rel_path = Path(expanded).resolve(strict=False).relative_to(root.resolve()).as_posix()
        except ValueError:
            return ""
    else:
        rel_path = normalize_rel_path(expanded)
    return rel_path


def path_within_target_root(path: str, root_filter: str, max_depth: str, root: Path) -> bool:
    if not root_filter:
        return True
    normalized = normalized_repo_target(root, root_filter)
    if not normalized:
        return False
    if path == normalized:
        depth = 0
    elif path.startswith(normalized.rstrip("/") + "/"):
        remainder = path[len(normalized.rstrip("/")) + 1 :]
        depth = len([part for part in remainder.split("/") if part])
    else:
        return False
    if max_depth:
        try:
            return depth <= int(max_depth)
        except ValueError:
            return True
    return True


def module_filter_match(path: str, modules: set[str]) -> bool:
    if not modules:
        return True

    lowered = path.lower()
    name = Path(lowered).name
    ext = Path(name).suffix
    parts = set(lowered.split("/"))

    def p24() -> bool:
        tokens = (
            "codex",
            "llm",
            "prompt",
            "transcript",
            "postmortem",
            "fallback",
            "report",
            "status",
            "session",
        )
        return lowered.startswith("prompts/") or any(token in lowered for token in tokens)

    def p25() -> bool:
        return (
            path in {"Upkeeper", "Upkeeper.conf", "AGENTS.md"}
            or lowered.startswith(("lib/upkeeper/", "docs/", "prompts/", "configurations/"))
            or "compatibility" in lowered
        )

    def p26() -> bool:
        return (
            ext in {".md", ".txt", ".rst"}
            or lowered.startswith(("docs/", "prompts/"))
            or name in {"readme.md", "agents.md"}
            or lowered.endswith(".conf")
        )

    def p27() -> bool:
        return "educational" in lowered or "debrief" in lowered or "p27" in lowered

    def p28() -> bool:
        return (
            "test" in parts
            or "tests" in parts
            or "spec" in parts
            or "specs" in parts
            or "validate" in lowered
            or name.endswith(("_test.py", ".bats"))
            or name.startswith("test_")
        )

    def p29() -> bool:
        reuse_tokens = {
            "artifact",
            "command",
            "config",
            "fixture",
            "format",
            "helper",
            "json",
            "marker",
            "parse",
            "parser",
            "prompt",
            "reuse",
            "status",
            "template",
            "transcript",
            "validate",
            "validation",
        }
        return (
            lowered.startswith(("lib/upkeeper/", "tools/", "tests/", "prompts/", "docs/"))
            or name in {"readme.md", "agents.md"}
            or any(token in lowered for token in reuse_tokens)
        )

    def p30() -> bool:
        hardening_tokens = {
            "backup",
            "bootstrap",
            "chimneysweep",
            "compatibility",
            "contract",
            "fallback",
            "flameon",
            "hardening",
            "health",
            "lattice",
            "manifest",
            "obligation",
            "preflight",
            "quota",
            "recovery",
            "regression",
            "restore",
            "sandbox",
            "security",
            "selection",
            "stress",
            "validate",
            "validation",
        }
        return (
            path in {"Upkeeper", "FlameOn", "ChimneySweep", "Upkeeper.conf", "AGENTS.md"}
            or lowered.startswith(("lib/upkeeper/", "tools/", "tests/", "testruns/", "docs/", "prompts/"))
            or name in {"readme.md", "plans.md"}
            or name.startswith("change_notes_")
            or any(token in lowered for token in hardening_tokens)
        )

    checks = {
        "p24": p24,
        "p25": p25,
        "p26": p26,
        "p27": p27,
        "p28": p28,
        "p29": p29,
        "p30": p30,
    }
    return any(checks[module]() for module in modules if module in checks)


def manifest_paths(root: Path, path: str) -> tuple[list[tuple[float, str]], str]:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return [], "manifest_unreadable"
    if not isinstance(payload, dict):
        return [], "manifest_invalid"
    schema_version = payload.get("schema_version")
    real_root = os.path.realpath(root)
    if schema_version == 1:
        if payload.get("root") != real_root:
            return [], "manifest_root_mismatch"
    elif schema_version == 2:
        expected_root_hash = hashlib.sha256(real_root.encode("utf-8", "surrogateescape")).hexdigest()
        if payload.get("root_hash") != expected_root_hash:
            return [], "manifest_root_mismatch"
    else:
        return [], "manifest_invalid"
    files = payload.get("files")
    if not isinstance(files, list):
        return [], "manifest_invalid_files"

    paths: list[tuple[float, str]] = []
    for item in files:
        if not isinstance(item, dict):
            continue
        rel_path = str(item.get("rel_path", ""))
        if not rel_path:
            continue
        stat_result, error = source_safe_file_stat(root, rel_path)
        if error:
            continue
        if isinstance(item.get("mtime_ns"), (int, float)):
            mtime_ns = int(item["mtime_ns"])
        else:
            try:
                mtime_ns = int(item.get("mtime", 0) * 1_000_000_000)
            except (TypeError, ValueError):
                mtime_ns = int(getattr(stat_result, "st_mtime_ns", 0))
        mtime = mtime_ns / 1_000_000_000
        paths.append((mtime, rel_path))
    return paths, "manifest"


def enumerate_paths(root: Path, select_untracked: bool) -> tuple[list[tuple[float, str]], str]:
    try:
        ls_files_args = ["git", "ls-files", "-c", "-z"]
        if select_untracked:
            ls_files_args = ["git", "ls-files", "-c", "-o", "--exclude-standard", "-z"]
        raw_paths = subprocess.check_output(["git", "-C", str(root), *ls_files_args[1:]], stderr=subprocess.DEVNULL)
        raw = raw_paths.decode("utf-8", "surrogateescape").split("\0")
        source = "enumerate"
    except (OSError, subprocess.CalledProcessError):
        raw = []
        source = "enumerate"
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [name for name in dirnames if name not in {".git", "runtime"}]
            for filename in filenames:
                rel = repo_rel_path(root, Path(dirpath) / filename)
                if rel:
                    raw.append(rel)

    paths: list[tuple[float, str]] = []
    for path in raw:
        if not path:
            continue
        stat_result, error = source_safe_file_stat(root, path)
        if not error and stat_result is not None:
            paths.append((stat_result.st_mtime, path))
    return sorted(paths, key=lambda item: (item[0], item[1])), source


def open_failure_markers(
    candidate_paths: set[str],
    *,
    failure_queue_dir: str,
    failure_queue_enabled: str,
    failure_queue_bypass: str,
) -> list[dict[str, object]]:
    if failure_queue_enabled != "1" or failure_queue_bypass == "1":
        return []
    open_dir = Path(failure_queue_dir) / "open"
    if not open_dir.is_dir():
        return []

    markers = []
    for marker_path in sorted(open_dir.glob("*.json")):
        try:
            with marker_path.open("r", encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(data, dict) or data.get("status") not in ("", None, "open"):
            continue
        target = str(data.get("target_path", ""))
        if target not in candidate_paths:
            continue
        try:
            first_seen = int(data.get("first_seen_epoch", data.get("last_seen_epoch", 0)) or 0)
        except (TypeError, ValueError):
            first_seen = 0
        markers.append(
            {
                "target_path": target,
                "first_seen_epoch": first_seen,
                "marker_id": str(data.get("marker_id", marker_path.stem)),
                "marker_path": str(marker_path),
                "failure_count": str(data.get("failure_count", "unknown")),
                "first_failure_kind": str(data.get("first_failure_kind", "unknown")),
                "first_failure_exit_line": str(data.get("first_failure_exit_line", "unknown")),
            }
        )
    return sorted(markers, key=lambda item: (item["first_seen_epoch"], item["target_path"], item["marker_id"]))


def source_safe_text_paths(root: Path, *, upkeeper_ignore_file: str | None = None) -> list[tuple[float, str]]:
    if not inside_git_repo(root):
        return []
    try:
        raw = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"], stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError):
        return []
    ignore_patterns = load_upkeeperignore_patterns(root, upkeeper_ignore_file)
    result: list[tuple[float, str]] = []
    for path in decode_git_output(raw).split("\0"):
        if not path:
            continue
        if path in EXCLUDED_EXACT or path.startswith(EXCLUDED_PREFIXES) or is_test_path(path):
            continue
        if upkeeper_path_ignored(path, ignore_patterns):
            continue
        if git_path_ignored(root, root / path):
            continue
        stat_result, error = source_safe_file_stat(root, path, require_text=True)
        if error or stat_result is None:
            continue
        result.append((stat_result.st_mtime, path))
    return sorted(result, key=lambda item: (item[0], item[1]))


def live_candidate_rows(
    root: Path,
    candidate_scope: str = "eligible",
    upkeeper_ignore_file: str | None = None,
) -> list[dict[str, Any]]:
    upkeeperignore_patterns = load_upkeeperignore_patterns(root, upkeeper_ignore_file)
    inside = inside_git_repo(root)
    git_status_map: dict[str, str] = {}
    head_blob_map: dict[str, str] = {}
    if inside:
        if candidate_scope == "current-tracked":
            raw = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"])
        else:
            raw = subprocess.check_output(["git", "-C", str(root), "ls-files", "-co", "--exclude-standard", "-z"])
        paths = [p for p in decode_git_output(raw).split("\0") if p]
        if paths:
            git_status_map = git_porcelain_status_map(root)
            head_blob_map = git_head_blob_map(root, paths)
    else:
        paths = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [name for name in dirnames if name not in {".git", "runtime"}]
            for filename in filenames:
                rel = repo_rel_path(root, Path(dirpath) / filename)
                if rel:
                    paths.append(rel)
    git_ignored = git_ignored_paths(root, paths) if inside else set()
    text_reason_cache: dict[str, tuple[os.stat_result | None, str]] = {}
    stat_cache: dict[str, tuple[os.stat_result | None, str]] = {}
    rows = []
    for rel in paths:
        reason = ""
        state = "eligible"
        p = root / rel
        if rel not in stat_cache:
            stat_cache[rel] = source_safe_file_stat(root, rel)
        st, reason = stat_cache[rel]
        reason = canonicalize_source_safety_reason(reason)
        if rel in EXCLUDED_EXACT:
            reason = "excluded_exact"
        elif rel.startswith(EXCLUDED_PREFIXES):
            reason = "excluded_prefix"
        elif upkeeper_path_ignored(rel, upkeeperignore_patterns):
            reason = "upkeeperignore"
        elif rel in git_ignored:
            reason = "gitignore"
        else:
            if not reason and st is not None:
                if candidate_scope == "current-tracked":
                    _, reason = text_reason_cache.setdefault(rel, source_safe_file_stat(root, rel, require_text=True))
                    reason = canonicalize_source_safety_reason(reason)
                else:
                    if is_test_path(rel):
                        reason = "test_path"
                    name = p.name
                    ext = p.suffix.lower()
                    candidate = name in BUILD_NAMES or ext in SCRIPT_EXTS
                    if not candidate and st.st_mode & 0o111:
                        _, text_reason = text_reason_cache.setdefault(rel, source_safe_file_stat(root, rel, require_text=True))
                        text_reason = canonicalize_source_safety_reason(text_reason)
                        candidate = not text_reason
                        if text_reason:
                            reason = "executable_not_text"
                    if candidate and not reason:
                        _, reason = text_reason_cache.setdefault(rel, source_safe_file_stat(root, rel, require_text=True))
                        reason = canonicalize_source_safety_reason(reason)
                    if not candidate and not reason:
                        reason = "unsupported_extension"
        if reason:
            state = "excluded"
        if reason == "symlink":
            meta = {
                "git_status": "symlink",
                "content_state": "symlink",
                "head_blob": "none",
                "worktree_hash": "unavailable",
            }
        else:
            meta = selected_git_metadata(
                root,
                rel,
                git_status=git_status_map.get(rel, ""),
                head_blob=head_blob_map.get(rel),
                include_worktree_hash=(state == "eligible"),
            )
        rows.append(
            {
                "path": stored_rel_path(rel),
                "candidate_state": state,
                "exclusion_reason": reason,
                "mtime_epoch": st.st_mtime if st is not None else None,
                "git_status": meta.get("git_status", ""),
                "content_state": meta.get("content_state", ""),
                "head_blob": meta.get("head_blob", ""),
                "worktree_hash": meta.get("worktree_hash", ""),
            }
        )
    return rows
