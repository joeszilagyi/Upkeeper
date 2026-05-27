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
import time
from dataclasses import dataclass


DEFAULT_UMBRELLA_ISSUE = "418"
DEFAULT_UMBRELLA_TITLE = (
    "High priority bug: non-perfect automated runs need mandatory local "
    "remediation custody"
)
INCIDENT_ROLLUP_FAILURE_LIMIT = 3
INCIDENT_ROLLUP_WINDOW_SECONDS = 15 * 60
INCIDENT_ROLLUP_COOLDOWN_SECONDS = 6 * 60 * 60
NONZERO_LAUNCHER_FOOTER_OWNER_WINDOW_LINES = 16
ENV_INCIDENT_ROLLUP_LIMIT = "UPKEEPER_INCIDENT_ROLLUP_FAILURE_LIMIT"
ENV_INCIDENT_ROLLUP_WINDOW_SECONDS = "UPKEEPER_INCIDENT_ROLLUP_WINDOW_SECONDS"
ENV_INCIDENT_ROLLUP_COOLDOWN_SECONDS = "UPKEEPER_INCIDENT_ROLLUP_COOLDOWN_SECONDS"

TIMESTAMP_PREFIX = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:[+-]\d{4})?\s+"
)
VISUAL_MARKER = re.compile(
    r"(?:^|\s+)█\s+(PAGE|--FYI--|WORKER|ACTION|WAIT|HEALTH|OK|RUN|INFO)\s+"
)
CYCLE_RE = re.compile(r"\bcycle=([^ \t]+)")
RUN_HASH_RE = re.compile(r"\brun_hash=([^ \t]+)")
EVENT_TOKEN_RE = re.compile(r"\b[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+\b")
KNOWN_EVENT_SIGNALS = (
    "operator_guide.stale",
    "previous_run.anomaly_summary",
    "startup_anomaly.gate_unresolved",
    "startup_anomaly.gate_violation",
    "startup_anomaly.gate",
    "lattice.unavailable",
    "transcript.prune_blocked",
    "log.rotate_blocked",
    "quota.current",
    "quota.guardrails",
    "quota.cooldown",
    "automation.obligation.open",
    "cycle.exit",
    "run.finish",
    "context_length_exceeded",
)
IGNORED_EVENT_TOKEN_SUFFIXES = (
    ".bash",
    ".conf",
    ".json",
    ".jsonl",
    ".md",
    ".py",
    ".sh",
    ".sqlite3",
    ".txt",
)
ANOMALY_KIND_LABELS = {
    "incident_rollup": "incident rollup",
    "page_error": "PAGE error",
    "failed_pr_check_gate": "PR check gate failure",
    "nonzero_cycle_exit": "nonzero cycle exit",
    "nonzero_launcher_exit": "nonzero launcher exit",
    "lattice_unavailable": "lattice degraded mode",
    "startup_anomaly_unresolved": "startup anomaly unresolved",
    "previous_run_anomaly_summary": "previous-run anomaly summary",
    "startup_anomaly_gate_active": "startup anomaly gate active",
    "warning_line": "warning",
    "backend_context_overflow": "backend context overflow",
    "expected_fixture_output": "expected fixture output",
}
HARD_INCIDENT_KINDS = {
    "page_error",
    "failed_pr_check_gate",
    "nonzero_cycle_exit",
    "nonzero_launcher_exit",
    "lattice_unavailable",
    "startup_anomaly_unresolved",
}
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
ROLLUP_FAMILY_RE = re.compile(r"\bcycle=[^ \t]+\s*")


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
    incident_key: str = ""
    incident_signals: tuple[dict[str, object], ...] = ()


def now_local() -> str:
    return _dt.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def now_epoch() -> int:
    return int(time.time())


