#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
TOOLS_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
ROOT_DIR="$(cd -- "$TOOLS_DIR/.." && pwd)"

MODE="quick"

WRAPPER_REQUIRED_COMMANDS=(
  awk
  cat
  cut
  date
  df
  find
  git
  grep
  jq
  mkdir
  mktemp
  mv
  ps
  python3
  rm
  rmdir
  sed
  sort
  tail
  tee
  tr
)

WRAPPER_BACKEND_COMMANDS=(
  codex
)

WRAPPER_CONDITIONAL_COMMANDS=(
  screen
)

WRAPPER_OPTIONAL_COMMANDS=(
  realpath
  stat
  zip
)

usage() {
  cat <<'USAGE'
Usage: tools/validate_upkeeper.sh [--quick|--full|--deps]

Validate the central Upkeeper checkout.

Modes:
  --deps    Report runtime/tool dependency status.
  --quick   Run syntax, version, module-map, prompt-template, help, and diff checks.
  --full    Run quick checks plus safe dry-runs, symlink behavior, and failure paths.

No mode launches a real Codex backend task. Full mode uses UPKEEPER_DRY_RUN=1
plus a local fake codex binary for launch/capture failure checks.
USAGE
}

log() {
  printf 'validate_upkeeper: %s\n' "$*"
}

fail() {
  printf 'validate_upkeeper: ERROR: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)
      MODE="quick"
      ;;
    --full)
      MODE="full"
      ;;
    --deps)
      MODE="deps"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

cd "$ROOT_DIR"

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || fail "missing required command: $command_name"
}

require_commands() {
  local command_name
  for command_name in bash chmod cp diff find git grep jq ln mkdir mktemp rm sed sort touch tr wc; do
    require_command "$command_name"
  done
}

dependency_status_line() {
  local class="$1"
  local command_name="$2"
  local note="$3"

  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok\t%s\t%s\t%s\n' "$class" "$command_name" "$note"
    return 0
  fi

  printf 'missing\t%s\t%s\t%s\n' "$class" "$command_name" "$note"
  return 1
}

check_dependencies() {
  local command_name
  local missing_required=0

  log "checking wrapper dependencies"
  printf 'status\tclass\tcommand\tnote\n'

  for command_name in "${WRAPPER_REQUIRED_COMMANDS[@]}"; do
    dependency_status_line "required" "$command_name" "required by Upkeeper startup/runtime" || missing_required=1
  done

  for command_name in "${WRAPPER_BACKEND_COMMANDS[@]}"; do
    dependency_status_line "backend" "$command_name" "required for non-dry-run codex exec cycles" || true
  done

  for command_name in "${WRAPPER_CONDITIONAL_COMMANDS[@]}"; do
    dependency_status_line "conditional" "$command_name" "required when detached screen fallback is enabled" || true
  done

  for command_name in "${WRAPPER_OPTIONAL_COMMANDS[@]}"; do
    case "$command_name" in
      realpath)
        dependency_status_line "optional" "$command_name" "central path resolution uses python3 fallback" || true
        ;;
      stat)
        dependency_status_line "optional" "$command_name" "transcript sizing uses python3 fallback" || true
        ;;
      zip)
        dependency_status_line "optional" "$command_name" "log rotation archives are disabled when missing" || true
        ;;
      *)
        dependency_status_line "optional" "$command_name" "optional helper" || true
        ;;
    esac
  done

  [[ "$missing_required" -eq 0 ]] || fail "one or more required wrapper dependencies are missing"
}

check_syntax() {
  local module

  log "checking Bash syntax"
  bash -n Upkeeper
  for module in lib/upkeeper/*.bash; do
    bash -n "$module"
  done
}

check_version_consistency() {
  local version header_version guide_version version_output

  log "checking version consistency"
  version="$(sed -n 's/^UPKEEPER_VERSION="\([^"]*\)"/\1/p' Upkeeper)"
  [[ -n "$version" ]] || fail "UPKEEPER_VERSION not found"

  header_version="$(sed -n 's/^## Version: //p' Upkeeper | sed -n '1p')"
  [[ "$header_version" == "$version" ]] || fail "Upkeeper header version $header_version != $version"

  guide_version="$(sed -n 's/^Version: //p' docs/scripts/upkeeper.md | sed -n '1p')"
  [[ "$guide_version" == "$version" ]] || fail "operator guide version $guide_version != $version"

  grep -Fq "$version changes:" change_notes.md || fail "change_notes.md missing $version entry"

  version_output="$(./Upkeeper --version)"
  [[ "$version_output" == "Upkeeper $version" ]] || fail "./Upkeeper --version output unexpected: $version_output"
}

check_module_map() {
  local array_file files_file line_count unique_count

  log "checking module map coverage"
  array_file="$(mktemp /tmp/upkeeper-module-map.XXXXXX)"
  files_file="$(mktemp /tmp/upkeeper-module-files.XXXXXX)"

  sed -n '/^UPKEEPER_MODULES=(/,/^)/p' Upkeeper \
    | sed -n 's/^[[:space:]]*"\([^"]*\.bash\)".*/\1/p' \
    | sort >"$array_file"
  find lib/upkeeper -maxdepth 1 -type f -name '*.bash' -printf '%f\n' | sort >"$files_file"

  diff -u "$files_file" "$array_file"
  line_count="$(wc -l <"$array_file" | tr -d ' ')"
  unique_count="$(sort -u "$array_file" | wc -l | tr -d ' ')"
  [[ "$line_count" == "$unique_count" ]] || fail "UPKEEPER_MODULES contains duplicates"
  log "module map covers $line_count modules"
  rm -f "$array_file" "$files_file"
}

