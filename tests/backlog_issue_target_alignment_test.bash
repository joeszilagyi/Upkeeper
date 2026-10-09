#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-backlog-target-alignment.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

log_line() {
  printf '%s %s\n' "$1" "$2" >>"$TEST_TMP_ROOT/wrapper.log"
}

log_line_parts() {
  local level="$1"
  shift
  log_line "$level" "$*"
}

shell_quote() {
  printf '%q' "$1"
}

truthy_as_int() {
  [[ "${1:-0}" == "1" ]] && printf '1' || printf '0'
}

config_truthy() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

upkeeper_value_hmac() {
  printf 'fixture-hmac'
}

finish_cycle() {
  fail "unexpected finish_cycle: $*"
}

upkeeper_issue_fix_next_enabled() {
  return 0
}

make_issue_793_gh_fixture() {
  local bin_dir="$1"

  mkdir -p "$bin_dir"
  cat >"$bin_dir/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cat <<'JSON'
{
  "number": 793,
  "title": "Slow test: client_link_tools_test exceeds shared runner slow budget",
  "url": "https://example.test/issues/793",
  "labels": [{"name": "bug"}],
  "createdAt": "2026-06-01T06:34:17Z",
  "state": "OPEN",
  "body": "The repair target is `tools/run_tests.sh`. Historical evidence also names `tools/upkeeper_lattice.py`, but it is unrelated to the slow client-link test.",
  "comments": []
}
JSON
SH
  chmod +x "$bin_dir/gh"
}

test_wrapper_selects_concrete_issue_target_and_logs_explicit_conflicts() {
  local repo bin_dir original_path

  repo="$TEST_TMP_ROOT/repo"
  bin_dir="$TEST_TMP_ROOT/bin"
  mkdir -p "$repo/tools"
  : >"$repo/tools/run_tests.sh"
  : >"$repo/tools/upkeeper_lattice.py"
  make_issue_793_gh_fixture "$bin_dir"
  original_path="$PATH"
  PATH="$bin_dir:$PATH"

  ROOT_DIR="$repo"
  CODEX_ISSUE_FIX_REQUESTED_NUMBER="793"
  CODEX_TARGET_FILE=""
  CODEX_ISSUE_FIX_NUMBER=""
  CODEX_ISSUE_FIX_TARGET_FILE=""
  CODEX_ISSUE_FIX_SELECTED_LABEL=""
  CODEX_ISSUE_SKIP_LABELS=""
  CODEX_ISSUE_PRIORITY_LABELS="bug"
  UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL="0"
  : >"$TEST_TMP_ROOT/wrapper.log"

  resolve_issue_fix_next_or_exit
  [[ "$CODEX_ISSUE_FIX_TARGET_FILE" == "tools/run_tests.sh" ]] ||
    fail "issue parser selected $CODEX_ISSUE_FIX_TARGET_FILE instead of tools/run_tests.sh"
  [[ "$CODEX_TARGET_FILE" == "tools/run_tests.sh" ]] ||
    fail "wrapper target did not follow concrete issue target: $CODEX_TARGET_FILE"

  CODEX_TARGET_FILE="tools/upkeeper_lattice.py"
  resolve_issue_fix_next_or_exit
  grep -Fq 'reason=explicit_target_differs_from_issue_inference' "$TEST_TMP_ROOT/wrapper.log" ||
    fail "explicit target conflict was not recorded"
  grep -Fq 'explicit_target=tools/upkeeper_lattice.py' "$TEST_TMP_ROOT/wrapper.log" ||
    fail "explicit target conflict log omitted explicit target"
  grep -Fq 'inferred_target=tools/run_tests.sh' "$TEST_TMP_ROOT/wrapper.log" ||
    fail "explicit target conflict log omitted inferred target"
  PATH="$original_path"
}

test_backlog_leaves_issue_target_unpinned_for_wrapper_resolution() {
  local captured_args target_hint

  prepare_backlog_runtime_env() { :; }
  log() { :; }
  backlog_update_active_owner_heartbeat() { :; }
  backlog_wait_detail() { :; }
  backlog_run_upkeeper_capture() {
    printf '%s\n' "$@" >"$TEST_TMP_ROOT/backlog.args"
  }
  BACKLOG_IGNORE_FAILURE_QUEUE="1"
  CODEX_MODEL="gpt-test"
  CODEX_REASONING_EFFORT="low"
  BACKLOG_REASONING_EFFORT_CLASS="fixture"
  BACKLOG_REASONING_EFFORT_SOURCE="fixture"
  target_hint="$(target_hint_for_issue 793)"
  [[ -z "$target_hint" ]] || fail "backlog still produced a heuristic issue target: $target_hint"

  run_upkeeper_for_one_target 793 "$target_hint"
  captured_args="$(<"$TEST_TMP_ROOT/backlog.args")"
  grep -Fxq -- '--fix-issue=793' <<<"$captured_args" ||
    fail "backlog omitted issue-repair selector"
  if grep -Fq -- '--target-file=' <<<"$captured_args"; then
    fail "backlog pinned an issue target instead of deferring to wrapper inference"
  fi
}

source "$PROJECT_ROOT/lib/upkeeper/runtime_format_json.bash"
source "$PROJECT_ROOT/lib/upkeeper/codex_io.bash"
BACKLOG_SOURCE_ONLY=1 source "$PROJECT_ROOT/orchestration/backlog.sh"

test_wrapper_selects_concrete_issue_target_and_logs_explicit_conflicts
test_backlog_leaves_issue_target_unpinned_for_wrapper_resolution

printf 'backlog_issue_target_alignment_test: ok\n'
