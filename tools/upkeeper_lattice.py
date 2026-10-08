#!/usr/bin/env python3
"""Stable CLI shim for the import-cacheable Upkeeper Lattice core."""

from __future__ import annotations

import sys
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

# Preserve the historical import surface for repository tooling that loads the
# CLI path directly while keeping the large implementation cacheable.
from upkeeper_lattice_core import *  # noqa: F403


if __name__ == "__main__":
    try:
        raise SystemExit(main())  # noqa: F405
    except BrokenPipeError:
        redirect_stdout_to_devnull()  # noqa: F405
        raise SystemExit(EXIT_SUCCESS)  # noqa: F405
