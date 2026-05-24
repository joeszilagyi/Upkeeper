#!/usr/bin/env python3
"""Detect prior-run anomalies and place them under local automation custody.

The scanner intentionally starts from the healthy unattended-run shape: routine
INFO/OK/RUN/WAIT progress is allowed, while warnings, pageable errors, failed
checks, unresolved startup gates, and degraded control-plane modes become
actionable unless a narrow local fixture context proves they are expected test
output.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import pathlib
import re
import sys
from dataclasses import dataclass


DEFAULT_UMBRELLA_ISSUE = "418"
DEFAULT_UMBRELLA_TITLE = (
    "High priority bug: non-perfect automated runs need mandatory local "
    "remediation custody"
)

TIMESTAMP_PREFIX = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:[+-]\d{4})?\s+"
)
VISUAL_MARKER = re.compile(
    r"(?:^|\s+)█\s+(PAGE|--FYI--|WORKER|ACTION|WAIT|HEALTH|OK|RUN|INFO)\s+"
)
CYCLE_RE = re.compile(r"\bcycle=([^ \t]+)")
RUN_HASH_RE = re.compile(r"\brun_hash=([^ \t]+)")
DYNAMIC_FINGERPRINT_PATTERNS = (
    (re.compile(r"\bcycle=[^ \t]+"), "cycle=<cycle>"),
    (re.compile(r"\brun_hash=[^ \t]+"), "run_hash=<run_hash>"),
    (re.compile(r"\bboot_id=[^ \t]+"), "boot_id=<boot_id>"),
    (re.compile(r"\buptime_seconds=[0-9.]+"), "uptime_seconds=<seconds>"),
    (re.compile(r"\b(oldest_epoch|newest_epoch|elapsed|elapsed_seconds|wait_seconds|sleep)=[^ \t]+"), r"\1=<number>"),
    (re.compile(r"\b(detail_bytes|transcript_bytes|transcript_lines|lines|listed_total|prior_cycle_count|state_count)=[0-9]+"), r"\1=<number>"),
    (re.compile(r"\bcmd#[0-9]+\b"), "cmd#<n>"),
    (re.compile(r"\bexited\\? [0-9]+\\? in\\? [0-9.]+m?s\b"), "exited <code> in <duration>"),
    (re.compile(r"\b(detail_sha256|log_sha256|prompt_sha256|sha256)=[0-9a-fA-F]{16,64}"), r"\1=<sha256>"),
    (re.compile(r"\btranscript=path-hmac-sha256:[0-9a-fA-F]+"), "transcript=path-hmac-sha256:<hash>"),
    (re.compile(r"\b(path|path_hmac|path_redacted|diagnostics_path_hmac)=path-hmac-sha256:[0-9a-fA-F]+"), r"\1=path-hmac-sha256:<hash>"),
    (re.compile(r"\b(path|selected_path|selectedPath|remote_url|remoteURL)=path-sha256:[0-9a-fA-F]+"), r"\1=path-sha256:<hash>"),
    (re.compile(r"path-hmac-sha256:[0-9a-fA-F]+"), "path-hmac-sha256:<hash>"),
    (re.compile(r"path-sha256:[0-9a-fA-F]+"), "path-sha256:<hash>"),
    (re.compile(r"value-hmac-sha256:[0-9a-fA-F]+"), "value-hmac-sha256:<hash>"),
    (re.compile(r"/tmp/upkeeper-[^ \t]+"), "/tmp/upkeeper-<path>"),
    (re.compile(r"/home/[^ \t]*/upkeeper-[^ \t]+"), "/home/<user>/upkeeper-<path>"),
)


@dataclass(frozen=True)
class Classification:
    kind: str
    severity: str
    target: str
    reason: str


@dataclass(frozen=True)
class Finding:
    ident: str
    fingerprint: str
    kind: str
    severity: str
    target: str
    reason: str
    line_number: int
    excerpt: str
    normalized: str
    cycle_id: str
    run_hash: str
    status: str


def now_local() -> str:
    return _dt.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def private_dir(path: pathlib.Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    try:
        path.chmod(0o700)
    except OSError:
        pass


def write_json(path: pathlib.Path, payload: dict) -> None:
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


def tail_lines(path: pathlib.Path, limit: int) -> list[tuple[int, str]]:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except FileNotFoundError:
        return []
    except OSError as exc:
        raise SystemExit(f"anomaly custody: cannot read loop log {path}: {exc}") from exc
    if limit > 0 and len(lines) > limit:
        start = len(lines) - limit
        return [(start + index + 1, line) for index, line in enumerate(lines[start:])]
    return [(index + 1, line) for index, line in enumerate(lines)]


def strip_prefix(line: str) -> str:
    value = TIMESTAMP_PREFIX.sub("", line, count=1)
    value = VISUAL_MARKER.sub(" ", value, count=1)
    return " ".join(value.split())


def bounded_excerpt(line: str, width: int = 260) -> str:
    value = " ".join(line.replace("\r", " ").replace("\t", " ").split())
    if len(value) <= width:
        return value
    return value[: width - 3] + "..."


def context_has(lines: list[tuple[int, str]], index: int, needle: str, radius: int = 12) -> bool:
    low = max(0, index - radius)
    high = min(len(lines), index + radius + 1)
    return any(needle in line for _, line in lines[low:high])


def expected_fixture(lines: list[tuple[int, str]], index: int, line: str) -> bool:
    if (
        "transcript directory is not private /tmp/upkeeper-transcripts-test." in line
        and context_has(lines, index, "transcript_artifacts_test: ok", radius=20)
    ):
        return True
    if (
        "startup_anomaly.gate_target status=missing" in line
        and "/tmp/upkeeper-client-link-test." in line
        and context_has(lines, index, "client_link_tools_test: ok", radius=40)
    ):
        return True
    if (
        "run temp directory is missing a trusted ownership marker" in line
        and "/tmp/upkeeper-bug-report-only." in line
        and context_has(lines, index, "bug_report_only_test: ok", radius=30)
    ):
        return True
    return False


def model_emitted_fixture_output(normalized: str) -> bool:
    lower = normalized.lower()
    marker = "upkeeper: primary:"
    if marker not in lower:
        return False
    payload = lower.split(marker, 1)[1].strip()
    if not payload:
        return False
    if payload in {
        "except exception as exc:",
    }:
        return True

    shell_fixture_tokens = (
        "printf ",
        "printf '",
        'printf "',
        "echo ",
        "grep ",
        "grep -fq ",
        "grep -eq ",
        "if grep ",
        "case ",
        "cat >",
        "awk ",
        "sed ",
        "warn=",
        "err=",
        "payload=",
        "$stamp",
        "$local_stamp",
        "$tmp",
        "$tmp_dir",
        "$output",
        "$log_file",
        ">>",
        "<<<",
        "|| {",
        "&&",
        "|*",
        "'*|",
        "*)",
        ";;",
        "\\n",
    )
    embedded_log_tokens = (
        "[warn]",
        "[error]",
        "[info]",
        "(warn|error)",
        "warn|error",
        "warn",
        "error",
        " page ",
        "startup_anomaly",
        "previous_run.anomaly",
        " cycle=",
        " run_hash=",
        "cycle.exit",
        "run.finish",
        " █ ",
    )
    if "warn=" in payload or "err=" in payload:
        return True
    if payload.startswith(("grep ", "printf ", "echo ", "if grep ", "case ")):
        return True
    if any(token in payload for token in shell_fixture_tokens) and any(
        token in payload for token in embedded_log_tokens
    ):
        return True
    if payload.startswith("'") and any(token in payload for token in embedded_log_tokens):
        return True
    return False


def target_for(normalized: str) -> str:
    lower = normalized.lower()
    if "lattice" in lower:
        return "tools/upkeeper_lattice.py"
    if "startup_anomaly" in lower or "previous_run.anomaly" in lower:
        if "previous_run" in lower:
            return "lib/upkeeper/previous_run_anomalies.bash"
        return "lib/upkeeper/startup_anomaly_state.bash"
    if "transcript" in lower:
        return "lib/upkeeper/transcript_output.bash"
    if "client-link" in lower or "client_link" in lower:
        return "tests/client_link_tools_test.bash"
    if "pr #" in lower or "backlog:" in lower or "checks_failed" in lower:
        return "orchestration/backlog.sh"
    if "quota" in lower:
        return "lib/upkeeper/quota_guardrails.bash"
    return "Upkeeper"


def classify(lines: list[tuple[int, str]], index: int, raw_line: str) -> Classification | None:
    if "anomaly custody:" in raw_line:
        return None
    if expected_fixture(lines, index, raw_line):
        return Classification("expected_fixture_output", "low", target_for(raw_line), "expected local negative-test fixture")

    normalized = strip_prefix(raw_line)
    lower = normalized.lower()
    target = target_for(normalized)

    if model_emitted_fixture_output(normalized):
        return None
    if "upkeeper: what was wrong:" in lower:
        return None
    if "█ page" in raw_line.lower() or "[error]" in lower:
        return Classification("page_error", "high", target, "pageable error output is not part of a healthy run")
    if "checks_failed" in lower or "checks failed" in lower or "stopping before selecting another issue" in lower:
        return Classification("failed_pr_check_gate", "high", target, "current PR check gate failed before more work")
    if "cycle.exit exit_code=" in lower and "exit_code=0" not in lower:
        return Classification("nonzero_cycle_exit", "high", target, "cycle exited non-zero")
    if "upkeeper exited with status" in lower or "launcher exiting with status" in lower:
        return Classification("nonzero_launcher_exit", "high", target, "launcher recorded a non-zero Upkeeper exit")
    if "lattice.unavailable" in lower:
        return Classification("lattice_unavailable", "high", target, "Lattice degraded mode is not a perfect run")
    if "startup_anomaly.gate_unresolved" in lower:
        return Classification("startup_anomaly_unresolved", "high", target, "startup anomaly gate remained unresolved")
    if "previous_run.anomaly_summary" in lower:
        return Classification("previous_run_anomaly_summary", "medium", target, "prior run anomaly residue was reported")
    if "startup_anomaly.gate" in lower and ("status=active" in lower or "gate_violation" in lower):
        return Classification("startup_anomaly_gate_active", "medium", target, "startup anomaly gate was active")
    if "automation.obligation.open" in lower:
        return None
    if "[warn]" in lower or "█ --fyi--" in raw_line.lower():
        ignored_waits = (
            "quota preflight:" in lower
            or "quota hibernating" in lower
            or "quota hibernation complete" in lower
            or "quota.cooldown bypassed" in lower
            or "quota.guardrails bypassed=1" in lower
        )
        if not ignored_waits:
            return Classification("warning_line", "medium", target, "warning/advisory output needs custody")
    return None


def normalize_fingerprint_text(text: str) -> str:
    value = text
    for pattern, replacement in DYNAMIC_FINGERPRINT_PATTERNS:
        value = pattern.sub(replacement, value)
    return " ".join(value.split())


def stable_fingerprint(kind: str, normalized: str) -> str:
    lower = normalized.lower()
    if kind == "previous_run_anomaly_summary":
        return "previous_run.anomaly_summary"
    if kind == "startup_anomaly_gate_active":
        if "gate_violation" in lower:
            return "startup_anomaly.gate_violation"
        return "startup_anomaly.gate status=active"
    if kind == "startup_anomaly_unresolved":
        reason_match = re.search(r"\breason=([^ \t]+)", normalized)
        if reason_match:
            return f"startup_anomaly.gate_unresolved reason={reason_match.group(1)}"
        return "startup_anomaly.gate_unresolved"
    if kind == "lattice_unavailable":
        return "lattice.unavailable"
    if kind == "failed_pr_check_gate":
        return "failed_pr_check_gate"
    return normalize_fingerprint_text(normalized)


def finding_id(kind: str, normalized: str, target: str) -> tuple[str, str]:
    fingerprint = stable_fingerprint(kind, normalized)
    digest = hashlib.sha256(f"{kind}\0{target}\0{fingerprint}".encode("utf-8", "surrogateescape")).hexdigest()
    return f"prior-run-{digest[:24]}", fingerprint


def make_finding(lines: list[tuple[int, str]], index: int, line_number: int, raw_line: str, item: Classification) -> Finding:
    normalized = strip_prefix(raw_line)
    cycle_match = CYCLE_RE.search(raw_line)
    run_hash_match = RUN_HASH_RE.search(raw_line)
    status = "expected_fixture" if item.kind == "expected_fixture_output" else "actionable"
    ident, fingerprint = finding_id(item.kind, normalized, item.target)
    return Finding(
        ident=ident,
        fingerprint=fingerprint,
        kind=item.kind,
        severity=item.severity,
        target=item.target,
        reason=item.reason,
        line_number=line_number,
        excerpt=bounded_excerpt(raw_line),
        normalized=normalized,
        cycle_id=cycle_match.group(1) if cycle_match else "",
        run_hash=run_hash_match.group(1) if run_hash_match else "",
        status=status,
    )


def existing_obligation_records(root: pathlib.Path) -> dict[str, dict]:
    seen: dict[str, dict] = {}
    for subdir in ("open", "resolved"):
        base = root / subdir
        if not base.is_dir():
            continue
        for path in base.glob("*.json"):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if not isinstance(data, dict):
                continue
            ident = str(data.get("id") or path.stem)
            if ident:
                seen[ident] = {"state": subdir, "path": path, "data": data}
    return seen


def finding_payload(finding: Finding, root: pathlib.Path, loop_log: pathlib.Path) -> dict:
    return {
        "schema": 1,
        "record_type": "anomaly_custody_finding",
        "status": finding.status,
        "id": finding.ident,
        "fingerprint": finding.fingerprint,
        "kind": finding.kind,
        "severity": finding.severity,
        "reason": finding.reason,
        "target_file": finding.target,
        "root": str(root),
        "loop_log": str(loop_log),
        "line_number": finding.line_number,
        "cycle_id": finding.cycle_id,
        "run_hash": finding.run_hash,
        "excerpt": finding.excerpt,
        "normalized_excerpt": finding.normalized,
        "created_at": now_local(),
    }


def obligation_payload(finding: Finding, root: pathlib.Path, loop_log: pathlib.Path) -> dict:
    summary = f"Prior backlog log anomaly needs repair or explicit custody: {finding.kind}"
    return {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": finding.ident,
        "created_at": now_local(),
        "kind": "prior_run_anomaly",
        "severity": finding.severity,
        "summary": summary,
        "fingerprint": finding.fingerprint,
        "first_seen_at": now_local(),
        "last_seen_at": now_local(),
        "occurrence_count": 1,
        "root": str(root),
        "source_cycle_id": finding.cycle_id,
        "source_run_hash": finding.run_hash,
        "launcher": "backlog",
        "variant": "anomaly-custody",
        "policy": "pre-issue-health",
        "workflow": "",
        "stage": "pre_issue_selection",
        "issue_number": DEFAULT_UMBRELLA_ISSUE,
        "issue_title": DEFAULT_UMBRELLA_TITLE,
        "target_scope": "target",
        "target_file": finding.target,
        "repair_target_file": finding.target,
        "exit_code": "",
        "reason": "PRIOR_RUN_ANOMALY",
        "level": "WARN" if finding.severity != "high" else "ERROR",
        "status_marker": "",
        "codex_exit": "",
        "codex_exec_started": "",
        "run_record": "",
        "transcript": "",
        "evidence": {
            "source": "backlog_loop_log",
            "loop_log": str(loop_log),
            "line_number": finding.line_number,
            "kind": finding.kind,
            "reason": finding.reason,
            "fingerprint": finding.fingerprint,
            "excerpt": finding.excerpt,
            "normalized_excerpt": finding.normalized,
        },
        "required_resolution": [
            "inspect the prior-run log evidence before normal backlog issue work",
            "decide whether the finding is a real bug, an expected fixture with missing context, stale residue, or a false-positive detector rule",
            "patch the wrapper, launcher, tests, docs, or detector rule when the source is repairable now",
            "if it cannot be repaired in this cycle, leave a durable tracked source change or BLOCKED report that keeps the finding from escaping local custody",
            "add deterministic validation for the repaired or intentionally expected outcome",
        ],
    }


def update_open_obligation(path: pathlib.Path, finding: Finding, loop_log: pathlib.Path) -> None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return
    if not isinstance(data, dict):
        return
    try:
        occurrence_count = int(data.get("occurrence_count") or 1)
    except (TypeError, ValueError):
        occurrence_count = 1
    data.setdefault("first_seen_at", data.get("created_at", now_local()))
    data["last_seen_at"] = now_local()
    data["occurrence_count"] = occurrence_count + 1
    data["last_source_cycle_id"] = finding.cycle_id
    data["last_source_run_hash"] = finding.run_hash
    data["last_evidence"] = {
        "source": "backlog_loop_log",
        "loop_log": str(loop_log),
        "line_number": finding.line_number,
        "kind": finding.kind,
        "reason": finding.reason,
        "fingerprint": finding.fingerprint,
        "excerpt": finding.excerpt,
        "normalized_excerpt": finding.normalized,
    }
    if not data.get("fingerprint"):
        data["fingerprint"] = finding.fingerprint
    evidence = data.get("evidence")
    if isinstance(evidence, dict):
        evidence.setdefault("fingerprint", finding.fingerprint)
        evidence["occurrence_count"] = data["occurrence_count"]
    write_json(path, data)


def audit(args: argparse.Namespace) -> int:
    root = pathlib.Path(args.root).resolve()
    loop_log = pathlib.Path(args.loop_log).expanduser()
    state_root = pathlib.Path(args.state_root)
    obligation_root = pathlib.Path(args.obligation_root)
    recent_lines = max(0, int(args.recent_lines))
    max_findings = max(1, int(args.max_findings))

    lines = tail_lines(loop_log, recent_lines)
    findings: list[Finding] = []
    expected_count = 0
    resolved_count = 0
    coalesced_count = 0
    seen_ids: set[str] = set()
    obligation_records = existing_obligation_records(obligation_root)
    for index, (line_number, raw_line) in enumerate(lines):
        classified = classify(lines, index, raw_line)
        if classified is None:
            continue
        finding = make_finding(lines, index, line_number, raw_line, classified)
        if finding.status == "expected_fixture":
            expected_count += 1
            continue
        record = obligation_records.get(finding.ident)
        if record and record.get("state") == "resolved":
            resolved_count += 1
            continue
        if finding.ident in seen_ids:
            coalesced_count += 1
            continue
        seen_ids.add(finding.ident)
        findings.append(finding)
        if len(findings) >= max_findings:
            break

    private_dir(state_root)
    finding_dir = state_root / "findings"
    created_obligations = 0
    updated_obligations = 0
    for finding in findings:
        write_json(finding_dir / f"{finding.ident}.json", finding_payload(finding, root, loop_log))
        if not args.write_obligations:
            continue
        record = obligation_records.get(finding.ident)
        if record is None:
            write_json(obligation_root / "open" / f"{finding.ident}.json", obligation_payload(finding, root, loop_log))
            obligation_records[finding.ident] = {
                "state": "open",
                "path": obligation_root / "open" / f"{finding.ident}.json",
                "data": {},
            }
            created_obligations += 1
        elif record.get("state") == "open":
            update_open_obligation(pathlib.Path(record["path"]), finding, loop_log)
            updated_obligations += 1

    status = "actionable" if findings else "clean"
    latest = {
        "schema": 1,
        "record_type": "anomaly_custody_audit",
        "status": status,
        "created_at": now_local(),
        "root": str(root),
        "loop_log": str(loop_log),
        "scanned_lines": len(lines),
        "recent_lines": recent_lines,
        "actionable_findings": len(findings),
        "expected_fixture_findings": expected_count,
        "resolved_fingerprint_findings": resolved_count,
        "coalesced_findings": coalesced_count,
        "created_obligations": created_obligations,
        "updated_obligations": updated_obligations,
        "obligation_root": str(obligation_root),
        "findings": [finding_payload(finding, root, loop_log) for finding in findings],
    }
    write_json(state_root / "latest.json", latest)

    print(
        "anomaly custody: "
        f"status={status} scanned_lines={len(lines)} "
        f"actionable={len(findings)} expected_fixture={expected_count} "
        f"resolved={resolved_count} coalesced={coalesced_count} "
        f"new_obligations={created_obligations} updated_obligations={updated_obligations}"
    )
    for finding in findings[:5]:
        print(
            "anomaly custody: "
            f"id={finding.ident} severity={finding.severity} kind={finding.kind} "
            f"target={finding.target} reason={finding.reason} excerpt={json.dumps(finding.excerpt)}"
        )
    if len(findings) > 5:
        print(f"anomaly custody: finding output truncated remaining={len(findings) - 5}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=os.getcwd(), help="repository root")
    parser.add_argument("--loop-log", required=True, help="backlog loop log to audit")
    parser.add_argument("--state-root", required=True, help="runtime state root for custody records")
    parser.add_argument("--obligation-root", required=True, help="automation obligation root")
    parser.add_argument("--recent-lines", default="1200", help="number of recent loop-log lines to scan")
    parser.add_argument("--max-findings", default="12", help="maximum actionable findings to record in one audit")
    parser.add_argument("--write-obligations", action="store_true", help="open automation obligations for new actionable findings")
    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return audit(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