check_prompt_template() {
  log "checking prompt templates"
  [[ -s prompts/default-review.md ]] || fail "prompts/default-review.md is missing or empty"
  [[ -s prompts/p23-data-contract-negative-fixture-audit.md ]] || fail "P23 standalone prompt is missing or empty"
  [[ -s prompts/p24-de-llm-ing-viability-review.md ]] || fail "P24 standalone prompt is missing or empty"
  [[ -s prompts/p25-contract-intent-compliance-review.md ]] || fail "P25 review module prompt is missing or empty"
  [[ -s prompts/p26-public-documentation-review.md ]] || fail "P26 review module prompt is missing or empty"
  [[ -s prompts/p27-educational-debrief-review.md ]] || fail "P27 review module prompt is missing or empty"
  grep -Fq "P24 - De-LLM-ing Viability Review" prompts/p24-de-llm-ing-viability-review.md || fail "P24 prompt title missing"
  grep -Fq "P24: not applicable" prompts/p24-de-llm-ing-viability-review.md || fail "P24 applicability gate missing"
  grep -Fq "no loss of operator-facing function" prompts/p24-de-llm-ing-viability-review.md || fail "P24 no-loss requirement missing"
  grep -Fq "without material new runtime cost" prompts/p24-de-llm-ing-viability-review.md || fail "P24 cost ceiling missing"
  grep -Fq "P25 - Contract And Intent Compliance Review" prompts/p25-contract-intent-compliance-review.md || fail "P25 prompt title missing"
  grep -Fq "P25: not applicable" prompts/p25-contract-intent-compliance-review.md || fail "P25 applicability gate missing"
  grep -Fq "central-first" prompts/p25-contract-intent-compliance-review.md || fail "P25 central-first contract missing"
  grep -Fq "operator-visible behavior" prompts/p25-contract-intent-compliance-review.md || fail "P25 operator-visible contract missing"
  grep -Fq "smallest sufficient" prompts/p25-contract-intent-compliance-review.md || fail "P25 simplicity contract missing"
  grep -Fq "P26 - Public Documentation And Readability Review" prompts/p26-public-documentation-review.md || fail "P26 prompt title missing"
  grep -Fq "P26: not applicable" prompts/p26-public-documentation-review.md || fail "P26 applicability gate missing"
  grep -Fq "current checked-in state as the delivered product" prompts/p26-public-documentation-review.md || fail "P26 delivered-product rule missing"
  grep -Fq "P27 - Educational Debrief Review" prompts/p27-educational-debrief-review.md || fail "P27 prompt title missing"
  grep -Fq "P27: not applicable" prompts/p27-educational-debrief-review.md || fail "P27 applicability gate missing"
  grep -Fq "P27 Educational Debrief:" prompts/p27-educational-debrief-review.md || fail "P27 saved structure missing"
  grep -Fq "What went wrong:" prompts/p27-educational-debrief-review.md || fail "P27 debrief structure missing"
  grep -Fq "code-comment clarity" README.md || fail "README missing P26 summary"
  grep -Fq "educational debrief" README.md || fail "README missing P27 summary"
  grep -Fq "public project material" docs/public-documentation-policy.md || fail "public documentation policy missing public-by-default rule"
}

check_help_and_diff() {
  local help

  log "checking help and whitespace"
  help="$(./Upkeeper --help)"
  grep -Fq -- "--review-module=p24" <<<"$help" || fail "help missing --review-module=p24"
  grep -Fq -- "--review-module=p25" <<<"$help" || fail "help missing --review-module=p25"
  grep -Fq -- "--review-module=p26" <<<"$help" || fail "help missing --review-module=p26"
  grep -Fq -- "--review-module=p27" <<<"$help" || fail "help missing --review-module=p27"
  grep -Fq -- "--p24" <<<"$help" || fail "help missing --p24"
  grep -Fq -- "--p25" <<<"$help" || fail "help missing --p25"
  grep -Fq -- "--p26" <<<"$help" || fail "help missing --p26"
  grep -Fq -- "--p27" <<<"$help" || fail "help missing --p27"
  grep -Fq -- "--ignore-failure-queue" <<<"$help" || fail "help missing --ignore-failure-queue"
  git diff --check
  git diff --cached --check
}

check_codex_mode_validation() {
  local output rc

  log "checking CODEX_MODE validation"

  set +e
  output="$(CODEX_MODE='sandbox workspace-write' ./Upkeeper --version 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 2 ]] || fail "missing-dash CODEX_MODE exited $rc, expected 2"
  grep -Fq "invalid CODEX_MODE first token sandbox" <<<"$output" || fail "missing-dash CODEX_MODE error was not clear"

  set +e
  output="$(CODEX_MODE='---sandbox workspace-write' ./Upkeeper --version 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 2 ]] || fail "triple-hyphen CODEX_MODE exited $rc, expected 2"
  grep -Fq "invalid CODEX_MODE first token ---sandbox" <<<"$output" || fail "triple-hyphen CODEX_MODE error was not clear"
}

