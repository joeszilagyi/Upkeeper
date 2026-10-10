#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT_DIR" <<'PY'
import base64
import io
import sys
from types import SimpleNamespace

root = sys.argv[1]
sys.path.insert(0, f"{root}/tools")
from upkeeper_lib import lattice_service


ARGS = SimpleNamespace(
    root="/fixture/repo",
    db="/fixture/repo/runtime/lattice.sqlite3",
    journal_mode="wal",
    allow_unsafe_db=True,
    raw_repo_identity=True,
    upkeeper_ignore_file="fixture.ignore",
)


def responses(raw: bytes):
    lines = raw.decode("ascii").splitlines()
    assert len(lines) % 3 == 0, lines
    parsed = []
    for index in range(0, len(lines), 3):
        rc, output, end = lines[index:index + 3]
        assert rc.startswith("RC "), rc
        assert output.startswith("OUTPUT_B64 "), output
        assert end == "END", end
        parsed.append((int(rc.split(" ", 1)[1]), base64.b64decode(output.split(" ", 1)[1]).decode("utf-8")))
    return parsed


calls = []


def execute(argv):
    calls.append(argv)
    print("command output")
    print("command error", file=sys.stderr)
    return 7


writer = io.BytesIO()
rc = lattice_service.run_service(
    ARGS,
    execute=execute,
    exit_success=0,
    exit_usage=2,
    reader=io.BytesIO(b"CMD 2\nquery\0metrics\0SHUTDOWN\n"),
    writer=writer,
)
assert rc == 0
assert calls == [[
    "--root", "/fixture/repo",
    "--db", "/fixture/repo/runtime/lattice.sqlite3",
    "--journal-mode", "wal",
    "--allow-unsafe-db",
    "--raw-repo-identity",
    "--upkeeper-ignore-file", "fixture.ignore",
    "query", "metrics",
]], calls
assert responses(writer.getvalue()) == [(7, "command output\ncommand error\n"), (0, "")]

calls.clear()
writer = io.BytesIO()
rc = lattice_service.run_service(
    ARGS,
    execute=execute,
    exit_success=0,
    exit_usage=2,
    reader=io.BytesIO(b"CMD 1\nservice\0SHUTDOWN\n"),
    writer=writer,
)
assert rc == 0
assert calls == []
assert responses(writer.getvalue()) == [(2, "upkeeper_lattice: service command cannot recurse"), (0, "")]

writer = io.BytesIO()
rc = lattice_service.run_service(
    ARGS,
    execute=execute,
    exit_success=0,
    exit_usage=2,
    reader=io.BytesIO(b"CMD 1\nunterminated"),
    writer=writer,
)
assert rc == 2
assert responses(writer.getvalue()) == [(2, "upkeeper_lattice: unexpected EOF while reading service argument")]

writer = io.BytesIO()
rc = lattice_service.run_service(
    ARGS,
    execute=execute,
    exit_success=0,
    exit_usage=2,
    reader=io.BytesIO(b"bad header\nSHUTDOWN\n"),
    writer=writer,
)
assert rc == 0
assert responses(writer.getvalue()) == [(2, "upkeeper_lattice: invalid service header: bad header"), (0, "")]
PY

printf 'lattice_service_protocol_test: ok\n'
