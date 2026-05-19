# Codex final response markers are the contract between the model and wrapper.
# Session parsing provides diagnostics for missing markers so operators can
# diagnose turn shape issues without trusting natural-language inference.
recover_status_marker_from_review_outcome() {
  local last_message_file="$1"
  local codex_exit_value="$2"
  local task_complete_last_agent_message="$3"
  local summary_json
  local recovery_outcome recovery_selected_file recovery_findings recovery_changes recovery_verification
  local recovered_marker

  [[ "$codex_exit_value" == "0" ]] || return 1
  [[ "$task_complete_last_agent_message" == "present" ]] || return 1
  [[ -n "$last_message_file" && -f "$last_message_file" ]] || return 1

  summary_json="$(review_report_summary_json "$last_message_file")" || return 1
  eval "$(review_summary_assignments "$summary_json" recovery)"
  case "$recovery_outcome" in
    REVIEWED_AND_FIXED|REVIEWED_AND_REPORTED|REVIEWED_CLEAN)
      recovered_marker="WORK_DONE"
      ;;
    STOPPED_ON_BLOCKER)
      recovered_marker="BLOCKED"
      ;;
    *)
      return 1
      ;;
  esac

  printf '%s\t%s\t%s\n' "$recovered_marker" "$recovery_outcome" "$recovery_selected_file"
}

recover_status_marker_from_blocker_request() {
  local last_message_file="$1"
  local codex_exit_value="$2"
  local task_complete_last_agent_message="$3"

  [[ "$codex_exit_value" == "0" ]] || return 1
  [[ "$task_complete_last_agent_message" == "present" ]] || return 1
  [[ -n "$last_message_file" && -f "$last_message_file" ]] || return 1

  python3 - "$last_message_file" <<'PY'
from pathlib import Path
import sys

try:
    text = Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace').lower()
except OSError:
    raise SystemExit(1)
question = any(needle in text for needle in (
    'i need your direction',
    'should i proceed',
    'do you want a different action',
    'how would you like to proceed',
))
stopped = any(needle in text for needle in (
    'stopped immediately',
    'per your agent',
    'per your agents',
    'unexpected modifications',
    'unexpected changes',
    'i have stopped',
    "i've stopped",
))
if question and stopped:
    print('BLOCKED\toperator_direction_request\t')
else:
    raise SystemExit(1)
PY
}

parse_status_marker() {
  local last_message_file="$1"
  local analysis
  analysis="$(while_marker_analysis_json "$last_message_file")"
  json_field "$analysis" '.accepted_marker'
}

