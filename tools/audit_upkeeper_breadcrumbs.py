#!/usr/bin/env python3
"""Audit local Upkeeper breadcrumb evidence into durable local custody records."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


TIMESTAMP_PREFIX = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:[+-]\d{4})?\s+")
VISUAL_MARKER = re.compile(r"(?:^|\s+)█\s+(PAGE|--FYI--|WORKER|ACTION|WAIT|HEALTH|OK|RUN|INFO)\s+")
DYNAMIC_PATTERNS = (
    (re.compile(r"\bcycle=[^ \t]+"), "cycle=<cycle>"),
    (re.compile(r"\brun_hash=[^ \t]+"), "run_hash=<run_hash>"),
    (re.compile(r"\btranscript=path-hmac-sha256:[0-9a-fA-F]+"), "transcript=path-hmac-sha256:<hash>"),
    (re.compile(r"path-hmac-sha256:[0-9a-fA-F]+"), "path-hmac-sha256:<hash>"),
    (re.compile(r"value-hmac-sha256:[0-9a-fA-F]+"), "value-hmac-sha256:<hash>"),
    (re.compile(r"\b\d+(?:\.\d+)?(?:ms|s|m)\b"), "<duration>"),
    (re.compile(r"/tmp/upkeeper-[^ \t]+"), "/tmp/upkeeper-<path>"),
)


@dataclass(frozen=True)
class Breadcrumb:
    ident: str
    fingerprint: str
    kind: str
    severity: str
    source: str
    source_path: str
    line_number: int
    excerpt: str
    normalized_excerpt: str
    status: str
    reason: str


def now_local() -> str:
    return dt.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    try:
        path.chmod(0o700)
    except OSError:
        pass


def write_json_atomic(path: Path, payload: dict) -> None:
    private_dir(path.parent)
    tmp = path.with_name(f"{path.name}.tmp.{os.getpid()}")
    with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)
    try:
        path.chmod(0o600)
    except OSError:
        pass


def read_json(path: Path) -> dict:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def stable_hash(*parts: str, length: int = 24) -> str:
    material = "\0".join(parts).encode("utf-8", "surrogateescape")
    return hashlib.sha256(material).hexdigest()[:length]


def normalize_line(line: str) -> str:
    value = TIMESTAMP_PREFIX.sub("", line, count=1)
    value = VISUAL_MARKER.sub(" ", value, count=1)
    value = " ".join(value.replace("\r", " ").split())
    for pattern, replacement in DYNAMIC_PATTERNS:
        value = pattern.sub(replacement, value)
    return value


def excerpt(line: str, limit: int = 260) -> str:
    value = " ".join(line.replace("\r", " ").replace("\t", " ").split())
    return value if len(value) <= limit else value[: limit - 3] + "..."


def tail_lines(path: Path, limit: int) -> list[tuple[int, str]]:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except FileNotFoundError:
        return []
    except OSError as exc:
        raise SystemExit(f"breadcrumb audit: cannot read {path}: {exc}") from exc
    if limit > 0 and len(lines) > limit:
        start = len(lines) - limit
        return [(start + index + 1, line) for index, line in enumerate(lines[start:])]
    return [(index + 1, line) for index, line in enumerate(lines)]


def context_has(lines: list[tuple[int, str]], index: int, needle: str, radius: int = 20) -> bool:
    low = max(0, index - radius)
    high = min(len(lines), index + radius + 1)
    return any(needle in line for _, line in lines[low:high])


def expected_fixture(lines: list[tuple[int, str]], index: int, line: str) -> bool:
    if (
        "transcript directory is not private /tmp/upkeeper-transcripts-test." in line
        and context_has(lines, index, "transcript_artifacts_test: ok")
    ):
        return True
    if (
        "machine health blocked live cycle before issue selection" in line
        and context_has(lines, index, "precontact_backup_test: ok", radius=30)
    ):
        return True
    if (
        "startup_anomaly.gate_target status=missing" in line
        and "/tmp/upkeeper-client-link-test." in line
        and context_has(lines, index, "client_link_tools_test: ok", radius=40)
    ):
        return True
    return False


def classify_line(line: str) -> tuple[str, str, str] | None:
    lower = line.lower()
    if "page" in lower and "[error]" in lower:
        return "page_error", "high", "pageable error output is not healthy"
    if "[error]" in lower:
        return "error_line", "high", "error output requires custody"
    if "checks failed" in lower or "\tfail\t" in lower:
        return "failed_check", "high", "check failure requires custody"
    if "startup_anomaly.gate_unresolved" in line:
        return "startup_anomaly_unresolved", "high", "startup anomaly gate remained unresolved"
    if "previous_run.anomaly" in line:
        return "previous_run_anomaly", "high", "prior run anomaly was reported"
    if "cycle.exit" in line and ("exit_code=0" not in line and "reason=work_done" not in line):
        return "cycle_exit_nonzero", "high", "cycle ended outside the healthy shape"
    if "lattice.unavailable" in line:
        return "lattice_unavailable", "medium", "lattice degraded mode was observed"
    if "transcript.prune_blocked" in line:
        return "transcript_prune_blocked", "medium", "transcript pruning was blocked"
    if "[warn]" in lower or " --fyi-- " in lower:
        return "warning_line", "medium", "warning output requires triage or suppression"
    return None


def breadcrumb_from_line(source: str, path: Path, line_number: int, line: str, *, status: str) -> Breadcrumb | None:
    classification = classify_line(line)
    if classification is None:
        return None
    kind, severity, reason = classification
    normalized = normalize_line(line)
    fingerprint = stable_hash(kind, normalized, length=32)
    return Breadcrumb(
        ident=f"{kind}-{stable_hash(kind, normalized)}",
        fingerprint=fingerprint,
        kind=kind,
        severity=severity,
        source=source,
        source_path=str(path),
        line_number=line_number,
        excerpt=excerpt(line),
        normalized_excerpt=normalized,
        status=status,
        reason=reason,
    )


def scan_text_file(source: str, path: Path, max_lines: int) -> tuple[list[Breadcrumb], list[Breadcrumb]]:
    lines = tail_lines(path, max_lines)
    open_items: list[Breadcrumb] = []
    suppressed_items: list[Breadcrumb] = []
    for index, (line_number, line) in enumerate(lines):
        if expected_fixture(lines, index, line):
            item = breadcrumb_from_line(source, path, line_number, line, status="suppressed")
            if item is not None:
                suppressed_items.append(item)
            continue
        item = breadcrumb_from_line(source, path, line_number, line, status="open")
        if item is not None:
            open_items.append(item)
    return open_items, suppressed_items


def iter_transcripts(paths: Iterable[Path]) -> Iterable[Path]:
    for transcript_dir in paths:
        if not transcript_dir.exists() or not transcript_dir.is_dir():
            continue
        yield from sorted(transcript_dir.glob("*.log"))


def marker_breadcrumb(path: Path, source: str, default_kind: str, default_severity: str) -> Breadcrumb | None:
    data = read_json(path)
    if not data:
        return None
    status = str(data.get("status") or "open")
    if status not in {"open", "unresolved"}:
        return None
    kind = str(data.get("kind") or default_kind)
    severity = str(data.get("severity") or default_severity)
    reason = str(data.get("reason") or data.get("summary") or f"{kind} marker is open")
    target = str(data.get("target_file") or data.get("repair_target_file") or "")
    normalized = normalize_line(f"{kind} {severity} {reason} {target}".strip())
    fingerprint = stable_hash(source, kind, normalized, length=32)
    return Breadcrumb(
        ident=f"{kind}-{stable_hash(source, kind, normalized)}",
        fingerprint=fingerprint,
        kind=kind,
        severity=severity,
        source=source,
        source_path=str(path),
        line_number=0,
        excerpt=excerpt(reason),
        normalized_excerpt=normalized,
        status="open",
        reason=reason,
    )


def marker_records(root: Path, source: str, default_kind: str, default_severity: str) -> list[Breadcrumb]:
    open_dir = root / "open"
    if not open_dir.exists():
        return []
    records: list[Breadcrumb] = []
    for path in sorted(open_dir.glob("*.json")):
        item = marker_breadcrumb(path, source, default_kind, default_severity)
        if item is not None:
            records.append(item)
    return records


def record_payload(item: Breadcrumb, *, seen_at: str, existing: dict | None = None) -> dict:
    existing = existing or {}
    first_seen = existing.get("first_seen_at") or seen_at
    occurrence_count = int(existing.get("occurrence_count") or 0) + 1
    return {
        "schema": 1,
        "record_type": "upkeeper_breadcrumb",
        "id": item.ident,
        "fingerprint": item.fingerprint,
        "status": item.status,
        "kind": item.kind,
        "severity": item.severity,
        "source": item.source,
        "source_path": item.source_path,
        "line_number": item.line_number,
        "first_seen_at": first_seen,
        "last_seen_at": seen_at,
        "occurrence_count": occurrence_count,
        "reason": item.reason,
        "evidence": {
            "excerpt": item.excerpt,
            "normalized_excerpt": item.normalized_excerpt,
        },
    }


def write_records(state_root: Path, open_items: list[Breadcrumb], suppressed_items: list[Breadcrumb], *, resolve_missing: bool) -> dict:
    seen_at = now_local()
    open_dir = state_root / "open"
    suppressed_dir = state_root / "suppressed"
    resolved_dir = state_root / "resolved"
    for directory in (open_dir, suppressed_dir, resolved_dir):
        private_dir(directory)

    seen_open_ids: set[str] = set()
    written_open = 0
    written_suppressed = 0
    for item in open_items:
        seen_open_ids.add(item.ident)
        path = open_dir / f"{item.ident}.json"
        payload = record_payload(item, seen_at=seen_at, existing=read_json(path))
        write_json_atomic(path, payload)
        written_open += 1
    for item in suppressed_items:
        path = suppressed_dir / f"{item.ident}.json"
        payload = record_payload(item, seen_at=seen_at, existing=read_json(path))
        payload["suppression_reason"] = "expected local negative-test fixture context"
        write_json_atomic(path, payload)
        written_suppressed += 1

    resolved_count = 0
    if resolve_missing:
        for path in sorted(open_dir.glob("*.json")):
            if path.stem in seen_open_ids:
                continue
            payload = read_json(path)
            if not payload:
                continue
            payload["status"] = "resolved"
            payload["resolved_at"] = seen_at
            payload["resolution_reason"] = "not_seen_in_current_breadcrumb_audit"
            write_json_atomic(resolved_dir / path.name, payload)
            try:
                path.unlink()
            except OSError:
                pass
            resolved_count += 1

    return {
        "written_open": written_open,
        "written_suppressed": written_suppressed,
        "resolved_missing": resolved_count,
    }


def unique(items: Iterable[Breadcrumb]) -> list[Breadcrumb]:
    by_id: dict[str, Breadcrumb] = {}
    for item in items:
        by_id[item.ident] = item
    return [by_id[key] for key in sorted(by_id)]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="Repository root. Default: current directory.")
    parser.add_argument("--state-root", default="", help="Breadcrumb state root. Default: ROOT/runtime/upkeeper-breadcrumbs.")
    parser.add_argument("--log", action="append", default=[], help="Log file to scan. May be repeated.")
    parser.add_argument("--transcript-dir", action="append", default=[], help="Transcript directory to scan. May be repeated.")
    parser.add_argument("--obligation-root", default="", help="Automation obligation root. Default: ROOT/runtime/upkeeper-obligations.")
    parser.add_argument("--failure-queue-root", default="", help="Tool failure queue root. Default: ROOT/runtime/unaddressed-tool-failures.")
    parser.add_argument("--max-lines", type=int, default=5000, help="Tail line limit per text file. 0 scans the whole file.")
    parser.add_argument("--write", action="store_true", help="Write open/suppressed breadcrumb records under state root.")
    parser.add_argument("--resolve-missing", action="store_true", help="Move previously open records not seen in this audit to resolved.")
    parser.add_argument("--json", action="store_true", help="Emit JSON summary.")
    parser.add_argument("--fail-on-open", action="store_true", help="Exit 2 when open breadcrumbs are present.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    state_root = Path(args.state_root).resolve() if args.state_root else root / "runtime/upkeeper-breadcrumbs"
    log_paths = [Path(item) for item in args.log] or [root / "Upkeeper.log"]
    transcript_dirs = [Path(item) for item in args.transcript_dir] or [root / "runtime/upkeeper-transcripts"]
    obligation_root = Path(args.obligation_root).resolve() if args.obligation_root else root / "runtime/upkeeper-obligations"
    failure_queue_root = Path(args.failure_queue_root).resolve() if args.failure_queue_root else root / "runtime/unaddressed-tool-failures"

    open_items: list[Breadcrumb] = []
    suppressed_items: list[Breadcrumb] = []
    scanned_sources = 0
    for path in log_paths:
        found, suppressed = scan_text_file("log", path, args.max_lines)
        open_items.extend(found)
        suppressed_items.extend(suppressed)
        scanned_sources += 1
    for path in iter_transcripts(transcript_dirs):
        found, suppressed = scan_text_file("transcript", path, args.max_lines)
        open_items.extend(found)
        suppressed_items.extend(suppressed)
        scanned_sources += 1
    open_items.extend(marker_records(obligation_root, "automation_obligation", "automation_obligation", "high"))
    open_items.extend(marker_records(failure_queue_root, "tool_failure_queue", "tool_failure", "high"))

    open_items = unique(open_items)
    suppressed_items = unique(suppressed_items)
    write_summary = {"written_open": 0, "written_suppressed": 0, "resolved_missing": 0}
    if args.write:
        write_summary = write_records(state_root, open_items, suppressed_items, resolve_missing=args.resolve_missing)

    summary = {
        "schema": 1,
        "status": "open_breadcrumbs" if open_items else "clean",
        "state_root": str(state_root),
        "scanned_sources": scanned_sources,
        "open_count": len(open_items),
        "suppressed_count": len(suppressed_items),
        **write_summary,
        "open": [record_payload(item, seen_at=now_local(), existing={"occurrence_count": -1}) for item in open_items],
        "suppressed": [record_payload(item, seen_at=now_local(), existing={"occurrence_count": -1}) for item in suppressed_items],
    }

    if args.json:
        json.dump(summary, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    else:
        print(
            "breadcrumb audit: "
            f"status={summary['status']} scanned_sources={scanned_sources} "
            f"open={len(open_items)} suppressed={len(suppressed_items)} "
            f"state_root={state_root}"
        )
    if args.fail_on_open and open_items:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
