#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-lattice-profile-test.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

output="$("$ROOT_DIR/tools/profile_lattice_selection.py" --mode max-cover)"
printf '%s\n' "$output" >"$TEST_TMP_ROOT/profile.json"

python3 - "$TEST_TMP_ROOT/profile.json" <<'PY' || fail "profile output did not satisfy contract"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["operation"] == "selection-candidates", data
assert data["mode"] == "max-cover", data
assert data["status"] == "ok", data
assert data["candidate_count"] > 0, data
assert data["eligible_count"] > 0, data
assert data["subprocess_run_count"] >= 0, data
assert data["subprocess_check_output_count"] >= 0, data
assert "wall_ms" in data and data["wall_ms"] >= 0, data
assert data["budget"]["enforced"] is False, data
PY

printf 'ok - lattice selection profile\n'
