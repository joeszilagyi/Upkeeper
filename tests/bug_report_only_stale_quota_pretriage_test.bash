#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-bug-report-stale-quota.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

write_quota_snapshot() {
  local session_file="$1"
  local model="$2"
  local primary_reset_offset="$3"
  local secondary_reset_offset="$4"

  mkdir -p "$(dirname -- "$session_file")"
  python3 - "$session_file" "$model" "$primary_reset_offset" "$secondary_reset_offset" <<'PY'
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
model = sys.argv[2]
primary_reset_offset = int(sys.argv[3])
secondary_reset_offset = int(sys.argv[4])
now = int(time.time())
event_timestamp = datetime.fromtimestamp(now, timezone.utc).isoformat().replace("+00:00", "Z")
rows = [
    {"type": "turn_context", "payload": {"model": model}},
    {
        "timestamp": event_timestamp,
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "rate_limits": {
                "limit_id": f"validation-{model}",
                "limit_name": f"{model} validation",
                "plan_type": "validation",
                "rate_limit_reached_type": None,
                "primary": {
                    "used_percent": 10.0,
                    "window_minutes": 300,
                    "resets_at": now + primary_reset_offset,
                },
                "secondary": {
                    "used_percent": 10.0,
                    "window_minutes": 10080,
                    "resets_at": now + secondary_reset_offset,
                },
            },
        },
    },
]
with path.open("w", encoding="utf-8") as handle:
    for row in rows:
        print(json.dumps(row, separators=(",", ":")), file=handle)
PY
}

test_bug_report_only_stale_quota_stop_leaves_local_custody_without_fallback() {
  local session_file output rc draft_file obligation_file last_run_output lock_dir

  session_file="$TEST_TMP_ROOT/codex-home/sessions/2026/06/05/session.jsonl"
  lock_dir="$PROJECT_ROOT/runtime/upkeeper-test-active-locks/bug-report-stale-quota-$$.lock"
  write_quota_snapshot "$session_file" "gpt-5.3-codex-spark" "-3600" "-7200"

  set +e
  output="$(
    CODEX_HOME="$TEST_TMP_ROOT/codex-home" \
      CODEX_LOG_FILE="$TEST_TMP_ROOT/Upkeeper.log" \
      CODEX_TRANSCRIPT_DIR="$TEST_TMP_ROOT/transcripts" \
      CODEX_ACTIVE_LOCK_DIR="$lock_dir" \
      CODEX_WRAPPER_HEALTH_STATE_DIR="$TEST_TMP_ROOT/health" \
      CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$TEST_TMP_ROOT/startup-gates" \
      CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
      CODEX_TERMINAL_VERBOSITY=quiet \
      CODEX_MODEL="gpt-5.3-codex-spark" \
      CODEX_REASONING_EFFORT="xhigh" \
      CODEX_MODE="--sandbox workspace-write" \
      CODEX_SESSION_SCAN_LIMIT=20 \
      UPKEEPER_CONFIG_DISABLE=1 \
      UPKEEPER_DRY_RUN=1 \
      UPKEEPER_AUTOMATION_LEDGER_DIR="$TEST_TMP_ROOT/automation-ledger" \
      UPKEEPER_OBLIGATION_DIR="$TEST_TMP_ROOT/obligations" \
      UPKEEPER_BUG_REPORT_DRAFT_DIR="$TEST_TMP_ROOT/bug-report-drafts" \
      "$PROJECT_ROOT/Upkeeper" --max-cover --bug-report-only --target-file=Upkeeper
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 75 ]] || fail "bug-report-only stale quota run exited $rc, expected 75"
  grep -Fq "reason=QUOTA_STALE_SNAPSHOT_BEFORE_TRIAGE" "$TEST_TMP_ROOT/Upkeeper.log" ||
    fail "quota stale pretriage run did not write the quota-specific cycle.exit reason"
  if grep -Fq "fallback.start" "$TEST_TMP_ROOT/Upkeeper.log"; then
    fail "quota stale pretriage run unexpectedly launched fallback"
  fi
  if grep -Fq "fallback.finish" "$TEST_TMP_ROOT/Upkeeper.log"; then
    fail "quota stale pretriage run unexpectedly finished fallback"
  fi
  grep -Fq "quota.pretriage_custody action=local_issue_ready_draft" "$TEST_TMP_ROOT/Upkeeper.log" ||
    fail "quota stale pretriage run did not log local custody"
  grep -Fq "parent_stop_outcome=skipped_" "$TEST_TMP_ROOT/Upkeeper.log" ||
    fail "quota stale pretriage run did not preserve parent-stop outcome"

  draft_file="$(find "$TEST_TMP_ROOT/bug-report-drafts" -maxdepth 1 -type f -name '*.md' | sort | head -n 1)"
  [[ -n "$draft_file" && -f "$draft_file" ]] || fail "quota stale pretriage run did not write a local draft"
  grep -Fq 'Title: Bug-report-only quota preflight stopped before target triage on stale snapshot evidence' "$draft_file" ||
    fail "quota stale pretriage draft had the wrong title"
  grep -Fq 'wrapper reason: QUOTA_STALE_SNAPSHOT_BEFORE_TRIAGE' "$draft_file" ||
    fail "quota stale pretriage draft did not preserve the wrapper reason"

  obligation_file="$(find "$TEST_TMP_ROOT/obligations/open" -maxdepth 1 -type f -name '*.json' | sort | head -n 1)"
  [[ -n "$obligation_file" && -f "$obligation_file" ]] || fail "quota stale pretriage run did not write an automation obligation"
  [[ "$(jq -r '.reason' "$obligation_file")" == "QUOTA_STALE_SNAPSHOT_BEFORE_TRIAGE" ]] ||
    fail "quota stale pretriage obligation has the wrong reason"
  [[ "$(jq -r '.summary' "$obligation_file")" == "Upkeeper report-only quota preflight stopped before target triage on stale snapshot evidence (exit 75)" ]] ||
    fail "quota stale pretriage obligation has the wrong summary"

  last_run_output="$(
    CODEX_HOME="$TEST_TMP_ROOT/codex-home" \
      CODEX_LOG_FILE="$TEST_TMP_ROOT/Upkeeper.log" \
      CODEX_TRANSCRIPT_DIR="$TEST_TMP_ROOT/transcripts" \
      CODEX_ACTIVE_LOCK_DIR="$lock_dir" \
      CODEX_WRAPPER_HEALTH_STATE_DIR="$TEST_TMP_ROOT/health" \
      CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$TEST_TMP_ROOT/startup-gates" \
      CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
      CODEX_TERMINAL_VERBOSITY=quiet \
      CODEX_MODEL="gpt-5.3-codex-spark" \
      CODEX_REASONING_EFFORT="xhigh" \
      CODEX_MODE="--sandbox workspace-write" \
      CODEX_SESSION_SCAN_LIMIT=20 \
      UPKEEPER_CONFIG_DISABLE=1 \
      UPKEEPER_AUTOMATION_LEDGER_DIR="$TEST_TMP_ROOT/automation-ledger" \
      UPKEEPER_OBLIGATION_DIR="$TEST_TMP_ROOT/obligations" \
      "$PROJECT_ROOT/Upkeeper" --last-run
  )"
  [[ "$last_run_output" == *"reason: QUOTA_STALE_SNAPSHOT_BEFORE_TRIAGE"* ]] ||
    fail "last-run summary did not preserve the quota-specific reason"
}

test_bug_report_only_stale_quota_stop_leaves_local_custody_without_fallback
printf 'bug_report_only_stale_quota_pretriage_test: ok\n'