write_validation_quota_snapshot() {
  local session_file="$1"
  local model="$2"
  local primary_reset_offset="${3:-3600}"
  local secondary_reset_offset="${4:-86400}"

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
path.parent.mkdir(parents=True, exist_ok=True)
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

check_cycle_start_log_contract() {
  local temp_dir code_home_q rc

  log "checking cycle.start log quoting"
  temp_dir="$(mktemp -d /tmp/upkeeper-log-contract.XXXXXX)"
  write_validation_quota_snapshot "$temp_dir/codex home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"
  printf -v code_home_q '%q' "$temp_dir/codex home"

  set +e
  CODEX_HOME="$temp_dir/codex home" \
    CODEX_LOG_FILE="$temp_dir/Upkeeper.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$temp_dir/active.lock" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    CODEX_TERMINAL_VERBOSITY=quiet \
    CODEX_MODEL=gpt-5.5 \
    CODEX_REASONING_EFFORT=xhigh \
    CODEX_FALLBACK_ENABLED=0 \
    CODEX_FALLBACK_SCREEN_ENABLED=0 \
    CODEX_POSTMORTEM_ENABLED=0 \
    UPKEEPER_DRY_RUN=1 \
    CODEX_MODE='--sandbox workspace-write' \
    ./Upkeeper >"$temp_dir/out.txt" 2>"$temp_dir/err.txt"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "cycle.start log contract dry-run exited $rc"
  grep -Fq 'mode=--sandbox\ workspace-write' "$temp_dir/Upkeeper.log" || fail "cycle.start did not quote CODEX_MODE with spaces"
  grep -Fq "code_home=$code_home_q" "$temp_dir/Upkeeper.log" || fail "cycle.start did not quote CODEX_HOME with spaces"
  grep -Fq "reason=DRY_RUN" "$temp_dir/Upkeeper.log" || fail "cycle.start log contract dry-run did not finish cleanly"
  rm -r "$temp_dir"
}

check_quota_fallback_exit_contract() {
  local temp_dir rc

  log "checking quota fallback cycle.exit contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-quota-fallback.XXXXXX)"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.3-codex-spark" "-3600" "86400"

  set +e
  CODEX_HOME="$temp_dir/codex-home" \
    CODEX_LOG_FILE="$temp_dir/Upkeeper.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$temp_dir/active.lock" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    CODEX_TERMINAL_VERBOSITY=quiet \
    CODEX_MODEL=gpt-5.3-codex-spark \
    CODEX_REASONING_EFFORT=xhigh \
    UPKEEPER_DRY_RUN=1 \
    ./Upkeeper --target-file=Upkeeper --prompt-file prompts/p24-de-llm-ing-viability-review.md >"$temp_dir/out.txt" 2>"$temp_dir/err.txt"
  rc=$?
  set -e

  [[ "$rc" -eq 7 ]] || fail "quota fallback dry-run exited $rc, expected 7"
  grep -Fq "fallback.finish trigger=primary_quota_before_run" "$temp_dir/Upkeeper.log" || fail "quota fallback dry-run did not finish fallback orchestration"
  grep -Fq "cycle.exit exit_code=7 reason=FALLBACK_CHAIN_EXIT" "$temp_dir/Upkeeper.log" || fail "quota fallback dry-run did not write cycle.exit"
  rm -r "$temp_dir"
}

check_review_module_flags() {
  local temp_dir output rc

  log "checking review module flags"
  temp_dir="$(mktemp -d /tmp/upkeeper-review-modules.XXXXXX)"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  CODEX_HOME="$temp_dir/codex-home" \
    CODEX_LOG_FILE="$temp_dir/Upkeeper.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$temp_dir/active.lock" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    CODEX_TERMINAL_VERBOSITY=quiet \
    CODEX_MODEL=gpt-5.5 \
    CODEX_REASONING_EFFORT=xhigh \
    CODEX_FALLBACK_ENABLED=0 \
    CODEX_FALLBACK_SCREEN_ENABLED=0 \
    CODEX_POSTMORTEM_ENABLED=0 \
    UPKEEPER_DRY_RUN=1 \
    ./Upkeeper --target-file=Upkeeper --review-modules=p24,p25,p26,p27 >"$temp_dir/out.txt" 2>"$temp_dir/err.txt"

  grep -Fq "review_modules=p24,p25,p26,p27" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not record selected modules"
  grep -Fq "review.module_prompt enabled module=p24" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not append P24"
  grep -Fq "review.module_prompt enabled module=p25" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not append P25"
  grep -Fq "review.module_prompt enabled module=p26" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not append P26"
  grep -Fq "review.module_prompt enabled module=p27" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not append P27"
  grep -Fq "cycle.exit exit_code=0 reason=DRY_RUN" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not finish cleanly"

  output="$(./Upkeeper --p24 --p25 --p26 --p27 --version)"
  [[ "$output" == "Upkeeper $(sed -n 's/^UPKEEPER_VERSION="\([^"]*\)"/\1/p' Upkeeper)" ]] || fail "review module shorthand flags broke --version"

  set +e
  output="$(./Upkeeper --review-module=nope --version 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || fail "invalid review module exited $rc, expected 3"
  grep -Fq "unknown review module: nope" <<<"$output" || fail "invalid review module error was not clear"

  rm -r "$temp_dir"
}

check_tool_failure_queue() {
  local temp_dir transcript clean_transcript marker_path open_count resolved_count marker_id

  log "checking tool failure queue"
  temp_dir="$(mktemp -d /tmp/upkeeper-tool-failure-queue.XXXXXX)"
  transcript="$temp_dir/failure-transcript.log"
  clean_transcript="$temp_dir/clean-transcript.log"

  cat >"$transcript" <<'EOF'
codex
exec
/bin/bash -lc 'tools/validate_upkeeper.sh --quick'
exited 1 in 0.1s
EOF

  (
    cd "$ROOT_DIR"
    LOG_FILE="$temp_dir/Upkeeper.log"
    CODEX_TERMINAL_VERBOSITY=silent
    CODEX_TOOL_FAILURE_QUEUE_ENABLED=1
    CODEX_TOOL_FAILURE_QUEUE_DIR="$temp_dir/failures"
    CODEX_TOOL_FAILURE_QUEUE_BYPASS=0
    CYCLE_ID="validation-open"
    CYCLE_RUN_HASH="validationhashopen"
    RUN_SELECTED_FAILURE_MARKER_PATH=""
    source lib/upkeeper/fallback_artifacts.bash
    source lib/upkeeper/runtime_foundation.bash
    source lib/upkeeper/tool_failure_queue.bash
    tool_failure_queue_finalize_run "lib/upkeeper/codex_io.bash" "$transcript" 0 "BLOCKED"
  )

  open_count="$(find "$temp_dir/failures/open" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$open_count" == "1" ]] || fail "tool failure queue did not create one open marker"
  marker_path="$(find "$temp_dir/failures/open" -type f -name '*.json' | head -n 1)"
  grep -Fq '"target_path": "lib/upkeeper/codex_io.bash"' "$marker_path" || fail "tool failure marker target missing"
  grep -Fq '"last_failure_kind": "validation"' "$marker_path" || fail "tool failure marker kind missing"
  grep -Fq "tool_failure_queue.open" "$temp_dir/Upkeeper.log" || fail "tool failure queue open event not logged"

  (
    cd "$ROOT_DIR"
    LOG_FILE="$temp_dir/unaddressed.log"
    CODEX_TERMINAL_VERBOSITY=silent
    CODEX_TOOL_FAILURE_QUEUE_ENABLED=1
    CODEX_TOOL_FAILURE_QUEUE_DIR="$temp_dir/unaddressed-failures"
    CODEX_TOOL_FAILURE_QUEUE_BYPASS=0
    CYCLE_ID="validation-unaddressed"
    CYCLE_RUN_HASH="validationhashunaddressed"
    RUN_SELECTED_FAILURE_MARKER_PATH=""
    source lib/upkeeper/fallback_artifacts.bash
    source lib/upkeeper/runtime_foundation.bash
    source lib/upkeeper/tool_failure_queue.bash
    tool_failure_queue_finalize_run "lib/upkeeper/help_selection.bash" "$transcript" 0 "WORK_DONE"
  )
  open_count="$(find "$temp_dir/unaddressed-failures/open" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$open_count" == "1" ]] || fail "tool failure queue wrongly resolved unverified WORK_DONE failure"
  grep -Fq "addressed_by_later_success=0" "$temp_dir/unaddressed.log" || fail "tool failure queue did not log unaddressed evidence"

  cat >"$clean_transcript" <<'EOF'
codex
tokens used
EOF

  (
    cd "$ROOT_DIR"
    LOG_FILE="$temp_dir/Upkeeper.log"
    CODEX_TERMINAL_VERBOSITY=silent
    CODEX_TOOL_FAILURE_QUEUE_ENABLED=1
    CODEX_TOOL_FAILURE_QUEUE_DIR="$temp_dir/failures"
    CODEX_TOOL_FAILURE_QUEUE_BYPASS=0
    CYCLE_ID="validation-resolve"
    CYCLE_RUN_HASH="validationhashresolve"
    RUN_SELECTED_FAILURE_MARKER_PATH="$marker_path"
    source lib/upkeeper/fallback_artifacts.bash
    source lib/upkeeper/runtime_foundation.bash
    source lib/upkeeper/tool_failure_queue.bash
    tool_failure_queue_finalize_run "lib/upkeeper/codex_io.bash" "$clean_transcript" 0 "WORK_DONE"
  )

  [[ ! -e "$marker_path" ]] || fail "tool failure queue did not remove resolved open marker"
  resolved_count="$(find "$temp_dir/failures/resolved" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$resolved_count" == "1" ]] || fail "tool failure queue did not keep one resolved marker"
  grep -Fq "tool_failure_queue.resolved" "$temp_dir/Upkeeper.log" || fail "tool failure queue resolved event not logged"

  marker_id="$(python3 - <<'PY'
