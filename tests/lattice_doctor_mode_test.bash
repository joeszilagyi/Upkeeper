#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LATTICE_TOOL="$ROOT_DIR/tools/upkeeper_lattice.py"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-lattice-doctor-mode.XXXXXX")"
trap 'rm -rf -- "$TMP_ROOT"' EXIT

REPO="$TMP_ROOT/repo"
DB="$REPO/runtime/lattice.sqlite3"
mkdir -p "$REPO"
(
  cd "$REPO"
  git init -q
  git config user.name "Lattice Doctor Test"
  git config user.email "lattice-doctor@example.invalid"
  printf 'runtime/\n' >.gitignore
  printf '# doctor fixture\n' >README.md
  git add -A
  git commit -q -m initial
)

"$LATTICE_TOOL" --root "$REPO" --db "$DB" init >/dev/null
"$LATTICE_TOOL" --root "$REPO" --db "$DB" doctor --fast >"$TMP_ROOT/fast.json"
"$LATTICE_TOOL" --root "$REPO" --db "$DB" doctor >"$TMP_ROOT/full.json"

python3 - "$TMP_ROOT/fast.json" "$TMP_ROOT/full.json" <<'PY'
import json
import sys

fast = json.load(open(sys.argv[1], encoding="utf-8"))
full = json.load(open(sys.argv[2], encoding="utf-8"))

assert fast["status"] == "ok", fast
assert fast["doctor_mode"] == "fast", fast
assert fast["checks"]["startup_liveness"] == "ok", fast
assert fast["checks"]["full_integrity"] == "deferred_to_explicit_doctor", fast
assert "foreign_key_check_rows" not in fast["checks"], fast
assert "quick_check" not in fast["checks"], fast
assert "raw_storage_enforcement" not in fast["checks"], fast

assert full["status"] == "ok", full
assert full["doctor_mode"] == "full", full
assert full["checks"]["full_integrity"] == "passed", full
assert full["checks"]["foreign_key_check_rows"] == [], full
assert full["checks"]["quick_check"] == "ok", full
assert "raw_storage_enforcement" in full["checks"], full
PY

# Create a deterministic foreign-key violation with enforcement disabled. The
# startup liveness probe deliberately defers the full scan, while explicit
# doctor must retain custody of the integrity failure.
python3 - "$DB" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute("PRAGMA foreign_keys=OFF")
conn.execute(
    "insert into files(repo_id, canonical_path, current_path, current_state) values (?, ?, ?, ?)",
    (999999, "orphan.py", "orphan.py", "active"),
)
conn.commit()
conn.close()
PY

"$LATTICE_TOOL" --root "$REPO" --db "$DB" doctor --fast >"$TMP_ROOT/fast-corrupt.json"
set +e
"$LATTICE_TOOL" --root "$REPO" --db "$DB" doctor >"$TMP_ROOT/full-corrupt.json"
full_corrupt_rc="$?"
set -e
[[ "$full_corrupt_rc" -eq 6 ]] || {
  printf 'lattice_doctor_mode_test: full doctor exited %s, expected 6\n' "$full_corrupt_rc" >&2
  exit 1
}

python3 - "$TMP_ROOT/fast-corrupt.json" "$TMP_ROOT/full-corrupt.json" <<'PY'
import json
import sys

fast = json.load(open(sys.argv[1], encoding="utf-8"))
full = json.load(open(sys.argv[2], encoding="utf-8"))
assert fast["status"] == "ok", fast
assert fast["checks"]["full_integrity"] == "deferred_to_explicit_doctor", fast
assert full["status"] == "integrity_failure", full
assert full["checks"]["foreign_key_check_rows"], full
PY

grep -Fq 'lattice_run doctor --fast' "$ROOT_DIR/lib/upkeeper/lattice.bash" || {
  printf 'lattice_doctor_mode_test: cycle startup does not select fast doctor\n' >&2
  exit 1
}
grep -Fq 'doctor_mode=fast' "$ROOT_DIR/lib/upkeeper/lattice.bash" || {
  printf 'lattice_doctor_mode_test: readiness log does not distinguish fast doctor\n' >&2
  exit 1
}

printf 'lattice_doctor_mode_test: ok\n'
