#!/usr/bin/env python3
"""Local lease registry for future isolated backlog workers.

This is intentionally a no-backend primitive. It does not launch Codex, create
worktrees, create branches, or touch GitHub. It gives a supervisor or future
launcher one deterministic place to claim issue/target ownership before any
backend work starts.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time
from typing import Any, Iterator


SCHEMA = 1
DEFAULT_TTL_SECONDS = 4 * 60 * 60


def now_epoch(args: argparse.Namespace) -> int:
    if getattr(args, "now_epoch", None) is not None:
        return int(args.now_epoch)
    return int(time.time())


def state_root_default() -> pathlib.Path:
    base = os.environ.get("XDG_STATE_HOME")
    if base:
        return pathlib.Path(base) / "upkeeper" / "backlog"
    return pathlib.Path.home() / ".local" / "state" / "upkeeper" / "backlog"


def private_dir(path: pathlib.Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    try:
        path.chmod(0o700)
    except OSError:
        pass


def lease_dir(state_root: pathlib.Path) -> pathlib.Path:
    return state_root.expanduser() / "parallel-workers"


def lease_file(state_root: pathlib.Path) -> pathlib.Path:
    return lease_dir(state_root) / "leases.json"


def lock_file(state_root: pathlib.Path) -> pathlib.Path:
    return lease_dir(state_root) / "leases.lock"


def read_json(path: pathlib.Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {"schema": SCHEMA, "leases": []}
    except (OSError, json.JSONDecodeError):
        return {"schema": SCHEMA, "leases": []}
    if not isinstance(data, dict):
        return {"schema": SCHEMA, "leases": []}
    leases = data.get("leases")
    if not isinstance(leases, list):
        data["leases"] = []
    data["schema"] = SCHEMA
    return data


def write_json(path: pathlib.Path, data: dict[str, Any]) -> None:
    private_dir(path.parent)
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
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


@contextlib.contextmanager
def locked_registry(state_root: pathlib.Path, *, write: bool = True) -> Iterator[dict[str, Any]]:
    root = lease_dir(state_root)
    private_dir(root)
    lock_path = lock_file(state_root)
    with open(lock_path, "a+", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        data = read_json(lease_file(state_root))
        yield data
        if write:
            write_json(lease_file(state_root), data)
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)


def stable(value: object) -> str:
    return str(value or "").strip()


def sanitize_token(value: object, fallback: str = "unknown") -> str:
    text = stable(value) or fallback
    cleaned = "".join(ch if ch.isalnum() or ch in "._:@%+=,-/" else "_" for ch in text)
    return cleaned[:180] or fallback


def repo_branch(root: pathlib.Path) -> str:
    try:
        completed = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=str(root),
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return "unknown"
    branch = completed.stdout.strip()
    return branch if completed.returncode == 0 and branch else "unknown"


def normalize_root(path: pathlib.Path) -> pathlib.Path:
    return path.expanduser().resolve(strict=False)


def validate_worker_worktree(root: pathlib.Path, worktree: pathlib.Path) -> tuple[bool, str]:
    root = normalize_root(root)
    worktree = normalize_root(worktree)
    if worktree == root:
        return False, "worker_worktree_is_main_checkout"
    if root in worktree.parents:
        return False, "worker_worktree_nested_inside_main_checkout"
    return True, ""


def lease_id(root: pathlib.Path, worker_id: str, issue_number: str) -> str:
    payload = f"{normalize_root(root)}\0{worker_id}\0{issue_number}"
    digest = hashlib.sha256(payload.encode("utf-8", "surrogateescape")).hexdigest()[:24]
    return f"parallel-lease-{digest}"


def active_leases(data: dict[str, Any], now: int) -> list[dict[str, Any]]:
    return [
        item
        for item in data.get("leases", [])
        if isinstance(item, dict)
        and item.get("status") == "active"
        and int(item.get("expires_epoch") or 0) > now
    ]


def expire_stale(data: dict[str, Any], now: int) -> int:
    count = 0
    for item in data.get("leases", []):
        if not isinstance(item, dict):
            continue
        if item.get("status") != "active":
            continue
        if int(item.get("expires_epoch") or 0) > now:
            continue
        item["status"] = "expired"
        item["expired_epoch"] = now
        item["updated_epoch"] = now
        item["next_action"] = "inspect stale worker branch or retry lease"
        count += 1
    return count


def print_kv(fields: dict[str, object]) -> None:
    for key, value in fields.items():
        print(f"{key}={sanitize_token(value)}")


def command_claim(args: argparse.Namespace) -> int:
    root = normalize_root(pathlib.Path(args.root))
    worktree = normalize_root(pathlib.Path(args.worktree))
    ok, reason = validate_worker_worktree(root, worktree)
    if not ok:
        print_kv(
            {
                "lease_status": "blocked",
                "reason": reason,
                "worker_id": args.worker_id,
                "issue_number": args.issue_number,
            }
        )
        return 3

    now = now_epoch(args)
    ttl = max(1, int(args.ttl_seconds))
    state_root = pathlib.Path(args.state_root)
    with locked_registry(state_root) as data:
        expired_count = expire_stale(data, now)
        issue_number = stable(args.issue_number)
        target_file = stable(args.target_file)
        worker_id = stable(args.worker_id)
        current = None
        for item in active_leases(data, now):
            if stable(item.get("worker_id")) == worker_id and stable(item.get("issue_number")) == issue_number:
                current = item
                continue
            if stable(item.get("issue_number")) == issue_number:
                print_kv(
                    {
                        "lease_status": "conflict",
                        "conflict_reason": "issue",
                        "issue_number": issue_number,
                        "owner_worker": item.get("worker_id"),
                        "owner_branch": item.get("branch"),
                        "owner_worktree": item.get("worktree"),
                        "expired_count": expired_count,
                    }
                )
                return 2
            if target_file and stable(item.get("target_file")) == target_file:
                print_kv(
                    {
                        "lease_status": "conflict",
                        "conflict_reason": "target_file",
                        "issue_number": issue_number,
                        "target_file": target_file,
                        "owner_issue": item.get("issue_number"),
                        "owner_worker": item.get("worker_id"),
                        "owner_branch": item.get("branch"),
                        "expired_count": expired_count,
                    }
                )
                return 2

        branch = stable(args.branch) or repo_branch(worktree)
        record = current or {}
        status = "renewed" if current else "claimed"
        if not current:
            record.update(
                {
                    "schema": SCHEMA,
                    "id": lease_id(root, worker_id, issue_number),
                    "status": "active",
                    "claimed_epoch": now,
                }
            )
            data.setdefault("leases", []).append(record)
        record.update(
            {
                "root": str(root),
                "worker_id": worker_id,
                "issue_number": issue_number,
                "issue_title": stable(args.issue_title),
                "target_file": target_file,
                "branch": branch,
                "worktree": str(worktree),
                "model": stable(args.model),
                "effort": stable(args.effort),
                "updated_epoch": now,
                "expires_epoch": now + ttl,
                "next_action": "run isolated backlog worker",
            }
        )
        print_kv(
            {
                "lease_status": status,
                "lease_id": record.get("id"),
                "worker_id": worker_id,
                "issue_number": issue_number,
                "target_file": target_file or "none",
                "branch": branch,
                "worktree": worktree,
                "expires_epoch": record["expires_epoch"],
                "expired_count": expired_count,
            }
        )
    return 0


def command_release(args: argparse.Namespace) -> int:
    now = now_epoch(args)
    state_root = pathlib.Path(args.state_root)
    with locked_registry(state_root) as data:
        expire_stale(data, now)
        for item in data.get("leases", []):
            if not isinstance(item, dict) or item.get("status") != "active":
                continue
            if stable(item.get("worker_id")) != stable(args.worker_id):
                continue
            if stable(args.issue_number) and stable(item.get("issue_number")) != stable(args.issue_number):
                continue
            item["status"] = "released"
            item["released_epoch"] = now
            item["updated_epoch"] = now
            item["release_reason"] = stable(args.reason) or "operator_release"
            item["next_action"] = "none"
            print_kv(
                {
                    "release_status": "released",
                    "lease_id": item.get("id"),
                    "worker_id": item.get("worker_id"),
                    "issue_number": item.get("issue_number"),
                    "reason": item.get("release_reason"),
                }
            )
            return 0
    print_kv({"release_status": "not_found", "worker_id": args.worker_id, "issue_number": args.issue_number or "any"})
    return 1


def command_expire(args: argparse.Namespace) -> int:
    now = now_epoch(args)
    with locked_registry(pathlib.Path(args.state_root)) as data:
        count = expire_stale(data, now)
    print_kv({"expire_status": "ok", "expired_count": count})
    return 0


def command_status(args: argparse.Namespace) -> int:
    now = now_epoch(args)
    with locked_registry(pathlib.Path(args.state_root)) as data:
        expire_stale(data, now)
        leases = [item for item in data.get("leases", []) if isinstance(item, dict)]
        if args.json:
            print(json.dumps({"schema": SCHEMA, "leases": leases}, indent=2, sort_keys=True))
            return 0
        print("worker_id\tstatus\tissue\tmodel\teffort\tbranch\tworktree\ttarget\texpires_in\tnext_action")
        for item in sorted(leases, key=lambda value: (stable(value.get("status")), stable(value.get("worker_id")), stable(value.get("issue_number")))):
            expires = int(item.get("expires_epoch") or 0)
            expires_in = max(0, expires - now) if item.get("status") == "active" else 0
            print(
                "\t".join(
                    [
                        stable(item.get("worker_id")) or "unknown",
                        stable(item.get("status")) or "unknown",
                        stable(item.get("issue_number")) or "unknown",
                        stable(item.get("model")) or "unknown",
                        stable(item.get("effort")) or "unknown",
                        stable(item.get("branch")) or "unknown",
                        stable(item.get("worktree")) or "unknown",
                        stable(item.get("target_file")) or "none",
                        str(expires_in),
                        stable(item.get("next_action")) or "unknown",
                    ]
                )
            )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=os.getcwd(), help="main checkout root; worker worktrees must be isolated from it")
    parser.add_argument("--state-root", default=str(state_root_default()), help="backlog state root")
    parser.add_argument("--now-epoch", type=int, help=argparse.SUPPRESS)
    sub = parser.add_subparsers(dest="command", required=True)

    claim = sub.add_parser("claim", help="claim an issue/target lease for one worker")
    claim.add_argument("--worker-id", required=True)
    claim.add_argument("--issue-number", required=True)
    claim.add_argument("--issue-title", default="")
    claim.add_argument("--target-file", default="")
    claim.add_argument("--branch", default="")
    claim.add_argument("--worktree", required=True)
    claim.add_argument("--model", default="")
    claim.add_argument("--effort", default="")
    claim.add_argument("--ttl-seconds", default=str(DEFAULT_TTL_SECONDS))
    claim.set_defaults(func=command_claim)

    release = sub.add_parser("release", help="release an active worker lease")
    release.add_argument("--worker-id", required=True)
    release.add_argument("--issue-number", default="")
    release.add_argument("--reason", default="operator_release")
    release.set_defaults(func=command_release)

    expire = sub.add_parser("expire", help="mark stale active leases expired")
    expire.set_defaults(func=command_expire)

    status = sub.add_parser("status", help="print worker lease status")
    status.add_argument("--json", action="store_true")
    status.set_defaults(func=command_status)
    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
