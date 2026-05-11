marker_analysis_json() {
  local last_message_file="$1"
  local marker_prefix="$2"
  local allowed_markers="$3"

  if [[ ! -f "$last_message_file" ]]; then
    printf '{"accepted_marker":"","candidate_marker":"","candidate_line":"","candidate_rejection_reason":""}'
    return 0
  fi

  python3 - "$last_message_file" "$marker_prefix" "$allowed_markers" <<'PY'
import json
import sys

path = sys.argv[1]
prefix = sys.argv[2]
allowed = [item for item in sys.argv[3].split() if item]
cores = {f"{prefix}: {status}": status for status in allowed}
result = {
    "accepted_marker": "",
    "candidate_marker": "",
    "candidate_line": "",
    "candidate_rejection_reason": "",
}


def decorated_reason(line: str, core: str) -> str:
    if line.startswith("```") and line.endswith("```") and line[3:-3].strip() == core:
        return "markdown_code_fence"
    if line in {f"`{core}`", f"``{core}``"}:
        return "markdown_backticks"
    if len(line) >= 2 and line[0] == line[-1] and line[0] in {"'", '"'}:
        if line[1:-1].strip() == core:
            return "quoted_marker"
    if line != core and line.rstrip(".;!?,") == core:
        return "trailing_punctuation"
    return ""


in_code_fence = False

with open(path, "r", encoding="utf-8", errors="replace") as handle:
    for raw_line in handle:
        line = raw_line.rstrip("\r\n").strip()
        if line.startswith("```"):
            for core, status in cores.items():
                if core in line:
                    reason = decorated_reason(line, core) or "markdown_code_fence"
                    result["candidate_marker"] = status
                    result["candidate_line"] = line
                    result["candidate_rejection_reason"] = reason
            in_code_fence = not in_code_fence
            continue
        for core, status in cores.items():
            if line == core and in_code_fence:
                result["candidate_marker"] = status
                result["candidate_line"] = line
                result["candidate_rejection_reason"] = "markdown_code_fence"
            elif line == core:
                result["accepted_marker"] = status
            elif core in line:
                reason = decorated_reason(line, core)
                if reason:
                    result["candidate_marker"] = status
                    result["candidate_line"] = line
                    result["candidate_rejection_reason"] = reason
                elif not result["candidate_line"]:
                    result["candidate_marker"] = status
                    result["candidate_line"] = line
                    result["candidate_rejection_reason"] = "decorated_marker"

print(json.dumps(result, separators=(",", ":")))
PY
}

while_marker_analysis_json() {
  marker_analysis_json "$1" "UPKEEPER_STATUS" "WORK_DONE NO_BACKEND_TASK BLOCKED"
}

postmortem_marker_analysis_json() {
  marker_analysis_json "$1" "CODEX_POSTMORTEM_STATUS" "REPORT_WRITTEN HARDENING_DONE BLOCKED"
}

parse_postmortem_marker() {
  local last_message_file="$1"
  local analysis accepted candidate reason
  analysis="$(postmortem_marker_analysis_json "$last_message_file")"
  accepted="$(json_field "$analysis" '.accepted_marker')"
  candidate="$(json_field "$analysis" '.candidate_marker')"
  reason="$(json_field "$analysis" '.candidate_rejection_reason')"
  if [[ -n "$accepted" ]]; then
    printf '%s' "$accepted"
  fi
}

