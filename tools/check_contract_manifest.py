#!/usr/bin/env python3
"""Check tab-separated required-text contract manifests."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from upkeeper_lib.contract_manifest import check_manifests


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("manifests", nargs="+", type=Path)
    args = parser.parse_args(argv)

    errors = check_manifests(args.root.resolve(), args.manifests)
    for error in errors:
        print(f"contract_manifest: ERROR: {error}", file=sys.stderr)
    if errors:
        return 1
    print(f"contract_manifest: ok manifests={len(args.manifests)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
