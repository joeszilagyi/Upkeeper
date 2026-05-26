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
from datetime import datetime
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
UNKNOWN_ROOT_EVIDENCE_NAMES = {
    "core",
    "core.dump",
    "nohup.out",
}
UNKNOWN_ROOT_EVIDENCE_SUFFIXES = (
    ".log",
    ".pid",
    ".trace",
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


@dataclass(frozen=True)
class Invariant:
    ident: str
    description: str
    severity: str
    evidence_source: str
    remediation_policy: str
    operator_message: str
    finding_classes: tuple[str, ...]


@dataclass(frozen=True)
class PolicyRule:
    policy_class: str
    action: str
    blocks_stage: bool
    invariant_id: str
    auto_clean: bool = False
    creates_obligation: bool = False
    repair_target_file: str = "Upkeeper"


@dataclass
class PolicyDecision:
    ident: str
    finding_id: str
    klass: str
    policy_class: str
    action: str
    status: str
    path: str
    blocks_stage: bool
    summary: str
    invariant_id: str
    invariant_severity: str
    invariant_message: str
    obligation_id: str = ""
    obligation_path: str = ""


POLICY_TABLE = {
    "untracked_root_scratch_artifact": PolicyRule(
        "known_safe_cleanup",
        "clean_local_scratch_artifact",
        True,
        "KP-002",
        auto_clean=True,
        repair_target_file="orchestration/backlog.sh",
    ),
    "untracked_python_bytecode_cache": PolicyRule(
        "known_safe_cleanup",
        "clean_local_bytecode_cache",
        True,
        "KP-002",
        auto_clean=True,
        repair_target_file="orchestration/backlog.sh",
    ),
    "tracked_root_scratch_artifact": PolicyRule(
        "data_integrity_blocker",
        "block_before_staging",
        True,
        "KP-001",
        creates_obligation=True,
        repair_target_file="orchestration/backlog.sh",
    ),
    "tracked_python_bytecode_cache": PolicyRule(
        "data_integrity_blocker",
        "block_before_staging",
        True,
        "KP-001",
        creates_obligation=True,
        repair_target_file="orchestration/backlog.sh",
    ),
    "tracked_log_artifact": PolicyRule(
        "data_integrity_blocker",
        "block_before_staging",
        True,
        "KP-001",
        creates_obligation=True,
        repair_target_file="orchestration/backlog.sh",
    ),
    "tracked_lock_artifact": PolicyRule(
        "data_integrity_blocker",
        "block_before_staging",
        True,
        "KP-001",
        creates_obligation=True,
        repair_target_file="orchestration/backlog.sh",
    ),
    "tracked_manifest_artifact": PolicyRule(
        "data_integrity_blocker",
        "block_before_staging",
        True,
        "KP-001",
        creates_obligation=True,
        repair_target_file="lib/upkeeper/file_manifest.bash",
    ),
    "tracked_transcript_artifact": PolicyRule(
        "data_integrity_blocker",
        "block_before_staging",
        True,
        "KP-001",
        creates_obligation=True,
        repair_target_file="lib/upkeeper/transcript_output.bash",
    ),
    "tracked_postmortem_artifact": PolicyRule(
        "data_integrity_blocker",
        "block_before_staging",
        True,
        "KP-001",
        creates_obligation=True,
        repair_target_file="Upkeeper",
    ),
    "tracked_runtime_artifact": PolicyRule(
        "data_integrity_blocker",
        "block_before_staging",
        True,
        "KP-001",
        creates_obligation=True,
        repair_target_file="orchestration/backlog.sh",
    ),
    "tracked_unknown_root_artifact": PolicyRule(
        "unsafe_unknown",
        "block_before_staging",
        True,
        "KP-003",
        creates_obligation=True,
        repair_target_file="Upkeeper",
    ),
    "unsafe_unknown_root_artifact": PolicyRule(
        "unsafe_unknown",
        "create_automation_obligation",
        True,
        "KP-003",
        creates_obligation=True,
        repair_target_file="Upkeeper",
    ),
    "recent_nonzero_cycle_exit": PolicyRule(
        "actionable_wrapper_bug",
        "create_automation_obligation",
        False,
        "KP-005",
        creates_obligation=True,
        repair_target_file="Upkeeper",
    ),
    "recent_page_error": PolicyRule(
        "actionable_wrapper_bug",
        "create_automation_obligation",
        False,
        "KP-005",
        creates_obligation=True,
        repair_target_file="Upkeeper",
    ),
    "active_lock_present": PolicyRule(
        "operator_fyi",
        "report_only",
        False,
        "KP-006",
        repair_target_file="Upkeeper",
    ),
    "open_automation_obligations": PolicyRule(
        "known_expected",
        "report_existing_obligations",
        False,
        "KP-004",
        repair_target_file="Upkeeper",
    ),
    "deferred_issue_records_present": PolicyRule(
        "operator_fyi",
        "report_only",
        False,
        "KP-004",
        repair_target_file="orchestration/backlog.sh",
    ),
}

INVARIANT_REGISTRY = {
    "KP-001": Invariant(
        "KP-001",
        "Local evidence artifacts must not become tracked source.",
        "high",
        "git ls-files and tracked source-boundary classes",
        "block before staging and create automation obligation",
        "tracked local evidence cannot be committed as source",
        (
            "tracked_root_scratch_artifact",
            "tracked_python_bytecode_cache",
            "tracked_log_artifact",
            "tracked_lock_artifact",
            "tracked_manifest_artifact",
            "tracked_transcript_artifact",
            "tracked_postmortem_artifact",
            "tracked_runtime_artifact",
        ),
    ),
    "KP-002": Invariant(
        "KP-002",
        "Only explicitly listed untracked scratch artifacts may be auto-cleaned.",
        "medium",
        "git status untracked paths and safe cleanup table",
        "clean local scratch artifact, then re-audit",
        "safe local scratch residue was removed before staging",
        ("untracked_root_scratch_artifact", "untracked_python_bytecode_cache"),
    ),
    "KP-003": Invariant(
        "KP-003",
        "Unknown local-evidence-like root artifacts must fail closed.",
        "high",
        "git status or git ls-files root artifact classification",
        "block or create automation obligation",
        "unknown root evidence needs operator custody before it can be staged",
        ("tracked_unknown_root_artifact", "unsafe_unknown_root_artifact"),
    ),
    "KP-004": Invariant(
        "KP-004",
        "Open obligations and deferred issue records must stay visible before new work.",
        "high",
        "runtime obligation inventory and optional state-root inventory",
        "report existing custody and avoid treating the queue as clean",
        "existing custody is visible and must be reconciled before fresh work",
        ("open_automation_obligations", "deferred_issue_records_present"),
    ),
    "KP-005": Invariant(
        "KP-005",
        "Pageable error and nonzero terminal evidence must map to actionable custody.",
        "high",
        "recent loop log cycle.exit and PAGE [ERROR] markers",
        "create automation obligation or require explicit expected-fixture classification",
        "recent hard terminal evidence needs wrapper custody before normal work",
        ("recent_nonzero_cycle_exit", "recent_page_error"),
    ),
    "KP-006": Invariant(
        "KP-006",
        "Active owner lock evidence must be visible before concurrent writers run.",
        "medium",
        "runtime active-lock inventory",
        "report active lock and require owner verification",
        "active lock state is present and should be verified before launching another writer",
        ("active_lock_present",),
    ),
    "KP-007": Invariant(
        "KP-007",
        "Before/after audit snapshots must preserve resolved and remaining invariant state.",
        "medium",
        "control-plane audit snapshot delta",
        "write snapshot evidence around staging, validation, and merge phases",
        "snapshot delta records what was cleaned, blocked, resolved, or still present",
        (),
    ),
}


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


def is_python_bytecode_cache(path: str) -> bool:
    pure = pathlib.PurePosixPath(path)
    return "__pycache__" in pure.parts or pure.suffix in {".pyc", ".pyo"}


def is_unknown_root_evidence(path: str) -> bool:
    if not is_root_path(path) or is_root_scratch(path) or path == "Upkeeper.log":
        return False
    name = pathlib.PurePosixPath(path).name
    if name in UNKNOWN_ROOT_EVIDENCE_NAMES:
        return True
    return any(name.endswith(suffix) for suffix in UNKNOWN_ROOT_EVIDENCE_SUFFIXES)


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
        if is_python_bytecode_cache(path):
            add_finding(
                findings,
                "tracked_python_bytecode_cache",
                "high",
                path,
                "git_ls_files",
                "Python bytecode cache is tracked as source",
                "remove bytecode cache artifacts from tracked source and regenerate them locally when needed",
            )
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
        if is_unknown_root_evidence(path):
            add_finding(
                findings,
                "tracked_unknown_root_artifact",
                "high",
                path,
                "git_ls_files",
                "root-level local evidence-like artifact is tracked as source",
                "verify whether the artifact is source; if not, remove it from tracked source and preserve useful evidence under ignored runtime state",
            )


def inventory_untracked_paths(paths: Iterable[str], findings: list[Finding]) -> None:
    for path in paths:
        if is_python_bytecode_cache(path):
            add_finding(
                findings,
                "untracked_python_bytecode_cache",
                "medium",
                path,
                "git_status",
                "Python bytecode cache is present outside ignored runtime state",
                "delete the bytecode cache before staging or committing",
            )
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
        if is_unknown_root_evidence(path):
            add_finding(
                findings,
                "unsafe_unknown_root_artifact",
                "high",
                path,
                "git_status",
                "root-level local evidence-like artifact is not in the safe cleanup table",
                "inspect the artifact and either move it under ignored runtime state or add a reviewed source file explicitly",
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


def private_dir(path: pathlib.Path, *, force_chmod: bool = True) -> None:
    existed = path.exists()
    path.mkdir(parents=True, exist_ok=True)
    if force_chmod or not existed:
        try:
            path.chmod(0o700)
        except OSError:
            pass


def write_private_json(path: pathlib.Path, data: dict[str, object], *, force_private_parent: bool = True) -> None:
    private_dir(path.parent, force_chmod=force_private_parent)
    tmp = path.with_name(f"{path.name}.tmp.{os.getpid()}")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(tmp, path)
        try:
            path.chmod(0o600)
        except OSError:
            pass
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def now_local() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def policy_for_finding(finding: dict[str, object]) -> PolicyRule:
    klass = str(finding.get("klass") or "")
    return POLICY_TABLE.get(
        klass,
        PolicyRule(
            "unsafe_unknown",
            "block_before_staging",
            True,
            "KP-003",
            creates_obligation=True,
            repair_target_file="Upkeeper",
        ),
    )


def decision_id(stage: str, finding: dict[str, object], rule: PolicyRule) -> str:
    return f"policy-{stable_hash(stage, str(finding.get('ident')), rule.policy_class, rule.action)}"


def invariant_record(rule: PolicyRule) -> Invariant:
    return INVARIANT_REGISTRY.get(
        rule.invariant_id,
        Invariant(
            rule.invariant_id,
            "Unregistered control-plane invariant.",
            "high",
            "control-plane audit policy table",
            rule.action,
            "unregistered invariant failed closed",
            (),
        ),
    )


def safe_repo_path(root: pathlib.Path, repo_path: str) -> pathlib.Path:
    if repo_path == "" or pathlib.PurePosixPath(repo_path).is_absolute() or "\0" in repo_path:
        raise ValueError("not a relative repository path")
    target = (root / repo_path).resolve(strict=False)
    try:
        target.relative_to(root)
    except ValueError as exc:
        raise ValueError("path escapes repository root") from exc
    return target


def cleanup_bytecode_path(target: pathlib.Path) -> str:
    if not target.exists() and not target.is_symlink():
        return "already_clean"
    if target.is_dir():
        for child in sorted(target.rglob("*"), key=lambda item: len(item.parts), reverse=True):
            if child.is_dir() and not child.is_symlink():
                child.rmdir()
            else:
                child.unlink()
        target.rmdir()
        return "cleaned"
    target.unlink()
    parent = target.parent
    while parent.name == "__pycache__" or (parent.exists() and parent.name == "__pycache__"):
        try:
            parent.rmdir()
        except OSError:
            break
        parent = parent.parent
    return "cleaned"


def cleanup_safe_artifact(root: pathlib.Path, finding: dict[str, object]) -> str:
    repo_path = str(finding.get("path") or "")
    target = safe_repo_path(root, repo_path)
    klass = str(finding.get("klass") or "")
    if klass == "untracked_root_scratch_artifact":
        if not target.exists() and not target.is_symlink():
            return "already_clean"
        if target.is_dir() and not target.is_symlink():
            raise OSError("root scratch artifact is a directory")
        target.unlink()
        return "cleaned"
    if klass == "untracked_python_bytecode_cache":
        return cleanup_bytecode_path(target)
    raise OSError(f"{klass} is not a safe cleanup class")


def obligation_id_for_decision(finding: dict[str, object], rule: PolicyRule) -> str:
    return f"control-plane-{stable_hash(str(finding.get('ident')), rule.policy_class, rule.action)}"


def obligation_payload(
    root: pathlib.Path,
    branch: str,
    stage: str,
    finding: dict[str, object],
    decision: PolicyDecision,
    rule: PolicyRule,
) -> dict[str, object]:
    ident = obligation_id_for_decision(finding, rule)
    return {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": ident,
        "kind": "control_plane_policy_blocker",
        "severity": str(finding.get("severity") or "medium"),
        "summary": str(finding.get("summary") or "control-plane audit policy blocker"),
        "created_at": now_local(),
        "root": str(root),
        "source": "upkeeper_control_plane_audit",
        "source_branch": branch,
        "stage": stage,
        "target_scope": "target",
        "target_file": str(finding.get("path") or ""),
        "repair_target_file": rule.repair_target_file,
        "repair_target_basis": "control_plane_policy_table",
        "repair_target_detail": str(finding.get("klass") or ""),
        "reason": "CONTROL_PLANE_POLICY_BLOCKER",
        "policy_class": rule.policy_class,
        "policy_action": rule.action,
        "policy_decision_id": decision.ident,
        "invariant_id": decision.invariant_id,
        "invariant_message": decision.invariant_message,
        "specific_issue_required": True,
        "evidence": {
            "finding_id": str(finding.get("ident") or ""),
            "class": str(finding.get("klass") or ""),
            "path": str(finding.get("path") or ""),
            "source": str(finding.get("source") or ""),
            "summary": str(finding.get("summary") or ""),
            "remediation": str(finding.get("remediation") or ""),
            "blocks_stage": decision.blocks_stage,
            "invariant_id": decision.invariant_id,
        },
        "required_resolution": [
            "inspect the control-plane audit finding before staging or model work",
            "delete only explicitly safe untracked scratch artifacts; do not auto-delete tracked source",
            "move local evidence under ignored runtime state or remove it from source with a reviewed patch",
            "rerun tests/control_plane_audit_test.bash",
            "rerun tools/validate_upkeeper.sh --quick",
        ],
    }


def write_obligation(
    root: pathlib.Path,
    branch: str,
    stage: str,
    obligation_root: pathlib.Path,
    finding: dict[str, object],
    decision: PolicyDecision,
    rule: PolicyRule,
) -> tuple[str, str]:
    payload = obligation_payload(root, branch, stage, finding, decision, rule)
    open_dir = obligation_root / "open"
    path = open_dir / f"{payload['id']}.json"
    status = "obligation_written"
    if path.exists():
        try:
            current = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            current = {}
        if isinstance(current, dict):
            payload["created_at"] = current.get("created_at") or payload["created_at"]
            payload["seen_count"] = int(current.get("seen_count") or 1) + 1
            payload["updated_at"] = now_local()
            status = "obligation_updated"
    else:
        payload["seen_count"] = 1
    write_private_json(path, payload)
    return status, str(path)


def apply_policies(payload: dict[str, object], args: argparse.Namespace) -> tuple[list[PolicyDecision], bool]:
    root = pathlib.Path(str(payload.get("root") or args.root)).resolve()
    branch = str(payload.get("branch") or "unknown")
    stage = str(args.stage or "manual")
    obligation_root = pathlib.Path(args.obligation_root).resolve() if args.obligation_root else root / "runtime/upkeeper-obligations"
    decisions: list[PolicyDecision] = []
    changed = False
    findings = payload.get("findings", [])
    if not isinstance(findings, list):
        findings = []
    for finding in findings:
        if not isinstance(finding, dict):
            continue
        rule = policy_for_finding(finding)
        invariant = invariant_record(rule)
        decision = PolicyDecision(
            ident=decision_id(stage, finding, rule),
            finding_id=str(finding.get("ident") or ""),
            klass=str(finding.get("klass") or ""),
            policy_class=rule.policy_class,
            action=rule.action,
            status="reported",
            path=str(finding.get("path") or ""),
            blocks_stage=rule.blocks_stage,
            summary=str(finding.get("summary") or ""),
            invariant_id=invariant.ident,
            invariant_severity=invariant.severity,
            invariant_message=invariant.operator_message,
        )
        if rule.auto_clean:
            if args.remediate_safe:
                try:
                    decision.status = cleanup_safe_artifact(root, finding)
                    changed = changed or decision.status == "cleaned"
                except OSError as exc:
                    decision.status = f"cleanup_failed:{exc}"
            else:
                decision.status = "cleanup_available"
        elif rule.creates_obligation:
            decision.obligation_id = obligation_id_for_decision(finding, rule)
            if args.write_obligations:
                status, path = write_obligation(root, branch, stage, obligation_root, finding, decision, rule)
                decision.status = status
                decision.obligation_path = path
            elif rule.blocks_stage:
                decision.status = "blocked"
            else:
                decision.status = "obligation_required"
        elif rule.action == "report_only":
            decision.status = "reported"
        else:
            decision.status = "reported"
        decisions.append(decision)
    return decisions, changed


def decorate_payload(payload: dict[str, object], decisions: list[PolicyDecision]) -> dict[str, object]:
    counts = payload.setdefault("counts", {})
    if not isinstance(counts, dict):
        counts = {}
        payload["counts"] = counts
    blocker_count = sum(1 for item in decisions if item.blocks_stage and item.status not in {"cleaned", "already_clean"})
    counts["policy_decision_count"] = len(decisions)
    counts["cleaned_count"] = sum(1 for item in decisions if item.status == "cleaned")
    counts["blocker_count"] = blocker_count
    counts["obligation_written_count"] = sum(1 for item in decisions if item.status in {"obligation_written", "obligation_updated"})
    payload["policy_decisions"] = [asdict(item) for item in decisions]
    payload["invariant_registry"] = [asdict(item) for item in INVARIANT_REGISTRY.values()]
    payload["invariant_failures"] = [
        {
            "invariant_id": item.invariant_id,
            "decision_id": item.ident,
            "class": item.klass,
            "severity": item.invariant_severity,
            "action": item.action,
            "status": item.status,
            "path": item.path,
            "message": item.invariant_message,
        }
        for item in decisions
        if item.status not in {"cleaned", "already_clean"}
    ]
    if counts.get("finding_count", 0) == 0:
        payload["status"] = "clean"
    elif blocker_count:
        payload["status"] = "blocked"
    else:
        payload["status"] = "findings"
    return payload


def payload_invariant_ids(payload: dict[str, object]) -> set[str]:
    values: set[str] = set()
    items = payload.get("invariant_failures", [])
    if not isinstance(items, list):
        return values
    for item in items:
        if isinstance(item, dict):
            value = item.get("invariant_id")
            if isinstance(value, str) and value:
                values.add(value)
    return values


def load_snapshot(path: str) -> dict[str, object]:
    if not path:
        return {}
    snapshot_path = pathlib.Path(path).resolve()
    try:
        data = json.loads(snapshot_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"control-plane audit: cannot read snapshot {snapshot_path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"control-plane audit: snapshot is not a JSON object: {snapshot_path}")
    return data


def add_snapshot_delta(payload: dict[str, object], before: dict[str, object] | None) -> None:
    if not before:
        return
    before_counts = before.get("counts", {}) if isinstance(before.get("counts"), dict) else {}
    after_counts = payload.get("counts", {}) if isinstance(payload.get("counts"), dict) else {}
    before_ids = payload_invariant_ids(before)
    after_ids = payload_invariant_ids(payload)
    payload["snapshot_delta"] = {
        "invariant_id": "KP-007",
        "before_status": before.get("status"),
        "after_status": payload.get("status"),
        "before_finding_count": before_counts.get("finding_count", 0),
        "after_finding_count": after_counts.get("finding_count", 0),
        "before_blocker_count": before_counts.get("blocker_count", 0),
        "after_blocker_count": after_counts.get("blocker_count", 0),
        "cleaned_count": after_counts.get("cleaned_count", 0),
        "resolved_invariants": sorted(before_ids - after_ids),
        "new_invariants": sorted(after_ids - before_ids),
        "remaining_invariants": sorted(before_ids & after_ids),
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
    runtime = {"runtime_inventory_skipped": True} if args.no_runtime else runtime_inventory(root, findings)
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
        f"blockers={counts.get('blocker_count', 0)} "
        f"cleaned={counts.get('cleaned_count', 0)} "
        f"obligations={counts.get('obligation_written_count', 0)} "
        f"tracked_changes={counts.get('tracked_change_count', 0)} "
        f"untracked={counts.get('untracked_path_count', 0)} "
        f"branch={payload.get('branch', 'unknown')}"
    )
    decisions = payload.get("policy_decisions", [])
    if isinstance(decisions, list):
        for item in decisions[:10]:
            if not isinstance(item, dict):
                continue
            print(
                "control_plane_audit: policy "
                f"id={item.get('ident')} "
                f"invariant={item.get('invariant_id')} "
                f"class={item.get('klass')} "
                f"policy={item.get('policy_class')} "
                f"action={item.get('action')} "
                f"status={item.get('status')} "
                f"blocks_stage={str(item.get('blocks_stage')).lower()} "
                f"path={item.get('path')}"
            )
        if len(decisions) > 10:
            print(f"control_plane_audit: policy output truncated remaining={len(decisions) - 10}")
    invariant_failures = payload.get("invariant_failures", [])
    if isinstance(invariant_failures, list):
        for item in invariant_failures[:10]:
            if not isinstance(item, dict):
                continue
            print(
                "control_plane_audit: invariant "
                f"id={item.get('invariant_id')} "
                f"status={item.get('status')} "
                f"severity={item.get('severity')} "
                f"action={item.get('action')} "
                f"path={item.get('path')} "
                f"message={item.get('message')}"
            )
        if len(invariant_failures) > 10:
            print(f"control_plane_audit: invariant output truncated remaining={len(invariant_failures) - 10}")
    delta = payload.get("snapshot_delta")
    if isinstance(delta, dict):
        print(
            "control_plane_audit: snapshot_delta "
            f"invariant={delta.get('invariant_id')} "
            f"before_status={delta.get('before_status')} "
            f"after_status={delta.get('after_status')} "
            f"before_findings={delta.get('before_finding_count')} "
            f"after_findings={delta.get('after_finding_count')} "
            f"cleaned={delta.get('cleaned_count')}"
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
    parser.add_argument("--no-runtime", action="store_true", help="do not inventory runtime locks or obligation state")
    parser.add_argument("--max-log-lines", type=int, default=400, help="recent log lines to scan")
    parser.add_argument("--stage", default="manual", help="policy context for stable decision ids")
    parser.add_argument("--snapshot-label", default="", help="optional label stored in the audit snapshot")
    parser.add_argument("--before-snapshot", default="", help="prior audit snapshot used to compute a before/after delta")
    parser.add_argument("--snapshot-out", default="", help="write the final decorated audit payload to this JSON file")
    parser.add_argument("--remediate-safe", action="store_true", help="clean only policy-listed safe untracked artifacts")
    parser.add_argument("--write-obligations", action="store_true", help="write blocker/actionable findings to the obligation root")
    parser.add_argument("--obligation-root", default="", help="automation obligation root; defaults to ROOT/runtime/upkeeper-obligations")
    parser.add_argument(
        "--fail-on",
        choices=("findings", "blockers", "never"),
        default="findings",
        help="exit nonzero for all findings, only policy blockers, or never",
    )
    parser.add_argument("--json", action="store_true", help="emit JSON instead of operator text")
    parser.add_argument("--no-fail", action="store_true", help="exit 0 even when findings are present")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    before_snapshot = load_snapshot(args.before_snapshot) if args.before_snapshot else {}
    payload = build_payload(args)
    decisions, changed = apply_policies(payload, args)
    if changed:
        payload = build_payload(args)
        remaining, _ = apply_policies(payload, argparse.Namespace(**{**vars(args), "remediate_safe": False}))
        decisions.extend(remaining)
    payload = decorate_payload(payload, decisions)
    payload["snapshot"] = {
        "label": args.snapshot_label or args.stage,
        "stage": args.stage,
        "created_at": now_local(),
        "invariant_id": "KP-007",
    }
    add_snapshot_delta(payload, before_snapshot)
    if args.snapshot_out:
        write_private_json(pathlib.Path(args.snapshot_out).resolve(), payload, force_private_parent=False)
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print_text(payload)
    fail_on = "never" if args.no_fail else args.fail_on
    counts = payload.get("counts", {})
    if not isinstance(counts, dict):
        counts = {}
    if fail_on == "findings" and counts.get("finding_count", 0):
        return 2
    if fail_on == "blockers" and counts.get("blocker_count", 0):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