review_report_summary_json() {
  local last_message_file="$1"

  python3 - "$last_message_file" <<'PY'
import json
import re
import sys

path = sys.argv[1]
empty = {
    "outcome": "",
    "selected_file": "",
    "findings": "",
    "changes": "",
    "verification": "",
}

try:
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        text = handle.read()
except OSError:
    print(json.dumps(empty, separators=(",", ":")))
    raise SystemExit(0)

lines = [line.strip() for line in text.splitlines()]


def clean(value, max_len=700):
    value = re.sub(r"\s+", " ", value.strip())
    if len(value) > max_len:
        value = value[: max_len - 15].rstrip() + "...<truncated>"
    return value


def normalized(line):
    value = line.strip()
    value = re.sub(r"^[#>*\-\d\.\s`]+", "", value)
    value = value.strip("`*: ")
    return re.sub(r"\s+", " ", value).lower()


def compact_items(items, max_items=8, max_len=900):
    cleaned = []
    for item in items:
        item = item.strip()
        if not item:
            continue
        if item.startswith("UPKEEPER_STATUS:") or item.startswith("CODEX_POSTMORTEM_STATUS:"):
            continue
        item = re.sub(r"^[-*]\s+", "", item)
        item = re.sub(r"^\d+[.)]\s+", "", item)
        item = item.strip("` ")
        if item:
            cleaned.append(item)
        if len(cleaned) >= max_items:
            break
    return clean("; ".join(cleaned), max_len=max_len)


def no_change_summary(value):
    value = re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()
    if not value:
        return False
    return (
        value in {"none", "n a", "not applicable"}
        or value.startswith("no changes")
        or value.startswith("no fixes")
        or value.startswith("no code changes")
        or value.startswith("nothing changed")
    )


def selected_file_from_source(source):
    markdown_link = re.search(r"\]\(([^)]+)\)", source)
    backtick_path = re.search(r"`([^`]+)`", source)
    if markdown_link:
        value = markdown_link.group(1).strip("<>").split(":", 1)[0]
    elif backtick_path:
        value = backtick_path.group(1)
    elif ":" in source:
        value = source.split(":", 1)[1].strip()
    else:
        value = source.strip("- ")
    value = clean(value, 240)
    if re.fullmatch(r"\d+(?:\.\d+)?", value):
        return ""
    if re.match(r"^(epoch|age|mtime|hash)\b", value.lower()):
        return ""
    return value


def capture_section(names):
    known_headers = (
        "review run",
        "file selection",
        "selected file",
        "file selected",
        "target file",
        "prompts run",
        "prompts applied",
        "findings",
        "fixes",
        "fixes found",
        "fixes implemented",
        "fixes applied",
        "implemented fix",
        "implemented fixes",
        "applied change",
        "applied changes",
        "changes applied",
        "changes proposed",
        "changes",
        "test results",
        "required persistence verification",
        "verification",
        "verification done",
        "outcome",
        "final status",
        "final status marker",
    )
    capturing = False
    items = []
    for line in lines:
        norm = normalized(line)
        if any(norm.startswith(name) for name in names):
            capturing = True
            if ":" in line:
                rest = line.split(":", 1)[1].strip()
                if rest:
                    items.append(rest)
            continue
        if not capturing:
            continue
        if not line:
            continue
        norm = normalized(line)
        if re.match(r"p(?:[1-9]|1[0-9]|2[0-3])\b", norm):
            break
        if re.search(r"\b(REVIEWED_AND_FIXED|REVIEWED_AND_REPORTED|REVIEWED_CLEAN|STOPPED_ON_BLOCKER)\b", line):
            break
        if any(norm.startswith(header) for header in known_headers):
            break
        if line.startswith(("UPKEEPER_STATUS:", "UPKEEPER_LOG_REVIEW:")):
            break
        items.append(line)
        if len(items) >= 10:
            break
    return compact_items(items)


outcome = ""
for line in lines:
    match = re.search(r"\b(REVIEWED_AND_FIXED|REVIEWED_AND_REPORTED|REVIEWED_CLEAN|STOPPED_ON_BLOCKER)\b", line)
    if match:
        outcome = match.group(1)
        break

selected_file = ""
for line in lines:
    match = re.search(r"\b(?:REVIEWED_AND_FIXED|REVIEWED_AND_REPORTED|REVIEWED_CLEAN|STOPPED_ON_BLOCKER)\b\s+for\s+(.+)", line)
    if not match:
        continue
    selected_file = selected_file_from_source(match.group(1))
    if selected_file:
        break

for index, line in enumerate(lines):
    if selected_file:
        break
    norm = normalized(line)
    if norm.startswith(("selected target baseline", "selected file baseline", "target baseline")):
        continue
    selected_label = norm.startswith(
        (
            "selected file",
            "file selected",
            "target file",
            "selected target",
            "target selected",
            "review target",
        )
    ) or re.match(
        r"selected\b.*\b(file|target)\b",
        norm,
    ) or re.match(
        r"selected\s+[`[]",
        line,
        re.I,
    )
    if not selected_label:
        continue
    source = line
    rest_after_colon = source.split(":", 1)[1].strip() if ":" in source else ""
    has_inline_target = re.search(r"`[^`]+`|\]\([^)]+\)", source)
    if not has_inline_target and (":" not in source or not rest_after_colon) and index + 1 < len(lines):
        for candidate in lines[index + 1 : index + 5]:
            if candidate:
                source = candidate
                break
    selected_file = selected_file_from_source(source)
    break

findings = capture_section(("findings",))
changes = capture_section(
    (
        "fixes",
        "fixes found",
        "fixes implemented",
        "fixes applied",
        "implemented fix",
        "implemented fixes",
        "applied change",
        "applied changes",
        "changes applied",
        "bug report",
        "bug reports",
        "issue filed",
        "issues filed",
        "report filed",
        "reports filed",
    )
)
verification = capture_section(
    (
        "required persistence verification",
        "test results",
        "verification",
    )
)
if outcome != "REVIEWED_AND_FIXED" and no_change_summary(changes):
    changes = ""

if outcome == "REVIEWED_AND_FIXED" and not changes:
    fallback = []
    for line in lines:
        lowered = line.lower()
        norm = normalized(line)
        if line.startswith("UPKEEPER_STATUS:"):
            continue
        if re.search(r"\b(REVIEWED_AND_FIXED|REVIEWED_AND_REPORTED|REVIEWED_CLEAN|STOPPED_ON_BLOCKER)\b", line):
            continue
        if re.match(r"p(?:[1-9]|1[0-9]|2[0-3])\b", norm):
            continue
        if norm.startswith(("findings", "target selection", "verification", "prompt set outcomes")):
            continue
        if no_change_summary(line):
            continue
        if "fix" in lowered or "change" in lowered:
            fallback.append(line)
    changes = compact_items(fallback)

print(
    json.dumps(
        {
            "outcome": outcome,
            "selected_file": selected_file,
            "findings": findings,
            "changes": changes,
            "verification": verification,
        },
        separators=(",", ":"),
    )
)
PY
}

