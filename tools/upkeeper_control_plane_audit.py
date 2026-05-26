#!/usr/bin/env python3
"""Inventory Upkeeper control-plane state without backend or network access."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import sys
from dataclasses import dataclass, asdict
from typing import Iterable


ROOT_SCRATCH_NAMES = {
    "$db",
    "$db-journal",
    ".upkeeper-tmp",
    "upkeeper.tmp",
}
ROOT_SCRATCH_SUFFIXES = (
    ".db",
    ".db-journal",
    ".sqlite",
    ".sqlite3",
    ".tmp",
    ".swp",
)
LOCAL_EVIDENCE_ROOTS = (
    "runtime/",
    "transcripts/",
    "postmortems/",
    "Upkeeper.log",
)


@dataclass(frozen=True)
class Finding:
    ident: str
    klass: str
    severity: str
    path: str
    source: str
    summary: str
    remediation: str


def stable_hash(*parts: str, length: int = 24) -> str:
    material = "\0".join(parts).encode("utf-8", "surrogateescape")
    return hashlib.sha256(material).hexdigest()[:length]


def git_bytes(root: pathlib.Path, args: list[str], *, allow_failure: bool = False) -> bytes:
    proc = subprocess.run(
        ["git", *args],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != 0 and not allow_failure:
        stderr = proc.stderr.decode("utf-8", "replace").strip()
        raise SystemExit(f"control-plane audit: git {' '.join(args)} failed: {stderr}")
    return proc.stdout


def git_text(root: pathlib.Path, args: list[str], *, allow_failure: bool = False) -> str:
    return git_bytes(root, args, allow_failure=allow_failure).decode("utf-8", "replace").strip()


def decode_path(value: bytes) -> str:
    return value.decode("utf-8", "surrogateescape")


def tracked_paths(root: pathlib.Path) -> list[str]:
    data = git_bytes(root, ["ls-files", "-z"])
    return sorted(path for path in (decode_path(item) for item in data.split(b"\0") if item) if path)


def porcelain_status(root: pathlib.Path) -> tuple[list[dict[str, str]], list[str], list[str]]:
    data = git_bytes(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])
    entries = [item for item in data.split(b"\0") if item]
    records: list[dict[str, str]] = []
    tracked_changed: list[str] = []
    untracked: list[str] = []
    index = 0
    while index < len(entries):
        raw = entries[index]
        text = decode_path(raw)
        code = text[:2]
        path = text[3:] if len(text) > 3 else ""
        original = ""
        if code and code[0] in {"R", "C"} and index + 1 < len(entries):
            index += 1
            original = decode_path(entries[index])
        if code == "??":
            untracked.append(path)
        else:
            tracked_changed.append(path)
        records.append({"code": code, "path": path, "original_path": original})
        index += 1
    return records, sorted(tracked_changed), sorted(untracked)


def branch_name(root: pathlib.Path) -> str:
    value = git_text(root, ["branch", "--show-current"], allow_failure=True)
    if value:
        return value
    return git_text(root, ["rev-parse", "--short", "HEAD"], allow_failure=True) or "unknown"


def is_root_path(path: str) -> bool:
    return path != "" and "/" not in path.rstrip("/")


def is_root_scratch(path: str) -> bool:
    name = pathlib.PurePosixPath(path).name
    if not is_root_path(path):
        return False
    if name in ROOT_SCRATCH_NAMES:
        return True
    if name.startswith("$"):
        return True
    return any(name.endswith(suffix) for suffix in ROOT_SCRATCH_SUFFIXES)


def local_evidence_class(path: str) -> tuple[str, str] | None:
    if path == "Upkeeper.log":
        return "tracked_log_artifact", "tracked Upkeeper.log is local runtime evidence"
    if path.startswith("runtime/"):
        if path.endswith(".lock") or "/lock" in path or "active.lock" in path:
            return "tracked_lock_artifact", "tracked lock state is local process-control evidence"
        if "manifest" in pathlib.PurePosixPath(path).name:
            return "tracked_manifest_artifact", "tracked manifest state is local selection evidence"
        if "transcript" in path:
            return "tracked_transcript_artifact", "tracked transcript state is local backend evidence"
        if "postmortem" in path:
            return "tracked_postmortem_artifact", "tracked postmortem state is local incident evidence"
        return "tracked_runtime_artifact", "tracked runtime state violates the source boundary"
    if path.startswith("transcripts/"):
        return "tracked_transcript_artifact", "tracked transcript state is local backend evidence"
    if path.startswith("postmortems/") or path.startswith("postmortem/"):
        return "tracked_postmortem_artifact", "tracked postmortem state is local incident evidence"
    if is_root_path(path) and path.endswith(".lock"):
        return "tracked_lock_artifact", "tracked lock state is local process-control evidence"
    return None


def add_finding(
    findings: list[Finding],
    klass: str,
    severity: str,
    path: str,
    source: str,
    summary: str,
    remediation: str,
) -> None:
    findings.append(
        Finding(
            ident=f"{klass}-{stable_hash(klass, path, summary)}",
            klass=klass,
            severity=severity,
            path=path,
            source=source,
            summary=summary,
            remediation=remediation,
        )
    )


def inventory_tracked_paths(paths: Iterable[str], findings: list[Finding]) -> None:
    for path in paths:
        if is_root_scratch(path):
            add_finding(
                findings,
                "tracked_root_scratch_artifact",
                "high",
                path,
                "git_ls_files",
                "root scratch artifact is tracked as source",
                "remove the artifact from tracked source and preserve any useful evidence under ignored runtime state",
            )
        evidence = local_evidence_class(path)
        if evidence is not None:
            klass, summary = evidence
            add_finding(
                findings,
                klass,
                "high",
                path,
                "git_ls_files",
                summary,
                "untrack the local evidence artifact and keep it under ignored machine-local state",
            )


def inventory_untracked_paths(paths: Iterable[str], findings: list[Finding]) -> None:
    for path in paths:
        if is_root_scratch(path):
            add_finding(
                findings,
                "untracked_root_scratch_artifact",
                "medium",
                path,
                "git_status",
                "root scratch artifact is present outside ignored runtime state",
                "delete it if disposable, or move evidence under ignored runtime state before continuing",
            )


def count_json_files(path: pathlib.Path) -> int:
    if not path.exists() or not path.is_dir():
        return 0
    return sum(1 for item in path.glob("*.json") if item.is_file())


def runtime_inventory(root: pathlib.Path, findings: list[Finding]) -> dict[str, object]:
    runtime = root / "runtime"
    active_lock = runtime / "upkeeper-active.lock"
    open_obligations = runtime / "upkeeper-obligations" / "open"
    anomaly_open = runtime / "upkeeper-anomaly-custody" / "open"
    manifest = runtime / "upkeeper-file-manifest.json"
    postmortems = runtime / "postmortems"
    transcripts = runtime / "transcripts"
    result = {
        "runtime_present": runtime.exists(),
        "active_lock_present": active_lock.exists(),
        "open_obligation_count": count_json_files(open_obligations),
        "open_anomaly_count": count_json_files(anomaly_open),
        "manifest_present": manifest.exists(),
        "postmortem_count": count_json_files(postmortems),
        "transcript_count": len(list(transcripts.glob("*"))) if transcripts.exists() and transcripts.is_dir() else 0,
    }
    if active_lock.exists():
        add_finding(
            findings,
            "active_lock_present",
            "medium",
            "runtime/upkeeper-active.lock",
            "runtime_inventory",
            "active Upkeeper owner lock is present",
            "verify the owner process or clear stale lock state before launching another writer",
        )
    open_count = int(result["open_obligation_count"])
    if open_count:
        add_finding(
            findings,
            "open_automation_obligations",
            "high",
            "runtime/upkeeper-obligations/open",
            "runtime_inventory",
            f"{open_count} open automation obligation(s) are present",
            "repair, classify, or preserve obligations before new workload",
        )
    return result


def state_root_inventory(state_root: pathlib.Path | None, findings: list[Finding]) -> dict[str, object]:
    if state_root is None:
        return {"state_root_configured": False}
    deferred_dirs = [
        state_root / "deferred",
        state_root / "issue-deferred",
        state_root / "deferred-issues",
    ]
    deferred_count = 0
    for path in deferred_dirs:
        deferred_count += count_json_files(path)
    result = {
        "state_root_configured": True,
        "state_root": str(state_root),
        "deferred_issue_record_count": deferred_count,
    }
    if deferred_count:
        add_finding(
            findings,
            "deferred_issue_records_present",
            "medium",
            str(state_root),
            "state_root_inventory",
            f"{deferred_count} deferred issue record(s) are present",
            "review deferred issue records before assuming the queue is clean",
        )
    return result


def recent_log_inventory(path: pathlib.Path | None, max_lines: int, findings: list[Finding]) -> dict[str, object]:
    if path is None or not path.exists():
        return {"log_configured": path is not None, "log_present": False}
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as exc:
        raise SystemExit(f"control-plane audit: cannot read log {path}: {exc}") from exc
    selected = lines[-max_lines:] if max_lines > 0 else lines
    final_disposition = ""
    nonzero_cycle_exit = 0
    pageable_error = 0
    for line in selected:
        if "final disposition:" in line:
            final_disposition = " ".join(line.split())
        lower = line.lower()
        if "cycle.exit" in line and "exit_code=0" not in line and "reason=work_done" not in lower:
            nonzero_cycle_exit += 1
        if " page " in lower and "[error]" in lower:
            pageable_error += 1
    if nonzero_cycle_exit:
        add_finding(
            findings,
            "recent_nonzero_cycle_exit",
            "high",
            str(path),
            "recent_log_inventory",
            f"{nonzero_cycle_exit} nonzero cycle.exit marker(s) found in recent log",
            "put the prior cycle under anomaly custody before new backend work",
        )
    if pageable_error:
        add_finding(
            findings,
            "recent_page_error",
            "high",
            str(path),
            "recent_log_inventory",
            f"{pageable_error} PAGE [ERROR] marker(s) found in recent log",
            "classify the pageable error as expected fixture output or repair the source failure",
        )
    return {
        "log_configured": True,
        "log_present": True,
        "scanned_lines": len(selected),
        "final_disposition": final_disposition,
        "nonzero_cycle_exit_count": nonzero_cycle_exit,
        "page_error_count": pageable_error,
    }


def build_payload(args: argparse.Namespace) -> dict[str, object]:
    root = pathlib.Path(args.root).resolve()
    if not (root / ".git").exists():
        git_top = git_text(root, ["rev-parse", "--show-toplevel"], allow_failure=True)
        if git_top:
            root = pathlib.Path(git_top).resolve()
    findings: list[Finding] = []
    tracked = tracked_paths(root)
    status_records, changed, untracked = porcelain_status(root)
    inventory_tracked_paths(tracked, findings)
    inventory_untracked_paths(untracked, findings)
    state_root = pathlib.Path(args.state_root).resolve() if args.state_root else None
    log_path = pathlib.Path(args.log).resolve() if args.log else root / "Upkeeper.log"
    if args.no_default_log and not args.log:
        log_path = None
    runtime = runtime_inventory(root, findings)
    external_state = state_root_inventory(state_root, findings)
    recent_log = recent_log_inventory(log_path, args.max_log_lines, findings)
    findings = sorted(findings, key=lambda item: (item.severity, item.klass, item.path, item.ident))
    return {
        "schema": 1,
        "record_type": "upkeeper_control_plane_audit",
        "status": "clean" if not findings else "findings",
        "root": str(root),
        "branch": branch_name(root),
        "counts": {
            "tracked_path_count": len(tracked),
            "tracked_change_count": len(changed),
            "untracked_path_count": len(untracked),
            "finding_count": len(findings),
        },
        "git": {
            "status_records": status_records,
            "tracked_changes": changed,
            "untracked_paths": untracked,
        },
        "runtime": runtime,
        "external_state": external_state,
        "recent_log": recent_log,
        "findings": [asdict(item) for item in findings],
    }


def print_text(payload: dict[str, object]) -> None:
    counts = payload.get("counts", {})
    if not isinstance(counts, dict):
        counts = {}
    print(
        "control_plane_audit: "
        f"status={payload.get('status')} "
        f"findings={counts.get('finding_count', 0)} "
        f"tracked_changes={counts.get('tracked_change_count', 0)} "
        f"untracked={counts.get('untracked_path_count', 0)} "
        f"branch={payload.get('branch', 'unknown')}"
    )
    findings = payload.get("findings", [])
    if isinstance(findings, list):
        for item in findings[:10]:
            if not isinstance(item, dict):
                continue
            print(
                "control_plane_audit: finding "
                f"id={item.get('ident')} "
                f"class={item.get('klass')} "
                f"severity={item.get('severity')} "
                f"path={item.get('path')} "
                f"summary={item.get('summary')}"
            )
        if len(findings) > 10:
            print(f"control_plane_audit: finding output truncated remaining={len(findings) - 10}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="repository root to audit")
    parser.add_argument("--state-root", default="", help="optional backlog state root to inventory")
    parser.add_argument("--log", default="", help="optional loop log path; defaults to Upkeeper.log when present")
    parser.add_argument("--no-default-log", action="store_true", help="do not read root Upkeeper.log unless --log is set")
    parser.add_argument("--max-log-lines", type=int, default=400, help="recent log lines to scan")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of operator text")
    parser.add_argument("--no-fail", action="store_true", help="exit 0 even when findings are present")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    payload = build_payload(args)
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print_text(payload)
    if payload.get("status") != "clean" and not args.no_fail:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
