#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

load_active_lock_fixture() {
  shell_quote() {
    printf '%q' "$1"
  }

  log_line() {
    printf 'worker=%s log=%s\n' "$worker_id" "$*"
  }

  log_line_parts() {
    log_line "$@"
  }

  finish_cycle() {
    local exit_code="$1"
    local reason="$2"
    local level="$3"
    shift 3
    printf 'worker=%s exit=%s reason=%s level=%s detail=%s\n' \
      "$worker_id" "$exit_code" "$reason" "$level" "$*"
    exit "$exit_code"
  }

  ROOT_DIR="$RACE_ROOT"
  LOG_FILE="$RACE_ROOT/Upkeeper.log"
  CODEX_TERMINAL_VERBOSITY="silent"
  CODEX_ACTIVE_LOCK_DIR="$RACE_LOCK_DIR"
  CYCLE_ID="race-$worker_id"
  CYCLE_RUN_HASH="race-run-$worker_id"
  CODEX_FALLBACK_CHAIN_TOKEN=""
  ACTIVE_LOCK_ACQUIRED="0"

  source "$PROJECT_ROOT/lib/upkeeper/runtime_foundation.bash"
  source "$PROJECT_ROOT/lib/upkeeper/active_lock.bash"
}

if [[ "${1:-}" == "--worker" ]]; then
  worker_id="${2:?worker id required}"
  load_active_lock_fixture

  : >"$RACE_READY_DIR/$worker_id"
  while [[ ! -e "$RACE_START_FILE" ]]; do
    sleep 0.01
  done

  acquire_active_lock_or_exit
  printf '%s\n' "$worker_id" >>"$RACE_WINNERS_FILE"
  while [[ ! -e "$RACE_RELEASE_FILE" ]]; do
    sleep 0.01
  done
  release_active_lock
  exit 0
fi

if [[ "${1:-}" == "--instance-change-worker" ]]; then
  worker_id="instance-change"
  load_active_lock_fixture

  acquire_active_lock_reclaim_guard() {
    local guard_dir="$1"

    mkdir -- "$guard_dir" || return 1
    mv -- "$CODEX_ACTIVE_LOCK_DIR" "$CODEX_ACTIVE_LOCK_DIR.previous"
    mkdir -- "$CODEX_ACTIVE_LOCK_DIR"
    printf 'fresh owner sentinel\n' >"$CODEX_ACTIVE_LOCK_DIR/fresh-owner"
  }

  acquire_active_lock_or_exit
  printf 'unexpected acquisition\n' >&2
  exit 0
fi

TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-active-lock-race.XXXXXX")"
trap 'find "$TEST_TMP_ROOT" -depth -delete 2>/dev/null || true' EXIT