review_pass_coverage_json() {
  local last_message_file="$1"
  [[ -f "$last_message_file" ]] || return 1
  python3 - "$last_message_file" <<'PY'
import json
import re
import sys

try:
    text = open(sys.argv[1], "r", encoding="utf-8", errors="replace").read()
except OSError:
    raise SystemExit(1)

present = set()
for raw_line in text.splitlines():
    line = raw_line.strip()
    line = re.sub(r"^(?:[-*+]\s*|\d+[.)]\s*)+", "", line)
    line = line.strip("`*_~> \t")
    match = re.match(
        r"^UPKEEPER_PASS_RESULT:\s+pass=P([1-9]|1[0-9]|2[0-3])\b",
        line,
        re.IGNORECASE,
    )
    if match:
        present.add(int(match.group(1)))

expected = set(range(1, 24))
missing = sorted(expected - present)
status = "complete" if not missing else "incomplete"
print(
    json.dumps(
        {
            "status": status,
            "expected": len(expected),
            "present": len(present),
            "missing": ",".join(f"P{value}" for value in missing) if missing else "none",
        },
        separators=(",", ":"),
    )
)
PY
}

prompt_pass_coverage_gate() {
  local last_message_file="$1"
  local pass_coverage_json pass_coverage_status pass_coverage_expected pass_coverage_present pass_coverage_missing
  local coverage_status coverage_expected coverage_present coverage_missing
  local should_log="${2:-1}"

  [[ "${CODEX_PROMPT_PASS:-}" == "all" ]] || return 1

  if pass_coverage_json="$(review_pass_coverage_json "$last_message_file")"; then
    eval "$(review_pass_coverage_assignments "$pass_coverage_json" coverage)"
    pass_coverage_status="$coverage_status"
    pass_coverage_expected="$coverage_expected"
    pass_coverage_present="$coverage_present"
    pass_coverage_missing="$coverage_missing"
    if [[ "$pass_coverage_status" == "complete" ]]; then
      if [[ "$should_log" == "1" ]]; then
        log_line "INFO" "review.pass_coverage prompt_pass=all status=$pass_coverage_status expected=$pass_coverage_expected present=$pass_coverage_present missing=$(shell_quote "$pass_coverage_missing")"
      fi
      return 0
    fi
    if [[ "$should_log" == "1" ]]; then
      log_line "WARN" "review.pass_coverage prompt_pass=all status=$pass_coverage_status expected=$pass_coverage_expected present=$pass_coverage_present missing=$(shell_quote "$pass_coverage_missing")"
    fi
    return 2
  fi

  if [[ "$should_log" == "1" ]]; then
    log_line "WARN" "review.pass_coverage prompt_pass=all status=unavailable expected=23 present=unknown missing=unknown"
  fi
  return 3
}

