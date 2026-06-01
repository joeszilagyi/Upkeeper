"""Required-text contract manifest parser and checker."""

from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ContractRow:
    row_id: str
    path: str
    contains: str
    error: str
    source: Path
    line: int


def iter_rows(path: Path) -> list[ContractRow]:
    rows: list[ContractRow] = []
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle, delimiter="\t")
        header_seen = False
        for line_no, fields in enumerate(reader, start=1):
            if not fields or not any(field.strip() for field in fields):
                continue
            if fields[0].lstrip().startswith("#"):
                continue
            if not header_seen and fields[:4] == ["id", "file", "contains", "error"]:
                header_seen = True
                continue
            header_seen = True
            if len(fields) != 4:
                raise ValueError(f"{path}:{line_no}: expected 4 TSV fields, got {len(fields)}")
            row_id, row_path, contains, error = fields
            if not row_id or not row_path or not contains or not error:
                raise ValueError(f"{path}:{line_no}: id, file, contains, and error are required")
            rows.append(ContractRow(row_id, row_path, contains, error, path, line_no))
    return rows


def check_manifests(root: Path, manifests: list[Path]) -> list[str]:
    errors: list[str] = []
    seen: dict[str, ContractRow] = {}
    rows: list[ContractRow] = []
    for manifest in manifests:
        rows.extend(iter_rows(manifest))

    for row in rows:
        prior = seen.get(row.row_id)
        if prior is not None:
            errors.append(
                f"{row.source}:{row.line}: duplicate id {row.row_id!r}; first seen at {prior.source}:{prior.line}"
            )
            continue
        seen[row.row_id] = row

        target = root / row.path
        if not target.is_file():
            errors.append(f"{row.source}:{row.line}: {row.error} (missing file: {row.path})")
            continue
        text = target.read_text(encoding="utf-8", errors="replace")
        if row.contains not in text:
            errors.append(f"{row.source}:{row.line}: {row.error} (missing text in {row.path})")
    return errors