fail() {
  local output_file
  printf 'FAIL: %s\n' "$*" >&2
  for output_file in "$TEST_TMP_ROOT"/*.out; do
    [[ -f "$output_file" ]] || continue
    printf '%s:\n' "$(basename -- "$output_file")" >&2
    sed 's/^/  /' "$output_file" >&2
  done
  exit 1
}

RACE_ROOT="$TEST_TMP_ROOT/repo"
RACE_LOCK_DIR="$RACE_ROOT/runtime/upkeeper-active.lock"
RACE_READY_DIR="$TEST_TMP_ROOT/ready"
RACE_START_FILE="$TEST_TMP_ROOT/start"
RACE_RELEASE_FILE="$TEST_TMP_ROOT/release"
RACE_WINNERS_FILE="$TEST_TMP_ROOT/winners"
mkdir -p -- "$RACE_LOCK_DIR" "$RACE_READY_DIR"
: >"$RACE_WINNERS_FILE"

cat >"$RACE_LOCK_DIR/state" <<EOF
cycle_id=stale-cycle
run_hash=stale-run
pid=99999999
wrapper_start=proc_start_ticks=0
boot_id=unknown
root_dir=$RACE_ROOT
self_path=$PROJECT_ROOT/Upkeeper
fallback_chain_token=
created_epoch=1
EOF
touch -d '2 minutes ago' "$RACE_LOCK_DIR"

export PROJECT_ROOT RACE_ROOT RACE_LOCK_DIR RACE_READY_DIR RACE_START_FILE RACE_RELEASE_FILE RACE_WINNERS_FILE

worker_count=12
worker_pids=()
for worker_id in $(seq 1 "$worker_count"); do
  bash "$0" --worker "$worker_id" >"$TEST_TMP_ROOT/worker-$worker_id.out" 2>&1 &
  worker_pids+=("$!")
done

ready=0
for _ in $(seq 1 500); do
  ready="$(find "$RACE_READY_DIR" -maxdepth 1 -type f | wc -l)"
  [[ "$ready" -eq "$worker_count" ]] && break
  sleep 0.01
done
[[ "$ready" -eq "$worker_count" ]] || fail "only $ready of $worker_count workers reached the start barrier"

: >"$RACE_START_FILE"

race_settled=0
running_workers="$worker_count"
winner_records=0
for _ in $(seq 1 1000); do
  running_workers=0
  for worker_pid in "${worker_pids[@]}"; do
    if kill -0 "$worker_pid" 2>/dev/null; then
      running_workers=$((running_workers + 1))
    fi
  done
  winner_records="$(wc -l <"$RACE_WINNERS_FILE")"
  if [[ "$winner_records" -gt 1 ]]; then
    break
  fi
  if [[ "$winner_records" -eq 1 && "$running_workers" -eq 1 ]]; then
    race_settled=1
    break
  fi
  if [[ "$running_workers" -eq 0 ]]; then
    break
  fi
  sleep 0.01
done
: >"$RACE_RELEASE_FILE"

winner_processes=0
loser_processes=0
for worker_pid in "${worker_pids[@]}"; do
  if wait "$worker_pid"; then
    winner_processes=$((winner_processes + 1))
  else
    loser_processes=$((loser_processes + 1))
  fi
done

winner_records="$(wc -l <"$RACE_WINNERS_FILE")"
[[ "$race_settled" -eq 1 ]] ||
  fail "race did not settle at one held owner (running=$running_workers winners=$winner_records)"
[[ "$winner_processes" -eq 1 ]] || fail "expected one successful owner, got $winner_processes"
[[ "$winner_records" -eq 1 ]] || fail "expected one winner record, got $winner_records"
[[ "$loser_processes" -eq $((worker_count - 1)) ]] ||
  fail "expected $((worker_count - 1)) losing reclaimers, got $loser_processes"

if ! grep -Fq 'reason=reclaim_lost' "$TEST_TMP_ROOT"/worker-*.out; then
  fail "losing reclaimers did not report reclaim_lost"
fi
if [[ -e "$RACE_LOCK_DIR" ]]; then
  fail "winning owner did not release the active lock"
fi
if [[ -e "$RACE_LOCK_DIR.reclaim" ]]; then
  fail "reclaim guard remained after the race"
fi

RACE_ROOT="$TEST_TMP_ROOT/instance-change-repo"
RACE_LOCK_DIR="$RACE_ROOT/runtime/upkeeper-active.lock"
mkdir -p -- "$RACE_LOCK_DIR"
cat >"$RACE_LOCK_DIR/state" <<EOF
cycle_id=stale-instance-cycle
run_hash=stale-instance-run
pid=99999999
wrapper_start=proc_start_ticks=0
boot_id=unknown
root_dir=$RACE_ROOT
self_path=$PROJECT_ROOT/Upkeeper
fallback_chain_token=
created_epoch=1
EOF
touch -d '2 minutes ago' "$RACE_LOCK_DIR"
export RACE_ROOT RACE_LOCK_DIR

set +e
bash "$0" --instance-change-worker >"$TEST_TMP_ROOT/instance-change.out" 2>&1
instance_change_rc=$?
set -e

[[ "$instance_change_rc" -eq 7 ]] || fail "changed-instance reclaimer exited $instance_change_rc, expected 7"
grep -Fq 'reclaim_reason=lock_instance_changed' "$TEST_TMP_ROOT/instance-change.out" ||
  fail "changed-instance reclaimer did not report lock_instance_changed"
[[ -f "$RACE_LOCK_DIR/fresh-owner" ]] || fail "changed-instance reclaimer removed the replacement lock"
[[ ! -e "$RACE_LOCK_DIR.reclaim" ]] || fail "changed-instance reclaimer left its guard"

printf 'active_lock_reclaim_race_test: ok\n'