log_review_report_summary() {
  local last_message_file="$1"
  local status_marker_value="${2:-missing}"
  local codex_exit_value="${3:-unknown}"
  local summary_json outcome selected_file findings changes verification
  local summary_outcome summary_selected_file summary_findings summary_changes summary_verification
  local pass_coverage_json pass_coverage_status pass_coverage_expected pass_coverage_present pass_coverage_missing
  local coverage_status coverage_expected coverage_present coverage_missing

  summary_json="$(review_report_summary_json "$last_message_file")"
  eval "$(review_summary_assignments "$summary_json" summary)"
  outcome="$summary_outcome"
  selected_file="$summary_selected_file"
  findings="$summary_findings"
  changes="$summary_changes"
  verification="$summary_verification"

  if [[ -z "$outcome" && -z "$selected_file" && -z "$findings" && -z "$changes" && -z "$verification" ]]; then
    return 0
  fi

  [[ -n "$outcome" ]] || outcome="unknown"
  if [[ -z "$selected_file" && -n "${RUN_SELECTED_REVIEW_PATH:-}" ]]; then
    selected_file="$RUN_SELECTED_REVIEW_PATH"
  fi
  [[ -n "$selected_file" ]] || selected_file="unknown"
  log_line "INFO" "review.summary status_marker=${status_marker_value:-missing} review_outcome=$outcome selected_file=$(shell_quote "$selected_file") findings=$(shell_quote "$findings") changes=$(shell_quote "$changes") verification=$(shell_quote "$verification") codex_exit=$codex_exit_value"
  terminal_emit_progress "review completed outcome=$outcome status_marker=${status_marker_value:-missing} selected_file=$selected_file"
  terminal_emit_review_finale "$outcome" "$selected_file" "$findings" "$changes" "$verification"

  if [[ "$outcome" == "REVIEWED_AND_FIXED" || "$outcome" == "REVIEWED_AND_REPORTED" || ( "$outcome" == "unknown" && -n "$changes" ) ]]; then
    local terminal_findings="$findings"
    local terminal_changes="$changes"
    [[ "${#terminal_findings}" -le 260 ]] || terminal_findings="${terminal_findings:0:260}..."
    [[ "${#terminal_changes}" -le 260 ]] || terminal_changes="${terminal_changes:0:260}..."
    log_line "INFO" "review.fix_details review_outcome=$outcome selected_file=$(shell_quote "$selected_file") findings=$(shell_quote "$findings") changes=$(shell_quote "$changes")"
    if terminal_wants_verbose_output; then
      terminal_emit_progress "bugs/fixes found: ${terminal_findings:-none}; changes: ${terminal_changes:-none}"
    fi
  fi

  prompt_pass_coverage_gate "$last_message_file" 1 || true
}

terminal_emit_review_finale() {
  local outcome="$1"
  local selected_file="$2"
  local findings="$3"
  local changes="$4"
  local verification="$5"
  local terminal_findings="$findings"
  local terminal_changes="$changes"
  local terminal_verification="$verification"
  local mode
  local level="INFO"

  terminal_wants_full_output && return 0
  terminal_wants_silent_output && return 0
  mode="$(terminal_mode)"
  case "$mode" in
    basic|quiet|verbose|debug1)
      ;;
    *)
      return 0
      ;;
  esac

  [[ "${#terminal_findings}" -le 420 ]] || terminal_findings="${terminal_findings:0:420}..."
  [[ "${#terminal_changes}" -le 420 ]] || terminal_changes="${terminal_changes:0:420}..."
  [[ "${#terminal_verification}" -le 300 ]] || terminal_verification="${terminal_verification:0:300}..."

  if [[ "$outcome" == "STOPPED_ON_BLOCKER" ]]; then
    level="WARN"
  fi

  printf '%s [%s] Upkeeper: final review for %s -> %s\n' "$(timestamp_now)" "$level" "${selected_file:-unknown}" "${outcome:-unknown}" >&2
  if [[ -n "$terminal_findings" ]]; then
    printf '%s [%s] Upkeeper: what was wrong: %s\n' "$(timestamp_now)" "$level" "$terminal_findings" >&2
  elif [[ "$outcome" == "REVIEWED_AND_FIXED" && -n "$terminal_changes" ]]; then
    printf '%s [INFO] Upkeeper: what was wrong: see change summary\n' "$(timestamp_now)" >&2
  elif [[ "$outcome" == "REVIEWED_AND_REPORTED" && -n "$terminal_changes" ]]; then
    printf '%s [INFO] Upkeeper: what was wrong: see issue report summary\n' "$(timestamp_now)" >&2
  elif [[ "$outcome" == "REVIEWED_CLEAN" ]]; then
    printf '%s [INFO] Upkeeper: what was wrong: nothing found\n' "$(timestamp_now)" >&2
  fi
  if [[ -n "$terminal_changes" ]]; then
    printf '%s [INFO] Upkeeper: what changed: %s\n' "$(timestamp_now)" "$terminal_changes" >&2
  fi
  if [[ -n "$terminal_verification" ]]; then
    printf '%s [INFO] Upkeeper: verification: %s\n' "$(timestamp_now)" "$terminal_verification" >&2
  fi
}

