#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-backlog-quota-hibernation-test.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'backlog_quota_hibernation_test: ERROR: %s\n' "$*" >&2
  exit 1
}

BACKLOG_SOURCE_ONLY=1
export BACKLOG_SOURCE_ONLY
source "$ROOT_DIR/orchestration/backlog.sh"

HIBERNATION_HEARTBEATS=()
backlog_update_active_owner_heartbeat() {
  HIBERNATION_HEARTBEATS+=("${2:-}")
}

prepare_hibernation() {
  local name="$1"

  BACKLOG_TEST_NOW_EPOCH=1000
  BACKLOG_TEST_FAKE_SLEEP=1
  BACKLOG_TEST_SLEEP_LOG="$TEST_ROOT/$name.sleeps"
  BACKLOG_LOOP_LOG_FILE="$TEST_ROOT/$name.loop.log"
  BACKLOG_QUOTA_HIBERNATE=1
  BACKLOG_QUOTA_HIBERNATE_MAX_SECONDS=0
  HIBERNATION_HEARTBEATS=()
  : >"$BACKLOG_TEST_SLEEP_LOG"
}

run_hibernation() {
  local blocked_until="$1"
  HIBERNATION_STATUS=0

  backlog_hibernate_until_epoch "$blocked_until" primary "test quota block" test_fixture || HIBERNATION_STATUS=$?
}

sleep_sequence() {
  tr '\n' ',' <"$BACKLOG_TEST_SLEEP_LOG" | sed 's/,$//'
}

test_default_boundary_wait_is_short() {
  local heartbeat_text

  prepare_hibernation default
  [[ "$BACKLOG_QUOTA_HIBERNATE_GRACE_SECONDS" == "5" ]] ||
    fail "default reset grace is $BACKLOG_QUOTA_HIBERNATE_GRACE_SECONDS, expected 5"
  [[ "$BACKLOG_QUOTA_HIBERNATE_POLL_SECONDS" == "15" ]] ||
    fail "default local poll is $BACKLOG_QUOTA_HIBERNATE_POLL_SECONDS, expected 15"
  run_hibernation 1010

  [[ "$HIBERNATION_STATUS" == "3" ]] || fail "default hibernation exited $HIBERNATION_STATUS, expected 3"
  [[ "$BACKLOG_TEST_NOW_EPOCH" == "1015" ]] ||
    fail "default reset boundary reached $BACKLOG_TEST_NOW_EPOCH, expected 1015"
  [[ "$(sleep_sequence)" == "5,5,5" ]] ||
    fail "default reset boundary slept $(sleep_sequence), expected 5,5,5 seconds"
  heartbeat_text="$(printf '%s\n' "${HIBERNATION_HEARTBEATS[@]}")"
  grep -Fq 'grace_seconds=5' <<<"$heartbeat_text" ||
    fail "default hibernation heartbeat omitted reset grace"
  grep -Fq 'next_local_check=5s' <<<"$heartbeat_text" ||
    fail "default hibernation heartbeat omitted final local check ETA"
}

test_explicit_zero_grace_rechecks_immediately() {
  prepare_hibernation zero-grace
  BACKLOG_QUOTA_HIBERNATE_GRACE_SECONDS=0
  BACKLOG_QUOTA_HIBERNATE_POLL_SECONDS=15
  run_hibernation 1000

  [[ "$HIBERNATION_STATUS" == "0" ]] || fail "zero-grace expired reset exited $HIBERNATION_STATUS, expected immediate retry"
  [[ ! -s "$BACKLOG_TEST_SLEEP_LOG" ]] ||
    fail "zero-grace expired reset slept $(sleep_sequence) seconds"
}

test_final_window_uses_tighter_local_poll() {
  prepare_hibernation adaptive
  BACKLOG_QUOTA_HIBERNATE_GRACE_SECONDS=5
  BACKLOG_QUOTA_HIBERNATE_POLL_SECONDS=15
  run_hibernation 1032

  [[ "$HIBERNATION_STATUS" == "3" ]] || fail "adaptive hibernation exited $HIBERNATION_STATUS, expected 3"
  [[ "$BACKLOG_TEST_NOW_EPOCH" == "1037" ]] ||
    fail "adaptive hibernation reached $BACKLOG_TEST_NOW_EPOCH, expected 1037"
  [[ "$(sleep_sequence)" == "15,5,5,5,5,2" ]] ||
    fail "adaptive hibernation slept $(sleep_sequence), expected 15,5,5,5,5,2"
}

test_invalid_config_uses_safe_defaults() {
  prepare_hibernation invalid
  BACKLOG_QUOTA_HIBERNATE_GRACE_SECONDS=invalid
  BACKLOG_QUOTA_HIBERNATE_POLL_SECONDS=0
  run_hibernation 1010

  [[ "$HIBERNATION_STATUS" == "3" ]] || fail "invalid-config hibernation exited $HIBERNATION_STATUS, expected 3"
  [[ "$BACKLOG_TEST_NOW_EPOCH" == "1015" ]] ||
    fail "invalid-config hibernation reached $BACKLOG_TEST_NOW_EPOCH, expected default grace wake"
  [[ "$(sleep_sequence)" == "5,5,5" ]] ||
    fail "invalid-config hibernation slept $(sleep_sequence), expected final-window default polls"
}

test_max_wait_remains_a_fail_closed_guard() {
  prepare_hibernation maximum
  BACKLOG_QUOTA_HIBERNATE_GRACE_SECONDS=5
  BACKLOG_QUOTA_HIBERNATE_POLL_SECONDS=15
  BACKLOG_QUOTA_HIBERNATE_MAX_SECONDS=4
  run_hibernation 1010

  [[ "$HIBERNATION_STATUS" == "4" ]] || fail "maximum-wait guard exited $HIBERNATION_STATUS, expected 4"
  [[ ! -s "$BACKLOG_TEST_SLEEP_LOG" ]] ||
    fail "maximum-wait guard slept $(sleep_sequence) seconds"
}

test_poll_helper_preserves_explicit_short_cadence() {
  [[ "$(backlog_quota_hibernation_poll_seconds 31 15)" == "15" ]] ||
    fail "poll helper shortened the non-final window"
  [[ "$(backlog_quota_hibernation_poll_seconds 30 15)" == "5" ]] ||
    fail "poll helper did not tighten the final window"
  [[ "$(backlog_quota_hibernation_poll_seconds 30 3)" == "3" ]] ||
    fail "poll helper overrode explicit short cadence"
  if backlog_quota_hibernation_poll_seconds invalid 15 >/dev/null 2>&1; then
    fail "poll helper accepted invalid remaining time"
  fi
}

test_default_boundary_wait_is_short
test_explicit_zero_grace_rechecks_immediately
test_final_window_uses_tighter_local_poll
test_invalid_config_uses_safe_defaults
test_max_wait_remains_a_fail_closed_guard
test_poll_helper_preserves_explicit_short_cadence
printf 'backlog_quota_hibernation_test: ok\n'
