#!/usr/bin/env python3
"""Test-only server that exercises the Lattice core without repeated imports."""

from __future__ import annotations

import base64
import contextlib
import io
import os
import sys
import time
import traceback
from pathlib import Path
from typing import BinaryIO


TOOLS_DIR = Path(__file__).resolve().parents[2] / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import upkeeper_lattice_core as lattice  # noqa: E402


def read_arg(reader: BinaryIO) -> str:
    value = bytearray()
    while True:
        byte = reader.read(1)
        if byte == b"":
            raise EOFError("unexpected EOF while reading request argument")
        if byte == b"\0":
            return value.decode("utf-8", errors="surrogateescape")
        value.extend(byte)


def emit_response(writer: BinaryIO, rc: int, stdout: str, stderr: str) -> None:
    stdout_b64 = base64.b64encode(stdout.encode("utf-8", errors="surrogateescape")).decode("ascii")
    stderr_b64 = base64.b64encode(stderr.encode("utf-8", errors="surrogateescape")).decode("ascii")
    writer.write(f"RC {int(rc)}\n".encode("ascii"))
    writer.write(f"STDOUT_B64 {stdout_b64}\n".encode("ascii"))
    writer.write(f"STDERR_B64 {stderr_b64}\n".encode("ascii"))
    writer.write(b"END\n")
    writer.flush()


def serve() -> int:
    reader = sys.stdin.buffer
    writer = sys.stdout.buffer
    while True:
        header = reader.readline()
        if header == b"":
            return 0
        header_text = header.decode("ascii", errors="replace").strip()
        if header_text == "SHUTDOWN":
            emit_response(writer, 0, "", "")
            return 0
        if not header_text.startswith("CMD "):
            emit_response(writer, 2, "", f"invalid harness header: {header_text}\n")
            continue
        try:
            argc = int(header_text.split(" ", 1)[1])
            if argc < 1:
                raise ValueError
            argv = [read_arg(reader) for _ in range(argc)]
        except (EOFError, ValueError) as exc:
            emit_response(writer, 2, "", f"invalid harness request: {exc}\n")
            continue

        stdout = io.StringIO()
        stderr = io.StringIO()
        if (
            os.environ.get("LATTICE_INPROCESS_HARNESS_TEST_HANG") == "1"
            and argv == ["test-hang"]
        ):
            time.sleep(60)
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            try:
                rc = lattice.main(argv)
            except SystemExit as exc:
                rc = int(exc.code or 0)
            except Exception:  # Surface an unexpected test-server failure.
                traceback.print_exc(file=stderr)
                rc = 70
        emit_response(writer, int(rc), stdout.getvalue(), stderr.getvalue())


if __name__ == "__main__":
    raise SystemExit(serve())
