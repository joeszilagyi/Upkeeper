"""Warm-process protocol for the Upkeeper Lattice command-line service.

This module deliberately owns only the wire protocol and process-local dispatch.
The Lattice core continues to own command parsing and command implementations.
Keeping the transport separate makes its framing and failure behavior testable
without importing or mutating a Lattice database.
"""

from __future__ import annotations

import base64
import contextlib
import io
import sys
from typing import Any, BinaryIO, Callable


def service_base_argv(args: Any) -> list[str]:
    """Return the root command arguments inherited by each service request."""

    base = ["--root", str(args.root)]
    if args.db is not None:
        base.extend(["--db", str(args.db)])
    base.extend(["--journal-mode", str(args.journal_mode)])
    if getattr(args, "allow_unsafe_db", False):
        base.append("--allow-unsafe-db")
    if getattr(args, "raw_repo_identity", False):
        base.append("--raw-repo-identity")
    if getattr(args, "upkeeper_ignore_file", None):
        base.extend(["--upkeeper-ignore-file", str(args.upkeeper_ignore_file)])
    return base


def service_read_arg(reader: BinaryIO) -> str:
    """Read one NUL-delimited UTF-8 argument from a service request."""

    buf = bytearray()
    while True:
        byte = reader.read(1)
        if byte == b"":
            raise EOFError("unexpected EOF while reading service argument")
        if byte == b"\0":
            return buf.decode("utf-8", errors="surrogateescape")
        buf.extend(byte)


def service_emit_response(writer: BinaryIO, rc: int, output: str) -> None:
    """Write one complete, line-framed service response."""

    encoded = base64.b64encode(output.encode("utf-8", errors="surrogateescape")).decode("ascii")
    writer.write(f"RC {int(rc)}\n".encode("ascii"))
    writer.write(f"OUTPUT_B64 {encoded}\n".encode("ascii"))
    writer.write(b"END\n")
    writer.flush()


def run_service(
    args: Any,
    *,
    execute: Callable[[list[str]], int],
    exit_success: int,
    exit_usage: int,
    reader: BinaryIO | None = None,
    writer: BinaryIO | None = None,
) -> int:
    """Serve NUL-delimited CLI requests through one warm Python process.

    Requests use ``CMD <argc>`` followed by NUL-delimited arguments. Responses
    retain the existing Bash-facing ``RC``/``OUTPUT_B64``/``END`` framing.
    ``execute`` is injected so the protocol does not import the Lattice core or
    create a circular dependency.
    """

    if reader is None:
        reader = sys.stdin.buffer
    if writer is None:
        writer = sys.stdout.buffer
    base = service_base_argv(args)

    while True:
        header = reader.readline()
        if header == b"":
            break
        header_text = header.decode("ascii", errors="replace").strip()
        if header_text == "SHUTDOWN":
            service_emit_response(writer, exit_success, "")
            break
        if not header_text.startswith("CMD "):
            service_emit_response(writer, exit_usage, f"upkeeper_lattice: invalid service header: {header_text}")
            continue
        try:
            argc = int(header_text.split(" ", 1)[1])
            if argc < 1:
                raise ValueError
        except ValueError:
            service_emit_response(writer, exit_usage, f"upkeeper_lattice: invalid service argc: {header_text}")
            continue
        try:
            command_args = [service_read_arg(reader) for _ in range(argc)]
        except EOFError as exc:
            service_emit_response(writer, exit_usage, f"upkeeper_lattice: {exc}")
            return exit_usage
        if command_args[0] == "service":
            service_emit_response(writer, exit_usage, "upkeeper_lattice: service command cannot recurse")
            continue

        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            try:
                rc = execute([*base, *command_args])
            except SystemExit as exc:
                rc = int(exc.code or exit_success)
        output = stdout.getvalue()
        error = stderr.getvalue()
        if error:
            output = f"{output}{error}"
        service_emit_response(writer, int(rc), output)

    return exit_success