import hashlib
print(hashlib.sha1(b"lib/upkeeper/codex_io.bash").hexdigest()[:24])
PY
)"
  mkdir -p "$temp_dir/selection-failures/open"
  python3 - "$temp_dir/selection-failures/open/$marker_id.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.write_text(json.dumps({
    "version": 1,
    "status": "open",
    "marker_id": "selectionmarker",
    "target_path": "lib/upkeeper/codex_io.bash",
    "first_seen_epoch": 1,
    "first_seen_cycle": "validation-selection",
    "failure_count": 2,
    "first_failure_kind": "validation",
    "first_failure_exit_line": "exited 1 in 0.1s",
}, sort_keys=True) + "\n", encoding="utf-8")
PY
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  CODEX_HOME="$temp_dir/codex-home" \
    CODEX_LOG_FILE="$temp_dir/selection.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$temp_dir/active.lock" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    CODEX_TOOL_FAILURE_QUEUE_DIR="$temp_dir/selection-failures" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    CODEX_TERMINAL_VERBOSITY=quiet \
    CODEX_MODEL=gpt-5.5 \
    CODEX_REASONING_EFFORT=xhigh \
    CODEX_FALLBACK_ENABLED=0 \
    CODEX_FALLBACK_SCREEN_ENABLED=0 \
    CODEX_POSTMORTEM_ENABLED=0 \
    CODEX_UPKEEPER_SELF_REVIEW_AFTER_DAYS=99999 \
    UPKEEPER_DRY_RUN=1 \
    ./Upkeeper >"$temp_dir/selection.out" 2>"$temp_dir/selection.err"

  grep -Fq "review.preselect path=lib/upkeeper/codex_io.bash" "$temp_dir/selection.log" || fail "failure queue did not force marked target"
  grep -Fq "failure_queue_selected=1" "$temp_dir/selection.log" || fail "failure queue selection was not logged"

  CODEX_HOME="$temp_dir/codex-home" \
    CODEX_LOG_FILE="$temp_dir/bypass.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts-bypass" \
    CODEX_ACTIVE_LOCK_DIR="$temp_dir/active-bypass.lock" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health-bypass" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates-bypass" \
    CODEX_TOOL_FAILURE_QUEUE_DIR="$temp_dir/selection-failures" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    CODEX_TERMINAL_VERBOSITY=quiet \
    CODEX_MODEL=gpt-5.5 \
    CODEX_REASONING_EFFORT=xhigh \
    CODEX_FALLBACK_ENABLED=0 \
    CODEX_FALLBACK_SCREEN_ENABLED=0 \
    CODEX_POSTMORTEM_ENABLED=0 \
    UPKEEPER_DRY_RUN=1 \
    ./Upkeeper --ignore-failure-queue >"$temp_dir/bypass.out" 2>"$temp_dir/bypass.err"

  grep -Fq "failure_queue_selected=0" "$temp_dir/bypass.log" || fail "failure queue bypass flag was not honored"

  rm -r "$temp_dir"
}

check_public_docs_policy() {
  log "checking public documentation policy"
  tools/check_public_docs.sh --quick
}

check_fallback_artifact_helpers() {
  local temp_dir artifact_file marker_file got

  log "checking fallback artifact helper contracts"
  temp_dir="$(mktemp -d /tmp/upkeeper-fallback-artifacts.XXXXXX)"
  artifact_file="$temp_dir/artifact.txt"
  marker_file="$temp_dir/marker.txt"

  source lib/upkeeper/fallback_artifacts.bash

  printf 'child-1\n' >"$artifact_file"
  got="$(read_artifact_or_unknown "$artifact_file")"
  [[ "$got" == "child-1" ]] || fail "artifact helper returned $got for normal artifact"

  printf 'blocked_until: 2026-05-07 10:00\nblocked_until_epoch: 177\n' >"$marker_file"
  got="$(marker_field "$marker_file" "blocked_until")"
  [[ "$got" == "2026-05-07 10:00" ]] || fail "marker helper returned $got for blocked_until"
  got="$(marker_field "$marker_file" "blocked_until_epoch")"
  [[ "$got" == "177" ]] || fail "marker helper returned $got for blocked_until_epoch"

  : >"$artifact_file"
  got="$(read_artifact_or_unknown "$artifact_file")"
  [[ "$got" == "unknown" ]] || fail "empty artifact returned $got instead of unknown"
  got="$(marker_field "$marker_file" "missing_key")"
  [[ -z "$got" ]] || fail "missing marker key returned $got instead of empty"

  got="$(read_artifact_or_unknown "$temp_dir/missing.txt")"
  [[ "$got" == "unknown" ]] || fail "missing artifact returned $got instead of unknown"
  got="$(read_artifact_or_unknown "$temp_dir")"
  [[ "$got" == "unknown" ]] || fail "directory artifact returned $got instead of unknown"
  got="$(marker_field "$temp_dir/missing-marker.txt" "blocked_until")"
  [[ -z "$got" ]] || fail "missing marker returned $got instead of empty"
  got="$(marker_field "$temp_dir" "blocked_until")"
  [[ -z "$got" ]] || fail "directory marker returned $got instead of empty"

  rm -r "$temp_dir"
}

check_postmortem_context_marker_classification() {
  local temp_dir transcript_path context_path bug_record_path incident_log_path report_path primary_last_message_copy

  log "checking postmortem context marker classification"
  temp_dir="$(mktemp -d /tmp/upkeeper-postmortem-context.XXXXXX)"
  transcript_path="$temp_dir/fallback-last-message.txt"
  context_path="$temp_dir/incident-context.txt"
  bug_record_path="$temp_dir/bug-record.md"
  incident_log_path="$temp_dir/incident-log.txt"
  report_path="$temp_dir/postmortem.md"
  primary_last_message_copy="$temp_dir/primary-last-message.txt"

  printf 'fallback completed with a recoverable marker typo\nUPKEEPER_STATUS: WORK_DONE.\n' >"$transcript_path"
  : >"$incident_log_path"
  : >"$report_path"
  : >"$primary_last_message_copy"

  (
    source lib/upkeeper/runtime_format_json.bash
    source lib/upkeeper/report_analysis.bash
    source lib/upkeeper/fallback_artifacts.bash
    source lib/upkeeper/status_session.bash
    source lib/upkeeper/quota_guardrails.bash
    source lib/upkeeper/postmortem_context.bash

    CYCLE_ID=validation
    CODEX_POSTMORTEM_DIR="$temp_dir/postmortems"
    mkdir -p "$CODEX_POSTMORTEM_DIR/$CYCLE_ID/screen"

    CODEX_ATTEMPT_ROLE=primary
    CODEX_MODEL=gpt-primary
    CODEX_REASONING_EFFORT=low
    CODEX_FALLBACK_MODEL=gpt-fallback
    CODEX_FALLBACK_REASONING_EFFORT=low
    CODEX_POSTMORTEM_MODEL=gpt-postmortem
    CODEX_POSTMORTEM_REASONING_EFFORT=low
    CODEX_EXECUTION_ORIGIN=validation
    FALLBACK_SCREEN_SESSION_NAME=validation-screen
    FALLBACK_SCREEN_TRANSCRIPT_PATH="$transcript_path"
    FALLBACK_SCREEN_EXIT_CODE=0
    DIRTY_PATH_COUNT=0
    TRACKED_MODIFIED_PATH_COUNT=0
    UNTRACKED_PATH_COUNT=0
    ROOT_DIR="$temp_dir/repo"
    LOG_FILE="$temp_dir/Upkeeper.log"
    status_marker=missing
    codex_exit=0
    session_end_state=none

    write_postmortem_context "$context_path" "primary_quota_before_run" "quota guardrail" "0" "$incident_log_path" "$primary_last_message_copy"
    write_postmortem_bug_record "$bug_record_path" "primary_quota_before_run" "quota guardrail" "0" "not_run" "$report_path" "$context_path" "$incident_log_path"
  )

  grep -Fq "incident_classification: CONTROLLED_QUOTA_HANDOFF" "$context_path" || fail "context did not classify recovered fallback marker as controlled handoff"
  grep -Fq "fallback_child_status_marker: WORK_DONE" "$context_path" || fail "context did not record recovered fallback marker"
  grep -Fq "fallback_child_status_marker_source: recovered_malformed_candidate" "$context_path" || fail "context did not record recovered marker source"
  grep -Fq -- "- incident_classification: CONTROLLED_QUOTA_HANDOFF" "$bug_record_path" || fail "bug record did not classify recovered fallback marker as controlled handoff"
  grep -Fq -- "- fallback_child_status_marker: WORK_DONE" "$bug_record_path" || fail "bug record did not record recovered fallback marker"
  grep -Fq -- "- fallback_child_status_marker_source: recovered_malformed_candidate" "$bug_record_path" || fail "bug record did not record recovered marker source"

  rm -r "$temp_dir"
}

