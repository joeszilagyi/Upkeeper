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
  ln
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
  bash -n Upkeeper.conf
  bash -n configurations/default.conf
  for module in lib/upkeeper/*.bash; do
    bash -n "$module"
  done
  bash -n testruns/*.sh
}

check_version_consistency() {
  local version header_version guide_version version_output release_notes_file

  log "checking version consistency"
  version="$(sed -n 's/^UPKEEPER_VERSION="\([^"]*\)"/\1/p' Upkeeper)"
  [[ -n "$version" ]] || fail "UPKEEPER_VERSION not found"
  release_notes_file="change_notes_$(date +%Y).md"

  header_version="$(sed -n 's/^## Version: //p' Upkeeper | sed -n '1p')"
  [[ "$header_version" == "$version" ]] || fail "Upkeeper header version $header_version != $version"

  guide_version="$(sed -n 's/^Version: //p' docs/scripts/upkeeper.md | sed -n '1p')"
  [[ "$guide_version" == "$version" ]] || fail "operator guide version $guide_version != $version"

  [[ ! -e change_notes.md ]] || fail "release notes must use annual change_notes_YYYY.md files"
  [[ -s "$release_notes_file" ]] || fail "$release_notes_file is missing or empty"
  grep -Fq "$version changes:" "$release_notes_file" || fail "$release_notes_file missing $version entry"

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
  [[ -s prompts/p28-unit-test-harvesting-review.md ]] || fail "P28 review module prompt is missing or empty"
  [[ -s Upkeeper.conf ]] || fail "root Upkeeper.conf is missing or empty"
  [[ -s configurations/default.conf ]] || fail "configurations/default.conf is missing or empty"
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
  grep -Fq "P28 - Unit Test Harvesting Review" prompts/p28-unit-test-harvesting-review.md || fail "P28 prompt title missing"
  grep -Fq "P28: not applicable" prompts/p28-unit-test-harvesting-review.md || fail "P28 applicability gate missing"
  grep -Fq "without backend model quota" prompts/p28-unit-test-harvesting-review.md || fail "P28 local test contract missing"
  grep -Fq "code-comment clarity" README.md || fail "README missing P26 summary"
  grep -Fq "educational debrief" README.md || fail "README missing P27 summary"
  grep -Fq "unit-test harvesting" README.md || fail "README missing P28 summary"
  grep -Fq "Upkeeper.conf" README.md || fail "README missing config file summary"
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
  grep -Fq -- "--review-module=p28" <<<"$help" || fail "help missing --review-module=p28"
  grep -Fq -- "--config-file=PATH" <<<"$help" || fail "help missing --config-file"
  grep -Fq -- "--no-config" <<<"$help" || fail "help missing --no-config"
  grep -Fq -- "--target-root=PATH" <<<"$help" || fail "help missing --target-root"
  grep -Fq -- "--selection-source=manifest|enumerate" <<<"$help" || fail "help missing --selection-source"
  grep -Fq -- "--selection-order=oldest|newest|random" <<<"$help" || fail "help missing --selection-order"
  grep -Fq -- "--refresh-manifest" <<<"$help" || fail "help missing --refresh-manifest"
  grep -Fq -- "--manifest-file=PATH" <<<"$help" || fail "help missing --manifest-file"
  grep -Fq -- "--include-glob=PATTERN" <<<"$help" || fail "help missing --include-glob"
  grep -Fq -- "--include-globs=a,b" <<<"$help" || fail "help missing --include-globs"
  grep -Fq -- "--exclude-glob=PATTERN" <<<"$help" || fail "help missing --exclude-glob"
  grep -Fq -- "--exclude-globs=a,b" <<<"$help" || fail "help missing --exclude-globs"
  grep -Fq -- "--selection-review-modules=p24,p25,p26,p27,p28" <<<"$help" || fail "help missing --selection-review-modules"
  grep -Fq -- "--p24" <<<"$help" || fail "help missing --p24"
  grep -Fq -- "--p25" <<<"$help" || fail "help missing --p25"
  grep -Fq -- "--p26" <<<"$help" || fail "help missing --p26"
  grep -Fq -- "--p27" <<<"$help" || fail "help missing --p27"
  grep -Fq -- "--p28" <<<"$help" || fail "help missing --p28"
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

check_disk_preflight_log_contract() {
  local temp_dir path_with_token path_q output extracted_free synthetic_free

  log "checking disk preflight log quoting"
  temp_dir="$(mktemp -d /tmp/upkeeper-disk-preflight.XXXXXX)"
  path_with_token="$temp_dir/path with spaces/free_percent=999"
  mkdir -p "$path_with_token"

  if ! output="$(
    bash -c '
      set -euo pipefail
      shell_quote() { printf "%q" "$1"; }
      source "$1"
      fields="$(disk_space_fields "arg0 tmp" "$2")"
      free_percent="$(disk_preflight_free_percent_from_fields "$fields")"
      synthetic_free="$(disk_preflight_free_percent_from_fields "label=root size_kb=1 used_kb=0 avail_kb=1 used_percent=0 free_percent=88 mount=/ path=/tmp/free_percent=999 probe_path=/tmp")"
      printf "%s\n" "$fields"
      printf "extracted_free=%s\n" "$free_percent"
      printf "synthetic_free=%s\n" "$synthetic_free"
    ' bash "$ROOT_DIR/lib/upkeeper/disk_preflight.bash" "$path_with_token"
  )"; then
    fail "disk preflight log contract check failed"
  fi

  printf -v path_q '%q' "$path_with_token"
  grep -Fq "label=arg0\\ tmp" <<<"$output" || fail "disk preflight label was not shell-quoted"
  grep -Fq "path=$path_q" <<<"$output" || fail "disk preflight path was not shell-quoted"
  extracted_free="$(sed -n 's/^extracted_free=//p' <<<"$output")"
  [[ -n "$extracted_free" ]] || fail "disk preflight free_percent extraction returned empty"
  [[ "$extracted_free" != "999" ]] || fail "disk preflight free_percent extraction used the path token"
  [[ "$extracted_free" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || fail "disk preflight free_percent was not numeric: $extracted_free"
  synthetic_free="$(sed -n 's/^synthetic_free=//p' <<<"$output")"
  [[ "$synthetic_free" == "88" ]] || fail "disk preflight free_percent parser did not use the intended field"

  rm -r "$temp_dir"
}

check_arg0_tmp_cleanup_contract() {
  local temp_dir arg0_root quarantine_root output

  log "checking Codex arg0 temp cleanup contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-arg0-cleanup.XXXXXX)"
  arg0_root="$temp_dir/arg0"
  quarantine_root="$temp_dir/quarantine"

  mkdir -p "$arg0_root/codex-arg0-old" "$arg0_root/unmanaged-cache"
  printf 'shim\n' >"$arg0_root/codex-arg0-old/shim"
  printf 'keep\n' >"$arg0_root/unmanaged-cache/keep"
  touch -t 202001010000 "$arg0_root/codex-arg0-old" "$arg0_root/unmanaged-cache"

  if ! output="$(
    CODEX_ARG0_TMP_ROOT="$arg0_root" \
      CODEX_ARG0_TMP_QUARANTINE_ROOT="$quarantine_root" \
      CODEX_ARG0_TMP_PREFLIGHT=1 \
      CODEX_ARG0_TMP_STALE_MINUTES=60 \
      CODEX_ARG0_TMP_ROTATE_ON_BLOCKED=1 \
      CODEX_HOME_DIR="$temp_dir/codex-home" \
      bash -c 'source "$1"; codex_arg0_tmp_cleanup_check' bash "$ROOT_DIR/lib/upkeeper/arg0_preflight.bash"
  )"; then
    fail "arg0 cleanup contract check failed"
  fi

  [[ "$output" == "ok removed=1 quarantined=0" ]] || fail "arg0 cleanup returned unexpected output: $output"
  [[ ! -e "$arg0_root/codex-arg0-old" ]] || fail "stale codex-arg0 shim directory was not removed"
  [[ -f "$arg0_root/unmanaged-cache/keep" ]] || fail "non-codex stale directory was modified"

  rm -r "$temp_dir"
}

check_bwrap_tmp_preflight_contract() {
  local temp_dir output rc

  log "checking Codex bubblewrap temp preflight contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-bwrap-preflight.XXXXXX)"

  if ! output="$(
    cd "$temp_dir"
    CODEX_BWRAP_TMP_ROOT="-bwrap-root" \
      CODEX_BWRAP_TMP_PREFLIGHT=1 \
      bash -c 'source "$1"; codex_bwrap_tmp_write_check' bash "$ROOT_DIR/lib/upkeeper/bwrap_preflight.bash"
  )"; then
    fail "bwrap temp preflight failed for a leading-dash relative root"
  fi

  [[ "$output" == "ok" ]] || fail "bwrap temp preflight returned unexpected output: $output"
  [[ -f "$temp_dir/-bwrap-root/lock" ]] || fail "bwrap temp preflight did not create the lock file"
  if compgen -G "$temp_dir/-bwrap-root/.upkeeper-write-test.*" >/dev/null; then
    fail "bwrap temp preflight left a probe directory behind"
  fi

  printf 'not a directory\n' >"$temp_dir/not-dir"
  set +e
  output="$(
    CODEX_BWRAP_TMP_ROOT="$temp_dir/not-dir" \
      CODEX_BWRAP_TMP_PREFLIGHT=1 \
      bash -c 'source "$1"; codex_bwrap_tmp_write_check' bash "$ROOT_DIR/lib/upkeeper/bwrap_preflight.bash"
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 1 ]] || fail "bwrap temp not-directory check exited $rc, expected 1"
  [[ "$output" == "not_directory:$temp_dir/not-dir" ]] || fail "bwrap temp not-directory check returned unexpected output: $output"

  rm -r -- "$temp_dir"
}

check_wrapper_health_log_quoting() {
  local temp_dir health_dir archive_dir state_file rc

  log "checking wrapper health log quoting"
  temp_dir="$(mktemp -d "/tmp/upkeeper-health quote.XXXXXX")"
  health_dir="$temp_dir/health state"
  archive_dir="$temp_dir/retired health"
  write_validation_quota_snapshot "$temp_dir/codex home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  CODEX_HOME="$temp_dir/codex home" \
    CODEX_LOG_FILE="$temp_dir/Upkeeper.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$temp_dir/active.lock" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$health_dir" \
    CODEX_WRAPPER_HEALTH_ARCHIVE_DIR="$archive_dir" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    CODEX_TERMINAL_VERBOSITY=quiet \
    CODEX_MODEL=gpt-5.5 \
    CODEX_REASONING_EFFORT=xhigh \
    CODEX_FALLBACK_ENABLED=0 \
    CODEX_FALLBACK_SCREEN_ENABLED=0 \
    CODEX_POSTMORTEM_ENABLED=0 \
    UPKEEPER_DRY_RUN=1 \
    ./Upkeeper --target-file=Upkeeper >"$temp_dir/first.out" 2>"$temp_dir/first.err"

  state_file="$(find "$health_dir" -maxdepth 1 -type f -name '*.state' | sort | sed -n '1p')"
  [[ -n "$state_file" ]] || fail "wrapper health dry-run did not create a state file"

  python3 - "$state_file" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
replacements = {
    "status": "running",
    "pid": "999999999",
    "last_mark_epoch": "1",
    "updated_epoch": "1",
}
updated = []
for line in lines:
    key = line.split("=", 1)[0]
    if key in replacements:
        updated.append(f"{key}={replacements[key]}")
    else:
        updated.append(line)
path.write_text("\n".join(updated) + "\n", encoding="utf-8")
PY

  : >"$temp_dir/Upkeeper.log"
  set +e
  CODEX_HOME="$temp_dir/codex home" \
    CODEX_LOG_FILE="$temp_dir/Upkeeper.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$temp_dir/active.lock" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$health_dir" \
    CODEX_WRAPPER_HEALTH_ARCHIVE_DIR="$archive_dir" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    CODEX_TERMINAL_VERBOSITY=quiet \
    CODEX_MODEL=gpt-5.5 \
    CODEX_REASONING_EFFORT=xhigh \
    CODEX_FALLBACK_ENABLED=0 \
    CODEX_FALLBACK_SCREEN_ENABLED=0 \
    CODEX_POSTMORTEM_ENABLED=0 \
    UPKEEPER_DRY_RUN=1 \
    ./Upkeeper --target-file=Upkeeper >"$temp_dir/second.out" 2>"$temp_dir/second.err"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "wrapper health quote dry-run exited $rc"
  grep -Fq "central_wrapper.health status=reclaimed action=archive" "$temp_dir/Upkeeper.log" || fail "wrapper health did not log stale-state archive"
  grep -Eq "state_file='[^']*health state/[^']*[.]state'" "$temp_dir/Upkeeper.log" || fail "wrapper health state_file path with spaces was not quoted"
  grep -Eq "archived_state_file='[^']*retired health/[^']*[.]state'" "$temp_dir/Upkeeper.log" || fail "wrapper health archived_state_file path with spaces was not quoted"
  rm -r "$temp_dir"
}

check_operator_guide_bootstrap_race() {
  local temp_dir guide_path

  log "checking operator guide bootstrap no-overwrite race"
  temp_dir="$(mktemp -d /tmp/upkeeper-operator-guide.XXXXXX)"
  guide_path="$temp_dir/docs/scripts/upkeeper.md"

  (
    set -euo pipefail
    CODEX_OPERATOR_GUIDE_PATH="$guide_path"
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=1
    CODEX_LOG_FILE="$temp_dir/Upkeeper.log"
    CODEX_TERMINAL_VERBOSITY=silent
    CODEX_HOME="$temp_dir/codex-home"
    CODEX_ACTIVE_LOCK_DIR="$temp_dir/active.lock"
    CODEX_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health"
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates"
    source "$ROOT_DIR/Upkeeper"

    mktemp() {
      local created
      created="$(command mktemp "$@")" || return 1
      mkdir -p "$(dirname -- "$CODEX_OPERATOR_GUIDE_PATH")"
      printf 'operator-created-guide\n' >"$CODEX_OPERATOR_GUIDE_PATH"
      printf '%s\n' "$created"
    }

    ensure_operator_guide
  )

  grep -Fxq "operator-created-guide" "$guide_path" || fail "operator guide bootstrap overwrote a race-created guide"
  if compgen -G "$temp_dir/docs/scripts/.upkeeper-guide.*" >/dev/null; then
    fail "operator guide bootstrap left a temp guide after the race path"
  fi
  grep -Fq "operator_guide.version_missing" "$temp_dir/Upkeeper.log" || fail "operator guide race-created file was not checked"
  rm -r "$temp_dir"
}

check_active_lock_incomplete_guard() {
  local temp_dir rc

  log "checking active lock incomplete-acquisition guard"
  temp_dir="$(mktemp -d /tmp/upkeeper-active-lock.XXXXXX)"
  mkdir "$temp_dir/active.lock"

  set +e
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
    ./Upkeeper --target-file=Upkeeper >"$temp_dir/out.txt" 2>"$temp_dir/err.txt"
  rc=$?
  set -e

  [[ "$rc" -eq 7 ]] || fail "incomplete active lock exited $rc, expected 7"
  grep -Fq "active_lock.incomplete" "$temp_dir/Upkeeper.log" || fail "incomplete active lock was not logged"
  grep -Fq "reason=UPKEEPER_ACTIVE_LOCK_HELD" "$temp_dir/Upkeeper.log" || fail "incomplete active lock did not use held exit reason"
  [[ -d "$temp_dir/active.lock" ]] || fail "incomplete active lock guard removed a fresh lock directory"
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
    ./Upkeeper --target-file=Upkeeper --review-modules=p24,p25,p26,p27,p28 >"$temp_dir/out.txt" 2>"$temp_dir/err.txt"

  grep -Fq "review_modules=p24,p25,p26,p27,p28" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not record selected modules"
  grep -Fq "review.module_prompt enabled module=p24" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not append P24"
  grep -Fq "review.module_prompt enabled module=p25" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not append P25"
  grep -Fq "review.module_prompt enabled module=p26" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not append P26"
  grep -Fq "review.module_prompt enabled module=p27" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not append P27"
  grep -Fq "review.module_prompt enabled module=p28" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not append P28"
  grep -Fq "cycle.exit exit_code=0 reason=DRY_RUN" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not finish cleanly"

  output="$(./Upkeeper --p24 --p25 --p26 --p27 --p28 --version)"
  [[ "$output" == "Upkeeper $(sed -n 's/^UPKEEPER_VERSION="\([^"]*\)"/\1/p' Upkeeper)" ]] || fail "review module shorthand flags broke --version"

  set +e
  output="$(./Upkeeper --review-module=nope --version 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || fail "invalid review module exited $rc, expected 3"
  grep -Fq "unknown review module: nope" <<<"$output" || fail "invalid review module error was not clear"

  rm -r "$temp_dir"
}

check_config_file_support() {
  local temp_dir profile output rc

  log "checking config file support"
  temp_dir="$(mktemp -d /tmp/upkeeper-config-file.XXXXXX)"
  profile="$temp_dir/profile.conf"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  cat >"$profile" <<'EOF'
CODEX_MODEL="gpt-5.5"
CODEX_REASONING_EFFORT="xhigh"
CODEX_TERMINAL_VERBOSITY="quiet"
CODEX_FALLBACK_ENABLED="0"
CODEX_FALLBACK_SCREEN_ENABLED="0"
CODEX_POSTMORTEM_ENABLED="0"
UPKEEPER_TARGET_FILE="Upkeeper"
UPKEEPER_REVIEW_MODULES="p28"
UPKEEPER_PROMPT_PASS="all"
UPKEEPER_IGNORE_FAILURE_QUEUE="1"
EOF

  CODEX_HOME="$temp_dir/codex-home" \
    CODEX_LOG_FILE="$temp_dir/Upkeeper.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$temp_dir/active.lock" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    UPKEEPER_DRY_RUN=1 \
    ./Upkeeper --config-file="$profile" >"$temp_dir/config.out" 2>"$temp_dir/config.err"

  grep -Fq "config_loaded=1" "$temp_dir/Upkeeper.log" || fail "config dry-run did not record loaded config"
  grep -Fq "config_file=$profile" "$temp_dir/Upkeeper.log" || fail "config dry-run did not record config path"
  grep -Fq "model=gpt-5.5" "$temp_dir/Upkeeper.log" || fail "config dry-run did not apply model"
  grep -Fq "target_file=Upkeeper" "$temp_dir/Upkeeper.log" || fail "config dry-run did not apply target file"
  grep -Fq "prompt_pass=all" "$temp_dir/Upkeeper.log" || fail "config dry-run did not apply prompt pass"
  grep -Fq "review_modules=p28" "$temp_dir/Upkeeper.log" || fail "config dry-run did not apply review module"
  grep -Fq "review.module_prompt enabled module=p28" "$temp_dir/Upkeeper.log" || fail "config dry-run did not append P28"

  : >"$temp_dir/Upkeeper.log"
  CODEX_HOME="$temp_dir/codex-home" \
    CODEX_LOG_FILE="$temp_dir/Upkeeper.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$temp_dir/active.lock" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    UPKEEPER_DRY_RUN=1 \
    ./Upkeeper --config-file="$profile" --target-file=lib/upkeeper/codex_io.bash --p26 >"$temp_dir/override.out" 2>"$temp_dir/override.err"

  grep -Fq "target_file=lib/upkeeper/codex_io.bash" "$temp_dir/Upkeeper.log" || fail "CLI target did not override config target"
  grep -Fq "review_modules=p26" "$temp_dir/Upkeeper.log" || fail "CLI review module did not override config modules"
  if grep -Fq "review_modules=p28" "$temp_dir/Upkeeper.log"; then
    fail "config review module leaked after CLI override"
  fi

  : >"$temp_dir/Upkeeper.log"
  UPKEEPER_CONFIG_FILE="$profile" \
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
    ./Upkeeper --no-config --target-file=Upkeeper >"$temp_dir/no-config.out" 2>"$temp_dir/no-config.err"

  grep -Fq "config_loaded=0" "$temp_dir/Upkeeper.log" || fail "--no-config did not disable config loading"

  set +e
  output="$(./Upkeeper --config-file="$temp_dir/missing.conf" --version 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || fail "missing explicit config exited $rc, expected 3"
  grep -Fq "config file not found" <<<"$output" || fail "missing explicit config error was not clear"

  rm -r "$temp_dir"
}

check_file_manifest_selection() {
  local temp_dir manifest_path output rc

  log "checking file manifest selection"
  temp_dir="$(mktemp -d /tmp/upkeeper-file-manifest.XXXXXX)"
  manifest_path="$temp_dir/manifest.json"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  run_manifest_dry_run() {
    local log_file="$1"
    shift
    CODEX_HOME="$temp_dir/codex-home" \
      CODEX_LOG_FILE="$log_file" \
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
      CODEX_FILE_MANIFEST_PATH="$manifest_path" \
      CODEX_UPKEEPER_SELF_REVIEW_AFTER_DAYS=99999 \
      UPKEEPER_DRY_RUN=1 \
      ./Upkeeper "$@" >"$temp_dir/out.txt" 2>"$temp_dir/err.txt"
  }

  run_manifest_dry_run "$temp_dir/manifest.log" \
    --target-root=lib/upkeeper \
    --target-depth=1 \
    --selection-source=manifest \
    --selection-order=oldest \
    --refresh-manifest

  [[ -s "$manifest_path" ]] || fail "manifest dry-run did not write manifest"
  grep -Fq "file_manifest.ready action=rebuilt reason=forced_refresh" "$temp_dir/manifest.log" || fail "manifest refresh was not logged"
  grep -Fq "selection_source=manifest" "$temp_dir/manifest.log" || fail "manifest selection source was not logged"
  grep -Fq "target_root=lib/upkeeper" "$temp_dir/manifest.log" || fail "manifest target root was not logged"
  grep -Fq "target_depth=1" "$temp_dir/manifest.log" || fail "manifest target depth was not logged"
  grep -Fq "cycle.exit exit_code=0 reason=DRY_RUN" "$temp_dir/manifest.log" || fail "manifest dry-run did not finish cleanly"
  jq -e '.schema_version == 1 and (.files | length) > 0 and (.files[0].abs_path | length > 0)' "$manifest_path" >/dev/null || fail "manifest JSON contract is invalid"

  run_manifest_dry_run "$temp_dir/newest.log" \
    --target-root=lib/upkeeper \
    --target-depth=1 \
    --selection-source=manifest \
    --selection-order=newest

  grep -Fq "file_manifest.ready action=reused reason=current" "$temp_dir/newest.log" || fail "current manifest was not reused"
  grep -Fq "selection_order=newest" "$temp_dir/newest.log" || fail "newest selection order was not logged"

  run_manifest_dry_run "$temp_dir/enumerate.log" \
    --selection-source=enumerate \
    --selection-order=random \
    --target-root=lib/upkeeper \
    --target-depth=1 \
    --include-glob='*.bash' \
    --exclude-glob='status_session.bash' \
    --selection-review-modules=p25,p26

  grep -Fq "file_manifest.skip reason=selection_source_disabled source=enumerate" "$temp_dir/enumerate.log" || fail "enumerate mode did not skip manifest"
  grep -Fq "selection_source=enumerate" "$temp_dir/enumerate.log" || fail "enumerate selection source was not logged"
  grep -Fq "selection_order=random" "$temp_dir/enumerate.log" || fail "random selection order was not logged"
  grep -Fq "include_globs=\\*.bash" "$temp_dir/enumerate.log" || fail "include glob was not shell-escaped in log"
  grep -Fq "exclude_globs=status_session.bash" "$temp_dir/enumerate.log" || fail "exclude glob was not logged"
  grep -Fq "selection_review_modules=p25\\,p26" "$temp_dir/enumerate.log" || fail "selection review module filter was not shell-escaped in log"

  CODEX_FILE_MANIFEST_MODE=off run_manifest_dry_run "$temp_dir/mode-off.log" \
    --selection-source=manifest \
    --target-root=lib/upkeeper \
    --target-depth=1
  grep -Fq "file_manifest.skip reason=manifest_mode_off" "$temp_dir/mode-off.log" || fail "manifest mode off was not logged"
  grep -Fq "selection_source=enumerate" "$temp_dir/mode-off.log" || fail "manifest mode off did not fall back to enumerate selection"

  run_manifest_dry_run "$temp_dir/forced.log" \
    --target-file=Upkeeper \
    --target-root=lib/upkeeper \
    --selection-source=manifest
  grep -Fq "review.preselect path=Upkeeper" "$temp_dir/forced.log" || fail "--target-file did not override target-root selection filter"

  set +e
  output="$(./Upkeeper --selection-review-modules=nope --version 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || fail "invalid selection review module exited $rc, expected 3"
  grep -Fq "unknown review module filter: nope" <<<"$output" || fail "invalid selection review module error was not clear"

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

check_runtime_format_json_helpers() {
  local got err_file rc

  log "checking runtime format/json helper contracts"
  source lib/upkeeper/runtime_format_json.bash

  got="$(format_epoch_local "")"
  [[ "$got" == "unknown" ]] || fail "empty epoch formatted as $got instead of unknown"
  got="$(format_epoch_local "not-an-epoch")"
  [[ "$got" == "not-an-epoch" ]] || fail "unformattable epoch fallback returned $got"

  got="$(json_field '{"accepted_marker":"WORK_DONE","candidate_marker":null}' '.accepted_marker')"
  [[ "$got" == "WORK_DONE" ]] || fail "json_field returned $got for accepted_marker"
  got="$(json_field '{"accepted_marker":"WORK_DONE","candidate_marker":null}' '.candidate_marker')"
  [[ -z "$got" ]] || fail "json_field returned $got for null candidate_marker"
  got="$(json_field '{"enabled":false}' '.enabled')"
  [[ "$got" == "false" ]] || fail "json_field dropped boolean false as ${got:-<empty>}"

  err_file="$(mktemp /tmp/upkeeper-json-field.XXXXXX)"
  set +e
  got="$(json_field '{' '.accepted_marker' 2>"$err_file")"
  rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || fail "json_field accepted malformed JSON"
  [[ -z "$got" ]] || fail "json_field wrote stdout for malformed JSON: $got"
  grep -Fq "json_field failed for jq path .accepted_marker" "$err_file" ||
    fail "json_field malformed JSON diagnostic missing"
  rm -f "$err_file"
}

check_startup_anomaly_state_parser_contract() {
  local temp_dir state_dir output

  log "checking startup anomaly state parser log contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-startup-state.XXXXXX)"
  state_dir="$temp_dir/startup gates"
  mkdir -p "$state_dir"
  printf 'cycle_id=cycle with spaces\nrun_hash=hash with spaces\nstatus=unresolved\ncreated_epoch=123 extra=bad\nreason=manual reason\n' >"$state_dir/bad state.state"

  output="$(
    cd "$ROOT_DIR"
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$state_dir" bash -c 'source lib/upkeeper/startup_anomaly_state.bash; startup_anomaly_state_lines'
  )"

  grep -Fq 'previous_cycle=cycle\ with\ spaces' <<<"$output" || fail "startup anomaly cycle id was not log-escaped"
  grep -Fq 'previous_run_hash=hash\ with\ spaces' <<<"$output" || fail "startup anomaly run hash was not log-escaped"
  grep -Fq 'bad\ state.state' <<<"$output" || fail "startup anomaly state path was not log-escaped"
  grep -Fq 'state_reason=manual\ reason' <<<"$output" || fail "startup anomaly reason was not log-escaped"
  grep -Eq 'created_epoch=[0-9]+ ' <<<"$output" || fail "startup anomaly fallback epoch missing"
  if grep -Fq 'extra=bad' <<<"$output"; then
    fail "startup anomaly parser accepted malformed created_epoch as log fields"
  fi
  if grep -Fq 'startup gates' <<<"$output" || grep -Fq 'manual reason' <<<"$output"; then
    fail "startup anomaly parser emitted raw whitespace in log field values"
  fi

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

check_postmortem_sequence_marker_contract() {
  local temp_dir case_name case_dir rc expected_status expected_log

  log "checking postmortem sequence marker contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-postmortem-sequence.XXXXXX)"

  for case_name in report_missing_marker hardening_missing_marker; do
    case_dir="$temp_dir/$case_name"
    mkdir -p "$case_dir/tmp"

    if ! CODEX_LOG_FILE="$case_dir/Upkeeper.log" \
      CODEX_POSTMORTEM_DIR="$case_dir/postmortems" \
      CODEX_TRANSCRIPT_DIR="$case_dir/transcripts" \
      CODEX_ACTIVE_LOCK_DIR="$case_dir/active.lock" \
      CODEX_WRAPPER_HEALTH_STATE_DIR="$case_dir/health" \
      CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
      CODEX_TERMINAL_VERBOSITY=silent \
      TMPDIR="$case_dir/tmp" \
      bash -lc '
        set -euo pipefail
        cd "$1"
        case_dir="$2"
        case_name="$3"

        source ./Upkeeper

        CYCLE_ID="validation-$case_name"
        CYCLE_RUN_HASH="validation-$case_name"
        LOG_FILE="$case_dir/Upkeeper.log"
        CODEX_POSTMORTEM_DIR="$case_dir/postmortems"
        TMPDIR="$case_dir/tmp"
        last_message_file="$case_dir/primary-last-message.txt"
        FALLBACK_SCREEN_TRANSCRIPT_PATH="$case_dir/fallback-last-message.txt"
        FALLBACK_SCREEN_EXIT_CODE=0
        DIRTY_PATH_COUNT=0
        TRACKED_MODIFIED_PATH_COUNT=0
        UNTRACKED_PATH_COUNT=0

        : >"$LOG_FILE"
        : >"$last_message_file"
        : >"$FALLBACK_SCREEN_TRANSCRIPT_PATH"

        run_aux_codex_exec() {
          local phase_label="$1"
          local last_message_path="$6"

          case "$phase_label:$case_name" in
            postmortem.report:report_missing_marker)
              {
                printf "# Upkeeper Postmortem\n"
                printf "## Incident Summary\n"
                printf "Report fixture without required marker.\n"
              } >"$POSTMORTEM_REPORT_PATH"
              printf "report fixture omitted required marker\n" >"$last_message_path"
              return 0
              ;;
            postmortem.report:hardening_missing_marker)
              {
                printf "# Upkeeper Postmortem\n"
                printf "## Incident Summary\n"
                printf "Report fixture with required marker.\n"
              } >"$POSTMORTEM_REPORT_PATH"
              printf "CODEX_POSTMORTEM_STATUS: REPORT_WRITTEN\n" >"$last_message_path"
              return 0
              ;;
            postmortem.hardening:hardening_missing_marker)
              printf "hardening fixture omitted required marker\n" >"$last_message_path"
              return 0
              ;;
          esac

          printf "unexpected auxiliary phase: %s for %s\n" "$phase_label" "$case_name" >&2
          return 64
        }

        set +e
        run_postmortem_sequence "failure" "marker contract" "0" >"$case_dir/sequence.out" 2>"$case_dir/sequence.err"
        rc=$?
        set -e

        printf "%s\n" "$rc" >"$case_dir/rc.txt"
        printf "%s\n" "$POSTMORTEM_SEQUENCE_STATUS" >"$case_dir/status.txt"
      ' bash "$ROOT_DIR" "$case_dir" "$case_name" >"$case_dir/bash.out" 2>"$case_dir/bash.err"; then
      cat "$case_dir/bash.err" >&2
      fail "postmortem sequence marker contract setup failed for $case_name"
    fi

    rc="$(tr -d '[:space:]' <"$case_dir/rc.txt")"
    [[ "$rc" == "8" ]] || fail "$case_name exited $rc, expected 8"

    case "$case_name" in
      report_missing_marker)
        expected_status="report_failed"
        expected_log="postmortem.report failed exit_code=0 marker=missing expected_marker=REPORT_WRITTEN"
        ;;
      hardening_missing_marker)
        expected_status="hardening_failed"
        expected_log="postmortem.hardening failed exit_code=0 marker=missing expected_marker=HARDENING_DONE"
        ;;
      *)
        fail "unknown marker contract case: $case_name"
        ;;
    esac

    grep -Fxq "$expected_status" "$case_dir/status.txt" || fail "$case_name status was not $expected_status"
    grep -Fq "$expected_log" "$case_dir/Upkeeper.log" || fail "$case_name did not log expected marker failure"
  done

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
/bin/bash -lc 'rg ERROR change_notes_2026.md'
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
diff --git a/change_notes_2026.md b/change_notes_2026.md
--- a/change_notes_2026.md
+++ b/change_notes_2026.md
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
  grep -Eq "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ search started: /bin/bash -lc 'rg ERROR change_notes_2026.md'" "$temp_dir/live-verbose.err" || fail "verbose live output did not report search command start"
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

check_status_session_jsonl_contract() {
  local temp_dir session_file state diagnostics agent_messages reached_type

  log "checking status session JSONL contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-status-session.XXXXXX)"
  session_file="$temp_dir/session.jsonl"
  printf '%s\n' \
    '[]' \
    '{"type":"event_msg","payload":"not-an-object"}' \
    '{"type":"event_msg","payload":{"type":"turn_aborted","reason":"rate limit / retry"}}' \
    '{"type":"response_item","payload":{"type":"message","role":"assistant"}}' \
    '{"type":"event_msg","payload":{"type":"token_count","rate_limits":"not-an-object"}}' \
    >"$session_file"

  state="$(bash -lc 'cd "$1"; source lib/upkeeper/status_session.bash; parse_session_end_state "$2"' bash "$ROOT_DIR" "$session_file")"
  [[ "$state" == "turn_aborted:rate_limit_retry" ]] || fail "malformed JSONL state was $state"

  diagnostics="$(bash -lc 'cd "$1"; source lib/upkeeper/status_session.bash; session_diagnostics_json "$2"' bash "$ROOT_DIR" "$session_file")"
  agent_messages="$(jq -r '.agent_message_count' <<<"$diagnostics")"
  reached_type="$(jq -r '.last_rate_limit_reached_type' <<<"$diagnostics")"
  [[ "$agent_messages" == "1" ]] || fail "malformed JSONL agent message count was $agent_messages"
  [[ "$reached_type" == "unknown" ]] || fail "malformed JSONL rate-limit sentinel was $reached_type"

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
  "change_notes_2026.md": {"status": "clean", "hash": "old"},
  "docs/scripts/upkeeper.md": {"status": "clean", "hash": "old"},
  "lib/upkeeper/worktree_state.bash": {"status": "clean", "hash": "old"},
  "tools/validate_upkeeper.sh": {"status": "clean", "hash": "old"},
  "unrelated.txt": {"status": "clean", "hash": "old"}
}
JSON
  cat >"$after_file" <<'JSON'
{
  "Upkeeper": {"status": "modified", "hash": "new"},
  "change_notes_2026.md": {"status": "modified", "hash": "new"},
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
check_disk_preflight_log_contract
check_arg0_tmp_cleanup_contract
check_bwrap_tmp_preflight_contract
check_wrapper_health_log_quoting
check_operator_guide_bootstrap_race
check_active_lock_incomplete_guard
check_quota_fallback_exit_contract
check_review_module_flags
check_config_file_support
check_file_manifest_selection
check_tool_failure_queue
check_public_docs_policy
check_fallback_artifact_helpers
check_runtime_format_json_helpers
check_startup_anomaly_state_parser_contract
check_postmortem_context_marker_classification
check_postmortem_sequence_marker_contract
check_live_output_filter_pipe
check_review_summary_parser
check_status_session_jsonl_contract
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
