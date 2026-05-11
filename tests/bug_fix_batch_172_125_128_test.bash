#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-bug-fix-batch.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT
source "$PROJECT_ROOT/lib/upkeeper/session_store_preflight.bash"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

make_git_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git config user.name "Upkeeper Test"
    git config user.email "upkeeper-test@localhost"
  )
}

test_lattice_record_pass_result_does_not_create_missing_db() {
  local repo="$TEST_TMP_ROOT/issue-172"
  local status output

  make_git_repo "$repo"

  set +e
  output="$(python3 "$PROJECT_ROOT/tools/upkeeper_lattice.py" --root "$repo" --db runtime/upkeeper-lattice/lattice.sqlite3 record-pass-result --pass P1 --file a.py --outcome clean 2>&1)"
  status=$?
  set -e
  if [[ $status -ne 3 ]]; then
    fail "safe runtime DB path expected failure before creation, got status=$status and output=$output"
  fi
  if [[ -f "$repo/runtime/upkeeper-lattice/lattice.sqlite3" ]]; then
    fail "DB file was unexpectedly created at runtime path"
  fi

  set +e
  output="$(python3 "$PROJECT_ROOT/tools/upkeeper_lattice.py" --root "$repo" --db source-tree.sqlite3 record-pass-result --pass P1 --file a.py --outcome clean 2>&1)"
  status=$?
  set -e
  if [[ $status -ne 4 ]]; then
    fail "unsafe DB path expected unsafe_db_path status, got status=$status and output=$output"
  fi
  if [[ -f "$repo/source-tree.sqlite3" ]]; then
    fail "Unsafe DB path was created despite safety rejection"
  fi
}

test_log_preflight_rejects_symlink_log_file() {
  local root="$TEST_TMP_ROOT/issue-125"
  local target log_runner status
  mkdir -p "$root"
  target="$root/link-target.log"
  touch "$target"
  ln -s "$target" "$root/Upkeeper.log"

  log_runner="$root/run-log-preflight.sh"
  cat >"$log_runner" <<EOF
#!/usr/bin/env bash
set -euo pipefail

source "$PROJECT_ROOT/lib/upkeeper/runtime_foundation.bash"
source "$PROJECT_ROOT/lib/upkeeper/progress_logging.bash"

LOG_FILE="Upkeeper.log"
LOG_FILE_DIR="."
LOG_FILE_NAME="Upkeeper.log"

CYCLE_ID="cycle-125"
CYCLE_RUN_HASH="run-125"

ensure_log_writable_or_exit "startup"
EOF
  chmod +x "$log_runner"

  set +e
  (cd "$root" && "$log_runner" >"$root/preflight.out" 2>"$root/preflight.err")
  status=$?
  set -e
  [[ $status -eq 3 ]] || fail "log preflight expected status 3, got $status"
  [[ "$(wc -c <"$target")" -eq 0 ]] || fail "symlink log target was modified"
  grep -q "symlink_log_file" "$root/preflight.err" || fail "symlink-specific rejection missing from log preflight"
}

test_session_store_write_check_rejects_sessions_dir_symlink() {
  local codex_home output

  codex_home="$TEST_TMP_ROOT/issue-128"
  mkdir -p "$codex_home"
  mkdir -p "$TEST_TMP_ROOT/real-sessions-dir"
  ln -s "$TEST_TMP_ROOT/real-sessions-dir" "$codex_home/sessions"
  CODEX_HOME_DIR="$codex_home"

  set +e
  output="$(codex_session_store_write_check)"
  local status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    fail "sessions directory symlink unexpectedly passed write probe: $output"
  fi
  if [[ "$output" != unsafe_symlink:* ]]; then
    fail "unexpected session preflight failure mode: $output"
  fi
}

test_lattice_record_pass_result_does_not_create_missing_db
test_log_preflight_rejects_symlink_log_file
test_session_store_write_check_rejects_sessions_dir_symlink

printf 'bug_fix_batch_172_125_128_test: ok\n'