check_live_output_filter_pipe() {
  local temp_dir rc

  log "checking live output filter consumes pipeline stdin"
  temp_dir="$(mktemp -d /tmp/upkeeper-live-filter.XXXXXX)"

  cat >"$temp_dir/transcript.log" <<'EOF'
Reading prompt from stdin...
OpenAI Codex v0.128.0 (research preview)
--------
user
- broad except Exception that treats malformed input as absence
ValueError, failed, or emit a Python traceback for normal malformed operator
codex
I am checking the selected file before running validation.
exec
/bin/bash -lc 'rg ERROR change_notes.md'
succeeded in 0ms:
14 6. change-note output ERROR failed Exception
exec
/bin/bash -lc "nl -ba tools/validate_upkeeper.sh | sed -n '220,310p'"
succeeded in 0ms:
238 source-view output ERROR failed Exception
273 validation ERROR cmd#[0-9]+ tests failed: exited 1 in 0.1s
exec
/bin/bash -lc "git ls-files | rg '(^|/)(tests?|specs?)/|(_test|test_)|\\.bats$'"
exited 1 in 0ms:
exec
/bin/bash -lc 'rg -n "prompt-file|model-override" tests Upkeeper lib docs 2>/dev/null'
exited 2 in 104ms:
exec
/bin/bash -lc 'launcher_examples/spark_5.3_burn_out_xhigh.sh --bogus'
exited 64 in 0ms:
diff --git a/change_notes.md b/change_notes.md
--- a/change_notes.md
+++ b/change_notes.md
+8. diff-block output ERROR failed Exception
exec
/bin/bash -lc 'bash -n launcher_examples/*.sh'
succeeded in 0ms:
succeeded in 1ms:
exec
python -m pytest
exited 1 in 0.1s
tokens used
123
Final prose mentions ERROR and failed but is not runtime evidence.
UPKEEPER_STATUS: WORK_DONE
UPKEEPER_STATUS: WORK_DONE
EOF

  run_live_filter_mode() {
    local mode="$1"
    local out_file="$temp_dir/live-$mode.out"
    local err_file="$temp_dir/live-$mode.err"

    set +e
    CODEX_TERMINAL_VERBOSITY="$mode" \
      bash -lc 'cd "$1"; source ./Upkeeper; codex_live_output_filter validation' bash "$ROOT_DIR" \
        <"$temp_dir/transcript.log" >"$out_file" 2>"$err_file"
    rc=$?
    set -e
    [[ "$rc" -eq 0 ]] || fail "live output filter exited $rc for mode $mode"
    [[ ! -s "$out_file" ]] || fail "live output filter wrote unexpected stdout for mode $mode"
  }

  run_live_filter_mode verbose
  grep -Fq "[INFO] Upkeeper: validation LLM: I am checking the selected file before running validation." "$temp_dir/live-verbose.err" || fail "verbose live output did not report assistant status before command"
  awk '/LLM: I am checking the selected file before running validation[.]/{ found=1; if (prev != "") exit 2; if ((getline next_line) <= 0 || next_line != "") exit 3 } { prev=$0 } END { exit found ? 0 : 1 }' "$temp_dir/live-verbose.err" || fail "verbose live output did not bracket assistant status with blank lines"
  grep -Eq "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ search started: /bin/bash -lc 'rg ERROR change_notes.md'" "$temp_dir/live-verbose.err" || fail "verbose live output did not report search command start"
  grep -Eq '\[INFO\] Upkeeper: validation cmd#[0-9]+ search started: /bin/bash -lc "nl -ba tools/validate_upkeeper[.]sh' "$temp_dir/live-verbose.err" || fail "verbose live output did not classify source file view as search"
  grep -Eq '\[INFO\] Upkeeper: validation cmd#[0-9]+ search started: /bin/bash -lc "git ls-files' "$temp_dir/live-verbose.err" || fail "verbose live output did not classify git ls-files discovery as search"
  grep -Eq "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ search exited nonzero: exited 1 in 0ms:" "$temp_dir/live-verbose.err" || fail "verbose live output did not report git ls-files discovery as non-error search failure"
  grep -Eq "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ search exited nonzero: exited 2 in 104ms:" "$temp_dir/live-verbose.err" || fail "verbose live output did not report non-error search failure"
  grep -Eq "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ check started: /bin/bash -lc 'bash -n launcher_examples/[*][.]sh'" "$temp_dir/live-verbose.err" || fail "verbose live output did not report successful check start"
  grep -Eq "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ check passed: succeeded in 0ms:" "$temp_dir/live-verbose.err" || fail "verbose live output did not report successful check completion"
  [[ "$(grep -Ec "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ check passed:" "$temp_dir/live-verbose.err")" -eq 1 ]] || fail "verbose live output repeated successful check completion"
  grep -Eq "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ tests started: python -m pytest" "$temp_dir/live-verbose.err" || fail "verbose live output did not report interesting command"
  grep -Eq "\\[ERROR\\] Upkeeper: validation cmd#[0-9]+ tests failed: exited 1 in 0.1s" "$temp_dir/live-verbose.err" || fail "verbose live output did not report failed command"
  [[ "$(grep -Fc "[INFO] Upkeeper: validation status: UPKEEPER_STATUS: WORK_DONE" "$temp_dir/live-verbose.err")" -eq 1 ]] || fail "verbose live output repeated duplicate status markers"
  if grep -Eq "broad except|ValueError|Python traceback|change-note output|source-view output|diff-block output|ERROR .*exited 1 in 0ms|ERROR .*exited 2|ERROR .*exited 64|tests failed: exited 1 in 0ms|Final prose mentions|validation command completed" "$temp_dir/live-verbose.err"; then
    fail "verbose live output reported prompt, uninteresting command output, or Codex prose as runtime signal"
  fi

  run_live_filter_mode basic
  grep -Fq "[INFO] Upkeeper: validation LLM: I am checking the selected file before running validation." "$temp_dir/live-basic.err" || fail "basic live output did not report assistant status before command"
  awk '/LLM: I am checking the selected file before running validation[.]/{ found=1; if (prev != "") exit 2; if ((getline next_line) <= 0 || next_line != "") exit 3 } { prev=$0 } END { exit found ? 0 : 1 }' "$temp_dir/live-basic.err" || fail "basic live output did not bracket assistant status with blank lines"
  grep -Eq "\\[INFO\\] Upkeeper: validation running check cmd#[0-9]+: /bin/bash -lc 'bash -n launcher_examples/[*][.]sh'" "$temp_dir/live-basic.err" || fail "basic live output did not report check start"
  grep -Eq "\\[INFO\\] Upkeeper: validation finished check cmd#[0-9]+: succeeded in 0ms:" "$temp_dir/live-basic.err" || fail "basic live output did not report check completion"
  [[ "$(grep -Ec "\\[INFO\\] Upkeeper: validation finished check cmd#[0-9]+:" "$temp_dir/live-basic.err")" -eq 1 ]] || fail "basic live output repeated successful check completion"
  grep -Eq "\\[ERROR\\] Upkeeper: validation cmd#[0-9]+ tests failed: exited 1 in 0.1s" "$temp_dir/live-basic.err" || fail "basic live output did not report failed command"
  if grep -Eq "search started|search exited nonzero|change-note output|source-view output|diff-block output|Final prose mentions" "$temp_dir/live-basic.err"; then
    fail "basic live output reported verbose search chatter or filtered text"
  fi

  run_live_filter_mode quiet
  grep -Eq "\\[ERROR\\] Upkeeper: validation cmd#[0-9]+ tests failed: exited 1 in 0.1s" "$temp_dir/live-quiet.err" || fail "quiet live output did not report failed command"
  [[ "$(grep -Fc "[INFO] Upkeeper: validation status: UPKEEPER_STATUS: WORK_DONE" "$temp_dir/live-quiet.err")" -eq 1 ]] || fail "quiet live output did not report one status marker"
  if grep -Eq "LLM:|search started|running check|finished check|tests started|change-note output|source-view output" "$temp_dir/live-quiet.err"; then
    fail "quiet live output was too chatty"
  fi

  run_live_filter_mode silent
  [[ ! -s "$temp_dir/live-silent.err" ]] || fail "silent live output wrote unexpected stderr"

  CODEX_LOG_FILE="$temp_dir/Upkeeper.log" CYCLE_ID=validation CYCLE_RUN_HASH=filter-test \
    CODEX_TERMINAL_VERBOSITY=basic \
    bash -lc 'cd "$1"; source ./Upkeeper; emit_codex_transcript_summary validation "$2" 1' bash "$ROOT_DIR" "$temp_dir/transcript.log" \
      >"$temp_dir/summary.out" 2>"$temp_dir/summary.err"
  grep -Fq "codex.transcript.signal label=validation text=exited\\ 1\\ in\\ 0.1s" "$temp_dir/Upkeeper.log" || fail "transcript summary did not report runtime failure"
  if grep -Fq "codex.transcript.signal label=validation text=exited\\ 2\\ in\\ 104ms:" "$temp_dir/Upkeeper.log"; then
    fail "transcript summary reported exploratory search failure as runtime signal"
  fi
  if grep -Fq "codex.transcript.signal label=validation text=exited\\ 1\\ in\\ 0ms:" "$temp_dir/Upkeeper.log"; then
    fail "transcript summary reported discovery search failure as runtime signal"
  fi
  grep -Fq "codex.transcript.signal label=validation text=UPKEEPER_STATUS:\\ WORK_DONE" "$temp_dir/Upkeeper.log" || fail "transcript summary did not report structured status marker"
  [[ "$(grep -Fc "codex.transcript.signal label=validation text=UPKEEPER_STATUS:\\ WORK_DONE" "$temp_dir/Upkeeper.log")" -eq 1 ]] || fail "transcript summary repeated duplicate status markers"
  if grep -Eq "broad except|ValueError|Python traceback|change-note output|source-view output|diff-block output|exited\\\\ 64|Final prose mentions" "$temp_dir/Upkeeper.log"; then
    fail "transcript summary reported prompt, uninteresting command output, or Codex prose as runtime signal"
  fi
  rm -r "$temp_dir"
}

check_review_summary_parser() {
  local temp_dir summary selected_file outcome

  log "checking review summary parser"
  temp_dir="$(mktemp -d /tmp/upkeeper-review-summary.XXXXXX)"
  cat >"$temp_dir/last-message.txt" <<'EOF'
REVIEWED_AND_FIXED

Selected `lib/upkeeper/codex_io.bash` from the authoritative preselection.

Implemented:
- [lib/upkeeper/codex_io.bash](/home/joe/projects/Upkeeper/main/lib/upkeeper/codex_io.bash): hardened JSON assignment handling.

Verification passed:
- `tools/validate_upkeeper.sh --quick`

UPKEEPER_LOG_REVIEW: CHECKED cycle=validation anomalies=none
UPKEEPER_STATUS: WORK_DONE
EOF

  summary="$(bash -lc 'cd "$1"; source ./Upkeeper; review_report_summary_json "$2"' bash "$ROOT_DIR" "$temp_dir/last-message.txt")"
  selected_file="$(printf '%s' "$summary" | jq -r '.selected_file')"
  outcome="$(printf '%s' "$summary" | jq -r '.outcome')"
  [[ "$selected_file" == "lib/upkeeper/codex_io.bash" ]] || fail "review summary selected_file was $selected_file"
  [[ "$outcome" == "REVIEWED_AND_FIXED" ]] || fail "review summary outcome was $outcome"

  cat >"$temp_dir/last-message.txt" <<'EOF'
REVIEWED_AND_FIXED

Selected [lib/upkeeper/fallback_availability.bash](/home/joe/projects/Upkeeper/main/lib/upkeeper/fallback_availability.bash) per the authoritative preselection. Baseline mtime was epoch `1778201006`.

Applied two focused fixes:
- Added a module header.

UPKEEPER_STATUS: WORK_DONE
EOF

  summary="$(bash -lc 'cd "$1"; source ./Upkeeper; review_report_summary_json "$2"' bash "$ROOT_DIR" "$temp_dir/last-message.txt")"
  selected_file="$(printf '%s' "$summary" | jq -r '.selected_file')"
  [[ "$selected_file" == "/home/joe/projects/Upkeeper/main/lib/upkeeper/fallback_availability.bash" ]] || fail "review summary selected markdown file was $selected_file"

  CODEX_TERMINAL_VERBOSITY=basic \
    bash -lc 'cd "$1"; source ./Upkeeper; terminal_emit_review_finale REVIEWED_AND_FIXED lib/upkeeper/example.bash "parser accepted malformed JSON as absent" "added strict rejection" "bash -n passed"' bash "$ROOT_DIR" \
      >"$temp_dir/finale-basic.out" 2>"$temp_dir/finale-basic.err"
  grep -Fq "final review for lib/upkeeper/example.bash -> REVIEWED_AND_FIXED" "$temp_dir/finale-basic.err" || fail "basic finale did not report final review"
  grep -Fq "what was wrong: parser accepted malformed JSON as absent" "$temp_dir/finale-basic.err" || fail "basic finale did not report finding"
  grep -Fq "what changed: added strict rejection" "$temp_dir/finale-basic.err" || fail "basic finale did not report change"
  grep -Fq "verification: bash -n passed" "$temp_dir/finale-basic.err" || fail "basic finale did not report verification"

  CODEX_TERMINAL_VERBOSITY=silent \
    bash -lc 'cd "$1"; source ./Upkeeper; terminal_emit_review_finale REVIEWED_AND_FIXED lib/upkeeper/example.bash "finding" "change" "verification"' bash "$ROOT_DIR" \
      >"$temp_dir/finale-silent.out" 2>"$temp_dir/finale-silent.err"
  [[ ! -s "$temp_dir/finale-silent.err" ]] || fail "silent finale wrote terminal output"

  rm -r "$temp_dir"
}

check_process_control_guards() {
  local temp_dir

  log "checking parent process-control guards"
  temp_dir="$(mktemp -d /tmp/upkeeper-process-control.XXXXXX)"

  if ! CODEX_LOG_FILE="$temp_dir/Upkeeper.log" CODEX_TERMINAL_VERBOSITY=quiet \
    bash -lc '
      set -euo pipefail
      cd "$1"
      source ./Upkeeper

      for invalid_pid in -1 0 1 abc "2 3"; do
        CODEX_LOOP_PARENT_PID="$invalid_pid"
        CODEX_LOOP_PARENT_COMM=bash
        CODEX_LOOP_PARENT_ARGS="bash -lc while ./Upkeeper"
        if parent_shell_details >"$2/invalid-parent.out"; then
          printf "invalid parent PID was accepted: %s\n" "$invalid_pid" >&2
          exit 1
        fi
      done

      CODEX_LOOP_PARENT_PID=424242
      CODEX_LOOP_PARENT_COMM=bash
      CODEX_LOOP_PARENT_ARGS="bash -lc while ./Upkeeper"
      CODEX_DISABLE_PARENT_STOP=0
      UPKEEPER_DRY_RUN=0
      CODEX_EXECUTION_ORIGIN=validation
      CODEX_LOOP_STOP_GRACE_SECONDS=1
      PARENT_LOOP_STOP_OUTCOME=
      kill_probe_count=0

      kill() {
        case "$1" in
          -0)
            kill_probe_count=$((kill_probe_count + 1))
            [[ "$kill_probe_count" -eq 1 ]]
            ;;
          -TERM)
            return 1
            ;;
          *)
            printf "unexpected kill invocation: %s\n" "$*" >&2
            return 1
            ;;
        esac
      }

      stop_parent_loop
      [[ "$PARENT_LOOP_STOP_OUTCOME" == "already_exited" ]] || {
        printf "unexpected stop outcome: %s\n" "${PARENT_LOOP_STOP_OUTCOME:-missing}" >&2
        exit 1
      }
    ' bash "$ROOT_DIR" "$temp_dir" >"$temp_dir/guard.out" 2>"$temp_dir/guard.err"; then
    cat "$temp_dir/guard.err" >&2
    fail "process-control guard check failed"
  fi

  grep -Fq "exited before SIGTERM could be delivered" "$temp_dir/Upkeeper.log" || fail "SIGTERM race was not logged"
  rm -r "$temp_dir"
}

