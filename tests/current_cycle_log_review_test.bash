#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-current-log-review.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'current_cycle_log_review_test: FAIL: %s\n' "$*" >&2
  exit 1
}

# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/upkeeper/report_analysis.bash"

CYCLE_ID="fixture-cycle"
LOG_FILE="$TEST_ROOT/Upkeeper.log"
STARTUP_ANOMALY_REASONS=""
message_file="$TEST_ROOT/last-message.txt"
digest="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

printf '2026-10-10T00:00:00 [INFO] cycle=fixture-cycle run_hash=fixture cycle.start\n' >"$LOG_FILE"
printf '2026-10-10T00:00:01 [INFO] cycle=fixture-cycle run_hash=fixture run.start\n' >>"$LOG_FILE"
printf '2026-10-10T00:00:02 [INFO] cycle=fixture-cycle run_hash=fixture run.finish\n' >>"$LOG_FILE"
printf '2026-10-10T00:00:03 [INFO] cycle=fixture-cycle run_hash=fixture cycle.exit\n' >>"$LOG_FILE"
printf 'UPKEEPER_LOG_REVIEW: CHECKED cycle=fixture-cycle anomalies=none log_sha256=%s\n' "$digest" >"$message_file"
printf 'UPKEEPER_STATUS: WORK_DONE\n' >>"$message_file"

UPKEEPER_CURRENT_CYCLE_LOG_REVIEW_ANOMALIES="none"
UPKEEPER_CURRENT_CYCLE_LOG_REVIEW_SHA256="$digest"
current_cycle_log_review_present "$message_file" ||
  fail "wrapper-provided clean snapshot was not accepted"

UPKEEPER_CURRENT_CYCLE_LOG_REVIEW_SHA256="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
if current_cycle_log_review_present "$message_file"; then
  fail "mismatched wrapper-provided digest was accepted"
fi

UPKEEPER_CURRENT_CYCLE_LOG_REVIEW_ANOMALIES="listed"
UPKEEPER_CURRENT_CYCLE_LOG_REVIEW_SHA256="$digest"
if current_cycle_log_review_present "$message_file"; then
  fail "anomaly-class mismatch was accepted"
fi

printf 'current_cycle_log_review_test: ok\n'
