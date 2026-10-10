#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-lattice-import-batch.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP_ROOT"' EXIT

python3 - "$PROJECT_ROOT" "$TEST_TMP_ROOT" <<'PY'
import argparse
import contextlib
import io
import json
import sqlite3
import subprocess
import sys
from pathlib import Path

project_root = Path(sys.argv[1])
tmp_root = Path(sys.argv[2])
sys.path.insert(0, str(project_root / "tools"))
import upkeeper_lattice_core as core

repo = tmp_root / "repo"
repo.mkdir()
subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
subprocess.run(["git", "config", "user.name", "Lattice Import Batch Test"], cwd=repo, check=True)
subprocess.run(["git", "config", "user.email", "lattice-import-batch@example.invalid"], cwd=repo, check=True)
(repo / "README.md").write_text("fixture\n", encoding="utf-8")
(repo / "tests").mkdir()
(repo / "tests/example.txt").write_text("fixture\n", encoding="utf-8")
subprocess.run(["git", "add", "README.md", "tests/example.txt"], cwd=repo, check=True)
subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=repo, check=True)

notes = tmp_root / "change_notes_batch.md"
with notes.open("w", encoding="utf-8") as handle:
    handle.write("# 2026 Change Notes\n\n2026-10-09: vbatch changes:\n")
    for number in range(1, 502):
        refs = "`README.md`, duplicate `README.md`, and `tests/example.txt`" if number == 1 else "`README.md` and `tests/example.txt`"
        handle.write(f"\t{number}. Batched {refs} reference.\n")

db = repo / "runtime/lattice.sqlite3"
args = argparse.Namespace(
    root=str(repo), db=str(db), journal_mode="WAL", allow_unsafe_db=False,
    paths=[str(notes)], raw=False, raw_storage_mode="minimal",
)
with contextlib.redirect_stdout(io.StringIO()):
    assert core.command_init(args) == core.EXIT_SUCCESS

calls: list[int] = []
original_connect = core.connect_checked

class CountingConnection:
    def __init__(self, connection):
        self.connection = connection

    def __getattr__(self, name):
        return getattr(self.connection, name)

    def __enter__(self):
        self.connection.__enter__()
        return self

    def __exit__(self, *exc):
        return self.connection.__exit__(*exc)

    def executemany(self, statement, rows):
        materialized = list(rows)
        if "insert or ignore into change_log_file_refs" in statement.lower():
            calls.append(len(materialized))
        return self.connection.executemany(statement, materialized)

def counted_connect(*args, **kwargs):
    return CountingConnection(original_connect(*args, **kwargs))

core.connect_checked = counted_connect
with contextlib.redirect_stdout(io.StringIO()) as output:
    assert core.command_import_change_notes(args) == core.EXIT_SUCCESS
first = json.loads(output.getvalue())
assert first["rows_seen"] == 501, first
assert first["rows_written"] == 1503, first
assert first["duplicates"] >= 1, first
assert calls == [500, 500, 2], calls

with contextlib.redirect_stdout(io.StringIO()) as output:
    assert core.command_import_change_notes(args) == core.EXIT_SUCCESS
second = json.loads(output.getvalue())
assert second["rows_written"] == 0, second
assert second["duplicates"] >= 1003, second

conn = sqlite3.connect(db)
try:
    assert conn.execute("select count(*) from change_log_entries where version='vbatch'").fetchone()[0] == 501
    assert conn.execute("""
        select count(*) from change_log_file_refs
        join change_log_entries using(change_log_entry_id)
        where version='vbatch'
    """).fetchone()[0] == 1002
finally:
    conn.close()
PY

printf 'lattice_import_batch_test: ok\n'
