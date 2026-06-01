#!/usr/bin/env python3
"""Report high-friction Upkeeper architecture patterns.

The first fatal contract is duplicate Bash function ownership across the root
entrypoint and sourced modules. Other checks are intentionally report-only so
the repo can ratchet them down after the existing debt is mapped to issues.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


BASH_FUNCTION_RE = re.compile(
    r"^(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(\))?\s*\{"
)
DECLARE_F_SED_EVAL_RE = re.compile(r"eval\s+\"\$\(declare\s+-f\s+")
PY_HEREDOC_RE = re.compile(r"<<\s*'?PY'?\s*$")
LOOP_START_RE = re.compile(r"^\s*(?:for|while)\b")
LOOP_END_RE = re.compile(r"^\s*done\b")
SUBPROCESS_RE = re.compile(r"\bsubprocess\.(?:run|check_output|Popen)\b")
GIT_OUTPUT_RE = re.compile(r"\bgit_output\(")
SQL_EXECUTE_RE = re.compile(r"\bconn\.execute\(")


@dataclass(frozen=True)
class Finding:
    code: str
    path: Path
    line: int
    message: str
    severity: str = "report"

    def format(self) -> str:
        return f"{self.severity.upper()} {self.code} {self.path}:{self.line} {self.message}"


@dataclass(frozen=True)
class BashFunction:
    name: str
    path: Path
    start_line: int
    end_line: int

    @property
    def length(self) -> int:
        return self.end_line - self.start_line + 1


def read_allowlist(path: Path | None) -> dict[str, str]:
    if path is None or not path.exists():
        return {}
    allow: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        allow[parts[0]] = "\t".join(parts[1:])
    return allow


def discover_bash_functions(path: Path) -> list[BashFunction]:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    functions: list[BashFunction] = []
    stack: list[tuple[str, int, int]] = []

    for index, line in enumerate(lines, start=1):
        if not stack:
            match = BASH_FUNCTION_RE.match(line)
            if match:
                name = match.group(1)
                depth = line.count("{") - line.count("}")
                stack.append((name, index, max(depth, 1)))
            continue

        name, start, depth = stack[-1]
        depth += line.count("{") - line.count("}")
        stack[-1] = (name, start, depth)
        if depth <= 0:
            functions.append(BashFunction(name, path, start, index))
            stack.pop()

    for name, start, _depth in stack:
        functions.append(BashFunction(name, path, start, len(lines)))
    return functions


def report_duplicate_functions(
    functions: list[BashFunction],
    allowlist: dict[str, str],
) -> list[Finding]:
    by_name: dict[str, list[BashFunction]] = {}
    findings: list[Finding] = []
    for func in functions:
        by_name.setdefault(func.name, []).append(func)

    for name, entries in sorted(by_name.items()):
        if len(entries) < 2:
            continue
        locations = ", ".join(f"{entry.path}:{entry.start_line}" for entry in entries)
        severity = "report" if name in allowlist else "error"
        note = f"allowlist={allowlist[name]}" if name in allowlist else "allowlist=missing"
        findings.append(
            Finding(
                "function-shadow",
                entries[0].path,
                entries[0].start_line,
                f"{name} defined {len(entries)} times ({locations}) {note}",
                severity,
            )
        )
    return findings


def report_function_size(functions: list[BashFunction], threshold: int) -> list[Finding]:
    findings: list[Finding] = []
    for func in functions:
        if func.length > threshold:
            findings.append(
                Finding(
                    "long-bash-function",
                    func.path,
                    func.start_line,
                    f"{func.name} length={func.length} threshold={threshold}",
                )
            )
    return findings


def scan_shell_file(path: Path, inline_python_threshold: int) -> list[Finding]:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    findings: list[Finding] = []
    heredoc_start = 0
    in_py = False
    loop_depth = 0

    for index, line in enumerate(lines, start=1):
        if DECLARE_F_SED_EVAL_RE.search(line):
            findings.append(
                Finding("declare-f-sed-eval", path, index, "function text rewriting through eval")
            )
        if PY_HEREDOC_RE.search(line):
            in_py = True
            heredoc_start = index
            continue
        if in_py and line == "PY":
            length = index - heredoc_start + 1
            if length > inline_python_threshold:
                findings.append(
                    Finding(
                        "long-inline-python",
                        path,
                        heredoc_start,
                        f"inline Python heredoc length={length} threshold={inline_python_threshold}",
                    )
                )
            in_py = False
            continue
        if LOOP_START_RE.search(line):
            loop_depth += 1
        if loop_depth > 0 and ("python3 -" in line or " jq " in f" {line} "):
            findings.append(
                Finding("shell-loop-process", path, index, "process launch inside shell loop")
            )
        if LOOP_END_RE.search(line) and loop_depth > 0:
            loop_depth -= 1
    return findings


def scan_python_file(path: Path) -> list[Finding]:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    findings: list[Finding] = []
    loop_depth = 0
    loop_indent_stack: list[int] = []

    for index, line in enumerate(lines, start=1):
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        while loop_indent_stack and stripped and indent <= loop_indent_stack[-1]:
            loop_indent_stack.pop()
        loop_depth = len(loop_indent_stack)
        if stripped.startswith(("for ", "while ")) and stripped.endswith(":"):
            loop_indent_stack.append(indent)
            loop_depth = len(loop_indent_stack)
        if loop_depth > 0:
            if SUBPROCESS_RE.search(line) or GIT_OUTPUT_RE.search(line):
                findings.append(
                    Finding("python-loop-subprocess", path, index, "subprocess/Git call inside loop")
                )
            if SQL_EXECUTE_RE.search(line):
                findings.append(
                    Finding("python-loop-sql", path, index, "SQLite execute inside loop")
                )
    return findings


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allowlist", type=Path, default=Path("config/architecture_lint_allowlist.tsv"))
    parser.add_argument("--bash-function-threshold", type=int, default=300)
    parser.add_argument("--inline-python-threshold", type=int, default=40)
    parser.add_argument("--report", action="store_true", help="accepted for explicit report mode")
    parser.add_argument("paths", nargs="*", default=["Upkeeper", "lib/upkeeper", "tools"])
    args = parser.parse_args(argv)

    root = Path.cwd()
    paths: list[Path] = []
    for raw in args.paths:
        path = Path(raw)
        if path.is_dir():
            paths.extend(sorted(p for p in path.rglob("*") if p.is_file()))
        elif path.exists():
            paths.append(path)

    bash_paths = [p for p in paths if p.name in {"Upkeeper", "FlameOn", "ChimneySweep"} or p.suffix in {".bash", ".sh"}]
    python_paths = [p for p in paths if p.suffix == ".py"]

    allowlist = read_allowlist(args.allowlist)
    bash_functions: list[BashFunction] = []
    findings: list[Finding] = []
    for path in bash_paths:
        bash_functions.extend(discover_bash_functions(path))
        findings.extend(scan_shell_file(path, args.inline_python_threshold))

    findings.extend(report_duplicate_functions(bash_functions, allowlist))
    findings.extend(report_function_size(bash_functions, args.bash_function_threshold))

    for path in python_paths:
        findings.extend(scan_python_file(path))

    errors = [finding for finding in findings if finding.severity == "error"]
    for finding in sorted(findings, key=lambda item: (item.severity != "error", item.code, str(item.path), item.line)):
        print(finding.format())

    print(
        f"SUMMARY architecture_findings={len(findings)} errors={len(errors)} "
        f"bash_functions={len(bash_functions)} scanned_paths={len(paths)}"
    )
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
