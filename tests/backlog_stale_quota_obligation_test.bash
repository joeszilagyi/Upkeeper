#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-backlog-stale-quota.XXXXXX")"
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

BACKLOG_SOURCE_ONLY=1
BACKLOG_CODEX_MODEL="gpt-stale-quota"
BACKLOG_CODEX_REASONING_EFFORT="high"
BACKLOG_QUOTA_GUARDRAIL_BYPASS=1
BACKLOG_OBLIGATION_DIR="$TEST_TMP_ROOT/obligations"
BACKLOG_STATE_ROOT="$TEST_TMP_ROOT/state"
CODEX_HOME_DIR="$TEST_TMP_ROOT/codex-home"
CODEX_SESSION_SCAN_LIMIT=20
LOG_FILE="$TEST_TMP_ROOT/Upkeeper.log"
export \
  BACKLOG_SOURCE_ONLY \
  BACKLOG_CODEX_MODEL \
  BACKLOG_CODEX_REASONING_EFFORT \
  BACKLOG_QUOTA_GUARDRAIL_BYPASS \
  BACKLOG_OBLIGATION_DIR \
  BACKLOG_STATE_ROOT \
  CODEX_HOME_DIR \
  CODEX_SESSION_SCAN_LIMIT \
  LOG_FILE

source "$ROOT_DIR/orchestration/backlog.sh"

test_stale_quota_evidence_opens_updates_and_retires_obligation() {
  local session_file output rc record_count record_file resolved_count

  session_file="$CODEX_HOME_DIR/sessions/2026/05/24/session.jsonl"
  write_quota_snapshot "$session_file" "$BACKLOG_CODEX_MODEL" -3600 86400

  if output="$(quota_preflight_allows_backlog_run 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  [[ "$rc" -eq 0 ]] || fail "stale quota bypass exited $rc, expected 0"
  grep -Fq "recorded_non_perfect_health=1" <<<"$output" ||
    fail "stale quota bypass did not report non-perfect health custody"
  grep -Fq "obligation_id=stale-quota-" <<<"$output" ||
    fail "stale quota bypass did not report the obligation id"

  record_count="$(find "$BACKLOG_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$record_count" == "1" ]] || fail "stale quota evidence wrote $record_count obligations, expected 1"
  record_file="$(find "$BACKLOG_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | sort | head -n 1)"
  [[ "$(jq -r '.kind' "$record_file")" == "stale_quota_evidence" ]] ||
    fail "stale quota obligation has wrong kind"
  [[ "$(jq -r '.reason' "$record_file")" == "STALE_QUOTA_EVIDENCE_AFTER_RESET" ]] ||
    fail "stale quota obligation has wrong reason"
  [[ "$(jq -r '.evidence.primary_reset_expired' "$record_file")" == "true" ]] ||
    fail "stale quota obligation did not preserve primary_reset_expired"
  [[ "$(jq -r '.evidence.secondary_bucket_current' "$record_file")" == "true" ]] ||
    fail "stale quota obligation did not preserve current secondary bucket"
  [[ "$(jq -r '.evidence.source_path_redacted' "$record_file")" == "true" ]] ||
    fail "stale quota obligation did not redact source path"

  if output="$(quota_preflight_allows_backlog_run 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  [[ "$rc" -eq 0 ]] || fail "duplicate stale quota bypass exited $rc, expected 0"
  record_count="$(find "$BACKLOG_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$record_count" == "1" ]] || fail "duplicate stale quota evidence wrote $record_count obligations, expected 1"
  [[ "$(jq -r '.seen_count' "$record_file")" == "2" ]] ||
    fail "duplicate stale quota evidence did not update seen_count"

  write_quota_snapshot "$session_file" "$BACKLOG_CODEX_MODEL" 3600 86400
  if output="$(quota_preflight_allows_backlog_run 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  [[ "$rc" -eq 0 ]] || fail "current quota evidence exited $rc, expected 0"
  grep -Fq "stale quota evidence retired count=1" <<<"$output" ||
    fail "current quota evidence did not retire stale quota obligation"
  record_count="$(find "$BACKLOG_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$record_count" == "0" ]] || fail "retired stale quota obligation left $record_count open records"
  resolved_count="$(find "$BACKLOG_OBLIGATION_DIR/resolved" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$resolved_count" == "1" ]] || fail "retired stale quota obligation wrote $resolved_count resolved records, expected 1"
}

test_stale_quota_evidence_opens_updates_and_retires_obligation
printf 'backlog_stale_quota_obligation_test: ok\n'