check_startup_anomaly_gate_allowlist() {
  local temp_dir before_file after_file output

  log "checking startup anomaly gate changed-path allowlist"
  temp_dir="$(mktemp -d /tmp/upkeeper-gate-allowlist.XXXXXX)"
  before_file="$temp_dir/before.json"
  after_file="$temp_dir/after.json"

  cat >"$before_file" <<'JSON'
{
  "Upkeeper": {"status": "clean", "hash": "old"},
  "change_notes.md": {"status": "clean", "hash": "old"},
  "docs/scripts/upkeeper.md": {"status": "clean", "hash": "old"},
  "lib/upkeeper/worktree_state.bash": {"status": "clean", "hash": "old"},
  "tools/validate_upkeeper.sh": {"status": "clean", "hash": "old"},
  "unrelated.txt": {"status": "clean", "hash": "old"}
}
JSON
  cat >"$after_file" <<'JSON'
{
  "Upkeeper": {"status": "modified", "hash": "new"},
  "change_notes.md": {"status": "modified", "hash": "new"},
  "docs/scripts/upkeeper.md": {"status": "modified", "hash": "new"},
  "lib/upkeeper/worktree_state.bash": {"status": "modified", "hash": "new"},
  "tools/validate_upkeeper.sh": {"status": "modified", "hash": "new"},
  "unrelated.txt": {"status": "modified", "hash": "new"}
}
JSON

  output="$(bash -lc 'cd "$1"; source lib/upkeeper/worktree_state.bash; startup_anomaly_gate_changed_path_violations "$2" "$3"' bash "$ROOT_DIR" "$before_file" "$after_file")"
  grep -Fq "changed_path='unrelated.txt'" <<<"$output" || fail "gate allowlist did not report unrelated changed path"
  if grep -Eq "Upkeeper|change_notes|docs/scripts|lib/upkeeper|tools/validate" <<<"$output"; then
    fail "gate allowlist reported an allowed Upkeeper-suite path: $output"
  fi

  rm -r "$temp_dir"
}

