#!/usr/bin/env python3
"""Classify whether a stopped backlog loop is safe to restart."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import time
from typing import Any


def run_text(argv: list[str], *, cwd: pathlib.Path) -> tuple[int, str]:
    try:
        proc = subprocess.run(
            argv,
            cwd=str(cwd),
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
    except OSError as exc:
        return 127, str(exc)
    return proc.returncode, proc.stdout


def repo_key(root: pathlib.Path) -> str:
    value = str(root)
    value = value.replace("/", "_").replace(":", "_").replace(" ", "_")
    return "".join(ch for ch in value if ch.isalnum() or ch in "_.-")


def read_tsv(path: pathlib.Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    try:
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
            key, sep, value = raw.partition("\t")
            if sep:
                fields[key] = value
    except OSError:
        pass
    return fields


def pid_alive(pid_text: str) -> bool:
    if not pid_text.isdigit():
        return False
    return pathlib.Path("/proc", pid_text).exists()


def git_branch(root: pathlib.Path) -> str:
    rc, out = run_text(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=root)
    return out.strip() if rc == 0 and out.strip() else "unknown"


def git_dirty(root: pathlib.Path) -> list[str]:
    rc, out = run_text(["git", "status", "--porcelain=v1"], cwd=root)
    if rc != 0:
        return [f"git_status_unavailable:{out.strip() or rc}"]
    return [line for line in out.splitlines() if line.strip()]


def open_obligations(root: pathlib.Path) -> list[pathlib.Path]:
    open_dir = root / "runtime" / "upkeeper-obligations" / "open"
    try:
        return sorted(path for path in open_dir.glob("*.json") if path.is_file())
    except OSError:
        return []


def read_recent_lines(log_path: pathlib.Path, limit: int) -> list[str]:
    try:
        lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    return lines[-limit:]


def last_index(lines: list[str], needle: str) -> int:
    for index in range(len(lines) - 1, -1, -1):
        if needle in lines[index]:
            return index
    return -1


def latest_pr_from_lines(lines: list[str]) -> str:
    for line in reversed(lines):
        match = re.search(r"PR #([0-9]+)", line)
        if match:
            return match.group(1)
    return ""


def classify_pr_checks(root: pathlib.Path, pr_number: str, no_github: bool) -> tuple[str, str]:
    if no_github or not pr_number:
        return "unknown", "not_checked"
    rc, out = run_text(["gh", "pr", "checks", pr_number, "--watch=false"], cwd=root)
    if rc == 127:
        return "unknown", "gh_unavailable"
    lowered = out.lower()
    if "\tfail\t" in lowered or re.search(r"(^|\n)fail(\n|$)", lowered):
        return "fail", "github_checks_failed"
    if "\tpending\t" in lowered or "pending" in lowered:
        return "pending", "github_checks_pending"
    if rc == 0 and "pass" in lowered:
        return "pass", "github_checks_passed"
    return "unknown", "github_checks_unknown"


def write_unknown_obligation(root: pathlib.Path, reason: str, excerpt: str) -> str:
    open_dir = root / "runtime" / "upkeeper-obligations" / "open"
    open_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(open_dir.parent, 0o700)
    os.chmod(open_dir, 0o700)
    digest = hashlib.sha256(f"{reason}\n{excerpt}".encode("utf-8", errors="replace")).hexdigest()[:24]
    path = open_dir / f"backlog-triage-{digest}.json"
    payload: dict[str, Any] = {
        "schema": 1,
        "id": f"backlog-triage-{digest}",
        "kind": "backlog_triage",
        "severity": "high",
        "status": "open",
        "reason": reason,
        "summary": "Backlog triage found unknown or contradictory stopped-loop evidence",
        "target_file": "orchestration/backlog.sh",
        "repair_target_file": "orchestration/backlog.sh",
        "created_epoch": int(time.time()),
        "evidence_excerpt": excerpt[-500:],
    }
    if not path.exists():
        path.write_text(json.dumps(payload, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        os.chmod(path, 0o600)
    return str(path)


def classify(args: argparse.Namespace) -> dict[str, Any]:
    root = pathlib.Path(args.root).resolve()
    state_root = pathlib.Path(args.state_root).expanduser()
    log_path = pathlib.Path(args.log).expanduser() if args.log else state_root / "loop.log"
    lines = read_recent_lines(log_path, args.lines)
    joined = "\n".join(lines)
    branch = git_branch(root)
    dirty = git_dirty(root)
    obligations = open_obligations(root)
    owner_file = state_root / f"active-owner.{repo_key(root)}.tsv"
    owner = read_tsv(owner_file)
    active_lock = root / "runtime" / "upkeeper-active.lock"
    pr_number = args.pr_number or latest_pr_from_lines(lines)
    pr_status, pr_reason = classify_pr_checks(root, pr_number, args.no_github)

    result: dict[str, Any] = {
        "safe_to_restart": "yes",
        "reason": "clean_noop",
        "next_action": "restart backlog loop when ready",
        "branch": branch,
        "log_file": str(log_path),
        "pr_number": pr_number or "none",
        "pr_check_status": pr_status,
        "dirty_count": len(dirty),
        "open_obligation_count": len(obligations),
        "active_owner": "no",
        "active_lock": "yes" if active_lock.exists() else "no",
        "obligation_path": "",
    }

    owner_pid = owner.get("pid", "")
    if owner_pid and pid_alive(owner_pid):
        result.update(
            safe_to_restart="wait",
            reason="active_backlog_owner",
            next_action=f"wait for backlog owner pid {owner_pid} or interrupt it intentionally",
            active_owner="yes",
        )
        return result

    if active_lock.exists():
        result.update(
            safe_to_restart="no",
            reason="active_lock_present",
            next_action="inspect the active lock and owning Upkeeper process before restarting",
        )
        return result

    if dirty:
        result.update(
            safe_to_restart="no",
            reason="dirty_worktree",
            next_action="commit, shelve, or intentionally autoshelve dirty work before restarting",
            dirty_sample="; ".join(dirty[:5]),
        )
        return result

    if obligations:
        result.update(
            safe_to_restart="no",
            reason="open_automation_obligation",
            next_action="repair or resolve the open automation obligation before restarting normal issue work",
            obligation_path=str(obligations[0]),
        )
        return result

    if pr_status == "pending":
        result.update(
            safe_to_restart="wait",
            reason="pr_checks_pending",
            next_action=f"wait for PR #{pr_number} checks to finish",
        )
        return result
    if pr_status == "fail":
        result.update(
            safe_to_restart="no",
            reason="pr_checks_failed",
            next_action=f"repair failing PR #{pr_number} checks before selecting more issue work",
        )
        return result

    quota_block = last_index(lines, "quota preflight: quota blocked")
    quota_done = last_index(lines, "quota hibernation complete")
    if quota_block >= 0 and quota_done < quota_block:
        result.update(
            safe_to_restart="wait",
            reason="quota_hibernating",
            next_action="wait until the logged quota wake time, then run one retry cycle",
        )
        return result

    if "Local validation\tfail" in joined or "PR #" in joined and "checks failed" in joined:
        result.update(
            safe_to_restart="no",
            reason="failed_validation_or_checks",
            next_action="repair the failing local validation or PR checks before restarting",
        )
        return result

    if "checks pending" in joined or "waiting for PR #" in joined:
        result.update(
            safe_to_restart="wait",
            reason="local_log_checks_pending",
            next_action="wait for the PR checks named in the backlog log",
        )
        return result

    if "automation.obligation.open" in joined or "UPKEEPER_STATUS: BLOCKED" in joined:
        result.update(
            safe_to_restart="no",
            reason="blocked_obligation_or_run",
            next_action="repair the blocked obligation or issue before restarting normal work",
        )
        return result

    if "merged PR #" in joined and "returned to clean main" not in joined and branch != "main":
        result.update(
            safe_to_restart="no",
            reason="merged_pr_cleanup_needed",
            next_action="checkout main, pull origin/main, and prune the merged backlog branch",
        )
        return result

    unknown_error_lines = [
        line
        for line in lines
        if (" PAGE " in line or "[ERROR]" in line)
        and "expected_negative_fixture=" not in line
        and "Local validation\tfail" not in line
    ]
    if unknown_error_lines:
        excerpt = unknown_error_lines[-1]
        obligation_path = ""
        if not args.no_write_obligation:
            obligation_path = write_unknown_obligation(root, "unknown_log_error", excerpt)
        result.update(
            safe_to_restart="no",
            reason="unknown_log_error",
            next_action="inspect the generated obligation before restarting",
            obligation_path=obligation_path,
        )
        return result

    if pr_status == "pass" and pr_number:
        result.update(
            safe_to_restart="yes",
            reason="pr_checks_passed",
            next_action=f"restart is safe; PR #{pr_number} checks are green",
        )
        return result

    return result


def emit_key_values(result: dict[str, Any]) -> None:
    for key in sorted(result):
        value = str(result[key]).replace("\n", " ")
        print(f"{key}={value}")
    print()
    print(f"Backlog triage: safe_to_restart={result['safe_to_restart']} reason={result['reason']}")
    print(f"Next action: {result['next_action']}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--state-root", default=os.environ.get("BACKLOG_STATE_ROOT", os.path.expanduser("~/.local/state/upkeeper/backlog")))
    parser.add_argument("--log", default="")
    parser.add_argument("--lines", type=int, default=400)
    parser.add_argument("--pr-number", default="")
    parser.add_argument("--no-github", action="store_true")
    parser.add_argument("--no-write-obligation", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    result = classify(args)
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        emit_key_values(result)
    return 0 if result["safe_to_restart"] in {"yes", "wait"} else 3


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
