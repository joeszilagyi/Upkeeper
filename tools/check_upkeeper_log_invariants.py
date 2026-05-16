#!/usr/bin/env python3
"""Check basic Upkeeper wrapper evidence invariants in local log files."""

from __future__ import annotations

import argparse
import re
import shlex
import sys
from collections import defaultdict
from pathlib import Path


TRACEBACK_PATTERNS = [
    "Traceback (most recent call last):",
    "command not found",
    "syntax error near unexpected token",
    "NameError:",
    "KeyError:",
    "IndexError:",
    "TypeError:",
]


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        fail(f"could not read {path}: {exc}")


def event_and_fields(line: str) -> tuple[str | None, dict[str, str]]:
    try:
        tokens = shlex.split(line)
    except ValueError as exc:
        fail(f"log line is not shell-parseable: {exc}: {line}")

    event = None
    fields: dict[str, str] = {}
    for token in tokens:
        if token in {"cycle.start", "cycle.exit", "run.finish"}:
            event = token
        elif "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value
    return event, fields


def check_no_tracebacks(path: Path, text: str) -> None:
    for pattern in TRACEBACK_PATTERNS:
        if pattern in text:
            fail(f"{path} contains raw traceback/shell noise pattern: {pattern}")


def check_log(path: Path) -> None:
    text = read_text(path)
    check_no_tracebacks(path, text)

    events: dict[str, dict[str, list[dict[str, str]]]] = defaultdict(
        lambda: {"cycle.start": [], "cycle.exit": [], "run.finish": []}
    )
    saw_event = False
    for line in text.splitlines():
        if not re.search(r"\b(cycle\.start|cycle\.exit|run\.finish)\b", line):
            continue
        event, fields = event_and_fields(line)
        if event is None:
            continue
        saw_event = True
        cycle = fields.get("cycle") or "__missing_cycle__"
        events[cycle][event].append(fields)

    if not saw_event:
        fail(f"{path} contains no cycle.start/cycle.exit/run.finish events")

    for cycle, grouped in sorted(events.items()):
        starts = grouped["cycle.start"]
        exits = grouped["cycle.exit"]
        finishes = grouped["run.finish"]

        if starts and len(exits) != 1:
            fail(f"{path} cycle {cycle} has {len(starts)} cycle.start events and {len(exits)} cycle.exit events")

        for exit_fields in exits:
            for key in ("exit_code", "reason"):
                if not exit_fields.get(key):
                    fail(f"{path} cycle {cycle} cycle.exit missing {key}")

            if not finishes:
                if exit_fields.get("codex_exec_started") != "0":
                    fail(
                        f"{path} cycle {cycle} exited before run.finish without codex_exec_started=0"
                    )

        for finish_fields in finishes:
            for key in ("codex_exit", "transcript", "transcript_bytes", "transcript_lines"):
                if not finish_fields.get(key):
                    fail(f"{path} cycle {cycle} run.finish missing {key}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check deterministic Upkeeper wrapper log evidence invariants."
    )
    parser.add_argument("log_file", type=Path)
    parser.add_argument(
        "--scan",
        action="append",
        default=[],
        type=Path,
        help="additional stdout/stderr/evidence file to scan for raw tracebacks",
    )
    args = parser.parse_args()

    check_log(args.log_file)
    for path in args.scan:
        check_no_tracebacks(path, read_text(path))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
