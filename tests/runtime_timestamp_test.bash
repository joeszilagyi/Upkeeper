#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/upkeeper/runtime_foundation.bash"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_builtin_timestamp_helpers_do_not_invoke_date() {
  local timestamp terminal_timestamp epoch epoch_seconds captured_line

  date() {
    printf 'unexpected-date-invocation\n' >&2
    return 97
  }

  timestamp="$(timestamp_now)" || fail "timestamp_now failed when date was unavailable"
  terminal_timestamp="$(terminal_timestamp_now)" ||
    fail "terminal_timestamp_now failed when date was unavailable"
  epoch="$(epoch_now_fraction)" || fail "epoch_now_fraction failed when date was unavailable"
  epoch_seconds="$(epoch_now_seconds)" || fail "epoch_now_seconds failed when date was unavailable"

  CYCLE_ID="timestamp-test"
  CYCLE_RUN_HASH="runtime"
  append_log_line_secure() {
    captured_line="$1"
  }
  terminal_emit_log_line() {
    return 0
  }
  log_line INFO 'builtin timestamp logging contract' ||
    fail "log_line failed when date was unavailable"

  [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$ ]] ||
    fail "timestamp_now changed format: $timestamp"
  [[ "$terminal_timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] ||
    fail "terminal_timestamp_now changed format: $terminal_timestamp"
  [[ "$epoch" =~ ^[0-9]+\.[0-9]{5}$ ]] ||
    fail "epoch_now_fraction changed format: $epoch"
  [[ "$epoch_seconds" =~ ^[0-9]+$ ]] ||
    fail "epoch_now_seconds changed format: $epoch_seconds"
  [[ "$captured_line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}\ \[INFO\]\ cycle=timestamp-test\ run_hash=runtime\ builtin\ timestamp\ logging\ contract$ ]] ||
    fail "log_line changed its timestamp or record format: $captured_line"
}

test_compatibility_fallback_uses_date_only_when_builtin_time_is_unavailable() {
  local timestamp terminal_timestamp epoch epoch_seconds

  upkeeper_printf_time_supported() {
    return 1
  }
  upkeeper_epoch_realtime_supported() {
    return 1
  }
  upkeeper_epoch_seconds_supported() {
    return 1
  }
  date() {
    case "$1" in
      '+%Y-%m-%dT%H:%M:%S%z') printf '2001-02-03T04:05:06-0700\n' ;;
      '+%Y-%m-%dT%H:%M:%S') printf '2001-02-03T04:05:06\n' ;;
      '+%s.%N') printf '123.456789\n' ;;
      '+%s') printf '123\n' ;;
      *) fail "unexpected fallback date format: $1" ;;
    esac
  }

  timestamp="$(timestamp_now)"
  terminal_timestamp="$(terminal_timestamp_now)"
  epoch="$(epoch_now_fraction)"
  epoch_seconds="$(epoch_now_seconds)"

  [[ "$timestamp" == '2001-02-03T04:05:06-0700' ]] || fail "timestamp fallback changed: $timestamp"
  [[ "$terminal_timestamp" == '2001-02-03T04:05:06' ]] ||
    fail "terminal timestamp fallback changed: $terminal_timestamp"
  [[ "$epoch" == '123.45679' ]] || fail "epoch fallback changed: $epoch"
  [[ "$epoch_seconds" == '123' ]] || fail "integer epoch fallback changed: $epoch_seconds"
}

test_builtin_timestamp_helpers_do_not_invoke_date
test_compatibility_fallback_uses_date_only_when_builtin_time_is_unavailable

printf 'runtime_timestamp_test: ok\n'