current_cycle_log_review_present() {
  local last_message_file="$1"
  [[ -f "$last_message_file" ]] || return 1
  python3 - "$last_message_file" "$CYCLE_ID" "$LOG_FILE" "$STARTUP_ANOMALY_REASONS" <<'PY'
import hashlib
import re
import sys

try:
    current_cycle = sys.argv[2]
    log_path = sys.argv[3]
    reasons = sys.argv[4]
    text = open(sys.argv[1], "r", encoding="utf-8", errors="replace").read()
except OSError:
    raise SystemExit(1)

anomalies_expectation = "none"
if reasons and reasons != "unknown":
    anomalies_expectation = "listed"

cycle_pattern = re.compile(r"\bcycle={}\b".format(re.escape(current_cycle)))
cycle_log_lines = []
cycle_start_seen = False
cycle_exit_seen = False
run_start_seen = False
run_finish_seen = False

try:
    with open(log_path, "r", encoding="utf-8", errors="replace") as log_file:
        for line in log_file:
            if not cycle_pattern.search(line):
                continue
            cycle_log_lines.append(line)
            if "cycle.start" in line:
                cycle_start_seen = True
            if "cycle.exit" in line:
                cycle_exit_seen = True
            if "run.start" in line:
                run_start_seen = True
            if "run.finish" in line:
                run_finish_seen = True
except OSError:
    raise SystemExit(1)

if not cycle_log_lines:
    raise SystemExit(1)
if not (cycle_start_seen and cycle_exit_seen and run_start_seen and run_finish_seen):
    raise SystemExit(1)

cycle_log_sha = hashlib.sha256("".join(cycle_log_lines).encode("utf-8", "surrogateescape")).hexdigest()

in_code_fence = False
marker_index = -1
status_index = -1
match = None
pattern = re.compile(r"^UPKEEPER_LOG_REVIEW: CHECKED cycle=([^\s`]+) anomalies=(none|listed) log_sha256=([0-9a-f]{64})$")

for index, raw_line in enumerate(text.splitlines(), start=1):
    line = raw_line.rstrip("\r\n").strip()
    if line.startswith("```"):
        in_code_fence = not in_code_fence
        continue
    if in_code_fence:
        continue
    if line.startswith("UPKEEPER_STATUS:") and cycle_pattern.search(line):
        status_index = index
        continue
    if not line.startswith("UPKEEPER_LOG_REVIEW: CHECKED"):
        continue
    candidate = pattern.fullmatch(line)
    if not candidate:
        raise SystemExit(1)
    if candidate.group(1) != current_cycle:
        raise SystemExit(1)
    if marker_index != -1:
        raise SystemExit(1)
    marker_index = index
    match = candidate

if marker_index == -1 or not match:
    raise SystemExit(1)
if status_index != -1 and marker_index > status_index:
    raise SystemExit(1)

if (
    match.group(1) == current_cycle
    and match.group(2) == anomalies_expectation
    and match.group(3) == cycle_log_sha
):
    raise SystemExit(0)

raise SystemExit(1)
PY
}