check_central_dry_runs() {
  local temp_dir

  log "checking central dry-run startup"
  temp_dir="$(mktemp -d /tmp/upkeeper-central-dry-run.XXXXXX)"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  CODEX_HOME="$temp_dir/codex-home" \
    CODEX_LOG_FILE="$temp_dir/Upkeeper.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$temp_dir/active.lock" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    CODEX_TERMINAL_VERBOSITY=quiet \
    CODEX_MODEL=gpt-5.5 \
    CODEX_REASONING_EFFORT=xhigh \
    CODEX_FALLBACK_ENABLED=0 \
    CODEX_FALLBACK_SCREEN_ENABLED=0 \
    CODEX_POSTMORTEM_ENABLED=0 \
    UPKEEPER_DRY_RUN=1 \
    ./Upkeeper >/dev/null

  CODEX_HOME="$temp_dir/codex-home" \
    CODEX_LOG_FILE="$temp_dir/Upkeeper.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$temp_dir/active.lock" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    CODEX_TERMINAL_VERBOSITY=quiet \
    CODEX_MODEL=gpt-5.5 \
    CODEX_REASONING_EFFORT=xhigh \
    CODEX_FALLBACK_ENABLED=0 \
    CODEX_FALLBACK_SCREEN_ENABLED=0 \
    CODEX_POSTMORTEM_ENABLED=0 \
    UPKEEPER_DRY_RUN=1 \
    ./Upkeeper --prompt-pass=all >/dev/null

  rm -r "$temp_dir"
}

check_symlinked_client() {
  local temp_dir

  log "checking symlinked client behavior"
  temp_dir="$(mktemp -d /tmp/upkeeper-symlink.XXXXXX)"

  git -C "$temp_dir" init -q
  touch "$temp_dir/tool.sh"
  chmod +x "$temp_dir/tool.sh"
  ln -s "$ROOT_DIR/Upkeeper" "$temp_dir/Upkeeper.sh"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  (
    cd "$temp_dir"
    ./Upkeeper.sh --version >/dev/null
    CODEX_HOME="$temp_dir/codex-home" \
      CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
      CODEX_TERMINAL_VERBOSITY=quiet \
      CODEX_MODEL=gpt-5.5 \
      CODEX_REASONING_EFFORT=xhigh \
      CODEX_FALLBACK_ENABLED=0 \
      CODEX_FALLBACK_SCREEN_ENABLED=0 \
      CODEX_POSTMORTEM_ENABLED=0 \
      UPKEEPER_DRY_RUN=1 \
      ./Upkeeper.sh >/dev/null
    grep -Fq "implementation=$ROOT_DIR/Upkeeper" Upkeeper.log
    grep -Fq "cycle.exit exit_code=0 reason=DRY_RUN" Upkeeper.log
  )
  rm -r "$temp_dir"
}

