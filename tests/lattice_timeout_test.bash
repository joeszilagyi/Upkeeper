#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-lattice-timeout.XXXXXX")"
export PYTHONDONTWRITEBYTECODE=1
trap 'lattice_force_stop_service 2>/dev/null || true; rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

shell_quote() {
  printf '%q' "$1"
}

log_line() {
  printf '%s %s\n' "$1" "$2" >>"$TEST_LOG"
}

log_line_parts() {
  local level="$1" part message=""
  shift
  for part in "$@"; do
    message+="$part"
  done
  log_line "$level" "$message"
}

finish_cycle() {
  local exit_code="$1" reason="$2" level="$3"
  shift 3
  printf 'exit_code=%s reason=%s level=%s detail=%s\n' \
    "$exit_code" "$reason" "$level" "$*" >"$FINISH_CAPTURE"
  exit "$exit_code"
}

run_mktemp() {
  mktemp "$TEST_TMP_ROOT/preselect.XXXXXX"
}

make_fixture() {
  local implementation="$TEST_TMP_ROOT/implementation"
  local fixture_tool

  mkdir -p "$implementation/tools"
  ln -s "$PROJECT_ROOT/tools/upkeeper_lib" "$implementation/tools/upkeeper_lib"
  fixture_tool="$implementation/tools/upkeeper_lattice.py"
  printf '%s\n' \
    '#!/usr/bin/env python3' \
    'import base64' \
    'import os' \
    'import subprocess' \
    'import sys' \
    'import time' \
    '' \
    'def start_child():' \
    '    pid_file = os.environ.get("LATTICE_TIMEOUT_CHILD_PID_FILE")' \
    '    if pid_file:' \
    '        child = subprocess.Popen([sys.executable, "-c", "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)"])' \
    '        with open(pid_file, "w", encoding="utf-8") as handle:' \
    '            handle.write(str(child.pid))' \
    '' \
    'def hang():' \
    '    time.sleep(60)' \
    '' \
    'def service():' \
    '    stream = sys.stdin.buffer' \
    '    while True:' \
    '        header = stream.readline()' \
    '        if not header:' \
    '            return' \
    '        if header == b"SHUTDOWN\\n":' \
    '            print("RC 0", flush=True)' \
    '            print("OUTPUT_B64 " + base64.b64encode(b"{}").decode(), flush=True)' \
    '            print("END", flush=True)' \
    '            return' \
    '        count = int(header.split()[1])' \
    '        args = []' \
    '        for _ in range(count):' \
    '            value = bytearray()' \
    '            while True:' \
    '                char = stream.read(1)' \
    '                if char == b"\\0":' \
    '                    break' \
    '                value.extend(char)' \
    '            args.append(value.decode())' \
    '        if args and args[0] == "init":' \
    '            print("RC 0", flush=True)' \
    '            print("OUTPUT_B64 " + base64.b64encode(b"{}").decode(), flush=True)' \
    '            print("END", flush=True)' \
    '        else:' \
    '            hang()' \
    '' \
    'if "service" in sys.argv[1:]:' \
    '    start_child()' \
    '    service()' \
    'elif "init" in sys.argv[1:]:' \
    '    print("{}")' \
    'else:' \
    '    hang()' \
    >"$fixture_tool"
  chmod +x "$fixture_tool"
  UPKEEPER_IMPLEMENTATION_DIR="$implementation"
}

reset_state() {
  lattice_force_stop_service 2>/dev/null || true
  TEST_LOG="$TEST_TMP_ROOT/test.log"
  FINISH_CAPTURE="$TEST_TMP_ROOT/finish.txt"
  : >"$TEST_LOG"
  rm -f "$FINISH_CAPTURE"
  ROOT_DIR="$TEST_TMP_ROOT/repo"
  mkdir -p "$ROOT_DIR"
  CYCLE_ID="cycle-timeout"
  CYCLE_RUN_HASH="run-timeout"
  UPKEEPER_LATTICE_DB="$ROOT_DIR/runtime/upkeeper-lattice/lattice.sqlite3"
  UPKEEPER_LATTICE_SQLITE_JOURNAL_MODE="delete"
  UPKEEPER_LATTICE_ENABLED="1"
  UPKEEPER_LATTICE_REQUIRED="0"
  UPKEEPER_LATTICE_SERVICE_ENABLED="1"
  UPKEEPER_LATTICE_COMMAND_TIMEOUT_SECONDS="1"
  UPKEEPER_LATTICE_TIMEOUT_KILL_AFTER_SECONDS="0"
  UPKEEPER_LATTICE_WARNED="0"
  UPKEEPER_LATTICE_AVAILABLE="0"
  unset LATTICE_TIMEOUT_CHILD_PID_FILE
}

source "$PROJECT_ROOT/lib/upkeeper/lattice.bash"
source "$PROJECT_ROOT/lib/upkeeper/help_selection.bash"
make_fixture