startup_anomaly_cycle_review_evidence_present() {
  local log_path="$1"
  local current_cycle="$2"
  [[ -f "$log_path" ]] || return 1

  python3 - "$log_path" "$current_cycle" <<'PY'
import re
import sys

log_path = sys.argv[1]
current_cycle = sys.argv[2]
cycle_pattern = re.compile(r"\bcycle={}\b".format(re.escape(current_cycle)))
cycle_line_seen = False
cycle_start_seen = False
cycle_exit_seen = False
run_start_seen = False
run_finish_seen = False

try:
    with open(log_path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not cycle_pattern.search(line):
                continue
            cycle_line_seen = True
            if "cycle.start" in line:
                cycle_start_seen = True
            if "cycle.exit" in line:
                cycle_exit_seen = True
            if "run.start" in line:
                run_start_seen = True
            if "run.finish" in line:
                run_finish_seen = True
except OSError:
    raise SystemExit(1)

if not cycle_line_seen:
    raise SystemExit(1)
if not (cycle_start_seen and cycle_exit_seen and run_start_seen and run_finish_seen):
    raise SystemExit(1)

raise SystemExit(0)
PY
}

record_startup_anomaly_gate_review() {
  local last_message_file="$1"
  local status_marker_value="${2:-missing}"
  local codex_exit_value="${3:-unknown}"
  [[ "$STARTUP_ANOMALY_GATE" == "1" ]] || return 0

  if [[ "$STARTUP_ANOMALY_GATE_CHANGED_PATH_VIOLATION" == "1" ]]; then
    log_line "WARN" "startup_anomaly.gate_unresolved reason=changed_path_violation reasons=$(shell_quote "${STARTUP_ANOMALY_REASONS:-unknown}") status_marker=${status_marker_value:-missing} codex_exit=$codex_exit_value action=force_upkeeper_next_run"
    if ! write_startup_anomaly_gate_state "unresolved" "changed_path_violation"; then
      finish_cycle 7 STARTUP_ANOMALY_STATE_UNWRITABLE ERROR "codex_exec_started=1"
    fi
  elif startup_anomaly_gate_has_unresolved_state "$STARTUP_ANOMALY_REASONS"; then
    log_line "WARN" "startup_anomaly.gate_unresolved reason=unresolved_startup_anomaly_state reasons=$(shell_quote "${STARTUP_ANOMALY_REASONS:-unknown}") status_marker=${status_marker_value:-missing} codex_exit=$codex_exit_value action=force_upkeeper_next_run"
    if ! write_startup_anomaly_gate_state "unresolved" "unresolved_startup_anomaly_state"; then
      finish_cycle 7 STARTUP_ANOMALY_STATE_UNWRITABLE ERROR "codex_exec_started=1"
    fi
  elif [[ "$codex_exit_value" != "0" ]]; then
    log_line "WARN" "startup_anomaly.gate_unresolved reason=nonzero_codex_exit reasons=$(shell_quote "${STARTUP_ANOMALY_REASONS:-unknown}") status_marker=${status_marker_value:-missing} codex_exit=$codex_exit_value action=force_upkeeper_next_run"
    if ! write_startup_anomaly_gate_state "unresolved" "nonzero_codex_exit"; then
      finish_cycle 7 STARTUP_ANOMALY_STATE_UNWRITABLE ERROR "codex_exec_started=1"
    fi
  elif startup_anomaly_cycle_review_evidence_present "$LOG_FILE" "$CYCLE_ID"; then
    STARTUP_ANOMALY_GATE_RESOLVED="1"
    if ! write_startup_anomaly_gate_state "resolved" "log_review_ack_checked"; then
      finish_cycle 7 STARTUP_ANOMALY_STATE_UNWRITABLE ERROR "codex_exec_started=1"
    fi
    mark_startup_anomaly_gate_states_resolved
    log_line "INFO" "startup_anomaly.gate_resolved status=checked reasons=$(shell_quote "${STARTUP_ANOMALY_REASONS:-unknown}") status_marker=${status_marker_value:-missing} codex_exit=$codex_exit_value"
  else
    log_line "WARN" "startup_anomaly.gate_unresolved reason=missing_current_cycle_log_review_evidence reasons=$(shell_quote "${STARTUP_ANOMALY_REASONS:-unknown}") status_marker=${status_marker_value:-missing} codex_exit=$codex_exit_value action=force_upkeeper_next_run"
    if ! write_startup_anomaly_gate_state "unresolved" "missing_current_cycle_log_review_evidence"; then
      finish_cycle 7 STARTUP_ANOMALY_STATE_UNWRITABLE ERROR "codex_exec_started=1"
    fi
  fi
}
