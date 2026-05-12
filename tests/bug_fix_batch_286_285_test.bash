#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-bug-fix-286-285.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

shell_quote() {
  printf '%q' "$1"
}

log_line() {
  :
}

finish_cycle() {
  local exit_code="$1"
  local reason="$2"
  local level="$3"
  shift 3
  printf 'exit=%s reason=%s level=%s detail=%s\n' "$exit_code" "$reason" "$level" "$*"
  exit "$exit_code"
}

run_mktemp() {
  local label="${1:-tmp}"
  mkdir -p -- "$TEST_TMP_ROOT"
  mktemp "$TEST_TMP_ROOT/${label}.XXXXXX"
}

source "$PROJECT_ROOT/lib/upkeeper/runtime_foundation.bash"
source "$PROJECT_ROOT/lib/upkeeper/active_lock.bash"
source "$PROJECT_ROOT/lib/upkeeper/precontact_backup.bash"

hash_token() {
  local token="${1:-}"
  python3 - "$token" <<'PY'
import hashlib
import sys
print(hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest())
PY
}

run_fallback_child() {
  local token="$1"
  local child_out_file
  child_out_file="$TEST_TMP_ROOT/fallback-child.out"
  set +e
  : >"$child_out_file"
  CODEX_ACTIVE_LOCK_DIR="$LOCK_DIR" \
  CODEX_FALLBACK_CHAIN_ACTIVE=1 \
  CODEX_ATTEMPT_ROLE=fallback \
  CYCLE_ID="${PARENT_CYCLE}-child" \
  CODEX_PARENT_CYCLE_ID="$PARENT_CYCLE" \
  CODEX_FALLBACK_PARENT_PID="$PARENT_PID" \
  CODEX_FALLBACK_PARENT_START="$PARENT_START" \
  CODEX_FALLBACK_CHAIN_TOKEN_FD=9 \
  UPROOT="$PROJECT_ROOT" \
  bash -c 'set -euo pipefail
    source "$UPROOT/lib/upkeeper/runtime_foundation.bash"
    source "$UPROOT/lib/upkeeper/active_lock.bash"
    log_line() { :; }
    shell_quote() { printf "%q" "$1"; }
    finish_cycle() {
      local exit_code="$1"
      local reason="$2"
      local level="$3"
      shift 3
      printf "exit=%s reason=%s level=%s detail=%s\n" "$exit_code" "$reason" "$level" "$*"
      exit "$exit_code"
    }

    acquire_active_lock_or_exit
    printf "active_lock_inherited=%s\n" "${ACTIVE_LOCK_ACQUIRED:-}"
    exit 0
  ' 9<<<"$token" >"$child_out_file" 2>&1
  CHILD_RC=$?
  CHILD_OUT="$(cat "$child_out_file")"
  set -e
}

test_fallback_chain_token_is_hashed_and_required_for_inheritance() {
  local repo lock_token

  repo="$TEST_TMP_ROOT/issue-286"
  mkdir -p "$repo"
  LOCK_DIR="$TEST_TMP_ROOT/issue-286-lock"
  PARENT_CYCLE="cycle-286"
  CYCLE_ID="$PARENT_CYCLE"
  CYCLE_RUN_HASH="run-286"
  ROOT_DIR="$repo"
  LOG_FILE="$TEST_TMP_ROOT/issue-286.log"
  CODEX_ACTIVE_LOCK_DIR="$LOCK_DIR"
  CODEX_FALLBACK_CHAIN_TOKEN="$(generate_fallback_chain_token)"
  CODEX_LOOP_PARENT_PID="${PPID:-1}"
  CODEX_LOOP_PARENT_COMM=""
  CODEX_LOOP_PARENT_ARGS=""

  acquire_active_lock_or_exit
  [[ "${ACTIVE_LOCK_ACQUIRED:-0}" == "1" ]] || fail "primary failed to acquire active lock"

  lock_token="$(awk -F= 'BEGIN { token = "" } /^fallback_chain_token=/{print $2; exit}' "$LOCK_DIR/state")"
  [[ -n "$lock_token" ]] || fail "active lock state missing fallback token hash"
  [[ "$lock_token" != "$CODEX_FALLBACK_CHAIN_TOKEN" ]] || fail "fallback token was written as raw text"

  [[ "$lock_token" == "$(hash_token "$CODEX_FALLBACK_CHAIN_TOKEN")" ]] || fail "fallback token did not hash into lock state"

  PARENT_PID="$$"
  PARENT_START="$(process_start_fingerprint "$PARENT_PID")"

  run_fallback_child "$CODEX_FALLBACK_CHAIN_TOKEN"
  [[ "$CHILD_RC" -eq 0 ]] || fail "fallback child with correct token exited $CHILD_RC"
  [[ "$CHILD_OUT" == *"active_lock_inherited=0"* ]] || fail "fallback child did not inherit lock with correct token"

  run_fallback_child "${CODEX_FALLBACK_CHAIN_TOKEN}bad"
  [[ "$CHILD_RC" -ne 0 ]] || fail "fallback child with bad token should not inherit"
  [[ "$CHILD_OUT" == *"fallback_chain_token_mismatch"* ]] || fail "mismatch token did not report token mismatch reason"
}

test_selected_target_validation_runs_when_precontact_backup_off() {
  local repo rc out_file

  repo="$TEST_TMP_ROOT/issue-285"
  mkdir -p "$repo/dir"
  printf '#!/usr/bin/env bash\nprintf "target"\n' > "$repo/dir/target.sh"
  ln -s target.sh "$repo/dir/target-link.sh"

  ROOT_DIR="$repo"
  LOG_FILE="$TEST_TMP_ROOT/issue-285.log"
  CYCLE_ID="cycle-285"
  CYCLE_RUN_HASH="run-285"
  UPKEEPER_PRECONTACT_BACKUP_ROOT="$TEST_TMP_ROOT/issue-285-vault"
  UPKEEPER_PRECONTACT_BACKUP_MODE=off
  UPKEEPER_PRECONTACT_BACKUP_ENABLED=1
  UPKEEPER_PRECONTACT_BACKUP_REQUIRED=1

  out_file="$TEST_TMP_ROOT/issue-285.out"
  set +e
  (
    precontact_backup_selected_target_or_exit "dir/target-link.sh"
  ) >"$out_file" 2>&1
  rc=$?
  set -e

  [[ "$rc" -eq 7 ]] || fail "backup-off symlink validation should fail closed with exit 7"
  grep -Fq "reason=symlink_target_rejected" "$out_file" ||
    fail "backup-off path should still validate target before mode checks"
  [[ -z "${RUN_PRECONTACT_BACKUP_ID:-}" ]] || fail "backup artifacts should not be created when mode=off"
}

test_fallback_chain_token_is_hashed_and_required_for_inheritance
test_selected_target_validation_runs_when_precontact_backup_off

printf 'bug_fix_batch_286_285_test: ok\n'