test_service_timeout_is_bounded_and_cleans_up() {
  local rc started service_pid child_pid child_pid_file="$TEST_TMP_ROOT/service-child.pid"
  reset_state
  LATTICE_TIMEOUT_CHILD_PID_FILE="$child_pid_file"
  export LATTICE_TIMEOUT_CHILD_PID_FILE
  started="$SECONDS"
  if lattice_run doctor --fast; then
    fail "warm-service doctor unexpectedly succeeded"
  else
    rc="$?"
  fi
  [[ "$rc" == "124" ]] || fail "warm-service timeout returned $rc, expected 124"
  [[ "$((SECONDS - started))" -le 4 ]] || fail "warm-service timeout exceeded its bound"
  [[ "${LATTICE_LAST_TIMEOUT:-0}" == "1" ]] || fail "warm-service timeout marker was not set"
  [[ "$LATTICE_LAST_OUTPUT" == *'"status":"timeout"'* ]] || fail "warm-service timeout detail is not structured"
  [[ "$LATTICE_LAST_OUTPUT" == *'"transport":"service"'* ]] || fail "warm-service timeout transport is wrong"
  service_pid="$(sed -n 's/.*lattice.service.started pid=\([0-9][0-9]*\).*/\1/p' "$TEST_LOG" | tail -n 1)"
  [[ -n "$service_pid" ]] || fail "warm-service timeout did not record its process identity"
  if kill -0 "$service_pid" 2>/dev/null; then
    fail "timed-out service process $service_pid survived cleanup"
  fi
  [[ -s "$child_pid_file" ]] || fail "warm-service timeout fixture did not start a descendant"
  child_pid="$(<"$child_pid_file")"
  if kill -0 "$child_pid" 2>/dev/null; then
    fail "timed-out service descendant $child_pid survived cleanup"
  fi
  [[ "${UPKEEPER_LATTICE_SERVICE_ACTIVE:-0}" == "0" ]] || fail "timed-out service remained active"
  [[ -z "${UPKEEPER_LATTICE_SERVICE_PID:-}" ]] || fail "timed-out service PID was retained"
}

test_direct_cli_timeout_is_bounded() {
  local rc started
  reset_state
  UPKEEPER_LATTICE_SERVICE_ENABLED="0"
  started="$SECONDS"
  if lattice_run doctor --fast; then
    fail "direct doctor unexpectedly succeeded"
  else
    rc="$?"
  fi
  [[ "$rc" == "124" ]] || fail "direct timeout returned $rc, expected 124"
  [[ "$((SECONDS - started))" -le 4 ]] || fail "direct timeout exceeded its bound"
  [[ "${LATTICE_LAST_TIMEOUT:-0}" == "1" ]] || fail "direct timeout marker was not set"
  [[ "$LATTICE_LAST_OUTPUT" == *'"transport":"cli"'* ]] || fail "direct timeout transport is wrong"
}

test_optional_startup_timeout_spools_recovery_evidence() {
  local recovery
  reset_state
  UPKEEPER_LATTICE_SERVICE_ENABLED="0"
  lattice_init_and_doctor_or_exit
  [[ "$UPKEEPER_LATTICE_AVAILABLE" == "0" ]] || fail "optional timeout marked Lattice available"
  grep -Fq 'lattice.timeout command=doctor' "$TEST_LOG" || fail "optional timeout log is missing"
  grep -Fq 'reason=doctor_timeout' "$TEST_LOG" || fail "optional degraded warning lacks timeout reason"
  recovery="$ROOT_DIR/runtime/upkeeper-lattice/recovery/lattice-unavailable.jsonl"
  [[ -s "$recovery" ]] || fail "optional timeout did not spool recovery evidence"
  grep -Fq '"reason":"doctor_timeout"' "$recovery" || fail "recovery evidence lacks timeout reason"
  grep -Fq '"detail_status":"timeout"' "$recovery" || fail "recovery evidence lacks timeout status"
}

test_required_startup_timeout_fails_closed() {
  local rc
  reset_state
  UPKEEPER_LATTICE_SERVICE_ENABLED="0"
  UPKEEPER_LATTICE_REQUIRED="1"
  if (lattice_init_and_doctor_or_exit); then
    fail "required startup timeout unexpectedly continued"
  else
    rc="$?"
  fi
  [[ "$rc" == "3" ]] || fail "required startup timeout returned $rc, expected 3"
  grep -Fq 'reason=LATTICE_TIMEOUT' "$FINISH_CAPTURE" || fail "required timeout did not use LATTICE_TIMEOUT custody"
  grep -Fq 'reason=doctor_timeout' "$FINISH_CAPTURE" || fail "required timeout detail lacks doctor phase"
}