resolved_status_marker_from_analysis() {
  local analysis="$1"
  local codex_exit="$2"
  local task_complete_last_agent_message="$3"
  local accepted candidate candidate_rejection_reason

  accepted="$(json_field "$analysis" '.accepted_marker')"
  if [[ "$accepted" == "NO_CHANGES" ]]; then
    accepted="WORK_DONE"
  fi
  if [[ -n "$accepted" ]]; then
    printf '%s' "$accepted"
    return 0
  fi
  candidate="$(json_field "$analysis" '.candidate_marker')"
  candidate_rejection_reason="$(json_field "$analysis" '.candidate_rejection_reason')"
  if [[ "$candidate" == "NO_CHANGES" ]]; then
    candidate="WORK_DONE"
  fi
  if [[ -n "$candidate" && "$candidate_rejection_reason" == "markdown_backticks" ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  if [[ -n "$candidate" && "$candidate_rejection_reason" == "trailing_content_after_marker" ]]; then
    printf '%s' "$candidate"
    return 0
  fi
}

parse_session_end_state() {
  local session_file="$1"
  [[ -n "$session_file" && -f "$session_file" ]] || {
    printf 'none'
    return 0
  }

  python3 - "$session_file" <<'PY'
import json
import re
import sys

path = sys.argv[1]
state = "none"


def event_payload(item):
    if not isinstance(item, dict) or item.get("type") != "event_msg":
        return None
    payload = item.get("payload")
    return payload if isinstance(payload, dict) else None


def reason_token(value):
    if not isinstance(value, str):
        return "unknown"
    token = re.sub(r"[^A-Za-z0-9_.:-]+", "_", value.strip()).strip("_")
    return token[:120] or "unknown"


try:
    with open(path, "r", encoding="utf-8", errors="ignore") as handle:
        for raw_line in handle:
            try:
                item = json.loads(raw_line)
            except json.JSONDecodeError:
                continue
            payload = event_payload(item)
            if payload is None:
                continue
            if payload.get("type") == "turn_aborted":
                reason = reason_token(payload.get("reason"))
                state = f"turn_aborted:{reason}"
            elif (
                payload.get("type") == "task_complete"
                and "last_agent_message" in payload
                and payload.get("last_agent_message") is None
            ):
                if state == "none":
                    state = "no_agent_message"
except OSError:
    pass

print(state)
PY
}

backend_usage_limit_summary_from_transcript() {
  local transcript_file="$1"
  [[ -n "$transcript_file" && -f "$transcript_file" ]] || return 1

  python3 - "$transcript_file" <<'PY'
import calendar
from datetime import datetime
from pathlib import Path
import re
import sys
import time

path = Path(sys.argv[1])
try:
    with path.open("rb") as handle:
        handle.seek(0, 2)
        size = handle.tell()
        handle.seek(max(0, size - 256 * 1024))
        data = handle.read()
except OSError:
    raise SystemExit(1)

text = data.decode("utf-8", errors="replace")
patterns = [
    re.compile(
        r"You(?:'ve| have) hit your usage limit for\s+"
        r"([A-Za-z0-9._:-]+)\.\s+"
        r"Switch to another model now, or try again at\s+([^\n.]+)\.",
        re.IGNORECASE,
    ),
]


def parse_local_epoch(value: str) -> int:
    cleaned = re.sub(r"\b(\d{1,2})(st|nd|rd|th)\b", r"\1", value.strip(), flags=re.I)
    cleaned = re.sub(r"\s+", " ", cleaned)
    formats = (
        "%B %d, %Y %I:%M %p",
        "%b %d, %Y %I:%M %p",
        "%B %d, %Y %H:%M",
        "%b %d, %Y %H:%M",
    )
    for fmt in formats:
        try:
            parsed = datetime.strptime(cleaned, fmt)
        except ValueError:
            continue
        return int(time.mktime(parsed.timetuple()))
    try:
        return int(calendar.timegm(datetime.fromisoformat(cleaned).timetuple()))
    except ValueError:
        return 0


matches = []
for pattern in patterns:
    matches.extend(pattern.findall(text))

if not matches:
    raise SystemExit(1)

model, reset_text = matches[-1]
reset_text = re.sub(r"\s+", " ", reset_text.strip())
reset_epoch = parse_local_epoch(reset_text)
print(f"{model}\t{reset_text}\t{reset_epoch}")
PY
}

session_diagnostics_json() {
  local session_file="$1"
  [[ -n "$session_file" && -f "$session_file" ]] || {
    printf '{"agent_message_count":0,"tool_call_count":0,"tool_result_count":0,"task_complete_last_agent_message":"missing","last_rate_limit_reached_type":"unknown","last_rate_limit_limit_id":"unknown","last_rate_limit_limit_name":"unknown","last_rate_limit_plan_type":"unknown","last_rate_limit_primary_used_percent":"unknown","last_rate_limit_secondary_used_percent":"unknown"}'
    return 0
  }

  python3 - "$session_file" <<'PY'
import json
import sys

path = sys.argv[1]
summary = {
    "agent_message_count": 0,
    "tool_call_count": 0,
    "tool_result_count": 0,
    "task_complete_last_agent_message": "missing",
    "last_rate_limit_reached_type": "unknown",
    "last_rate_limit_limit_id": "unknown",
    "last_rate_limit_limit_name": "unknown",
    "last_rate_limit_plan_type": "unknown",
    "last_rate_limit_primary_used_percent": "unknown",
    "last_rate_limit_secondary_used_percent": "unknown",
}


def object_or_empty(value):
    return value if isinstance(value, dict) else {}


try:
    with open(path, "r", encoding="utf-8", errors="ignore") as handle:
        for raw_line in handle:
            try:
                item = json.loads(raw_line)
            except json.JSONDecodeError:
                continue
            if not isinstance(item, dict):
                continue

            payload = object_or_empty(item.get("payload"))
            payload_type = payload.get("type")

            if item.get("type") == "response_item":
                if payload_type == "message" and payload.get("role") == "assistant":
                    summary["agent_message_count"] += 1
                elif payload_type == "function_call":
                    summary["tool_call_count"] += 1
                elif payload_type == "function_call_output":
                    summary["tool_result_count"] += 1
                continue

            if item.get("type") != "event_msg":
                continue

            if payload_type == "task_complete" and "last_agent_message" in payload:
                last_agent_message = payload.get("last_agent_message")
                if last_agent_message is None:
                    summary["task_complete_last_agent_message"] = "null"
                elif isinstance(last_agent_message, str) and last_agent_message.strip():
                    summary["task_complete_last_agent_message"] = "present"
                else:
                    summary["task_complete_last_agent_message"] = "blank"
            elif payload_type == "token_count":
                rate_limits = payload.get("rate_limits")
                if not isinstance(rate_limits, dict) or not rate_limits:
                    continue
                primary = object_or_empty(rate_limits.get("primary"))
                secondary = object_or_empty(rate_limits.get("secondary"))
                summary["last_rate_limit_reached_type"] = rate_limits.get("rate_limit_reached_type")
                if summary["last_rate_limit_reached_type"] is None:
                    summary["last_rate_limit_reached_type"] = "null"
                summary["last_rate_limit_limit_id"] = rate_limits.get("limit_id") or "unknown"
                summary["last_rate_limit_limit_name"] = rate_limits.get("limit_name") or "unknown"
                summary["last_rate_limit_plan_type"] = rate_limits.get("plan_type")
                if summary["last_rate_limit_plan_type"] is None:
                    summary["last_rate_limit_plan_type"] = "null"
                summary["last_rate_limit_primary_used_percent"] = primary.get("used_percent", "unknown")
                summary["last_rate_limit_secondary_used_percent"] = secondary.get("used_percent", "unknown")
except OSError:
    pass

print(json.dumps(summary, sort_keys=True))
PY
}