def _safe_int(value: object, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _read_int_env(name: str, default: int) -> int:
    value = os.getenv(name, "")
    if not value:
        return default
    return _safe_int(value, default)


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


def compact_title_text(value: str, width: int = 90) -> str:
    text = " ".join(str(value).replace("\r", " ").replace("\t", " ").split())
    text = text.strip(" \"'`[](){}")
    if len(text) <= width:
        return text
    return text[: width - 3].rstrip(" ./_-") + "..."


def anomaly_signal(kind: str, normalized: str) -> str:
    if kind == "incident_rollup":
        return "incident.rollup"
    lower = normalized.lower()
    for signal in KNOWN_EVENT_SIGNALS:
        if signal in lower:
            return signal
    if kind == "failed_pr_check_gate":
        return "PR checks"
    if kind == "nonzero_cycle_exit" and "cycle.exit" in lower:
        return "cycle.exit"
    if kind == "page_error" and "page" in lower:
        return "PAGE"
    for token in EVENT_TOKEN_RE.findall(normalized):
        token_lower = token.lower()
        if token_lower.startswith("v") and len(token_lower) > 1 and token_lower[1].isdigit():
            continue
        if token_lower.endswith(IGNORED_EVENT_TOKEN_SUFFIXES):
            continue
        return compact_title_text(token, 70)
    return ""


def anomaly_title_label(kind: str, normalized: str) -> str:
    if kind == "incident_rollup":
        return "incident rollup"
    label = ANOMALY_KIND_LABELS.get(kind, kind.replace("_", " "))
    signal = anomaly_signal(kind, normalized)
    if not signal:
        return label
    if signal.lower().replace(".", "_").replace(" ", "_") == kind:
        return signal
    if signal.lower() in label.lower():
        return label
    if label.lower() in signal.lower():
        return signal
    return f"{signal} {label}"


def anomaly_summary(finding: Finding) -> str:
    label = anomaly_title_label(finding.kind, finding.normalized)
    return f"Prior backlog log anomaly needs repair or explicit custody: {label}"


def issue_title_for_finding(finding: Finding) -> str:
    label = anomaly_title_label(finding.kind, finding.normalized)
    target = compact_title_text(finding.target or "machine-local state", 80)
    return f"High priority bug: prior-run {label} needs repair for {target}"[:180]


def generic_prior_run_issue_title(value: object) -> bool:
    text = str(value or "").strip()
    if not text:
        return True
    return text == DEFAULT_UMBRELLA_TITLE or text.startswith(
        "High priority bug: automation obligation prior_run_anomaly needs repair"
    )


def context_has(lines: list[tuple[int, str]], index: int, needle: str, radius: int = 12) -> bool:
    low = max(0, index - radius)
    high = min(len(lines), index + radius + 1)
    return any(needle in line for _, line in lines[low:high])


def failure_transcript_tail_echo(lines: list[tuple[int, str]], index: int, normalized: str) -> bool:
    lower = normalized.lower()
    terminal_tokens = (
        "run.finish",
        "cycle.exit",
        "codex exited non-zero",
        "startup_anomaly.gate_unresolved",
        "checks_failed",
        "checks failed",
        "stopping before selecting another issue",
        "automation.obligation.open",
        "upkeeper exited with status",
        "launcher exiting with status",
    )
    if "failure transcript tail" in lower:
        return not (CYCLE_RE.search(normalized) or RUN_HASH_RE.search(normalized))
    if any(token in lower for token in terminal_tokens):
        return False
    low = max(0, index - 140)
    for prior_index in range(index - 1, low - 1, -1):
        prior_lower = strip_prefix(lines[prior_index][1]).lower()
        if "failure transcript tail" in prior_lower:
            return True
        if "codex review finished" in prior_lower or "review completed" in prior_lower:
            return False
    return False


def backend_context_overflow_text(normalized: str) -> bool:
    lower = normalized.lower()
    return (
        "context_length_exceeded" in lower
        or "context length exceeded" in lower
        or "remote compact" in lower
        or "input exceeds the context window" in lower
        or "maximum context length" in lower
    )


def expected_fixture(lines: list[tuple[int, str]], index: int, line: str) -> bool:
    lower = line.lower()
    if "live_output.false_positive_error_echo classification=quoted_backend_source_fixture" in lower:
        return True
    if (
        "transcript directory is not private" in lower
        and "upkeeper-transcripts-test." in lower
        and context_has(lines, index, "transcript_artifacts_test: ok", radius=20)
    ):
        return True
    if (
        "transcript.prune_blocked reason=missing_ownership_marker" in lower
        and context_has(lines, index, "transcript_artifacts_test: ok", radius=20)
    ):
        return True
    if (
        "pre-contact backup prerequisite missing" in lower
        and context_has(lines, index, "precontact_backup_test: ok", radius=80)
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


def is_expected_final_review_stopper(line: str) -> bool:
    lower = line.lower()
    return (
        "upkeeper: final review for" in lower
        and "-> stopped_on_blocker" in lower
    )


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
    if payload.startswith("print(") and (
        "run_record_read=fail" in payload
        or " error=" in payload
        or "exception" in payload
        or "traceback" in payload
    ):
        return True

    shell_fixture_tokens = (
        "rg -n ",
        "rg --",
        "printf ",
        "printf '",
        'printf "',
        "log_line ",
        "log_line_parts ",
        "echo ",
        "grep ",
        "grep -fq ",
        "grep -eq ",
        "if grep ",
        "if [[",
        "case ",
        "cat >",
        "awk ",
        "sed ",
        "warn=",
        "err=",
        "payload=",
        "sample=",
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
        "[quoted-warn]",
        "[quoted-error]",
        "[info]",
        "(warn|error)",
        "warn|error",
        "warn",
        "error",
        " page ",
        " quoted-page ",
        "startup_anomaly",
        "previous_run.anomaly",
        " cycle=",
        " run_hash=",
        "cycle.exit",
        "run.finish",
        " █ ",
    )
    if re.match(r"^\d{4}-\d{2}-\d{2}t\d{2}:\d{2}:\d{2}", payload) and any(
        token in payload for token in embedded_log_tokens
    ):
        return True
    if "warn=" in payload or "err=" in payload:
        return True
    if payload.startswith(("rg -n ", "rg --", "grep ", "printf ", "log_line ", "log_line_parts ", "echo ", "if grep ", "if [[", "case ", "sample=", "payload=")):
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
    if backend_context_overflow_text(normalized):
        return "lib/upkeeper/transcript_output.bash"
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


def managed_quota_guardrail_telemetry(normalized: str) -> bool:
    lower = normalized.lower()
    if "quota.guardrails" not in lower:
        return False
    return (
        " partial_decision" in lower
        or " deferred" in lower
        or " action=defer_to_backend_usage_limit" in lower
    )


def managed_quota_current_telemetry(normalized: str) -> bool:
    lower = normalized.lower()
    if "quota.current" not in lower:
        return False
    return " using snapshot_selection=" in lower


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
    if failure_transcript_tail_echo(lines, index, normalized):
        return None
    if backend_context_overflow_text(normalized):
        return Classification(
            "backend_context_overflow",
            "high",
            target,
            "backend context window was exceeded before a clean status marker",
        )
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
    if is_expected_final_review_stopper(normalized):
        return None
    if "[warn]" in lower or "█ --fyi--" in raw_line.lower():
        ignored_waits = (
            "quota preflight:" in lower
            or "quota hibernating" in lower
            or "quota hibernation complete" in lower
            or "quota.cooldown bypassed" in lower
            or "quota.guardrails bypassed=1" in lower
            or managed_quota_guardrail_telemetry(normalized)
            or managed_quota_current_telemetry(normalized)
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
    if kind == "incident_rollup":
        normalized = ROLLUP_FAMILY_RE.sub("cycle=<cycle> ", normalize_fingerprint_text(normalized))
        return normalized.strip()
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
    if kind == "backend_context_overflow":
        return "backend_context_overflow"
    return normalize_fingerprint_text(normalized)


def finding_id(kind: str, normalized: str, target: str) -> tuple[str, str]:
    fingerprint = stable_fingerprint(kind, normalized)
    digest = hashlib.sha256(f"{kind}\0{target}\0{fingerprint}".encode("utf-8", "surrogateescape")).hexdigest()
    return f"prior-run-{digest[:24]}", fingerprint


def hard_incident_kind(kind: str) -> bool:
    return kind in HARD_INCIDENT_KINDS


def incident_signal_payload(finding: Finding) -> dict[str, object]:
    return {
        "id": finding.ident,
        "kind": finding.kind,
        "severity": finding.severity,
        "target_file": finding.target,
        "reason": finding.reason,
        "line_number": finding.line_number,
        "fingerprint": finding.fingerprint,
        "excerpt": finding.excerpt,
        "normalized_excerpt": finding.normalized,
        "cycle_id": finding.cycle_id,
        "run_hash": finding.run_hash,
    }


def incident_signature(findings: list[Finding]) -> tuple[str, str]:
    parts = sorted(
        f"{finding.kind}\0{finding.target}\0{finding.fingerprint}"
        for finding in findings
        if hard_incident_kind(finding.kind)
    )
    if not parts:
        parts = sorted(f"{finding.kind}\0{finding.target}\0{finding.fingerprint}" for finding in findings)
    fingerprint = "incident_rollup " + " | ".join(
        compact_title_text(part.replace("\0", ":"), 120) for part in parts
    )
    digest = hashlib.sha256(("\0".join(["incident_rollup", *parts])).encode("utf-8", "surrogateescape")).hexdigest()
    return f"prior-run-incident-{digest[:24]}", fingerprint


def roll_up_incident_findings(findings: list[Finding]) -> tuple[list[Finding], int, int]:
    """Collapse same-source-cycle hard cascades into one actionable owner.

    Exact repeated fingerprints are still coalesced earlier. This pass handles a
    different failure mode: one bad source cycle can emit several distinct PAGE,
    nonzero-exit, startup-gate, or degraded-mode signals that all point at the
    same incident. Keeping the signals inside one rollup obligation prevents the
    next loops from filing and selecting a swarm of sibling issue records.
    """

    by_cycle: dict[str, list[Finding]] = {}
    cycle_order: list[str] = []
    passthrough: list[Finding] = []
    for finding in findings:
        if not finding.cycle_id:
            passthrough.append(finding)
            continue
        if finding.cycle_id not in by_cycle:
            by_cycle[finding.cycle_id] = []
            cycle_order.append(finding.cycle_id)
        by_cycle[finding.cycle_id].append(finding)

    rolled: list[Finding] = []
    rollup_count = 0
    rolled_signal_count = 0
    consumed_ids: set[str] = set()

    for cycle_id in cycle_order:
        group = by_cycle[cycle_id]
        hard = [finding for finding in group if hard_incident_kind(finding.kind)]
        if len(hard) < 2:
            continue
        ordered = sorted(group, key=lambda item: item.line_number)
        representative = hard[0]
        ident, fingerprint = incident_signature(ordered)
        signal_kinds = ", ".join(dict.fromkeys(finding.kind for finding in ordered))
        signal_targets = ", ".join(dict.fromkeys(finding.target for finding in ordered))
        normalized = (
            f"incident_rollup cycle={cycle_id} hard_signals={len(hard)} "
            f"signals={signal_kinds} targets={signal_targets}"
        )
        excerpt = bounded_excerpt(normalized)
        rolled.append(
            Finding(
                ident=ident,
                fingerprint=fingerprint,
                kind="incident_rollup",
                severity="high",
                target="Upkeeper",
                reason="multiple hard control-plane anomaly signals belong to one source-cycle incident",
                line_number=ordered[0].line_number,
                excerpt=excerpt,
                normalized=normalized,
                cycle_id=cycle_id,
                run_hash=representative.run_hash,
                status="actionable",
                incident_key=f"incident:{fingerprint}",
                incident_signals=tuple(incident_signal_payload(finding) for finding in ordered),
            )
        )
        rollup_count += 1
        rolled_signal_count += len(ordered)
        consumed_ids.update(finding.ident for finding in ordered)

    result: list[Finding] = []
    for finding in findings:
        if finding.ident not in consumed_ids:
            result.append(finding)
    rolled_by_id: dict[str, Finding] = {}
    for finding in rolled:
        prior = rolled_by_id.get(finding.ident)
        if prior is None or finding.line_number > prior.line_number:
            rolled_by_id[finding.ident] = finding
    result.extend(sorted(rolled_by_id.values(), key=lambda item: item.line_number))
    result.sort(key=lambda item: item.line_number)
    return result, rollup_count, rolled_signal_count


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
    payload = {
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
    if finding.incident_key:
        payload["incident_key"] = finding.incident_key
        payload["incident_signal_count"] = len(finding.incident_signals)
        payload["incident_signals"] = list(finding.incident_signals)
    return payload


def incident_rollup_history_payload(data: dict, finding: Finding) -> None:
    cycles = data.get("incident_source_cycle_ids")
    if not isinstance(cycles, list):
        cycles = []
    if finding.cycle_id and finding.cycle_id not in cycles:
        cycles.append(finding.cycle_id)
    if cycles:
        data["incident_source_cycle_ids"] = cycles[-50:]
    signal_ids = data.get("incident_signal_ids")
    if not isinstance(signal_ids, list):
        signal_ids = []
    seen = {str(item).strip() for item in signal_ids if str(item).strip()}
    for signal in finding.incident_signals:
        signal_id = str(signal.get("id") or "").strip()
        if signal_id and signal_id not in seen:
            signal_ids.append(signal_id)
            seen.add(signal_id)
    if signal_ids:
        data["incident_signal_ids"] = signal_ids
        data["incident_signal_count"] = len(signal_ids)


def apply_incident_rollup_circuit_breaker(data: dict, finding: Finding) -> None:
    if finding.kind != "incident_rollup":
        return
    limit = max(1, _read_int_env(ENV_INCIDENT_ROLLUP_LIMIT, INCIDENT_ROLLUP_FAILURE_LIMIT))
    window_seconds = max(0, _read_int_env(ENV_INCIDENT_ROLLUP_WINDOW_SECONDS, INCIDENT_ROLLUP_WINDOW_SECONDS))
    cooldown_seconds = max(0, _read_int_env(ENV_INCIDENT_ROLLUP_COOLDOWN_SECONDS, INCIDENT_ROLLUP_COOLDOWN_SECONDS))
    if limit <= 1:
        return

    now = now_epoch()
    prior_seen = _safe_int(data.get("incident_rollup_last_seen_epoch"), 0)
    prior_cycle = str(data.get("incident_rollup_last_cycle_id", ""))

    if (
        prior_seen
        and finding.cycle_id
        and finding.cycle_id != prior_cycle
        and (now - prior_seen) <= window_seconds
    ):
        immediate_failures = _safe_int(data.get("incident_rollup_immediate_failure_count"), 0) + 1
    else:
        immediate_failures = 1

    data["incident_rollup_last_seen_epoch"] = now
    data["incident_rollup_last_seen_at"] = now_local()
    data["incident_rollup_last_cycle_id"] = finding.cycle_id
    data["incident_rollup_immediate_failure_count"] = immediate_failures
    data["incident_rollup_failure_limit"] = limit
    data["incident_rollup_immediate_window_seconds"] = window_seconds
    incident_rollup_history_payload(data, finding)

    if immediate_failures < limit:
        data.pop("selection_state", None)
        data.pop("next_retry_epoch", None)
        data.pop("next_retry_at", None)
        data.pop("cooldown_reason", None)
        data.pop("cooldown_attempt_limit", None)
        data.pop("incident_rollup_cooldown_seconds", None)
        data.pop("incident_rollup_circuit_breaker", None)
        return

    data["selection_state"] = "incident_circuit_breaker"
    data["incident_rollup_circuit_breaker"] = "active"
    data["cooldown_reason"] = "incident_rollup_immediate_failure_burst"
    data["cooldown_attempt_limit"] = limit
    data["incident_rollup_cooldown_seconds"] = cooldown_seconds
    if cooldown_seconds > 0:
        existing_retry = _safe_int(data.get("next_retry_epoch"), 0)
        retry_until = now + cooldown_seconds
        if retry_until > existing_retry:
            data["next_retry_epoch"] = retry_until
            data["next_retry_at"] = now_local_from_epoch(retry_until)

    required = data.get("required_resolution")
    if isinstance(required, list):
        note = "incident rollup repeated immediate failures are blocked; run local recovery steps and explicit validation before retrying this obligation"
        if note not in [str(item) for item in required]:
            required.append(note)
            data["required_resolution"] = required
    else:
        data["required_resolution"] = [
            "incident rollup repeated immediate failures are blocked; run local recovery steps and explicit validation before retrying this obligation"
        ]


def now_local_from_epoch(epoch: int) -> str:
    return _dt.datetime.fromtimestamp(epoch, _dt.timezone.utc).astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def obligation_payload(finding: Finding, root: pathlib.Path, loop_log: pathlib.Path) -> dict:
    title_label = anomaly_title_label(finding.kind, finding.normalized)
    signal = anomaly_signal(finding.kind, finding.normalized)
    payload = {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": finding.ident,
        "created_at": now_local(),
        "kind": "prior_run_anomaly",
        "severity": finding.severity,
        "summary": anomaly_summary(finding),
        "anomaly_kind": finding.kind,
        "anomaly_signal": signal,
        "anomaly_title_label": title_label,
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
        "issue_number": "",
        "issue_title": issue_title_for_finding(finding),
        "issue_title_basis": "prior_run_anomaly_signal",
        "owner_issue_number": DEFAULT_UMBRELLA_ISSUE,
        "owner_issue_title": DEFAULT_UMBRELLA_TITLE,
        "specific_issue_required": True,
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
    if finding.incident_key:
        payload["incident_key"] = finding.incident_key
        payload["incident_signal_count"] = len(finding.incident_signals)
        payload["evidence"]["incident_key"] = finding.incident_key
        payload["evidence"]["incident_signal_count"] = len(finding.incident_signals)
        payload["evidence"]["incident_signals"] = list(finding.incident_signals)
        payload["incident_source_cycle_ids"] = [finding.cycle_id] if finding.cycle_id else []
        payload["incident_signal_ids"] = [signal.get("id") for signal in finding.incident_signals if signal.get("id")]
        payload["incident_rollup_immediate_failure_count"] = 1
        payload["incident_rollup_failure_limit"] = INCIDENT_ROLLUP_FAILURE_LIMIT
        payload["incident_rollup_immediate_window_seconds"] = INCIDENT_ROLLUP_WINDOW_SECONDS
        payload["incident_rollup_last_seen_epoch"] = now_epoch()
        payload["incident_rollup_last_seen_at"] = now_local()
        payload["incident_rollup_last_cycle_id"] = finding.cycle_id
        payload["selection_state"] = "incident_rollup_active"
        payload["required_resolution"] = [
            "inspect every signal inside the incident rollup before normal backlog issue work",
            "identify the single underlying source-cycle failure or explicitly split unrelated signals with deterministic evidence",
            "patch the wrapper, launcher, tests, docs, or detector rule when the source is repairable now",
            "preserve individual signal evidence inside the rollup instead of filing duplicate sibling obligations for the same incident",
            "add deterministic validation for the repaired or intentionally expected outcome",
        ]
    return payload


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
    data["anomaly_kind"] = finding.kind
    data["anomaly_signal"] = anomaly_signal(finding.kind, finding.normalized)
    data["anomaly_title_label"] = anomaly_title_label(finding.kind, finding.normalized)
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
    if finding.incident_key:
        data["incident_key"] = finding.incident_key
        data["incident_signal_count"] = len(finding.incident_signals)
        data["last_evidence"]["incident_key"] = finding.incident_key
        data["last_evidence"]["incident_signal_count"] = len(finding.incident_signals)
        data["last_evidence"]["incident_signals"] = list(finding.incident_signals)
    if finding.kind == "incident_rollup":
        incident_rollup_history_payload(data, finding)
        apply_incident_rollup_circuit_breaker(data, finding)
    if not data.get("fingerprint"):
        data["fingerprint"] = finding.fingerprint
    if first_summary := anomaly_summary(finding):
        if str(data.get("summary") or "").strip().endswith(f": {finding.kind}") or not str(data.get("summary") or "").strip():
            data["summary"] = first_summary
    if generic_prior_run_issue_title(data.get("issue_title")):
        data["issue_title"] = issue_title_for_finding(finding)
        data["issue_title_basis"] = "prior_run_anomaly_signal"
    evidence = data.get("evidence")
    if isinstance(evidence, dict):
        evidence.setdefault("fingerprint", finding.fingerprint)
        evidence["occurrence_count"] = data["occurrence_count"]
    write_json(path, data)


def terminal_failure_companion(finding: Finding) -> bool:
    lower = finding.normalized.lower()
    if finding.kind == "backend_context_overflow":
        return True
    if "codex.transcript_capture_failed" in lower:
        return True
    if "codex.live_output_filter_failed" in lower:
        return True
    if "run.finish" in lower and (
        "codex_exit=" in lower
        or "wait_result=failed" in lower
        or "status_marker=missing" in lower
        or "session_end_state=no_agent_message" in lower
        or "transcript_bytes=0" in lower
        or "transcript_lines=0" in lower
    ):
        return True
    if "codex exited non-zero without an upkeeper_status marker" in lower:
        return True
    if "codex exited non-zero without transcript output" in lower:
        return True
    if "cycle.exit exit_code=" in lower and (
        "missing_status_marker" in lower
        or "codex_exec_empty_transcript" in lower
        or "status_marker_source=missing" in lower
        or "codex_exit=1" in lower
        or "codex_exit=101" in lower
        or "transcript_bytes=0" in lower
        or "transcript_lines=0" in lower
    ):
        return True
    return False


def terminal_failure_owner(record: dict, finding: Finding, root: pathlib.Path) -> bool:
    if record.get("state") not in {"open", "resolved"}:
        return False
    data = record.get("data")
    if not isinstance(data, dict):
        return False
    record_root = str(data.get("root") or "")
    if record_root and pathlib.Path(record_root).resolve() != root:
        return False
    kind = str(data.get("kind") or "")
    reason = str(data.get("reason") or "")
    if kind not in {
        "blocked",
        "local_validation_failure",
        "lattice_unavailable",
        "missing_status_marker",
        "wrapper_execution_failure",
        "backend_context_overflow",
        "codex_exec_empty_transcript",
        "turn_aborted_without_marker",
    } and reason not in {
        "BLOCKED",
        "BATCH_VALIDATION_FAILED",
        "LATTICE_UNAVAILABLE",
        "MISSING_STATUS_MARKER",
        "UPKEEPER_CHILD_EXIT_NONZERO",
        "BACKEND_CONTEXT_LENGTH_EXCEEDED",
        "CODEX_EXEC_EMPTY_TRANSCRIPT",
        "TURN_ABORTED_WITHOUT_MARKER",
    }:
        return False
    source_cycle_id = str(data.get("source_cycle_id") or "")
    source_run_hash = str(data.get("source_run_hash") or "")
    if finding.cycle_id and source_cycle_id == finding.cycle_id:
        return True
    if finding.run_hash and source_run_hash == finding.run_hash:
        return True
    return False


def source_cycle_owner_record(
    finding: Finding,
    obligation_records: dict[str, dict],
    root: pathlib.Path,
) -> dict | None:
    if not (finding.cycle_id or finding.run_hash):
        return None
    for record in obligation_records.values():
        if terminal_failure_owner(record, finding, root):
            return record
    return None


def terminal_failure_owner_record(
    finding: Finding,
    obligation_records: dict[str, dict],
    root: pathlib.Path,
) -> dict | None:
    if not terminal_failure_companion(finding):
        return None
    for record in obligation_records.values():
        if terminal_failure_owner(record, finding, root):
            return record
    return None


def nonzero_launcher_footer_companion(finding: Finding) -> bool:
    if finding.kind != "nonzero_launcher_exit":
        return False
    if finding.cycle_id or finding.run_hash:
        return False
    lower = finding.normalized.lower()
    return (
        "outcome/results: upkeeper exited with status" in lower
        or "final disposition: launcher exiting with status" in lower
        or "launcher exiting with status" in lower
    )


def recent_terminal_failure_owner_record(
    finding: Finding,
    recent_owner: tuple[dict, int] | None,
) -> dict | None:
    if not nonzero_launcher_footer_companion(finding):
        return None
    if recent_owner is None:
        return None
    record, line_number = recent_owner
    if finding.line_number < line_number:
        return None
    if finding.line_number - line_number > NONZERO_LAUNCHER_FOOTER_OWNER_WINDOW_LINES:
        return None
    return record


def update_terminal_failure_owner(path: pathlib.Path, finding: Finding, loop_log: pathlib.Path) -> None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return
    if not isinstance(data, dict):
        return
    try:
        coalesced_count = int(data.get("coalesced_failure_evidence_count") or 0)
    except (TypeError, ValueError):
        coalesced_count = 0
    data["updated_at"] = now_local()
    data["coalesced_failure_evidence_count"] = coalesced_count + 1
    data["last_coalesced_failure_evidence"] = {
        "source": "backlog_loop_log",
        "loop_log": str(loop_log),
        "line_number": finding.line_number,
        "kind": finding.kind,
        "reason": finding.reason,
        "fingerprint": finding.fingerprint,
        "excerpt": finding.excerpt,
        "normalized_excerpt": finding.normalized,
    }
    write_json(path, data)


def audit(args: argparse.Namespace) -> int:
    root = pathlib.Path(args.root).resolve()
    loop_log = pathlib.Path(args.loop_log).expanduser()
    state_root = pathlib.Path(args.state_root)
    obligation_root = pathlib.Path(args.obligation_root)
    recent_lines = max(0, int(args.recent_lines))
    max_findings = max(0, int(args.max_findings))

    lines = tail_lines(loop_log, recent_lines)
    candidate_findings: list[Finding] = []
    findings: list[Finding] = []
    known_open_findings: list[tuple[dict, Finding]] = []
    expected_count = 0
    resolved_count = 0
    coalesced_count = 0
    incident_rollup_count = 0
    incident_signal_count = 0
    seen_ids: set[str] = set()
    known_open_ids: set[str] = set()
    truncated_count = 0
    created_obligations = 0
    updated_obligations = 0
    obligation_records = existing_obligation_records(obligation_root)
    recent_terminal_owner: tuple[dict, int] | None = None
    for index, (line_number, raw_line) in enumerate(lines):
        classified = classify(lines, index, raw_line)
        if classified is None:
            continue
        finding = make_finding(lines, index, line_number, raw_line, classified)
        if finding.status == "expected_fixture":
            expected_count += 1
            continue
        terminal_owner = source_cycle_owner_record(finding, obligation_records, root)
        if terminal_owner is None:
            terminal_owner = terminal_failure_owner_record(finding, obligation_records, root)
        if terminal_owner is None:
            terminal_owner = recent_terminal_failure_owner_record(finding, recent_terminal_owner)
        if terminal_owner is not None:
            if args.write_obligations and terminal_owner.get("state") == "open":
                update_terminal_failure_owner(pathlib.Path(terminal_owner["path"]), finding, loop_log)
                updated_obligations += 1
            elif terminal_owner.get("state") == "resolved":
                resolved_count += 1
            coalesced_count += 1
            if finding.cycle_id or finding.run_hash or terminal_failure_companion(finding):
                recent_terminal_owner = (terminal_owner, finding.line_number)
            continue
        if finding.ident in seen_ids:
            coalesced_count += 1
            if finding.kind == "incident_rollup":
                for replace_index in range(len(candidate_findings) - 1, -1, -1):
                    prior = candidate_findings[replace_index]
                    if prior.ident == finding.ident:
                        candidate_findings[replace_index] = finding
                        break
            continue
        seen_ids.add(finding.ident)
        candidate_findings.append(finding)

    candidate_findings, incident_rollup_count, incident_signal_count = roll_up_incident_findings(candidate_findings)
    coalesced_count += max(0, incident_signal_count - incident_rollup_count)

    for finding in candidate_findings:
        record = obligation_records.get(finding.ident)
        if record and record.get("state") == "resolved":
            resolved_count += 1
            continue
        if record and record.get("state") == "open":
            if finding.ident in known_open_ids:
                coalesced_count += 1
                continue
            known_open_ids.add(finding.ident)
            known_open_findings.append((record, finding))
            continue
        if max_findings > 0 and len(findings) >= max_findings:
            truncated_count += 1
            continue
        findings.append(finding)

    private_dir(state_root)
    finding_dir = state_root / "findings"
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
    for record, finding in known_open_findings:
        if args.write_obligations:
            update_open_obligation(pathlib.Path(record["path"]), finding, loop_log)
            updated_obligations += 1

    if findings:
        status = "actionable"
    elif known_open_findings:
        status = "known_open"
    else:
        status = "clean"
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
        "known_open_findings": len(known_open_findings),
        "expected_fixture_findings": expected_count,
        "resolved_fingerprint_findings": resolved_count,
        "coalesced_findings": coalesced_count,
        "incident_rollup_findings": incident_rollup_count,
        "incident_signal_findings": incident_signal_count,
        "truncated_findings": truncated_count,
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
        f"known_open={len(known_open_findings)} resolved={resolved_count} "
        f"coalesced={coalesced_count} incident_rollups={incident_rollup_count} "
        f"truncated={truncated_count} "
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
    parser.add_argument("--max-findings", default="0", help="maximum new actionable findings to record in one audit; 0 means no cap")
    parser.add_argument("--write-obligations", action="store_true", help="open automation obligations for new actionable findings")
    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return audit(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
