#!/usr/bin/env python3
"""Guard and execute cleanup for an already-green backlog PR."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
import sys
from typing import Any


def run(argv: list[str], *, cwd: pathlib.Path, env: dict[str, str] | None = None) -> tuple[int, str]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    try:
        proc = subprocess.run(
            argv,
            cwd=str(cwd),
            env=merged_env,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
    except OSError as exc:
        return 127, str(exc)
    return proc.returncode, proc.stdout


def git_lines(root: pathlib.Path, args: list[str]) -> list[str]:
    rc, out = run(["git", *args], cwd=root)
    if rc != 0:
        raise RuntimeError(out.strip() or f"git {' '.join(args)} failed")
    return out.splitlines()


def current_branch(root: pathlib.Path) -> str:
    rc, out = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=root)
    return out.strip() if rc == 0 and out.strip() else "unknown"


def parse_worktrees(root: pathlib.Path) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    current: dict[str, str] = {}
    for line in git_lines(root, ["worktree", "list", "--porcelain"]):
        if not line:
            if current:
                records.append(current)
                current = {}
            continue
        key, _, value = line.partition(" ")
        current[key] = value
    if current:
        records.append(current)
    return records


def worktree_dirty(path: pathlib.Path) -> bool:
    rc, out = run(["git", "status", "--porcelain=v1"], cwd=path)
    return rc != 0 or bool(out.strip())


def gh_pr_view(root: pathlib.Path, pr_number: str, repo: str) -> dict[str, Any]:
    cmd = [
        "gh",
        "pr",
        "view",
        pr_number,
        "--json",
        "number,state,isDraft,baseRefName,headRefName,mergeable,mergeStateStatus,url",
    ]
    if repo:
        cmd.extend(["--repo", repo])
    rc, out = run(cmd, cwd=root)
    if rc != 0:
        raise RuntimeError(out.strip() or "gh pr view failed")
    return json.loads(out)


def gh_checks_state(root: pathlib.Path, pr_number: str, repo: str) -> tuple[str, str]:
    cmd = ["gh", "pr", "checks", pr_number, "--watch=false"]
    if repo:
        cmd.extend(["--repo", repo])
    rc, out = run(cmd, cwd=root)
    lowered = out.lower()
    if "\tfail\t" in lowered or lowered.strip() == "fail":
        return "fail", out
    if "pending" in lowered:
        return "pending", out
    if rc == 0 and "pass" in lowered:
        return "pass", out
    return "unknown", out


def fail_result(reason: str, next_action: str, **extra: Any) -> dict[str, Any]:
    result: dict[str, Any] = {
        "merge_ready": "no",
        "safe_to_restart": "no",
        "reason": reason,
        "next_action": next_action,
    }
    result.update(extra)
    return result


def ok_result(reason: str, next_action: str, **extra: Any) -> dict[str, Any]:
    result: dict[str, Any] = {
        "merge_ready": "yes",
        "safe_to_restart": "yes",
        "reason": reason,
        "next_action": next_action,
    }
    result.update(extra)
    return result


def validate_pr(root: pathlib.Path, pr_number: str, repo: str) -> tuple[dict[str, Any] | None, dict[str, Any], str]:
    pr = gh_pr_view(root, pr_number, repo)
    checks_state, checks_raw = gh_checks_state(root, pr_number, repo)
    base = str(pr.get("baseRefName") or "")
    head = str(pr.get("headRefName") or "")
    mergeable = str(pr.get("mergeable") or "UNKNOWN")
    merge_state = str(pr.get("mergeStateStatus") or "UNKNOWN")

    if pr.get("state") != "OPEN":
        return fail_result("pr_not_open", "open or select a different PR", pr_state=pr.get("state", "unknown")), pr, checks_state
    if pr.get("isDraft"):
        return fail_result("pr_is_draft", "mark the PR ready for review before merging"), pr, checks_state
    if base != "main":
        return fail_result("pr_base_not_main", "only main-based backlog PRs can be merge-stewarded", pr_base=base), pr, checks_state
    if checks_state != "pass":
        return fail_result(f"checks_{checks_state}", "wait for or repair PR checks before merging", checks=checks_state), pr, checks_state
    if mergeable not in {"MERGEABLE", "UNKNOWN"}:
        return fail_result("pr_not_mergeable", "update the branch until GitHub reports it mergeable", mergeable=mergeable), pr, checks_state
    if merge_state in {"DIRTY", "BLOCKED", "BEHIND"}:
        return fail_result("pr_merge_state_blocked", "update the branch until the merge state is clean", merge_state=merge_state), pr, checks_state
    return None, pr | {"headRefName": head, "checks_raw": checks_raw}, checks_state


def inspect_main_worktrees(root: pathlib.Path) -> tuple[dict[str, Any] | None, list[pathlib.Path]]:
    main_worktrees: list[pathlib.Path] = []
    for record in parse_worktrees(root):
        if record.get("branch") == "refs/heads/main":
            path = pathlib.Path(record["worktree"])
            main_worktrees.append(path)
            if path != root and worktree_dirty(path):
                return fail_result(
                    "dirty_main_worktree",
                    f"clean or commit dirty worktree holding main: {path}",
                    worktree=str(path),
                ), main_worktrees
    return None, main_worktrees


def steward(args: argparse.Namespace) -> dict[str, Any]:
    root = pathlib.Path(args.root).resolve()
    pr_number = str(args.pr_number)
    pr_failure, pr, checks_state = validate_pr(root, pr_number, args.repo)
    if pr_failure:
        return pr_failure
    worktree_failure, main_worktrees = inspect_main_worktrees(root)
    if worktree_failure:
        return worktree_failure

    branch = current_branch(root)
    if branch != "main" and not main_worktrees:
        return fail_result("main_worktree_missing", "checkout or add a clean main worktree before merge cleanup", branch=branch)

    if args.dry_run:
        return ok_result(
            "dry_run_ready",
            f"PR #{pr_number} is green and merge-steward ready",
            pr_number=pr_number,
            checks=checks_state,
            branch=branch,
            main_worktree_count=len(main_worktrees),
        )

    merge_cmd = ["gh", "pr", "merge", pr_number, "--merge", "--delete-branch"]
    if args.repo:
        merge_cmd.extend(["--repo", args.repo])
    rc, out = run(merge_cmd, cwd=root, env={f"CODEX_ALLOW_PR_MERGE": pr_number})
    if rc != 0:
        return fail_result("merge_failed", "repair the merge failure before restarting", merge_output=out.strip())

    sync_root = main_worktrees[0] if main_worktrees else root
    rc, fetch_out = run(["git", "fetch", "origin", "main", "--prune"], cwd=sync_root)
    if rc != 0:
        return fail_result("main_fetch_failed", "fetch origin/main manually before restarting", fetch_output=fetch_out.strip())
    rc, pull_out = run(["git", "pull", "--ff-only", "origin", "main"], cwd=sync_root)
    if rc != 0:
        return fail_result("main_sync_failed", "sync local main manually before restarting", pull_output=pull_out.strip())
    if worktree_dirty(sync_root):
        return fail_result("main_dirty_after_merge", "inspect local main before restarting", worktree=str(sync_root))

    return ok_result(
        "merged_clean",
        f"PR #{pr_number} merged; local main synced and clean",
        pr_number=pr_number,
        main_worktree=str(sync_root),
    )


def emit(result: dict[str, Any], *, as_json: bool) -> None:
    if as_json:
        print(json.dumps(result, sort_keys=True))
        return
    for key in sorted(result):
        print(f"{key}={str(result[key]).replace(chr(10), ' ')}")
    print()
    print(f"Merge steward: merge_ready={result['merge_ready']} reason={result['reason']}")
    print(f"Next action: {result['next_action']}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--repo", default="")
    parser.add_argument("--pr-number", required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    args.dry_run = not args.execute

    try:
        result = steward(args)
    except Exception as exc:  # noqa: BLE001 - command boundary must fail closed plainly.
        result = fail_result("steward_exception", "inspect merge-steward error before restarting", error=f"{type(exc).__name__}:{exc}")
    emit(result, as_json=args.json)
    return 0 if result["merge_ready"] == "yes" else 3


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
