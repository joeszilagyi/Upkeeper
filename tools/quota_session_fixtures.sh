#!/usr/bin/env bash
# Named fake Codex session/quota JSONL fixtures for local validation only.
#
# All writers require an explicit destination path under a caller-owned temp
# tree. They never inspect the operator's real CODEX_HOME and never launch
# Codex; callers decide which temp CODEX_HOME should contain the resulting
# sessions/ files.

upkeeper_fixture_write_quota_jsonl() {
  local scenario="$1"
  local session_file="$2"
  local model="${3:-gpt-5.5}"
  local limit_prefix="${4:-validation}"
  local plan_type="${5:-validation}"
  local primary_reset_offset="${6:-3600}"
  local secondary_reset_offset="${7:-86400}"

  python3 - "$scenario" "$session_file" "$model" "$limit_prefix" "$plan_type" "$primary_reset_offset" "$secondary_reset_offset" <<'PY'
import json
import math
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

scenario, path_text, model, limit_prefix, plan_type, primary_offset, secondary_offset = sys.argv[1:8]
path = Path(path_text)
path.parent.mkdir(parents=True, exist_ok=True)
if "sessions" in path.parts:
    session_root = Path(*path.parts[: path.parts.index("sessions") + 1])
    session_root.chmod(0o700)

now = int(time.time())
event_timestamp = datetime.fromtimestamp(now, timezone.utc).isoformat().replace("+00:00", "Z")
primary_reset = now + int(primary_offset)
secondary_reset = now + int(secondary_offset)


def token_count_row(
    *,
    row_model=model,
    reached_type=None,
    primary_used=10.0,
    secondary_used=10.0,
    primary_resets_at=primary_reset,
    secondary_resets_at=secondary_reset,
):
    return {
        "timestamp": event_timestamp,
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "rate_limits": {
                "limit_id": f"{limit_prefix}-{row_model}",
                "limit_name": f"{row_model} {limit_prefix} fixture",
                "plan_type": plan_type,
                "rate_limit_reached_type": reached_type,
                "primary": {
                    "used_percent": primary_used,
                    "window_minutes": 300,
                    "resets_at": primary_resets_at,
                },
                "secondary": {
                    "used_percent": secondary_used,
                    "window_minutes": 10080,
                    "resets_at": secondary_resets_at,
                },
            },
        },
    }


rows = [{"type": "turn_context", "payload": {"model": model}}]
raw_lines = []

if scenario == "valid_current_session_snapshot":
    rows.append(token_count_row())
elif scenario == "stale_quota_snapshot":
    rows.append(token_count_row(primary_resets_at=now - 3600, secondary_resets_at=now - 60))
elif scenario == "wrong_model_bucket":
    wrong_model = f"{model}-other"
    rows[0] = {"type": "turn_context", "payload": {"model": wrong_model}}
    rows.append(token_count_row(row_model=wrong_model))
elif scenario == "malformed_jsonl_near_valid_records":
    raw_lines.append("not-jsonl")
    rows.extend(
        [
            {"type": "event_msg", "payload": "not-an-object"},
            token_count_row(),
            {"type": "event_msg", "payload": {"type": "turn_aborted", "reason": "rate limit / retry"}},
        ]
    )
elif scenario == "empty_transcript_session_evidence":
    rows.append({"timestamp": event_timestamp, "type": "event_msg", "payload": {"type": "task_complete", "last_agent_message": None}})
elif scenario == "nonfinite_reset_window":
    rows.append(token_count_row(primary_resets_at=math.nan))
elif scenario == "missing_required_fields":
    rows.append(
        {
            "timestamp": event_timestamp,
            "type": "event_msg",
            "payload": {
                "type": "token_count",
                "rate_limits": {
                    "limit_id": f"{limit_prefix}-{model}",
                    "limit_name": f"{model} {limit_prefix} fixture",
                    "plan_type": plan_type,
                    "rate_limit_reached_type": None,
                    "primary": {"used_percent": 10.0},
                },
            },
        }
    )
elif scenario == "usage_limit_session_snapshot":
    rows.append(token_count_row(reached_type="primary", primary_used=100.0, secondary_used=10.0))
    rows.append({"timestamp": event_timestamp, "type": "event_msg", "payload": {"type": "task_complete", "last_agent_message": None}})
else:
    raise SystemExit(f"unknown quota/session fixture scenario: {scenario}")

with path.open("w", encoding="utf-8") as handle:
    for raw in raw_lines:
        print(raw, file=handle)
    for row in rows:
        print(json.dumps(row, separators=(",", ":")), file=handle)
PY
}

upkeeper_fixture_write_valid_current_session_snapshot() {
  upkeeper_fixture_write_quota_jsonl valid_current_session_snapshot "$@"
}

upkeeper_fixture_write_stale_quota_snapshot() {
  upkeeper_fixture_write_quota_jsonl stale_quota_snapshot "$@"
}

upkeeper_fixture_write_wrong_model_bucket() {
  upkeeper_fixture_write_quota_jsonl wrong_model_bucket "$@"
}

upkeeper_fixture_write_malformed_jsonl_near_valid_records() {
  upkeeper_fixture_write_quota_jsonl malformed_jsonl_near_valid_records "$@"
}

upkeeper_fixture_write_empty_transcript_session_evidence() {
  upkeeper_fixture_write_quota_jsonl empty_transcript_session_evidence "$@"
}

upkeeper_fixture_write_nonfinite_reset_window() {
  upkeeper_fixture_write_quota_jsonl nonfinite_reset_window "$@"
}

upkeeper_fixture_write_missing_required_fields() {
  upkeeper_fixture_write_quota_jsonl missing_required_fields "$@"
}

upkeeper_fixture_write_usage_limit_session_snapshot() {
  upkeeper_fixture_write_quota_jsonl usage_limit_session_snapshot "$@"
}
