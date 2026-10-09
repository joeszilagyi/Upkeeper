#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-lattice-validation-timeout.XXXXXX")"
trap 'lattice_harness_stop 2>/dev/null || true; rm -r "$TEST_ROOT"' EXIT

source "$ROOT_DIR/tests/lib/lattice_command_guard.bash"
source "$ROOT_DIR/tests/lib/lattice_inprocess_harness.bash"

fail() {
  printf 'lattice_validation_timeout_test: ERROR: %s\n' "$*" >&2
  exit 1
}

fake_lattice="$TEST_ROOT/upkeeper_lattice.py"
child_pid_file="$TEST_ROOT/direct-child.pid"
direct_artifact="$TEST_ROOT/direct-timeout.jsonl"
cat >"$fake_lattice" <<'EOF'
#!/usr/bin/env bash
sleep 60 &
printf '%s\n' "$!" >"$LATTICE_WEDGE_CHILD_PID_FILE"
wait
EOF
chmod +x "$fake_lattice"

started="$SECONDS"
set +e
LATTICE_WEDGE_CHILD_PID_FILE="$child_pid_file" \
  lattice_command_guard_run \
    lattice_test:simulated-max-cover 1 "$direct_artifact" \
    "$fake_lattice" query selection-candidates --mode max-cover --format jsonl \
    >"$TEST_ROOT/direct.out" 2>"$TEST_ROOT/direct.err"
rc="$?"
set -e
[[ "$rc" -eq 124 ]] || fail "direct wedged command exited $rc, expected 124"
[[ "$((SECONDS - started))" -le 4 ]] || fail "direct wedged command exceeded its deadline"
[[ -s "$child_pid_file" ]] || fail "direct wedge fixture did not start a descendant"
child_pid="$(<"$child_pid_file")"
if kill -0 "$child_pid" 2>/dev/null; then
  fail "direct timeout left descendant $child_pid running"
fi
grep -Fq 'phase=lattice_test:simulated-max-cover' "$TEST_ROOT/direct.err" ||
  fail "direct timeout output did not name the phase"
grep -Fq 'query selection-candidates --mode max-cover --format jsonl' "$TEST_ROOT/direct.err" ||
  fail "direct timeout output did not name the command"
grep -Fq "artifact=$direct_artifact" "$TEST_ROOT/direct.err" ||
  fail "direct timeout output did not name the artifact"

python3 - "$direct_artifact" "$fake_lattice" <<'PY'
import json
import os
import stat
import sys

artifact, command = sys.argv[1:3]
rows = [json.loads(line) for line in open(artifact, encoding="utf-8")]
assert len(rows) == 1, rows
row = rows[0]
assert row["schema"] == "upkeeper.lattice-validation-timeout.v1", row
assert row["phase"] == "lattice_test:simulated-max-cover", row
assert row["status"] == "timeout" and row["exit_code"] == 124, row
assert row["timeout_seconds"] == 1, row
assert row["cleanup"] == "process_group_term_kill", row
assert command in row["command"], row
assert "query selection-candidates --mode max-cover --format jsonl" in row["command"], row
assert stat.S_IMODE(os.stat(artifact).st_mode) == 0o600, oct(stat.S_IMODE(os.stat(artifact).st_mode))
PY

harness_artifact="$TEST_ROOT/harness-timeout.jsonl"
LATTICE_HARNESS_COMMAND_TIMEOUT_SECONDS=1
LATTICE_HARNESS_TIMEOUT_ARTIFACT="$harness_artifact"
export LATTICE_INPROCESS_HARNESS_TEST_HANG=1
lattice_harness_start "$TEST_ROOT/harness"
harness_pid="$LATTICE_HARNESS_PID"
set +e
lattice_harness_run test-hang >"$TEST_ROOT/harness.out" 2>"$TEST_ROOT/harness.err"
rc="$?"
set -e
[[ "$rc" -eq 124 ]] || fail "in-process wedged command exited $rc, expected 124"
if kill -0 "$harness_pid" 2>/dev/null; then
  fail "in-process timeout left harness $harness_pid running"
fi
python3 - "$harness_artifact" <<'PY'
import json
import sys

row = json.loads(open(sys.argv[1], encoding="utf-8").readline())
assert row["phase"] == "lattice_inprocess:response_header", row
assert row["command"] == "test-hang", row
assert row["status"] == "timeout" and row["timeout_seconds"] == 1, row
assert row["cleanup"] == "harness_process_term_kill", row
PY

printf 'lattice_validation_timeout_test: ok\n'
