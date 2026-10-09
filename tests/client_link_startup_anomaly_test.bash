#!/usr/bin/env bash
set -euo pipefail

# This remains separately timed because it launches a distinct real client
# dry-run that exercises startup-anomaly containment and obligation isolation.
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/tests/lib/client_link_fixture.bash"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-client-link-startup-test.XXXXXX")"
trap 'rm -r "$TEST_TMP_ROOT" 2>/dev/null || true' EXIT
chmod 700 "$TEST_TMP_ROOT"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

central_open_obligation_inventory() {
  local open_dir="$PROJECT_ROOT/runtime/upkeeper-obligations/open"

  [[ -d "$open_dir" ]] || return 0
  find "$open_dir" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort
}

test_doctor_client_link_reports_no_repo_local_upkeeper_candidate() {
  local repo="$TEST_TMP_ROOT/startup-anomaly-client"
  local out="$TEST_TMP_ROOT/startup-anomaly-doctor.out"
  local err="$TEST_TMP_ROOT/startup-anomaly-doctor.err"
  local rc

  client_link_init_repo "$repo"
  client_link_install_fake_age
  "$PROJECT_ROOT/tools/install_client_link.sh" --repo="$repo" >/dev/null

  set +e
  STARTUP_ANOMALY_GATE=1 \
    CODEX_DISK_MIN_FREE_PERCENT=101 \
    CODEX_LOG_FILE="$repo/startup-anomaly-doctor.log" \
    CODEX_LOG_FILE_ALLOW_UNSAFE=1 \
    CODEX_STARTUP_ANOMALY_FORCE_UPKEEPER=1 \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$TEST_TMP_ROOT/startup-anomaly-state" \
    UPKEEPER_AUTOMATION_LEDGER_DIR="$TEST_TMP_ROOT/startup-anomaly-ledger" \
    UPKEEPER_OBLIGATION_DIR="$TEST_TMP_ROOT/startup-anomaly-obligations" \
    CODEX_HOME="$TEST_TMP_ROOT/startup-anomaly-codex-home" \
    CODEX_HOME_DIR="$TEST_TMP_ROOT/startup-anomaly-codex-home" \
    PATH="$TEST_TMP_ROOT/bin:$PATH" \
    "$PROJECT_ROOT/tools/doctor_upkeeper.sh" --repo="$repo" --skip-deps >"$out" 2>"$err"
  rc="$?"
  set -e

  [[ "$rc" -ne 0 ]] || fail "doctor succeeded unexpectedly during startup-anomaly fixture"
  grep -Fq "startup_anomaly.gate_target status=missing action=fail_closed reason=no_repo_local_upkeeper_candidate" "$err" ||
    fail "startup-anomaly gate did not report expected no local candidate"
  grep -Fq "doctor_upkeeper: ERROR: client dry-run failed with exit 7" "$err" ||
    fail "doctor did not surface exit 7 for startup-anomaly fixture"
}

test_fixture_does_not_leak_central_open_obligations() {
  local before after

  before="$(central_open_obligation_inventory)"
  test_doctor_client_link_reports_no_repo_local_upkeeper_candidate
  after="$(central_open_obligation_inventory)"
  [[ "$after" == "$before" ]] ||
    fail "startup-anomaly fixture created central open obligations"
}

test_fixture_does_not_leak_central_open_obligations

printf 'client_link_startup_anomaly_test: ok\n'
