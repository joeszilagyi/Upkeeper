#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-lattice-import-cache.XXXXXX")"
trap 'rm -rf -- "$TMP_ROOT"' EXIT

TOOLS_ROOT="$TMP_ROOT/tools"
FIXTURE_REPO="$TMP_ROOT/repo"
CACHE_ROOT="$TMP_ROOT/pycache"
LATTICE_TOOL="$TOOLS_ROOT/upkeeper_lattice.py"
mkdir -p "$TOOLS_ROOT" "$FIXTURE_REPO" "$CACHE_ROOT"
cp "$ROOT_DIR/tools/upkeeper_lattice.py" "$TOOLS_ROOT/upkeeper_lattice.py"
cp "$ROOT_DIR/tools/upkeeper_lattice_core.py" "$TOOLS_ROOT/upkeeper_lattice_core.py"
cp -R "$ROOT_DIR/tools/upkeeper_lib" "$TOOLS_ROOT/upkeeper_lib"
mkdir -p "$TMP_ROOT/lib"
cp -R "$ROOT_DIR/lib/upkeeper" "$TMP_ROOT/lib/upkeeper"
chmod 755 "$LATTICE_TOOL"

(
  cd "$FIXTURE_REPO"
  git init -q
  git config user.name "Lattice Cache Test"
  git config user.email "lattice-cache@example.invalid"
  printf 'runtime/\n' >.gitignore
  printf '# cache fixture\n' >README.md
  git add -A
  git commit -q -m initial
)

shim_size="$(wc -c <"$LATTICE_TOOL" | tr -d ' ')"
core_size="$(wc -c <"$TOOLS_ROOT/upkeeper_lattice_core.py" | tr -d ' ')"
[[ "$shim_size" -lt 4096 ]] || {
  printf 'lattice_import_cache_test: CLI shim unexpectedly large: %s bytes\n' "$shim_size" >&2
  exit 1
}
[[ "$core_size" -gt 100000 ]] || {
  printf 'lattice_import_cache_test: implementation core unexpectedly small: %s bytes\n' "$core_size" >&2
  exit 1
}

PYTHONPYCACHEPREFIX="$CACHE_ROOT" \
  "$LATTICE_TOOL" --root "$FIXTURE_REPO" --db runtime/lattice.sqlite3 init >/dev/null

mapfile -t core_pyc_files < <(find "$CACHE_ROOT" -type f -name 'upkeeper_lattice_core*.pyc' -print)
[[ "${#core_pyc_files[@]}" -eq 1 ]] || {
  printf 'lattice_import_cache_test: expected one core bytecode cache, found %s\n' "${#core_pyc_files[@]}" >&2
  exit 1
}
core_pyc="${core_pyc_files[0]}"
touch -d '@946684800' "$core_pyc"
cache_mtime_before="$(stat -c '%Y' "$core_pyc")"

PYTHONPYCACHEPREFIX="$CACHE_ROOT" \
  "$LATTICE_TOOL" --root "$FIXTURE_REPO" --db runtime/lattice.sqlite3 doctor >/dev/null
cache_mtime_after="$(stat -c '%Y' "$core_pyc")"
[[ "$cache_mtime_after" == "$cache_mtime_before" ]] || {
  printf 'lattice_import_cache_test: valid core bytecode cache was rewritten\n' >&2
  exit 1
}

python3 - "$LATTICE_TOOL" <<'PY'
import importlib.util
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("lattice_compatibility_import", path)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert module.PASS_REGISTRY
assert module.main.__module__ == "upkeeper_lattice_core"
PY

printf 'lattice_import_cache_test: ok\n'