test_max_cover_timeout_falls_back_deterministically() {
  local repo="$TEST_TMP_ROOT/selection-repo" output selected
  reset_state
  repo="$TEST_TMP_ROOT/selection-repo"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git config user.name "Upkeeper Test"
    git config user.email "upkeeper-test@localhost"
    : >.upkeeperignore
    printf '#!/usr/bin/env bash\nprintf "oldest\\n"\n' >oldest.sh
    printf '#!/usr/bin/env bash\nprintf "newest\\n"\n' >newest.sh
    chmod +x oldest.sh newest.sh
    touch -d '@1700000000' oldest.sh
    touch -d '@1700000100' newest.sh
    git add -A
    git commit -q -m fixture
  )
  ROOT_DIR="$repo"
  SELF_PATH="$PROJECT_ROOT/Upkeeper"
  CODEX_UPKEEPER_SELF_REVIEW_AFTER_DAYS="7"
  STARTUP_ANOMALY_GATE="0"
  CODEX_STARTUP_ANOMALY_FORCE_UPKEEPER="0"
  CODEX_TARGET_FILE=""
  CODEX_TOOL_FAILURE_QUEUE_DIR="$repo/runtime/tool-failure-queue"
  CODEX_TOOL_FAILURE_QUEUE_ENABLED="0"
  CODEX_TOOL_FAILURE_QUEUE_BYPASS="0"
  CODEX_SELECTION_SOURCE="enumerate"
  CODEX_FILE_MANIFEST_PATH="$repo/runtime-manifest.json"
  CODEX_SELECTION_ORDER="oldest"
  CODEX_SELECT_UNTRACKED="1"
  CODEX_TARGET_ROOT=""
  CODEX_TARGET_MAX_DEPTH=""
  CODEX_SELECTION_INCLUDE_GLOBS=""
  CODEX_SELECTION_EXCLUDE_GLOBS=""
  CODEX_SELECTION_REVIEW_MODULES=""
  CODEX_SELECTION_RANDOM_SEED=""
  CODEX_MAX_COVER_MODE="1"
  UPKEEPER_LATTICE_ENABLED="1"
  UPKEEPER_LATTICE_SELECTION_MODE="max-cover"
  UPKEEPER_LATTICE_DB="$repo/runtime/lattice.sqlite3"
  CODEX_UPKEEPER_IGNORE_FILE="$repo/.upkeeperignore"

  output="$(preselect_review_target)"
  selected="$(sed -n 's/^path=//p' <<<"$output")"
  [[ "$selected" == "oldest.sh" ]] || fail "max-cover timeout fallback selected $selected, expected oldest.sh"
  grep -Fq 'selection_mode=max_cover_fallback' <<<"$output" || fail "max-cover timeout did not report fallback mode"
  grep -Fq 'lattice_status=lattice_query_timeout' <<<"$output" || fail "max-cover timeout status is missing"
  grep -Fq 'unavailable (lattice_query_timeout)' <<<"$output" || fail "fallback basis does not explain timeout"
}

test_required_max_cover_timeout_fails_closed() {
  local rc compiled="$TEST_TMP_ROOT/compiled.txt"
  reset_state
  : >"$compiled"
  UPKEEPER_LATTICE_REQUIRED="1"
  preselect_review_target() {
    printf '%s\n' \
      'path=oldest.sh' \
      'epoch=1700000000' \
      'mtime=2023-11-14 00:00:00 +0000' \
      'age=1h 0m' \
      'git_status=tracked' \
      'content_state=matches_head' \
      'head_blob=fixture' \
      'worktree_hash=fixture' \
      'eligible_count=1' \
      'selection_mode=max_cover_fallback' \
      'lattice_status=lattice_query_timeout' \
      'selection_source=enumerate' \
      'manifest_status=enumerated' \
      'selection_order=oldest' \
      'select_untracked=1' \
      'target_root=none' \
      'target_max_depth=none' \
      'include_globs=none' \
      'exclude_globs=none' \
      'selection_review_modules=none' \
      'failure_queue_selected=0' \
      'selection_basis=timeout fixture'
  }
  if (append_preselected_review_target "$compiled"); then
    fail "required max-cover timeout unexpectedly continued"
  else
    rc="$?"
  fi
  [[ "$rc" == "3" ]] || fail "required max-cover timeout returned $rc, expected 3"
  grep -Fq 'reason=LATTICE_TIMEOUT' "$FINISH_CAPTURE" || fail "required max-cover timeout lost custody reason"
  grep -Fq 'command=selection-candidates' "$FINISH_CAPTURE" || fail "required max-cover timeout lacks command evidence"
}

test_service_timeout_is_bounded_and_cleans_up
test_direct_cli_timeout_is_bounded
test_optional_startup_timeout_spools_recovery_evidence
test_required_startup_timeout_fails_closed
test_max_cover_timeout_falls_back_deterministically
test_required_max_cover_timeout_fails_closed
printf 'lattice_timeout_test: ok\n'
