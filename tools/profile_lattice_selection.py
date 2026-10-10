#!/usr/bin/env python3
"""Profile the Lattice selection-candidates hot path on a deterministic repo."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def run_git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def make_fixture_repo(root: Path) -> Path:
    repo = root / "repo"
    repo.mkdir()
    run_git(repo, "init", "-q")
    run_git(repo, "config", "user.name", "Lattice Profile")
    run_git(repo, "config", "user.email", "lattice-profile@example.invalid")
    (repo / ".gitignore").write_text("runtime/\n", encoding="utf-8")
    (repo / "README.md").write_text("# Lattice Profile\n", encoding="utf-8")
    (repo / "script.sh").write_text("#!/usr/bin/env bash\nprintf 'profile\\n'\n", encoding="utf-8")
    tests_dir = repo / "tests"
    tests_dir.mkdir()
    (tests_dir / "example.txt").write_text("profile fixture\n", encoding="utf-8")
    (repo / "docs.md").write_text("docs fixture\n", encoding="utf-8")
    run_git(repo, "add", "-A")
    run_git(repo, "commit", "-q", "-m", "initial profile fixture")
    return repo


def load_lattice_module(root: Path) -> Any:
    path = root / "tools" / "upkeeper_lattice.py"
    spec = importlib.util.spec_from_file_location("upkeeper_lattice_profiled", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@contextlib.contextmanager
def count_lattice_subprocesses(lattice: Any):
    counts = {"run": 0, "check_output": 0}
    original_run = lattice.subprocess.run
    original_check_output = lattice.subprocess.check_output

    def counted_run(*args: Any, **kwargs: Any) -> Any:
        counts["run"] += 1
        return original_run(*args, **kwargs)

    def counted_check_output(*args: Any, **kwargs: Any) -> Any:
        counts["check_output"] += 1
        return original_check_output(*args, **kwargs)

    lattice.subprocess.run = counted_run
    lattice.subprocess.check_output = counted_check_output
    try:
        yield counts
    finally:
        lattice.subprocess.run = original_run
        lattice.subprocess.check_output = original_check_output


@contextlib.contextmanager
def count_repo_git_info_calls(lattice: Any):
    core_module = sys.modules[lattice.pass_result_hmac_key.__module__]
    counts = {"repo_git_info": 0, "pass_result_hmac_key": 0}
    original_repo_git_info = core_module.repo_git_info
    original_pass_result_hmac_key = core_module.pass_result_hmac_key

    def counted_repo_git_info(*args: Any, **kwargs: Any) -> Any:
        counts["repo_git_info"] += 1
        return original_repo_git_info(*args, **kwargs)

    def counted_pass_result_hmac_key(*args: Any, **kwargs: Any) -> Any:
        counts["pass_result_hmac_key"] += 1
        return original_pass_result_hmac_key(*args, **kwargs)

    core_module.repo_git_info = counted_repo_git_info
    core_module.pass_result_hmac_key = counted_pass_result_hmac_key
    try:
        yield counts
    finally:
        core_module.repo_git_info = original_repo_git_info
        core_module.pass_result_hmac_key = original_pass_result_hmac_key


@contextlib.contextmanager
def count_max_cover_sql(lattice: Any):
    core_module = sys.modules[lattice.pass_result_hmac_key.__module__]
    counts = {"max_cover_sql": 0}
    original_connect_checked = core_module.connect_checked

    def traced_connect_checked(*args: Any, **kwargs: Any) -> Any:
        conn = original_connect_checked(*args, **kwargs)

        def trace(statement: str) -> None:
            normalized = " ".join(statement.lower().split())
            if (
                normalized.startswith("with candidate_paths")
                or normalized.startswith("select file_id from files")
                or normalized.startswith("select f.file_id from file_paths")
                or (normalized.startswith("select file_id, pass_code") and " from file_pass_runs " in normalized)
            ):
                counts["max_cover_sql"] += 1

        conn.set_trace_callback(trace)
        return conn

    core_module.connect_checked = traced_connect_checked
    try:
        yield counts
    finally:
        core_module.connect_checked = original_connect_checked


def run_lattice(lattice: Any, argv: list[str]) -> tuple[int, str]:
    stdout = io.StringIO()
    with contextlib.redirect_stdout(stdout):
        rc = int(lattice.main(argv))
    return rc, stdout.getvalue()


def profile_selection(args: argparse.Namespace) -> dict[str, Any]:
    root = repo_root()
    lattice = load_lattice_module(root)
    with tempfile.TemporaryDirectory(prefix="upkeeper-lattice-profile-") as tmp_raw:
        tmp = Path(tmp_raw)
        repo = make_fixture_repo(tmp)
        db = repo / "runtime" / "upkeeper-lattice" / "profile.sqlite3"
        init_rc, init_output = run_lattice(lattice, ["--root", str(repo), "--db", str(db), "init"])
        if init_rc != 0:
            return {
                "operation": "selection-candidates",
                "status": "init_failed",
                "rc": init_rc,
                "output": init_output[-500:],
            }

        start_rc, start_output = run_lattice(
            lattice,
            [
                "--root", str(repo), "--db", str(db), "record-cycle-start",
                "--cycle-id", "profile-cycle", "--run-hash", "profile-run",
                "--execution-origin", "profile", "--model", "profile", "--effort", "low",
                "--mode", "profile", "--config-file", "profile.conf", "--dirty-path-count", "0", "--dry-run", "1",
            ],
        )
        if start_rc != 0:
            return {"operation": "selection-candidates", "status": "record_start_failed", "rc": start_rc, "output": start_output[-500:]}

        query_argv = [
            "--root",
            str(repo),
            "--db",
            str(db),
            "query",
            "selection-candidates",
            "--mode",
            args.mode,
            "--format",
            "jsonl",
        ]
        with count_lattice_subprocesses(lattice) as counts, count_repo_git_info_calls(lattice) as identity_counts, count_max_cover_sql(lattice) as sql_counts:
            start = time.perf_counter()
            rc, output = run_lattice(lattice, query_argv)
            elapsed_ms = int(round((time.perf_counter() - start) * 1000))
        rows = [json.loads(line) for line in output.splitlines() if line.strip().startswith("{")]
        result = {
            "operation": "selection-candidates",
            "mode": args.mode,
            "status": "ok" if rc == 0 else "failed",
            "rc": rc,
            "candidate_count": len(rows),
            "eligible_count": sum(1 for row in rows if row.get("candidate_state") == "eligible"),
            "wall_ms": elapsed_ms,
            "subprocess_run_count": counts["run"],
            "subprocess_check_output_count": counts["check_output"],
            "repo_git_info_count": identity_counts["repo_git_info"],
            "pass_result_hmac_key_count": identity_counts["pass_result_hmac_key"],
            "max_cover_sql_count": sql_counts["max_cover_sql"],
            "budget": {
                "max_wall_ms": args.max_wall_ms,
                "max_subprocess_run": args.max_subprocess_run,
                "max_subprocess_check_output": args.max_subprocess_check_output,
                "max_repo_git_info": args.max_repo_git_info,
                "max_pass_result_hmac_key": args.max_pass_result_hmac_key,
                "max_max_cover_sql": args.max_max_cover_sql,
                "enforced": args.enforce,
            },
        }
        over_budget = []
        if result["wall_ms"] > args.max_wall_ms:
            over_budget.append("wall_ms")
        if result["subprocess_run_count"] > args.max_subprocess_run:
            over_budget.append("subprocess_run_count")
        if result["subprocess_check_output_count"] > args.max_subprocess_check_output:
            over_budget.append("subprocess_check_output_count")
        if result["repo_git_info_count"] > args.max_repo_git_info:
            over_budget.append("repo_git_info_count")
        if result["pass_result_hmac_key_count"] > args.max_pass_result_hmac_key:
            over_budget.append("pass_result_hmac_key_count")
        if result["max_cover_sql_count"] > args.max_max_cover_sql:
            over_budget.append("max_cover_sql_count")
        result["over_budget"] = over_budget
        return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", default="max-cover", choices=["oldest-mtime", "max-cover"])
    parser.add_argument("--max-wall-ms", type=int, default=5000)
    parser.add_argument("--max-subprocess-run", type=int, default=100)
    parser.add_argument("--max-subprocess-check-output", type=int, default=30)
    parser.add_argument("--max-repo-git-info", type=int, default=2)
    parser.add_argument("--max-pass-result-hmac-key", type=int, default=1)
    parser.add_argument("--max-max-cover-sql", type=int, default=2)
    parser.add_argument("--enforce", action="store_true", help="fail when measured values exceed the current report budget")
    args = parser.parse_args(argv)

    result = profile_selection(args)
    print(json.dumps(result, sort_keys=True))
    if result.get("status") != "ok":
        return 1
    if args.enforce and result.get("over_budget"):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