check_missing_module_failure() {
  local temp_dir rc

  log "checking copied launcher missing-module failure"
  temp_dir="$(mktemp -d /tmp/upkeeper-missing-module.XXXXXX)"

  cp Upkeeper "$temp_dir/Upkeeper"
  chmod +x "$temp_dir/Upkeeper"

  set +e
  "$temp_dir/Upkeeper" --version >"$temp_dir/out.txt" 2>"$temp_dir/err.txt"
  rc=$?
  set -e

  [[ "$rc" -eq 70 ]] || fail "missing-module check exited $rc, expected 70"
  grep -Fq "Upkeeper module missing" "$temp_dir/err.txt" || fail "missing-module error was not visible"
  rm -r "$temp_dir"
}

check_missing_prompt_failure() {
  local temp_dir rc

  log "checking missing default prompt-template failure"
  temp_dir="$(mktemp -d /tmp/upkeeper-missing-prompt.XXXXXX)"

  cp Upkeeper "$temp_dir/Upkeeper"
  chmod +x "$temp_dir/Upkeeper"
  cp -R lib "$temp_dir/lib"
  mkdir -p "$temp_dir/docs/scripts"
  cp docs/scripts/upkeeper.md "$temp_dir/docs/scripts/upkeeper.md"
  git -C "$temp_dir" init -q
  touch "$temp_dir/tool.sh"
  chmod +x "$temp_dir/tool.sh"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  (
    cd "$temp_dir"
    set +e
    CODEX_HOME="$temp_dir/codex-home" \
      CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
      CODEX_TERMINAL_VERBOSITY=quiet \
      CODEX_MODEL=gpt-5.5 \
      CODEX_REASONING_EFFORT=xhigh \
      CODEX_FALLBACK_ENABLED=0 \
      CODEX_FALLBACK_SCREEN_ENABLED=0 \
      CODEX_POSTMORTEM_ENABLED=0 \
      UPKEEPER_DRY_RUN=1 \
      ./Upkeeper >out.txt 2>err.txt
    rc=$?
    set -e

    [[ "$rc" -eq 70 ]] || fail "missing-prompt check exited $rc, expected 70"
    grep -Fq "PROMPT_TEMPLATE_MISSING" Upkeeper.log || fail "missing-prompt reason not logged"
    grep -Fq "prompt_template_missing" err.txt || fail "missing-prompt error was not visible"
  )
  rm -r "$temp_dir"
}

check_empty_transcript_failure() {
  local temp_dir rc

  log "checking empty transcript failure classification"
  temp_dir="$(mktemp -d /tmp/upkeeper-empty-transcript.XXXXXX)"
  mkdir -p "$temp_dir/bin" "$temp_dir/codex-home/sessions/2026/05/07"

  cat >"$temp_dir/bin/codex" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "exec" ]]; then
  cat >/dev/null
  exit 101
fi
exit 101
SH
  chmod +x "$temp_dir/bin/codex"

  python3 - "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" <<'PY'
import json
import sys
import time
from datetime import datetime, timezone

path = sys.argv[1]
now = int(time.time())
event_timestamp = datetime.fromtimestamp(now, timezone.utc).isoformat().replace("+00:00", "Z")
rows = [
    {"type": "turn_context", "payload": {"model": "gpt-5.5"}},
    {
        "timestamp": event_timestamp,
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "rate_limits": {
                "limit_id": "validation-gpt-5.5",
                "limit_name": "gpt-5.5 validation",
                "plan_type": "validation",
                "rate_limit_reached_type": None,
                "primary": {
                    "used_percent": 10.0,
                    "window_minutes": 300,
                    "resets_at": now + 3600,
                },
                "secondary": {
                    "used_percent": 10.0,
                    "window_minutes": 10080,
                    "resets_at": now + 86400,
                },
            },
        },
    },
]
with open(path, "w", encoding="utf-8") as handle:
    for row in rows:
        print(json.dumps(row, separators=(",", ":")), file=handle)
PY

  set +e
  PATH="$temp_dir/bin:$PATH" \
    CODEX_HOME="$temp_dir/codex-home" \
    CODEX_LOG_FILE="$temp_dir/Upkeeper.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$temp_dir/active.lock" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    CODEX_TERMINAL_VERBOSITY=quiet \
    CODEX_MODEL=gpt-5.5 \
    CODEX_REASONING_EFFORT=xhigh \
    CODEX_FALLBACK_ENABLED=1 \
    CODEX_FALLBACK_MODEL=gpt-5.3-codex-spark \
    CODEX_FALLBACK_SCREEN_ENABLED=0 \
    CODEX_POSTMORTEM_ENABLED=0 \
    "$ROOT_DIR/Upkeeper" --target-file=launcher_examples/spark_5.3_burn_out_xhigh.sh \
      >"$temp_dir/out.txt" 2>"$temp_dir/err.txt"
  rc=$?
  set -e

  [[ "$rc" -eq 3 ]] || fail "empty-transcript check exited $rc, expected 3"
  grep -Fq "reason=CODEX_EXEC_EMPTY_TRANSCRIPT" "$temp_dir/Upkeeper.log" || fail "empty-transcript reason not logged"
  grep -Fq "codex.session_diagnostics_ignored reason=empty_transcript" "$temp_dir/Upkeeper.log" || fail "empty-transcript diagnostics ignore not logged"
  grep -Fq "transcript_bytes=0 transcript_lines=0" "$temp_dir/Upkeeper.log" || fail "empty-transcript size evidence not logged"
  grep -Fq "session_end_state=codex_no_output agent_messages=0 tool_calls=0 tool_results=0" "$temp_dir/Upkeeper.log" || fail "empty-transcript summary still reported stale session diagnostics"
  if grep -Fq "TURN_ABORTED_WITHOUT_MARKER" "$temp_dir/Upkeeper.log"; then
    fail "empty-transcript check was misclassified as TURN_ABORTED_WITHOUT_MARKER"
  fi
  if grep -Fq "fallback.start" "$temp_dir/Upkeeper.log"; then
    fail "empty-transcript check attempted generic fallback before classification"
  fi
  rm -r "$temp_dir"
}

require_commands
if [[ "$MODE" == "deps" ]]; then
  check_dependencies
  log "dependency validation passed"
  exit 0
fi

check_syntax
check_version_consistency
check_module_map
check_prompt_template
check_help_and_diff
check_codex_mode_validation
check_cycle_start_log_contract
check_quota_fallback_exit_contract
check_review_module_flags
check_tool_failure_queue
check_public_docs_policy
check_fallback_artifact_helpers
check_postmortem_context_marker_classification
check_live_output_filter_pipe
check_review_summary_parser
check_process_control_guards
check_startup_anomaly_gate_allowlist

if [[ "$MODE" == "full" ]]; then
  check_central_dry_runs
  check_symlinked_client
  check_missing_module_failure
  check_missing_prompt_failure
  check_empty_transcript_failure
fi

log "$MODE validation passed"
