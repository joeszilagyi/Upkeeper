#!/usr/bin/env python3
"""Create the stable, non-custody retry state for an automation obligation.

The retry selector and the attempt writer both use this program.  Keeping the
fingerprint here prevents a change to either caller from accidentally making a
cooldown self-invalidating (for example because its attempt counter changed).
The input is one obligation JSON object on standard input; output is safe,
structured state only, never an evidence excerpt.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess
import sys


def canonical_hash(value):
    encoded = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8", "surrogatepass")
    return hashlib.sha256(encoded).hexdigest()


def text(value, limit=4096):
    return str(value or "").strip()[:limit]


def git_value(root, *args):
    try:
        result = subprocess.run(
            ["git", "-C", str(root), *args],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    if result.returncode:
        return "unknown"
    return text(result.stdout, 256) or "unknown"


def target_digest(root, target):
    raw = text(target)
    if not raw:
        return ""
    target_path = PurePosixPath(raw.replace("\\", "/"))
    if target_path.is_absolute() or ".." in target_path.parts:
        return "invalid"
    candidate = root.joinpath(*target_path.parts)
    try:
        candidate.resolve(strict=False).relative_to(root)
        metadata = candidate.lstat()
    except (OSError, ValueError):
        return "missing"
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        return "invalid"
    digest = hashlib.sha256()
    try:
        with candidate.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError:
        return "unreadable"
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--root", required=True)
    args = parser.parse_args()
    try:
        item = json.load(sys.stdin)
    except json.JSONDecodeError:
        print(json.dumps({"status": "invalid_json"}, separators=(",", ":")))
        return 1
    if not isinstance(item, dict):
        print(json.dumps({"status": "invalid_json"}, separators=(",", ":")))
        return 1
    try:
        root = Path(args.root).resolve()
    except OSError:
        root = Path(args.root).absolute()

    repair_target = text(item.get("repair_target_file")) or text(item.get("target_file"))
    state = {
        "schema": 1,
        "target_file": text(item.get("target_file")),
        "repair_target_file": repair_target,
        "repair_target_sha256": target_digest(root, repair_target),
        "repository_branch": git_value(root, "symbolic-ref", "--quiet", "--short", "HEAD"),
        "repository_head": git_value(root, "rev-parse", "--verify", "HEAD"),
        "failure_fingerprint": text(item.get("fingerprint")),
        "reason": text(item.get("reason")),
        "issue_number": text(item.get("issue_number"), 128),
        "issue_title_sha256": canonical_hash(text(item.get("issue_title"))),
        "evidence_sha256": canonical_hash(item.get("evidence", {})),
        "required_resolution_sha256": canonical_hash(item.get("required_resolution", [])),
        "retry_context": text(os.environ.get("UPKEEPER_OBLIGATION_RETRY_CONTEXT"), 256),
    }
    print(
        json.dumps(
            {"status": "ok", "fingerprint": canonical_hash(state), "state": state},
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
