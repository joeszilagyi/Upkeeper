#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
TOOLS_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
ROOT_DIR="$(cd -- "$TOOLS_DIR/.." && pwd)"
UPKEEPER_IMPLEMENTATION_DIR="$ROOT_DIR"
source "$ROOT_DIR/lib/upkeeper/review_modules.bash"

MODE="quick"
VALIDATION_PROFILE="0"
VALIDATION_INTEGRATION_TIMEOUT_SECONDS="${VALIDATION_INTEGRATION_TIMEOUT_SECONDS:-300}"
VALIDATION_FULL_TIMEOUT_SECONDS="${VALIDATION_FULL_TIMEOUT_SECONDS:-420}"
VALIDATION_FILE_MANIFEST_TIMEOUT_SECONDS="${VALIDATION_FILE_MANIFEST_TIMEOUT_SECONDS:-600}"

WRAPPER_REQUIRED_COMMANDS=(
  bash
  awk
  cat
  chmod
  cut
  date
  df
  env
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
  wc
)

WRAPPER_BACKEND_COMMANDS=(
  codex
)

WRAPPER_CONDITIONAL_COMMANDS=(
  screen
)

WRAPPER_LAUNCHER_REQUIRED_COMMANDS=(
  age
)

WRAPPER_OPTIONAL_COMMANDS=(
  realpath
  stat
  zip
)

usage() {
  cat <<'USAGE'
Usage: tools/validate_upkeeper.sh [--smoke|--quick|--full|--deps] [--profile]

Validate the central Upkeeper checkout.

Modes:
  --deps    Report runtime/tool dependency status.
  --smoke   Run the fast local edit-loop checks: syntax, version, module map,
            prompt templates, help/docs/diff, parser helpers, and launcher
            argument contracts.
  --quick   Run smoke plus bounded static/fixture checks. Quick mode does not
            run wrapper dry-run integration paths such as manifest or Lattice
            selection.
  --full    Run quick checks plus bounded safe dry-runs, symlink behavior, the
            local stress corpus, and failure paths.

Flags:
  --profile Print elapsed time for each validation check.

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

validation_now_us() {
  local now="${EPOCHREALTIME:-}"
  if [[ -n "$now" ]]; then
    printf '%s\n' "${now/./}"
    return 0
  fi
  date +%s%6N
}

validation_run_check() {
  local name="$1"
  local timeout_seconds="$2"
  shift
  shift
  local start_us end_us elapsed_us
  local pid rc elapsed

  if [[ "$VALIDATION_PROFILE" == "1" ]]; then
    start_us="$(validation_now_us)"
  fi

  if [[ "$timeout_seconds" =~ ^[0-9]+$ && "$timeout_seconds" -gt 0 ]]; then
    set +e
    "$@" &
    pid=$!
    elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
      if ((elapsed >= timeout_seconds)); then
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        set -e
        fail "check $name exceeded ${timeout_seconds}s timeout"
      fi
      sleep 1
      elapsed=$((elapsed + 1))
    done
    wait "$pid"
    rc=$?
    set -e
    if [[ "$rc" -ne 0 ]]; then
      return "$rc"
    fi
  else
    "$@"
  fi

  if [[ "$VALIDATION_PROFILE" == "1" ]]; then
    end_us="$(validation_now_us)"
    elapsed_us=$((end_us - start_us))
    printf 'validate_upkeeper: timing check=%s elapsed=%d.%03ds\n' \
      "$name" "$((elapsed_us / 1000000))" "$(((elapsed_us % 1000000) / 1000))"
  fi
}

run_check() {
  local name="$1"
  shift
  validation_run_check "$name" 0 "$@"
}

run_bounded_check() {
  local name="$1"
  local timeout_seconds="$2"
  shift
  shift
  validation_run_check "$name" "$timeout_seconds" "$@"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --smoke)
      MODE="smoke"
      ;;
    --quick)
      MODE="quick"
      ;;
    --full)
      MODE="full"
      ;;
    --deps)
      MODE="deps"
      ;;
    --profile)
      VALIDATION_PROFILE="1"
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

VALIDATION_TMP_ROOT="$(mktemp -d /tmp/upkeeper-validate.XXXXXX)"
VALIDATION_ACTIVE_LOCK_TOKEN="upkeeper-validate-active-locks/${VALIDATION_TMP_ROOT##*/}.$$"
VALIDATION_ACTIVE_LOCK_ROOT="$ROOT_DIR/runtime/$VALIDATION_ACTIVE_LOCK_TOKEN"
trap 'rm -r "$VALIDATION_TMP_ROOT" "$VALIDATION_ACTIVE_LOCK_ROOT" 2>/dev/null || true' EXIT
export CODEX_POSTMORTEM_DIR="$VALIDATION_TMP_ROOT/postmortems"
export UPKEEPER_PRECONTACT_BACKUP_ROOT="$VALIDATION_TMP_ROOT/precontact-vault"
export UPKEEPER_AUTOMATION_LEDGER_DIR="$VALIDATION_TMP_ROOT/automation-ledger"
export UPKEEPER_OBLIGATION_DIR="$VALIDATION_TMP_ROOT/automation-obligations"

# The validator is often launched from FlameOn/ChimneySweep full-burn cycles.
# Keep validation fixtures on the plain Upkeeper defaults unless an individual
# check explicitly exercises launcher behavior.
export CODEX_5H_STOP_PERCENT=5
export CODEX_SPARK_5H_STOP_PERCENT=0
export CODEX_WEEK_STOP_PERCENT=15
export CODEX_WEEK_STOP_BUFFER_PERCENT=0
export CODEX_SPARK_WEEK_STOP_BUFFER_PERCENT=5
export CODEX_QUOTA_GUARDRAIL_BYPASS=0
export CODEX_QUOTA_COOLDOWN_BYPASS=0
export UPKEEPER_LATTICE_REQUIRED=0
export UPKEEPER_PRECONTACT_BACKUP_MODE=auto
export UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
export UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1
export UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT=""

validation_active_lock_dir() {
  local checkout_root="$1"
  local name="${2:-active}"
  local safe_name
  local lock_root

  [[ -n "$checkout_root" ]] || checkout_root="$ROOT_DIR"
  safe_name="${name//[^A-Za-z0-9_.-]/_}"
  [[ -n "$safe_name" ]] || safe_name="active"
  lock_root="$checkout_root/runtime/$VALIDATION_ACTIVE_LOCK_TOKEN"
  mkdir -p "$lock_root"
  printf '%s/%s.lock\n' "$lock_root" "$safe_name"
}

run_upkeeper_validation_cycle() {
  local checkout_root="$1"
  local name="$2"
  local code_home="$3"
  local log_file="$4"
  local transcript_dir="$5"
  local out_file="$6"
  local err_file="$7"
  shift 7
  local safe_name active_lock_dir health_state_dir health_archive_dir startup_gate_dir
  local guide_bootstrap terminal_verbosity model reasoning_effort dry_run
  local fallback_enabled fallback_screen_enabled postmortem_enabled
  local -a env_args=()

  [[ -n "$checkout_root" ]] || checkout_root="$ROOT_DIR"
  safe_name="${name//[^A-Za-z0-9_.-]/_}"
  [[ -n "$safe_name" ]] || safe_name="validation-cycle"

  active_lock_dir="${VALIDATION_CYCLE_ACTIVE_LOCK_DIR:-$(validation_active_lock_dir "$checkout_root" "$safe_name")}"
  health_state_dir="${VALIDATION_CYCLE_WRAPPER_HEALTH_STATE_DIR:-$VALIDATION_TMP_ROOT/health-$safe_name}"
  health_archive_dir="${VALIDATION_CYCLE_WRAPPER_HEALTH_ARCHIVE_DIR:-$VALIDATION_TMP_ROOT/retired-health-$safe_name}"
  startup_gate_dir="${VALIDATION_CYCLE_STARTUP_ANOMALY_GATE_STATE_DIR:-$VALIDATION_TMP_ROOT/startup-gates-$safe_name}"
  guide_bootstrap="${VALIDATION_CYCLE_OPERATOR_GUIDE_BOOTSTRAP:-0}"
  terminal_verbosity="${VALIDATION_CYCLE_TERMINAL_VERBOSITY:-quiet}"
  model="${VALIDATION_CYCLE_CODEX_MODEL:-gpt-5.5}"
  reasoning_effort="${VALIDATION_CYCLE_REASONING_EFFORT:-xhigh}"
  fallback_enabled="${VALIDATION_CYCLE_FALLBACK_ENABLED:-0}"
  fallback_screen_enabled="${VALIDATION_CYCLE_FALLBACK_SCREEN_ENABLED:-0}"
  postmortem_enabled="${VALIDATION_CYCLE_POSTMORTEM_ENABLED:-0}"
  dry_run="${VALIDATION_CYCLE_UPKEEPER_DRY_RUN:-1}"

  env_args=(
    "CODEX_HOME=$code_home"
    "CODEX_LOG_FILE=$log_file"
    "CODEX_TRANSCRIPT_DIR=$transcript_dir"
    "CODEX_ACTIVE_LOCK_DIR=$active_lock_dir"
    "CODEX_WRAPPER_HEALTH_STATE_DIR=$health_state_dir"
    "CODEX_WRAPPER_HEALTH_ARCHIVE_DIR=$health_archive_dir"
    "CODEX_STARTUP_ANOMALY_GATE_STATE_DIR=$startup_gate_dir"
    "CODEX_OPERATOR_GUIDE_BOOTSTRAP=$guide_bootstrap"
    "CODEX_TERMINAL_VERBOSITY=$terminal_verbosity"
    "CODEX_MODEL=$model"
    "CODEX_REASONING_EFFORT=$reasoning_effort"
    "CODEX_FALLBACK_ENABLED=$fallback_enabled"
    "CODEX_FALLBACK_SCREEN_ENABLED=$fallback_screen_enabled"
    "CODEX_POSTMORTEM_ENABLED=$postmortem_enabled"
    "UPKEEPER_DRY_RUN=$dry_run"
  )

  if [[ "${VALIDATION_CYCLE_CODEX_MODE+x}" ]]; then
    env_args+=("CODEX_MODE=$VALIDATION_CYCLE_CODEX_MODE")
  fi
  if [[ "${VALIDATION_CYCLE_VERBOSE_METADATA+x}" ]]; then
    env_args+=("UPKEEPER_VERBOSE_METADATA=$VALIDATION_CYCLE_VERBOSE_METADATA")
  fi
  if [[ "${VALIDATION_CYCLE_LOG_ROTATE_KEEP_HOURS+x}" ]]; then
    env_args+=("CODEX_LOG_ROTATE_KEEP_HOURS=$VALIDATION_CYCLE_LOG_ROTATE_KEEP_HOURS")
  fi
  if [[ "${VALIDATION_CYCLE_LOG_ROTATE_AFTER_HOURS+x}" ]]; then
    env_args+=("CODEX_LOG_ROTATE_AFTER_HOURS=$VALIDATION_CYCLE_LOG_ROTATE_AFTER_HOURS")
  fi
  if [[ "${VALIDATION_CYCLE_CONFIG_FILE+x}" ]]; then
    env_args+=("UPKEEPER_CONFIG_FILE=$VALIDATION_CYCLE_CONFIG_FILE")
  fi

  (
    cd "$checkout_root"
    env "${env_args[@]}" ./Upkeeper "$@"
  ) >"$out_file" 2>"$err_file"
}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || fail "missing required command: $command_name; see docs/dependencies.md"
}

platform_support_status_line() {
  local kernel wsl_note

  kernel="$(uname -s 2>/dev/null || printf unknown)"
  wsl_note=""
  if [[ "$kernel" == "Linux" && -r /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
    wsl_note="; WSL detected"
  fi

  case "$kernel" in
    Linux)
      printf 'ok\tplatform\t%s\tLinux with GNU userland is the supported CI/operator baseline%s\n' "$kernel" "$wsl_note"
      return 0
      ;;
    Darwin)
      printf 'missing\tplatform\t%s\tmacOS is documented as deferred until BSD/GNU utility drift is resolved\n' "$kernel"
      return 1
      ;;
    *)
      printf 'missing\tplatform\t%s\tunsupported platform; see docs/dependencies.md\n' "$kernel"
      return 1
      ;;
  esac
}

require_supported_platform() {
  local kernel

  kernel="$(uname -s 2>/dev/null || printf unknown)"
  case "$kernel" in
    Linux)
      return 0
      ;;
    Darwin)
      fail "unsupported platform: macOS/Darwin is documented as deferred; see docs/dependencies.md"
      ;;
    *)
      fail "unsupported platform: $kernel; see docs/dependencies.md"
      ;;
  esac
}

require_commands() {
  local command_name
  for command_name in bash chmod cp date diff find git grep jq ln mkdir mktemp python3 rm sed sort touch tr uname wc; do
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
  local unsupported_platform=0
  local missing_required=0
  local missing_launcher_required=0

  log "checking wrapper dependencies"
  printf 'status\tclass\tcommand\tnote\n'

  platform_support_status_line || unsupported_platform=1

  for command_name in "${WRAPPER_REQUIRED_COMMANDS[@]}"; do
    dependency_status_line "required" "$command_name" "required by Upkeeper startup/runtime" || missing_required=1
  done

  for command_name in "${WRAPPER_BACKEND_COMMANDS[@]}"; do
    dependency_status_line "backend" "$command_name" "required for non-dry-run codex exec cycles" || true
  done

  for command_name in "${WRAPPER_CONDITIONAL_COMMANDS[@]}"; do
    dependency_status_line "conditional" "$command_name" "required when detached screen fallback is enabled" || true
  done

  for command_name in "${WRAPPER_LAUNCHER_REQUIRED_COMMANDS[@]}"; do
    dependency_status_line "launcher-required" "$command_name" "required for live FlameOn/ChimneySweep full-burn encrypted backup" || missing_launcher_required=1
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

  [[ "$unsupported_platform" -eq 0 ]] || fail "unsupported platform for unattended Upkeeper runs; see docs/dependencies.md"
  [[ "$missing_required" -eq 0 ]] || fail "one or more required wrapper dependencies are missing; see docs/dependencies.md"
  [[ "$missing_launcher_required" -eq 0 ]] || fail "one or more full-burn launcher dependencies are missing; see docs/dependencies.md"
}

check_private_artifact_umask_contract() {
  log "checking private artifact umask contract"
  python3 - "$ROOT_DIR/Upkeeper" <<'PY' || fail "Upkeeper does not set umask 077 before other executable statements"
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
for line in lines:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    if stripped == "set -euo pipefail":
        continue
    raise SystemExit(0 if stripped == "umask 077" else 1)
raise SystemExit(1)
PY
}

check_issue_fix_private_packet_contract() {
  log "checking issue-fix private packet contract"
  grep -Fq 'UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL' "$ROOT_DIR/Upkeeper.conf" || fail "Upkeeper.conf does not expose the private issue packet gate"
  grep -Fq 'UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL' "$ROOT_DIR/configurations/default.conf" || fail "default config does not expose the private issue packet gate"
  grep -Fq 'UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL' "$ROOT_DIR/docs/scripts/upkeeper.md" || fail "operator docs do not describe the private issue packet gate"
  grep -Fq 'issue_url=withheld' "$ROOT_DIR/lib/upkeeper/prompt_compile.bash" || fail "issue-fix prompt no longer withholds private issue metadata by default"
  grep -Fq 'UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL=1' "$ROOT_DIR/lib/upkeeper/prompt_compile.bash" || fail "issue-fix prompt does not describe the explicit private-packet opt-in"
  grep -Fq 'issue_packet_to_model=' "$ROOT_DIR/lib/upkeeper/codex_io.bash" || fail "issue-fix selection log does not declare private-packet model exposure"
  grep -Fq 'title_hash=' "$ROOT_DIR/lib/upkeeper/codex_io.bash" || fail "issue-fix selection log does not hash the issue title"
  grep -Fq 'url_hash=' "$ROOT_DIR/lib/upkeeper/codex_io.bash" || fail "issue-fix selection log does not hash the issue URL"
  if grep -Fq 'url=$(shell_quote "$CODEX_ISSUE_FIX_URL") title=$(shell_quote "$CODEX_ISSUE_FIX_TITLE")' "$ROOT_DIR/lib/upkeeper/codex_io.bash"; then
    fail "issue-fix selection log still emits raw issue URL/title text"
  fi
  bash tests/bug_fix_batch_271_266_265_test.bash
}

check_authority_control_docs_contract() {
  local control_id

  log "checking authority control docs contract"
  [[ -s docs/authority.md ]] || fail "docs/authority.md is missing"
  [[ -s docs/capability-profiles.md ]] || fail "docs/capability-profiles.md is missing"
  [[ -s docs/control-ledger.md ]] || fail "docs/control-ledger.md is missing"
  [[ -s docs/policy-decisions.md ]] || fail "docs/policy-decisions.md is missing"

  grep -Fq "Authority Questions" docs/authority.md ||
    fail "authority model is missing the authority questions table"
  grep -Fq "Wrapper local control plane" docs/capability-profiles.md ||
    fail "capability profiles do not name the wrapper local control plane"
  grep -Fq "Backend Codex issue apply stage" docs/capability-profiles.md ||
    fail "capability profiles do not cover issue apply backend authority"
  grep -Fq "Control id" docs/control-ledger.md ||
    fail "control ledger is missing its control id table"

  for control_id in AUTH-001 AUTH-002 AUTH-003 AUTH-004 AUTH-005 AUTH-006 AUTH-007 AUTH-008 AUTH-009 AUTH-010 AUTH-011 AUTH-012 AUTH-013; do
    grep -Fq "| $control_id |" docs/control-ledger.md ||
      fail "control ledger missing $control_id"
  done

  grep -Fq "docs/authority.md" README.md ||
    fail "README does not point to the authority model"
  grep -Fq "docs/capability-profiles.md" docs/security.md ||
    fail "security docs do not point to capability profiles"
  grep -Fq "docs/control-ledger.md" docs/compatibility.md ||
    fail "compatibility docs do not preserve the control-ledger contract"
  grep -Fq "docs/policy-decisions.md" README.md ||
    fail "README does not point to the policy decision schema"
  grep -Fq "docs/policy-decisions.md" docs/authority.md ||
    fail "authority docs do not point to policy decisions"
  grep -Fq "docs/policy-decisions.md" docs/security.md ||
    fail "security docs do not point to policy decisions"
  grep -Fq "docs/policy-decisions.md" docs/compatibility.md ||
    fail "compatibility docs do not preserve the policy decision schema contract"
}

check_policy_decisions_contract() {
  log "checking structured policy decision contract"
  [[ -s lib/upkeeper/policy_decisions.bash ]] || fail "policy decision module is missing or empty"
  grep -Fq '"policy_decisions.bash"' Upkeeper || fail "module map does not load policy_decisions.bash"
  grep -Fq '`policy_decisions.bash`' lib/upkeeper/README.md || fail "module README missing policy_decisions.bash ownership"
  grep -Fq 'schema_version' docs/policy-decisions.md || fail "policy decision docs missing schema_version"
  grep -Fq 'may_contact_backend' docs/policy-decisions.md || fail "policy decision docs missing backend-contact field"
  grep -Fq 'may_write_source' docs/policy-decisions.md || fail "policy decision docs missing source-write field"
  grep -Fq 'may_retarget' docs/policy-decisions.md || fail "policy decision docs missing retarget field"
  grep -Fq 'denied_actions' docs/policy-decisions.md || fail "policy decision docs missing denied_actions field"
  grep -Fq 'wrapper-local-control-plane' docs/capability-profiles.md || fail "capability profiles missing policy profile ids"
  bash tests/policy_decisions_test.bash
}

check_schema_compatibility_contract() {
  local term
  local -a required_terms

  log "checking schema compatibility contract"
  required_terms=(
    "## Compatibility Classes"
    '`stable`'
    '`experimental`'
    '`deprecated`'
    '`removed`'
    "## Schema And Contract Version Rules"
    "## Migration And Deprecation Rules"
    "## Public Examples And Validation"
    "## Lattice Import/Export Compatibility"
    "schema_version"
    "row_type"
    "row_version"
    "logical_key"
    "payload_sha256"
    "record conflicts instead of silently"
  )
  for term in "${required_terms[@]}"; do
    grep -Fq "$term" docs/compatibility.md ||
      fail "compatibility docs missing schema contract term: $term"
  done

  grep -Fq "Lattice export/import compatibility is governed by" docs/lattice.md ||
    fail "Lattice docs do not point to compatibility contract"
  grep -Fq "recorded as conflicts rather than overwritten silently" docs/lattice.md ||
    fail "Lattice docs missing JSONL conflict compatibility rule"
  grep -Fq "unclassified" README.md &&
    grep -Fq "tracked public behavior defaults to stable" README.md ||
    fail "README missing default stable compatibility rule"
  grep -Fq "stable by default" docs/public-documentation-policy.md ||
    fail "public documentation policy missing default stable compatibility rule"
  grep -Fq "Prompt compatibility" prompts/README.md ||
    fail "prompt index missing prompt compatibility section"
  grep -Fq "UPKEEPER_PASS_RESULT" prompts/README.md ||
    fail "prompt compatibility section missing pass-result marker contract"
}

check_syntax() {
  local module

  log "checking Bash syntax"
  bash -n Upkeeper
  bash -n FlameOn
  bash -n ChimneySweep
  bash -n Upkeeper.conf
  bash -n configurations/default.conf
  bash -n completions/*.bash
  for module in lib/upkeeper/*.bash; do
    bash -n "$module"
  done
  bash -n tools/*.sh
  bash -n tests/*.bash
  bash -n testruns/*.sh
  bash -n orchestration/*.sh
  python3 - <<'PY'
from pathlib import Path

path = Path("tools/check_upkeeper_log_invariants.py")
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
}

check_log_line_source_length_contract() {
  local offenders

  log "checking log-line source length contract"
  grep -Fq 'log_line_parts()' lib/upkeeper/runtime_foundation.bash ||
    fail "runtime foundation is missing log_line_parts helper"
  grep -Fq 'startup_anomaly_log_gate_unresolved()' lib/upkeeper/startup_anomaly_state.bash ||
    fail "startup anomaly gate logging is not centralized"

  offenders="$(
    awk '
      length($0) > 240 && /log_line/ {
        printf "%s:%d:%d:%s\n", FILENAME, FNR, length($0), $0
      }
    ' Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash
  )"
  if [[ -n "$offenders" ]]; then
    printf '%s\n' "$offenders" >&2
    fail "log_line/log_line_parts call sites exceed 240 characters"
  fi
}

check_test_invocation_mode_contract() {
  local bad_modes

  log "checking test invocation mode contract"
  bad_modes="$(
    find tests -maxdepth 1 -type f -name '*.bash' -perm /111 -print |
      sort
  )"
  [[ -z "$bad_modes" ]] ||
    fail "tests/*.bash must be non-executable and invoked with bash: $bad_modes"

  grep -Fq 'bash "$test_script"' .github/workflows/ci.yml ||
    fail "CI no longer invokes tests through bash"
  python3 - <<'PY' || fail "CI unit-test step does not fail fast explicitly"
from pathlib import Path

text = Path(".github/workflows/ci.yml").read_text(encoding="utf-8")
unit_block = text.split("- name: Unit tests", 1)[1].split("- name: Public docs", 1)[0]
raise SystemExit(0 if "set -euo pipefail" in unit_block else 1)
PY
  grep -Fq 'unit tests invoked with Bash from' README.md ||
    fail "README no longer documents Bash-invoked tests"
  grep -Fq 'set -e; for test_script in tests/*.bash; do bash "$test_script"; done' docs/dependencies.md ||
    fail "dependencies docs no longer show Bash-invoked tests"
  grep -Fq 'set -e; for test_script in tests/*.bash; do bash "$test_script"; done' AGENTS.md ||
    fail "agent contract no longer shows Bash-invoked tests"
}

check_backlog_launcher_contract() {
  local temp_dir status

  log "checking backlog launcher safety contract"
  grep -Fq 'BACKLOG_ALLOW_INTERACTIVE_STDIO' orchestration/backlog.sh || fail "backlog launcher missing interactive-stdio override"
  grep -Fq 'BACKLOG_INTERACTIVE_MODE="${BACKLOG_INTERACTIVE_MODE:-watch}"' orchestration/backlog.sh || fail "backlog launcher does not default interactive use to watch mode"
  grep -Fq 'backlog_run_owned_watch_pipeline' orchestration/backlog.sh || fail "backlog launcher does not own and wait on the interactive watch pipeline"
  grep -Fq 'wait "$BACKLOG_WATCH_FORMATTER_PID"' orchestration/backlog.sh || fail "backlog launcher does not wait for watch formatter drain before returning to the shell"
  ! grep -Fq '> >(backlog_timestamp_stream | tee -a "$log_file" | backlog_color_attention_stream)' orchestration/backlog.sh || fail "backlog launcher still uses asynchronous process substitution for watch output"
  grep -Fq 'backlog_timestamp_stream >>"$log_file"' orchestration/backlog.sh || fail "backlog launcher no longer exposes explicit timestamped detach mode"
  grep -Fq 'backlog_line_starts_with_timestamp' orchestration/backlog.sh || fail "backlog launcher does not avoid double-prefixing timestamped lines"
  grep -Fq 'backlog_attention_marker_for_line' orchestration/backlog.sh || fail "backlog launcher does not classify operator attention markers"
  grep -Fq 'backlog_color_attention_stream' orchestration/backlog.sh || fail "backlog launcher does not color pageable terminal alerts separately from the loop log"
  grep -Fq 'BACKLOG_VISUAL_BLOCK="${BACKLOG_VISUAL_BLOCK:-█}"' orchestration/backlog.sh || fail "backlog launcher visual status block default drifted"
  grep -Fq 'BACKLOG_JOB_SUMMARY_BAR="${BACKLOG_JOB_SUMMARY_BAR:-##### ##### #####}"' orchestration/backlog.sh || fail "backlog launcher green job summary bar default drifted"
  grep -Fq 'backlog_emit_job_start_summary' orchestration/backlog.sh || fail "backlog launcher does not emit local job start summaries"
  grep -Fq 'backlog_emit_job_finish_summary' orchestration/backlog.sh || fail "backlog launcher does not emit local job finish summaries"
  grep -Fq 'deferred no-change issue #' orchestration/backlog.sh || fail "backlog launcher does not locally defer issue-targeted no-change cycles"
  grep -Fq 'PAGE|--FYI--|WORKER|ACTION|WAIT|HEALTH|OK|RUN|INFO' orchestration/backlog.sh || fail "backlog launcher attention marker taxonomy drifted"
  grep -Fq '([+-][0-9][0-9][0-9][0-9])? /, "", candidate)' orchestration/backlog.sh || fail "backlog launcher recent-activity parser does not understand zone-suffixed timestamped loop logs"
  grep -Fq 'sub(/^[^[:space:]]+[[:space:]]+/, "", candidate)' orchestration/backlog.sh || fail "backlog launcher recent-activity parser does not strip visual block columns"
  grep -Fq 'sub(/^([A-Z][A-Z]+|--FYI--)[[:space:]]+/, "", candidate)' orchestration/backlog.sh || fail "backlog launcher recent-activity parser does not understand attention-marked loop logs"
  grep -Fq 'interactive stdio remained attached after backlog auto-detach' orchestration/backlog.sh || fail "backlog launcher does not fail closed after failed auto-detach"
  grep -Fq 'interactive stdin remained attached after backlog watch-mode reexec' orchestration/backlog.sh || fail "backlog launcher does not fail closed after failed watch-mode reexec"
  grep -Fq 'another backlog run already owns this checkout' orchestration/backlog.sh || fail "backlog launcher does not explain active backlog ownership"
  grep -Fq 'active-owner.' orchestration/backlog.sh || fail "backlog launcher does not track an explicit repo-local active owner file"
  grep -Fq 'start_ticks' orchestration/backlog.sh || fail "backlog launcher does not guard against stale PID reuse in active owner tracking"
  grep -Fq 'BACKLOG_DUPLICATE_MODE="${BACKLOG_DUPLICATE_MODE:-exit}"' orchestration/backlog.sh || fail "backlog launcher does not default duplicate invocations to clean exit"
  grep -Fq 'BACKLOG_OWNER_HEARTBEAT_STALE_SECONDS' orchestration/backlog.sh || fail "backlog launcher does not define owner heartbeat freshness"
  grep -Fq 'backlog_owner_health_status' orchestration/backlog.sh || fail "backlog launcher cannot classify active owner health"
  grep -Fq 'duplicate invocation not needed; primary owner is healthy; exiting 0' orchestration/backlog.sh || fail "backlog launcher does not plainly exit duplicate invocations"
  grep -Fq 'owner heartbeat: state=' orchestration/backlog.sh || fail "backlog launcher does not emit truthful owner heartbeats"
  grep -Fq 'backlog_wait_detail' orchestration/backlog.sh || fail "backlog launcher does not label wait planes"
  grep -Fq 'wait_elapsed_seconds' orchestration/backlog.sh || fail "backlog launcher does not emit elapsed wait metadata"
  grep -Fq 'backlog_refresh_active_owner_heartbeat' orchestration/backlog.sh || fail "backlog launcher heartbeat still risks replacing specific wait state"
  grep -Fq 'backlog_wait_detail llm codex_issue_repair' orchestration/backlog.sh || fail "backlog launcher does not label issue-repair backend waits"
  grep -Fq 'backlog_wait_detail_since github pr_checks' orchestration/backlog.sh || fail "backlog launcher does not label GitHub PR-check waits"
  grep -Fq 'plane=git waiting_for=push' orchestration/backlog.sh || fail "backlog launcher does not label git push waits"
  grep -Fq 'terminal_progress.start plane=llm waiting_for=codex_backend_review' lib/upkeeper/progress_logging.bash || fail "terminal progress does not label backend wait plane"
  grep -Fq 'run.finish plane=llm waiting_for=codex_backend_review' Upkeeper || fail "Upkeeper run.finish does not label backend wait plane"
  grep -Fq 'waiting_on_pr_checks' orchestration/backlog.sh || fail "backlog launcher does not keep PR-check waits under the owner lease"
  grep -Fq 'gh pr checks "$pr_number" --watch=false' orchestration/backlog.sh || fail "backlog launcher PR check watcher is not local polling"
  grep -Fq 'BACKLOG_PR_CHECK_PROGRESS="${BACKLOG_PR_CHECK_PROGRESS:-1}"' orchestration/backlog.sh || fail "backlog launcher does not default PR-check progress on"
  grep -Fq 'BACKLOG_PR_CHECKS_PROGRESS_SUMMARY' orchestration/backlog.sh || fail "backlog launcher does not preserve PR-check progress details for pending polls"
  grep -Fq 'gh run view "$run_id" --json jobs' orchestration/backlog.sh || fail "backlog launcher does not use local GitHub Actions job metadata for PR-check progress"
  grep -Fq 'BACKLOG_PR_CHECK_GATE_BEFORE_NEXT_ISSUE="${BACKLOG_PR_CHECK_GATE_BEFORE_NEXT_ISSUE:-1}"' orchestration/backlog.sh || fail "backlog launcher does not default PR-check gating before next issue"
  grep -Fq 'backlog_ensure_pr_checks_allow_next_issue' orchestration/backlog.sh || fail "backlog launcher does not gate issue selection on current PR checks"
  grep -Fq 'per-bug validation: python compile' orchestration/backlog.sh || fail "backlog launcher per-bug validation does not compile changed Python files"
  grep -Fq 'per-bug validation: lattice focused coverage (tests/lattice_test.bash)' orchestration/backlog.sh || fail "backlog launcher per-bug validation does not run focused Lattice coverage"
  grep -Fq 'BACKLOG_AUTOSHELVE_DIRTY_WORKTREE="${BACKLOG_AUTOSHELVE_DIRTY_WORKTREE:-1}"' orchestration/backlog.sh || fail "backlog launcher does not default dirty-worktree autoshelve on"
  grep -Fq 'autoshelving local changes to' orchestration/backlog.sh || fail "backlog launcher does not explain dirty-worktree autoshelve"
  grep -Fq 'autoshelve_next_branch_name' orchestration/backlog.sh || fail "backlog launcher no longer avoids autoshelve branch-name collisions"
  grep -Fq 'autoshelve_is_control_plane_trigger_path' orchestration/backlog.sh || fail "backlog launcher cannot identify dirty control-plane fixes"
  grep -Fq 'Upkeeper remediation path(s)' orchestration/backlog.sh || fail "backlog launcher does not locally apply autoshelved control-plane remediation"
  grep -Fq 'stopping before stale automation can run' orchestration/backlog.sh || fail "backlog launcher does not fail closed when control-plane remediation cannot apply"
  grep -Fq 'BACKLOG_QUOTA_HIBERNATE="${BACKLOG_QUOTA_HIBERNATE:-1}"' orchestration/backlog.sh || fail "backlog launcher does not default quota hibernation on"
  grep -Fq 'backlog_hibernate_until_epoch' orchestration/backlog.sh || fail "backlog launcher is missing quota hibernation helper"
  grep -Fq 'quota preflight: quota blocked bucket=' orchestration/backlog.sh || fail "backlog launcher does not explain quota hibernation"
  grep -Fq 'latest_active_primary_quota_block_marker' orchestration/backlog.sh || fail "backlog launcher does not honor active quota block markers"
  grep -Fq 'BACKLOG_QUOTA_GUARDRAIL_BYPASS="${BACKLOG_QUOTA_GUARDRAIL_BYPASS:-1}"' orchestration/backlog.sh || fail "backlog launcher does not default burn quota guardrail bypass on"
  grep -Fq 'BACKLOG_QUOTA_COOLDOWN_BYPASS="${BACKLOG_QUOTA_COOLDOWN_BYPASS:-1}"' orchestration/backlog.sh || fail "backlog launcher does not default burn quota cooldown bypass on"
  grep -Fq 'quota preflight: burn bypass continuing despite stale quota evidence' orchestration/backlog.sh || fail "backlog launcher does not explain stale quota bypass"
  grep -Fq 'backlog_open_stale_quota_obligation' orchestration/backlog.sh || fail "backlog launcher does not record stale quota evidence obligations"
  grep -Fq 'recorded_non_perfect_health=1' tests/backlog_stale_quota_obligation_test.bash || fail "stale quota obligation test does not assert non-perfect health output"
  grep -Fq 'BACKLOG_OBLIGATION_RETRY_LIMIT="${BACKLOG_OBLIGATION_RETRY_LIMIT:-3}"' orchestration/backlog.sh || fail "backlog launcher does not define obligation retry limit"
  grep -Fq 'cooldown_deferred' orchestration/backlog.sh || fail "backlog launcher does not stop fresh issue work while every obligation is cooling down"
  grep -Fq 'BACKLOG_OBLIGATION_ISSUE_REPORTS="${BACKLOG_OBLIGATION_ISSUE_REPORTS:-1}"' orchestration/backlog.sh || fail "backlog launcher does not default obligation issue reports on"
  grep -Fq 'BACKLOG_OBLIGATION_GITHUB_ISSUE_WRITE="${BACKLOG_OBLIGATION_GITHUB_ISSUE_WRITE:-1}"' orchestration/backlog.sh || fail "backlog launcher does not default obligation GitHub issue filing on"
  grep -Fq 'BACKLOG_ANOMALY_CUSTODY_MAX_FINDINGS="${BACKLOG_ANOMALY_CUSTODY_MAX_FINDINGS:-0}"' orchestration/backlog.sh || fail "backlog launcher still caps anomaly custody findings by default"
  grep -Fq 'backlog_sync_obligation_issue_reports' orchestration/backlog.sh || fail "backlog launcher does not sync obligation issue reports before selection"
  grep -Fq 'automation obligation GitHub issue creation had failures; stopping before normal issue selection' orchestration/backlog.sh || fail "backlog launcher does not fail closed when obligation issue filing fails"
  grep -Fq 'backlog_ensure_transcript_artifact_marker' orchestration/backlog.sh || fail "backlog launcher does not trust its owned transcript artifact directory"
  grep -Fq 'CODEX_LOG_FILE_ALLOW_UNSAFE="${BACKLOG_CODEX_LOG_FILE_ALLOW_UNSAFE:-1}"' orchestration/backlog.sh || fail "backlog launcher does not trust its owned custom log directory"
  grep -Fq 'BACKLOG_SOURCE_ONLY' orchestration/backlog.sh || fail "backlog launcher cannot be source-tested without running main"
  BACKLOG_SOURCE_ONLY=1 bash -lc '
    set -euo pipefail
    cd "$1"
    source ./orchestration/backlog.sh
    log() { :; }
    backlog_update_active_owner_heartbeat() { :; }
    run_changed_python_compile_validation() { return 0; }
    run_focused_issue_validation() { return 0; }
    git() { return 0; }
    bash() { return 42; }
    status=0
    if run_per_bug_validation 1 tools/upkeeper_lattice.py; then
      status=0
    else
      status="$?"
    fi
    [[ "$status" == "42" ]]
  ' bash "$ROOT_DIR" || fail "backlog per-bug validation does not propagate failed commands when called from a conditional"
  BACKLOG_SOURCE_ONLY=1 bash -lc '
    set -euo pipefail
    cd "$1"
    source ./orchestration/backlog.sh
    cleanup_ephemeral_artifacts() { :; }
    has_worktree_changes() { return 0; }
    run_per_bug_validation() { return 43; }
    git() { printf "git should not run after validation failure\n" >&2; return 99; }
    status=0
    if commit_and_push_changes 1 "" tools/upkeeper_lattice.py; then
      status=0
    else
      status="$?"
    fi
    [[ "$status" == "43" ]]
  ' bash "$ROOT_DIR" || fail "backlog commit path does not stop after per-bug validation failure"
  BACKLOG_SOURCE_ONLY=1 bash -lc '
    set -euo pipefail
    cd "$1"
    source ./orchestration/backlog.sh
    [[ "$(backlog_partial_commit_message 1 prior-run-abc "")" == "Preserve partial backlog work for obligation prior-run-abc" ]]
    [[ "$(backlog_partial_commit_message 1 "" "")" == "Preserve partial backlog work for automation obligation" ]]
    [[ "$(backlog_partial_commit_message 0 "" 123)" == "Preserve partial backlog work for issue #123" ]]
    [[ "$(backlog_partial_commit_message 0 "" "")" == "Preserve partial backlog work for wrapper-selected Upkeeper pass" ]]
  ' bash "$ROOT_DIR" || fail "backlog partial commit messages do not preserve obligation ownership"
  BACKLOG_SOURCE_ONLY=1 bash -lc '
    set -euo pipefail
    cd "$1"
    source ./orchestration/backlog.sh
    run_batch_validation() { return 44; }
    wait_for_pr_checks() { printf "wait_for_pr_checks should not run after batch validation failure\n" >&2; return 99; }
    gh() { printf "gh should not run after batch validation failure\n" >&2; return 98; }
    git() { printf "git should not run after batch validation failure\n" >&2; return 97; }
    status=0
    if merge_and_clean 410 backlog/test; then
      status=0
    else
      status="$?"
    fi
    [[ "$status" == "44" ]]
  ' bash "$ROOT_DIR" || fail "backlog merge path does not stop after batch validation failure"
  grep -Fq 'rm -f -- "$ROOT_DIR/\$db"' orchestration/backlog.sh || fail "backlog launcher does not clean literal db scratch artifacts before staging"
  python3 - <<'PY' || fail "backlog autoshelve no longer runs before gh/jq/rg dependency gates"
from pathlib import Path

text = Path("orchestration/backlog.sh").read_text(encoding="utf-8")
text = text[text.index("main()"):]
git_gate = text.index("require_command git")
autoshelve = text.index("autoshelve_dirty_worktree_if_enabled")
clean_gate = text.index("require_clean_worktree", autoshelve)
gh_gate = text.index("require_command gh")
jq_gate = text.index("require_command jq")
rg_gate = text.index("require_command rg")
assert git_gate < autoshelve < clean_gate < gh_gate < jq_gate < rg_gate
PY
  [[ -x orchestration/backlog_loop.sh ]] || fail "backlog safe loop wrapper is not executable"
  grep -Fq 'CODEX_TERMINAL_VERBOSITY="${BACKLOG_CODEX_TERMINAL_VERBOSITY:-${CODEX_TERMINAL_VERBOSITY:-quiet}}"' orchestration/backlog.sh || fail "backlog launcher does not default to quiet terminal output"
  grep -Fq 'backlog_loop_timestamp_stream >>"$log_file"' orchestration/backlog_loop.sh || fail "backlog loop wrapper does not detach stdin and record timestamped output"
  grep -Fq 'ineligible_explicit_issue_target' lib/upkeeper/codex_io.bash || fail "issue target handoff does not reject ineligible explicit targets before preselection"
  if command -v script >/dev/null 2>&1; then
    temp_dir="$VALIDATION_TMP_ROOT/backlog-stdio"
    mkdir -p "$temp_dir"
    printf '2026-05-15T17:21:47 █ RUN     backlog: running Upkeeper for issue #999 with gpt-5.3-codex-spark/xhigh target=tools/example.sh\n' >"$temp_dir/loop.log"
    status=0
    env -u BACKLOG_STDIO_WATCHED -u BACKLOG_STDIO_AUTODETACHED \
      -u BACKLOG_ALLOW_INTERACTIVE_STDIO -u BACKLOG_ALLOW_INTERACTIVE_STDIN \
      BACKLOG_STDIO_AUTODETACH_PROBE=1 BACKLOG_LOOP_LOG_FILE="$temp_dir/loop.log" \
      script -qfec ./orchestration/backlog.sh "$temp_dir/typescript" >/dev/null 2>&1 || status="$?"
    [[ "$status" == "0" ]] || fail "backlog launcher interactive stdio auto-detach probe exited $status"
    grep -Fq '# backlog: interactive stdin detected; keeping output in this terminal and mirroring to '"$temp_dir/loop.log" "$temp_dir/typescript" ||
      fail "backlog launcher did not explain interactive watch mode"
    python3 - "$temp_dir/typescript" <<'PY' ||
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
pattern = r"(?m)^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} █ INFO\s+# backlog: interactive stdin detected;"
raise SystemExit(0 if re.search(pattern, text) else 1)
PY
      fail "backlog launcher watch notice is not timestamped with a visual block and attention marker"
    grep -Fq '# backlog: recent activity: running Upkeeper for issue #999 with gpt-5.3-codex-spark/xhigh target=tools/example.sh' "$temp_dir/typescript" ||
      fail "backlog launcher did not parse timestamped recent activity"

    cat >"$temp_dir/fake-watch-child" <<'SH'
#!/usr/bin/env bash
printf 'fake child first\n'
printf 'fake child final\n'
exit 7
SH
    chmod +x "$temp_dir/fake-watch-child"
    status=0
    BACKLOG_SOURCE_ONLY=1 BACKLOG_ALERT_COLOR=never bash -lc '
      set -euo pipefail
      cd "$1"
      source ./orchestration/backlog.sh
      SCRIPT_PATH="$2"
      set +e
      backlog_run_owned_watch_pipeline "$3"
      rc="$?"
      set -e
      printf "SENTINEL_AFTER_HELPER\n"
      exit "$rc"
    ' bash "$ROOT_DIR" "$temp_dir/fake-watch-child" "$temp_dir/owned-watch.log" >"$temp_dir/owned-watch.out" 2>"$temp_dir/owned-watch.err" || status="$?"
    [[ "$status" == "7" ]] || fail "backlog owned watch pipeline did not preserve child exit status"
    grep -Fq 'fake child final' "$temp_dir/owned-watch.log" ||
      fail "backlog owned watch pipeline did not mirror final child output to the loop log"
    python3 - "$temp_dir/owned-watch.out" <<'PY' ||
import sys
from pathlib import Path

lines = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines()
try:
    final_index = next(index for index, line in enumerate(lines) if "fake child final" in line)
    sentinel_index = next(index for index, line in enumerate(lines) if line == "SENTINEL_AFTER_HELPER")
except StopIteration:
    raise SystemExit(1)
raise SystemExit(0 if final_index < sentinel_index else 1)
PY
      fail "backlog owned watch pipeline can return to the shell before formatter output drains"
  fi

  temp_dir="$VALIDATION_TMP_ROOT/backlog-alert-markers"
  mkdir -p "$temp_dir"
  BACKLOG_SOURCE_ONLY=1 bash -lc '
    set -euo pipefail
    cd "$1"
    source ./orchestration/backlog.sh
    backlog_format_attention_line "2026-05-16T17:00:37-0700 [ERROR] Upkeeper: primary cmd#15 check failed: exited 1 in 5s" >"$2/worker.out"
    backlog_format_attention_line "2026-05-17T10:26:29-0700 [ERROR] Upkeeper: primary: echo '\''ERROR: tools/upkeeper_lattice.py not found'\''" >"$2/echo-error.out"
    backlog_format_attention_line "2026-05-21T11:26:43-0700 [ERROR] Upkeeper: primary: printf \"2026-05-21T11:00:01-0700 [WARN] cycle=%s run_hash=abc startup_anomaly.gate status=active force_upkeeper=1 action=block_normal_selection_until_upkeeper_suite_checked\\\\n\" \"\$cycle\"" >"$2/printf-warn-fixture.out"
    backlog_format_attention_line "2026-05-16T18:12:41-0700 [ERROR] cycle=x run_hash=y active_lock.failed reason=state_write_failed" >"$2/page.out"
    backlog_format_attention_line "2026-05-16T18:20:00 backlog: quota preflight: deferring backlog run this cycle" >"$2/wait.out"
    backlog_format_attention_line "2026-05-16T18:20:30 Upkeeper: machine health blocked live cycle before issue selection: pre-contact backup prerequisite missing (recipient_missing)" >"$2/fyi.out"
    backlog_format_attention_line "2026-05-16T18:21:00 PAGE   [ERROR] already marked" >"$2/existing.out"
    backlog_format_attention_line "2026-05-16T18:21:01 █ RUN     backlog: running Upkeeper for issue #999 with gpt target=x" >"$2/existing-block.out"
    BACKLOG_ALERT_COLOR=always backlog_color_attention_line "$(backlog_format_attention_line "2026-05-16T18:21:02 Already up to date.")" >"$2/ok-color.out"
    BACKLOG_ALERT_COLOR=always backlog_color_attention_line "$(backlog_format_attention_line "2026-05-16T18:21:03 [ERROR] wrapper exploded")" >"$2/page-color.out"
    BACKLOG_ALERT_COLOR=always BACKLOG_ALERT_BLINK=0 backlog_color_attention_line "$(backlog_format_attention_line "2026-05-16T18:21:06 [ERROR] wrapper exploded")" >"$2/page-no-blink-color.out"
    BACKLOG_ALERT_COLOR=always backlog_color_attention_line "$(backlog_format_attention_line "2026-05-16T18:21:04 previous_run.anomaly_summary x")" >"$2/fyi-color.out"
    BACKLOG_ALERT_COLOR=always backlog_color_attention_line "$(backlog_format_attention_line "2026-05-16T18:21:05 backlog: running Upkeeper for issue #1")" >"$2/run-color.out"
    BACKLOG_ALERT_COLOR=always backlog_color_attention_line "$BACKLOG_JOB_SUMMARY_BAR" >"$2/job-bar-color.out"
    BACKLOG_STDIO_WATCHED=0
    BACKLOG_STDIO_AUTODETACHED=0
    backlog_emit_job_start_summary "tools/example.sh" "issue #1: example" "fix locally" >"$2/job-start.out" 2>&1
    BACKLOG_JOB_START_EPOCH=100
    BACKLOG_TEST_NOW_EPOCH=145
    BACKLOG_JOB_START_TIME="2026-05-16T18:21:07"
    BACKLOG_JOB_TARGET="tools/example.sh"
    backlog_emit_job_finish_summary "tracked changes committed and pushed" "PR #1 has 1/10 recorded fixes" >"$2/job-finish.out" 2>&1
    printf "%s\n" "$BACKLOG_JOB_SUMMARY_BLANK_SENTINEL" "$BACKLOG_JOB_SUMMARY_BAR_SENTINEL" "${BACKLOG_JOB_SUMMARY_LINE_SENTINEL}2026-05-16T18:21:08 file being worked: tools/example.sh" | backlog_timestamp_stream >"$2/job-stream.out"
  ' bash "$ROOT_DIR" "$temp_dir"
  grep -Fq '2026-05-16T17:00:37 █ WORKER  [ERROR] Upkeeper: primary cmd#15 check failed: exited 1 in 5s' "$temp_dir/worker.out" ||
    fail "backlog launcher did not classify worker command failures separately from pageable errors"
  grep -Fq "2026-05-17T10:26:29 █ INFO    [ERROR] Upkeeper: primary: echo 'ERROR: tools/upkeeper_lattice.py not found'" "$temp_dir/echo-error.out" ||
    fail "backlog launcher treated echoed model ERROR text as a pageable wrapper error"
  grep -Fq '2026-05-21T11:26:43 █ INFO    [ERROR] Upkeeper: primary: printf "2026-05-21T11:00:01-0700 [WARN] cycle=%s run_hash=abc startup_anomaly.gate status=active force_upkeeper=1 action=block_normal_selection_until_upkeeper_suite_checked\\n" "$cycle"' "$temp_dir/printf-warn-fixture.out" ||
    fail "backlog launcher treated model printf warning fixture text as a pageable wrapper error"
  grep -Fq '2026-05-16T18:12:41 █ PAGE    [ERROR] cycle=x run_hash=y active_lock.failed reason=state_write_failed' "$temp_dir/page.out" ||
    fail "backlog launcher did not classify wrapper/control-plane errors as PAGE"
  grep -Fq '2026-05-16T18:20:00 █ WAIT    backlog: quota preflight: deferring backlog run this cycle' "$temp_dir/wait.out" ||
    fail "backlog launcher did not classify quota waits as WAIT"
  grep -Fq '2026-05-16T18:20:30 █ --FYI-- Upkeeper: machine health blocked live cycle before issue selection: pre-contact backup prerequisite missing (recipient_missing)' "$temp_dir/fyi.out" ||
    fail "backlog launcher did not classify advisory health output as FYI"
  grep -Fxq '2026-05-16T18:21:00 █ PAGE    [ERROR] already marked' "$temp_dir/existing.out" ||
    fail "backlog launcher did not normalize existing attention markers into visual-block format"
  grep -Fxq '2026-05-16T18:21:01 █ RUN     backlog: running Upkeeper for issue #999 with gpt target=x' "$temp_dir/existing-block.out" ||
    fail "backlog launcher duplicated an existing visual block marker"
  grep -Fq $'\033[1;32m█\033[0m OK' "$temp_dir/ok-color.out" ||
    fail "backlog launcher did not color OK visual block green"
  grep -Fq $'\033[97;41m2026-05-16T18:21:03\033[0m \033[5;1;31m█\033[0m \033[5;1;31mPAGE   \033[0m \033[97m[\033[5;1;31mERROR\033[0m\033[97m] wrapper exploded\033[0m' "$temp_dir/page-color.out" ||
    fail "backlog launcher did not color PAGE timestamp/block/marker, white payload, and ERROR text with the expected blink boundary"
  grep -Fq $'\033[97;41m2026-05-16T18:21:06\033[0m \033[1;31m█\033[0m \033[1;31mPAGE   \033[0m \033[97m[\033[1;31mERROR\033[0m\033[97m] wrapper exploded\033[0m' "$temp_dir/page-no-blink-color.out" ||
    fail "backlog launcher did not honor BACKLOG_ALERT_BLINK=0 for PAGE block, marker, payload, and ERROR text"
  grep -Fq $'\033[38;5;208m2026-05-16T18:21:04\033[0m \033[1;38;5;208m█\033[0m \033[1;38;5;208m--FYI--\033[0m previous_run.anomaly_summary x' "$temp_dir/fyi-color.out" ||
    fail "backlog launcher did not color FYI timestamp/block/marker with the expected bold boundary"
  grep -Fq $'\033[1;36m█\033[0m RUN' "$temp_dir/run-color.out" ||
    fail "backlog launcher did not color RUN visual block cyan"
  grep -Fq $'\033[5;1;32m##### ##### #####\033[0m' "$temp_dir/job-bar-color.out" ||
    fail "backlog launcher did not color job summary bars bold blinking green"
  [[ "$(grep -Fc '##### ##### #####' "$temp_dir/job-start.out")" -eq 2 ]] ||
    fail "backlog launcher job start summary did not emit two green bars"
  grep -Fq 'file being worked: tools/example.sh' "$temp_dir/job-start.out" ||
    fail "backlog launcher job start summary omitted target file"
  grep -Fq 'why: issue #1: example' "$temp_dir/job-start.out" ||
    fail "backlog launcher job start summary omitted reason"
  grep -Fq 'expected outcome: fix locally' "$temp_dir/job-start.out" ||
    fail "backlog launcher job start summary omitted expected outcome"
  [[ "$(grep -Fc '##### ##### #####' "$temp_dir/job-finish.out")" -eq 2 ]] ||
    fail "backlog launcher job finish summary did not emit two green bars"
  grep -Fq 'file worked: tools/example.sh' "$temp_dir/job-finish.out" ||
    fail "backlog launcher job finish summary omitted target file"
  grep -Fq 'outcome/results: tracked changes committed and pushed' "$temp_dir/job-finish.out" ||
    fail "backlog launcher job finish summary omitted outcome"
  grep -Fq 'run time: 45s' "$temp_dir/job-finish.out" ||
    fail "backlog launcher job finish summary did not calculate runtime"
  python3 - "$temp_dir/job-stream.out" <<'PY' || fail "backlog launcher job summary sentinel stream was not rendered as plain local output"
import sys
from pathlib import Path

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
if lines[:3] != ["", "##### ##### #####", "2026-05-16T18:21:08 file being worked: tools/example.sh"]:
    raise SystemExit(1)
PY

  temp_dir="$VALIDATION_TMP_ROOT/backlog-burn-env"
  mkdir -p "$temp_dir"
  env -u BACKLOG_CODEX_MODEL \
    -u BACKLOG_CODEX_REASONING_EFFORT \
    -u BACKLOG_QUOTA_GUARDRAIL_BYPASS \
    -u BACKLOG_QUOTA_COOLDOWN_BYPASS \
    BACKLOG_SOURCE_ONLY=1 bash -lc '
    set -euo pipefail
    cd "$1"
    source ./orchestration/backlog.sh
    prepare_backlog_runtime_env
    printf "model=%s\n" "$CODEX_MODEL"
    printf "effort=%s\n" "$CODEX_REASONING_EFFORT"
    printf "week=%s\n" "$CODEX_WEEK_STOP_PERCENT"
    printf "bypass=%s\n" "$CODEX_QUOTA_GUARDRAIL_BYPASS"
    printf "cooldown=%s\n" "$CODEX_QUOTA_COOLDOWN_BYPASS"
  ' bash "$ROOT_DIR" >"$temp_dir/defaults.out"
  grep -Fxq 'model=gpt-5.3-codex-spark' "$temp_dir/defaults.out" ||
    fail "backlog launcher did not default to Spark model"
  grep -Fxq 'effort=xhigh' "$temp_dir/defaults.out" ||
    fail "backlog launcher did not default to xhigh reasoning"
  grep -Fxq 'week=0' "$temp_dir/defaults.out" ||
    fail "backlog launcher did not default to spend-to-zero weekly floor"
  grep -Fxq 'bypass=1' "$temp_dir/defaults.out" ||
    fail "backlog launcher did not export quota guardrail bypass"
  grep -Fxq 'cooldown=1' "$temp_dir/defaults.out" ||
    fail "backlog launcher did not export quota cooldown bypass"

  temp_dir="$VALIDATION_TMP_ROOT/backlog-owner-lease"
  mkdir -p "$temp_dir"
  BACKLOG_SOURCE_ONLY=1 \
    BACKLOG_STATE_ROOT="$temp_dir/state" \
    BACKLOG_TEST_OWNER_MATCH=1 \
    BACKLOG_TEST_NOW_EPOCH=1000 \
    BACKLOG_OWNER_HEARTBEAT_STALE_SECONDS=300 \
    bash -lc '
      set -euo pipefail
      cd "$1"
      source ./orchestration/backlog.sh
      owner_file="$(backlog_active_owner_file)"
      mkdir -p "$(dirname "$owner_file")"
      BACKLOG_ACTIVE_OWNER_START_TICKS=123
      backlog_write_owner_record "$owner_file" "$$" 123 branch "$2/loop.log" waiting_on_pr_checks "pr=397 checks_pending" 397 pending
      backlog_owner_health_status "$owner_file" >"$2/healthy.out"
      BACKLOG_TEST_NOW_EPOCH=1401
      export BACKLOG_TEST_NOW_EPOCH
      if backlog_owner_health_status "$owner_file" >"$2/stale.out"; then
        printf "owner unexpectedly healthy after stale heartbeat window\n" >&2
        exit 1
      fi
    ' bash "$ROOT_DIR" "$temp_dir"
  grep -Fq 'healthy pid=' "$temp_dir/healthy.out" ||
    fail "backlog launcher owner health check did not accept a fresh heartbeat"
  grep -Fq 'stale_heartbeat' "$temp_dir/stale.out" ||
    fail "backlog launcher owner health check did not reject a stale heartbeat"

  temp_dir="$VALIDATION_TMP_ROOT/backlog-pr-check-hibernate"
  mkdir -p "$temp_dir"
  if ! BACKLOG_SOURCE_ONLY=1 \
    BACKLOG_STATE_ROOT="$temp_dir/state" \
    BACKLOG_TEST_OWNER_MATCH=1 \
    BACKLOG_TEST_NOW_EPOCH=1000 \
    BACKLOG_TEST_FAKE_SLEEP=1 \
    BACKLOG_TEST_SLEEP_LOG="$temp_dir/sleeps.log" \
    BACKLOG_TEST_PR_CHECK_STATUS_SEQUENCE=pending,pending,pass \
    BACKLOG_PR_CHECK_INTERVAL_SECONDS=60 \
    bash -lc '
      set -euo pipefail
      cd "$1"
      source ./orchestration/backlog.sh
      write_backlog_active_owner
      wait_for_pr_checks 397
    ' bash "$ROOT_DIR" >"$temp_dir/pr.out" 2>"$temp_dir/pr.err"; then
    cat "$temp_dir/pr.err" >&2
    fail "backlog launcher PR check hibernation fake-clock check failed"
  fi
  [[ "$(cat "$temp_dir/sleeps.log")" == $'60\n60' ]] ||
    fail "backlog launcher PR check hibernation did not sleep between pending polls"
  grep -Fq "checks pending; holding owner lease" "$temp_dir/pr.err" ||
    fail "backlog launcher PR check hibernation did not explain local owner hold"
  grep -Fq 'progress: checks total=1 pass=0 pending=1 fail=0 other=0; active="fake PR check"' "$temp_dir/pr.err" ||
    fail "backlog launcher PR check hibernation did not emit local progress details"
  grep -Fq "owner heartbeat: state=waiting_on_pr_checks" "$temp_dir/pr.err" ||
    fail "backlog launcher PR check hibernation did not refresh owner heartbeat"
  grep -Fq "detail=plane=github waiting_for=pr_checks" "$temp_dir/pr.err" ||
    fail "backlog launcher PR check hibernation did not label the GitHub wait plane"
  grep -Fq "wait_elapsed_seconds=120" "$temp_dir/pr.err" ||
    fail "backlog launcher PR check hibernation did not report elapsed wait time"

  temp_dir="$VALIDATION_TMP_ROOT/backlog-pr-check-empty-settling"
  mkdir -p "$temp_dir"
  if ! BACKLOG_SOURCE_ONLY=1 \
    BACKLOG_STATE_ROOT="$temp_dir/state" \
    BACKLOG_TEST_OWNER_MATCH=1 \
    BACKLOG_TEST_NOW_EPOCH=1000 \
    BACKLOG_TEST_FAKE_SLEEP=1 \
    BACKLOG_TEST_SLEEP_LOG="$temp_dir/sleeps.log" \
    BACKLOG_TEST_PR_CHECK_STATUS_SEQUENCE=no_checks,pending,pass \
    BACKLOG_PR_CHECK_INTERVAL_SECONDS=60 \
    BACKLOG_PR_CHECK_EMPTY_GRACE_SECONDS=300 \
    bash -lc '
      set -euo pipefail
      cd "$1"
      source ./orchestration/backlog.sh
      write_backlog_active_owner
      wait_for_pr_checks 398
    ' bash "$ROOT_DIR" >"$temp_dir/pr.out" 2>"$temp_dir/pr.err"; then
    cat "$temp_dir/pr.err" >&2
    fail "backlog launcher PR check empty-settling fake-clock check failed"
  fi
  [[ "$(cat "$temp_dir/sleeps.log")" == $'60\n60' ]] ||
    fail "backlog launcher PR check empty-settling did not sleep between settling and pending polls"
  grep -Fq "checks not reported yet; treating as pending/settling" "$temp_dir/pr.err" ||
    fail "backlog launcher PR check empty state was not reported as pending/settling"
  grep -Fq "status=no_checks_reported_yet" "$temp_dir/pr.err" ||
    fail "backlog launcher PR check empty state did not include no-checks progress detail"
  ! grep -Fq "checks_failed" "$temp_dir/pr.err" ||
    fail "backlog launcher PR check empty state was misclassified as failed"

  temp_dir="$VALIDATION_TMP_ROOT/backlog-pr-check-empty-timeout"
  mkdir -p "$temp_dir"
  if BACKLOG_SOURCE_ONLY=1 \
    BACKLOG_STATE_ROOT="$temp_dir/state" \
    BACKLOG_TEST_OWNER_MATCH=1 \
    BACKLOG_TEST_NOW_EPOCH=1000 \
    BACKLOG_TEST_FAKE_SLEEP=1 \
    BACKLOG_TEST_SLEEP_LOG="$temp_dir/sleeps.log" \
    BACKLOG_TEST_PR_CHECK_STATUS_SEQUENCE=no_checks \
    BACKLOG_PR_CHECK_INTERVAL_SECONDS=60 \
    BACKLOG_PR_CHECK_EMPTY_GRACE_SECONDS=120 \
    bash -lc '
      set -euo pipefail
      cd "$1"
      source ./orchestration/backlog.sh
      write_backlog_active_owner
      wait_for_pr_checks 399
    ' bash "$ROOT_DIR" >"$temp_dir/pr.out" 2>"$temp_dir/pr.err"; then
    cat "$temp_dir/pr.err" >&2
    fail "backlog launcher PR check empty state did not fail after bounded grace"
  fi
  [[ "$(cat "$temp_dir/sleeps.log")" == $'60\n60' ]] ||
    fail "backlog launcher PR check empty-timeout did not use bounded grace sleeps"
  grep -Fq "checks were not reported after 120s" "$temp_dir/pr.err" ||
    fail "backlog launcher PR check empty-timeout did not explain bounded grace expiry"

  temp_dir="$VALIDATION_TMP_ROOT/backlog-pr-check-next-issue-gate"
  mkdir -p "$temp_dir"
  if ! BACKLOG_SOURCE_ONLY=1 \
    BACKLOG_STATE_ROOT="$temp_dir/state" \
    BACKLOG_TEST_OWNER_MATCH=1 \
    BACKLOG_TEST_NOW_EPOCH=1000 \
    bash -lc '
      set -euo pipefail
      cd "$1"
      source ./orchestration/backlog.sh
      write_backlog_active_owner
      backlog_ensure_pr_checks_allow_next_issue 397 0
      BACKLOG_TEST_PR_CHECK_STATUS_SEQUENCE=fail
      export BACKLOG_TEST_PR_CHECK_STATUS_SEQUENCE
      set +e
      backlog_ensure_pr_checks_allow_next_issue 397 1
      rc="$?"
      set -e
      [[ "$rc" == "1" ]]
    ' bash "$ROOT_DIR" >"$temp_dir/gate.out" 2>"$temp_dir/gate.err"; then
    cat "$temp_dir/gate.err" >&2
    fail "backlog launcher did not stop issue selection when current PR checks failed"
  fi
  grep -Fq "checks failed; stopping before selecting another issue" "$temp_dir/gate.err" ||
    fail "backlog launcher did not explain PR-check gate failure before next issue"
}

check_prior_run_anomaly_custody_contract() {
  local temp_dir obligation_count selected_json prompt_file second_count

  log "checking prior-run anomaly custody contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-anomaly-custody.XXXXXX)"

  cat >"$temp_dir/loop.log" <<'LOG'
2026-05-21T12:00:00 █ OK      [INFO] Upkeeper: primary status: UPKEEPER_STATUS: WORK_DONE
2026-05-21T12:00:01 █ --FYI-- [WARN] cycle=prior-cycle run_hash=abc123 previous_run.anomaly_summary scan_minutes=240 listed_total=1 action=force_upkeeper_self_review
2026-05-21T12:00:03 █ --FYI-- [WARN] cycle=next-cycle run_hash=def456 previous_run.anomaly_summary scan_minutes=240 listed_total=7 action=force_upkeeper_self_review
2026-05-21T12:00:02 █ PAGE    [ERROR] cycle=prior-cycle run_hash=abc123 unexpected.wrapper.failure reason=fixture
LOG

  tools/upkeeper_anomaly_custody.py \
    --root "$ROOT_DIR" \
    --loop-log "$temp_dir/loop.log" \
    --state-root "$temp_dir/custody" \
    --obligation-root "$temp_dir/obligations" \
    --recent-lines 100 \
    --max-findings 10 \
    --write-obligations >"$temp_dir/audit.out"

  grep -Fq 'anomaly custody: status=actionable' "$temp_dir/audit.out" ||
    fail "prior-run anomaly custody did not report actionable findings"
  [[ "$(jq -r '.status' "$temp_dir/custody/latest.json")" == "actionable" ]] ||
    fail "prior-run anomaly custody latest record was not actionable"
  [[ "$(jq -r '.actionable_findings' "$temp_dir/custody/latest.json")" -ge 2 ]] ||
    fail "prior-run anomaly custody did not detect both warning and page-error deviations"
  [[ "$(jq -r '.coalesced_findings' "$temp_dir/custody/latest.json")" == "1" ]] ||
    fail "prior-run anomaly custody did not coalesce duplicate dynamic cycle evidence"
  obligation_count="$(find "$temp_dir/obligations/open" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$obligation_count" == "2" ]] ||
    fail "prior-run anomaly custody opened duplicate local automation obligations"
  [[ "$(jq -s '[.[] | select(.evidence.kind == "previous_run_anomaly_summary")] | length' "$temp_dir"/obligations/open/*.json)" == "1" ]] ||
    fail "prior-run anomaly custody did not collapse repeated previous-run summaries to one owner"
  jq -e 'select(.kind == "prior_run_anomaly") | select(.issue_number == "") | select(.owner_issue_number == "418") | select(.specific_issue_required == true) | select(.evidence.normalized_excerpt | contains("unexpected.wrapper.failure"))' \
    "$temp_dir"/obligations/open/*.json >/dev/null ||
    fail "prior-run anomaly custody obligation did not require a specific issue beyond the umbrella"

  tools/upkeeper_anomaly_custody.py \
    --root "$ROOT_DIR" \
    --loop-log "$temp_dir/loop.log" \
    --state-root "$temp_dir/custody" \
    --obligation-root "$temp_dir/obligations" \
    --recent-lines 100 \
    --max-findings 10 \
    --write-obligations >"$temp_dir/audit-second.out"
  second_count="$(find "$temp_dir/obligations/open" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$second_count" == "$obligation_count" ]] ||
    fail "prior-run anomaly custody reopened duplicate obligations for the same fingerprint"
  [[ "$(jq -r '.created_obligations' "$temp_dir/custody/latest.json")" == "0" ]] ||
    fail "prior-run anomaly custody recreated existing obligations instead of updating them"
  [[ "$(jq -r '.updated_obligations' "$temp_dir/custody/latest.json")" == "$obligation_count" ]] ||
    fail "prior-run anomaly custody did not update existing coalesced obligations"

  selected_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" \
      bash -c 'source "$1"; automation_select_open_obligation_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.status' <<<"$selected_json")" == "ok" ]] ||
    fail "prior-run anomaly custody obligation was not selectable"
  prompt_file="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" \
      bash -c 'source "$1"; automation_prepare_obligation_prompt_file "$2"' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash" "$selected_json"
  )"
  grep -Fq 'Evidence packet:' "$prompt_file" ||
    fail "prior-run anomaly custody prompt omitted the evidence packet"
  grep -Fq 'Healthy unattended runs have a small expected sequence' "$prompt_file" ||
    fail "prior-run anomaly custody prompt omitted the healthy-run contract"

  cat >"$temp_dir/fixture.log" <<'LOG'
2026-05-21T12:03:28 █ PAGE    [ERROR] cycle=fixture run_hash=hash transcript directory is not private /tmp/upkeeper-transcripts-test.PDBM8W/transcripts-link
2026-05-21T12:03:29 █ INFO    transcript_artifacts_test: ok
LOG
  tools/upkeeper_anomaly_custody.py \
    --root "$ROOT_DIR" \
    --loop-log "$temp_dir/fixture.log" \
    --state-root "$temp_dir/fixture-custody" \
    --obligation-root "$temp_dir/fixture-obligations" \
    --recent-lines 100 \
    --max-findings 10 \
    --write-obligations >"$temp_dir/fixture-audit.out"
  [[ "$(jq -r '.actionable_findings' "$temp_dir/fixture-custody/latest.json")" == "0" ]] ||
    fail "prior-run anomaly custody treated a proved negative-test fixture as actionable"
  [[ "$(jq -r '.expected_fixture_findings' "$temp_dir/fixture-custody/latest.json")" == "1" ]] ||
    fail "prior-run anomaly custody did not count the expected negative-test fixture"

  cat >"$temp_dir/model-fixture.log" <<'LOG'
2026-05-23T07:07:51 █ INFO    [ERROR] Upkeeper: primary: printf '"'%s [WARN] cycle=prior-cycle run_hash=abc startup_anomaly.gate_unresolved reason=changed_path_violation reasons=previous_run_anomaly boot_id=boot-current\n' "$stamp_old" >>"$log_file"
2026-05-23T07:07:52 █ INFO    [ERROR] Upkeeper: primary: echo "2026-05-23T07:00:00 █ PAGE [ERROR] cycle=quoted run_hash=abc runner.output"
2026-05-23T07:21:59 █ PAGE    [ERROR] Upkeeper: primary: *'"'[ERROR]'*|*'[WARN]'*|*'█'*|*'startup_anomaly.gate_unresolved'*|*'previous_run.anomaly_summary'*|*'cycle.exit'*|*'run.finish'*)
2026-05-23T07:02:16 █ PAGE    [ERROR] Upkeeper: primary: grep -Fq 'previous_cycle=prior-normal' "$tmp_dir/out" && echo 'normal_cycle=passed' || { echo 'normal_cycle=failed'; exit 1; }
2026-05-23T07:29:58 █ PAGE    [ERROR] Upkeeper: primary: warn='[''WARN'']'
2026-05-23T17:30:22 █ PAGE    [ERROR] Upkeeper: primary: except Exception as exc:
2026-05-23T23:22:04 █ PAGE    [ERROR] Upkeeper: primary: print(f'run_record_read=fail error={type(exc).__name__}:{exc}')
LOG
  tools/upkeeper_anomaly_custody.py \
    --root "$ROOT_DIR" \
    --loop-log "$temp_dir/model-fixture.log" \
    --state-root "$temp_dir/model-fixture-custody" \
    --obligation-root "$temp_dir/model-fixture-obligations" \
    --recent-lines 100 \
    --max-findings 10 \
    --write-obligations >"$temp_dir/model-fixture-audit.out"
  [[ "$(jq -r '.actionable_findings' "$temp_dir/model-fixture-custody/latest.json")" == "0" ]] ||
    fail "prior-run anomaly custody treated quoted backend fixture text as actionable"
  if grep -R -Fq 'run_record_read=fail' "$temp_dir/model-fixture-obligations" 2>/dev/null; then
    fail "prior-run anomaly custody opened an obligation for quoted Python fixture text"
  fi

  grep -Fq 'run_backlog_anomaly_custody_audit' orchestration/backlog.sh ||
    fail "backlog launcher does not invoke prior-run anomaly custody before issue selection"
  grep -Fq 'run_upkeeper_for_obligation' orchestration/backlog.sh ||
    fail "backlog launcher does not route selected obligations to Upkeeper"

  rm -r "$temp_dir"
}

check_breadcrumb_audit_contract() {
  local temp_dir open_count suppressed_count resolved_count page_record

  log "checking breadcrumb audit contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-breadcrumb-audit.XXXXXX)"
  mkdir -p "$temp_dir/transcripts" "$temp_dir/obligations/open" "$temp_dir/failures/open"
  cat >"$temp_dir/Upkeeper.log" <<'LOG'
2026-05-24T05:00:00 █ INFO    normal healthy line
2026-05-24T05:00:01 █ PAGE    [ERROR] Upkeeper: live failure that needs custody
2026-05-24T05:00:02 █ --FYI-- [WARN] cycle=abc run_hash=def startup_anomaly.gate_unresolved reason=changed_path_violation
2026-05-24T05:00:03 [ERROR] cycle=fixture transcript directory is not private /tmp/upkeeper-transcripts-test.ABC/transcripts-link
transcript_artifacts_test: ok
LOG
  cat >"$temp_dir/transcripts/session.log" <<'LOG'
2026-05-24T05:00:04 [WARN] cycle=abc run_hash=ghi transcript.prune_blocked reason=missing_ownership_marker path_redacted=1
LOG
  cat >"$temp_dir/obligations/open/prior.json" <<JSON
{"schema":1,"record_type":"automation_obligation","status":"open","id":"prior","kind":"prior_run_anomaly","severity":"high","summary":"prior anomaly fixture","reason":"PRIOR_RUN_ANOMALY","root":"$ROOT_DIR","target_file":"Upkeeper"}
JSON

  tools/audit_upkeeper_breadcrumbs.py \
    --root "$ROOT_DIR" \
    --state-root "$temp_dir/breadcrumbs" \
    --log "$temp_dir/Upkeeper.log" \
    --transcript-dir "$temp_dir/transcripts" \
    --obligation-root "$temp_dir/obligations" \
    --failure-queue-root "$temp_dir/failures" \
    --write \
    --json >"$temp_dir/audit.json"

  [[ "$(jq -r '.status' "$temp_dir/audit.json")" == "open_breadcrumbs" ]] ||
    fail "breadcrumb audit did not report open breadcrumbs"
  [[ "$(jq -r '.open_count' "$temp_dir/audit.json")" == "4" ]] ||
    fail "breadcrumb audit did not collect expected open breadcrumbs"
  [[ "$(jq -r '.suppressed_count' "$temp_dir/audit.json")" == "1" ]] ||
    fail "breadcrumb audit did not suppress expected negative fixture"
  open_count="$(find "$temp_dir/breadcrumbs/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$open_count" == "4" ]] || fail "breadcrumb audit wrote $open_count open records, expected 4"
  suppressed_count="$(find "$temp_dir/breadcrumbs/suppressed" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$suppressed_count" == "1" ]] || fail "breadcrumb audit wrote $suppressed_count suppressed records, expected 1"
  jq -e '.suppression_rationale == "expected_negative_fixture" and has("suppression_expires_at")' "$temp_dir/breadcrumbs/suppressed"/*.json >/dev/null ||
    fail "breadcrumb audit suppression record lacks machine-readable rationale and expiry field"
  page_record="$(find "$temp_dir/breadcrumbs/open" -maxdepth 1 -type f -name 'page_error-*.json' | head -1)"
  [[ -n "$page_record" ]] || fail "breadcrumb audit did not write page_error record"

  tools/audit_upkeeper_breadcrumbs.py \
    --root "$ROOT_DIR" \
    --state-root "$temp_dir/breadcrumbs" \
    --log "$temp_dir/Upkeeper.log" \
    --transcript-dir "$temp_dir/transcripts" \
    --obligation-root "$temp_dir/obligations" \
    --failure-queue-root "$temp_dir/failures" \
    --write \
    --json >"$temp_dir/audit-second.json"
  [[ "$(jq -r '.occurrence_count' "$page_record")" == "2" ]] ||
    fail "breadcrumb audit did not update existing breadcrumb occurrence count"

  mkdir -p "$temp_dir/empty-transcripts" "$temp_dir/empty-obligations/open" "$temp_dir/empty-failures/open"
  printf '2026-05-24T05:01:00 █ INFO clean\n' >"$temp_dir/clean.log"
  tools/audit_upkeeper_breadcrumbs.py \
    --root "$ROOT_DIR" \
    --state-root "$temp_dir/breadcrumbs" \
    --log "$temp_dir/clean.log" \
    --transcript-dir "$temp_dir/empty-transcripts" \
    --obligation-root "$temp_dir/empty-obligations" \
    --failure-queue-root "$temp_dir/empty-failures" \
    --write \
    --resolve-missing \
    --json >"$temp_dir/audit-resolved.json"
  [[ "$(jq -r '.resolved_missing' "$temp_dir/audit-resolved.json")" == "4" ]] ||
    fail "breadcrumb audit did not resolve missing open breadcrumbs"
  resolved_count="$(find "$temp_dir/breadcrumbs/resolved" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$resolved_count" == "4" ]] || fail "breadcrumb audit resolved record count was $resolved_count, expected 4"
  open_count="$(find "$temp_dir/breadcrumbs/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$open_count" == "0" ]] || fail "breadcrumb audit left open records after resolve-missing"

  rm -r "$temp_dir"
}

check_lattice_custody_policy_contract() {
  log "checking Lattice custody authority policy"

  for policy_path in docs/lattice.md docs/scripts/upkeeper.md docs/compatibility.md; do
    grep -Fq "supporting evidence, not sole custody authority" "$policy_path" ||
      fail "Lattice custody policy missing supporting-evidence wording in $policy_path"
    grep -Fq "log/transcript/runtime evidence" "$policy_path" ||
      fail "Lattice custody policy missing fallback evidence wording in $policy_path"
  done

  grep -Fq "issues #112, #113, #115, #116, #117, and #118" docs/lattice.md ||
    fail "Lattice docs do not name the integrity blocker issue set"
  for evidence_flag in --log --transcript-dir --obligation-root --failure-queue-root; do
    grep -Fq -- "$evidence_flag" tools/audit_upkeeper_breadcrumbs.py ||
      fail "breadcrumb audit tool missing fallback evidence option $evidence_flag"
  done
  if rg -n '\b(upkeeper_lattice\.py|UPKEEPER_LATTICE|lattice_record_|runtime/upkeeper-lattice)\b' \
    tools/audit_upkeeper_breadcrumbs.py lib/upkeeper/breadcrumb_gate.bash >/dev/null; then
    fail "breadcrumb/audit custody code now depends directly on Lattice"
  fi
}

check_automation_obligation_root_boundary_contract() {
  local temp_dir selected_json selected_after_current_removed

  log "checking automation obligation root boundary contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-obligation-root.XXXXXX)"
  mkdir -p "$temp_dir/obligations/open"

  python3 - "$ROOT_DIR" "$temp_dir/obligations/open" <<'PY'
import json
import pathlib
import sys

root = sys.argv[1]
open_dir = pathlib.Path(sys.argv[2])

records = [
    {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": "foreign-root-obligation",
        "created_at": "2026-05-22T01:00:00-0700",
        "kind": "lattice_unavailable",
        "severity": "high",
        "summary": "foreign fixture obligation",
        "root": "/tmp/upkeeper-foreign-fixture/client",
        "target_scope": "target",
        "target_file": "Upkeeper",
        "repair_target_file": "Upkeeper",
        "reason": "LATTICE_UNAVAILABLE",
    },
    {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": "current-root-obligation",
        "created_at": "2026-05-22T02:00:00-0700",
        "kind": "blocked",
        "severity": "medium",
        "summary": "current root obligation",
        "root": root,
        "target_scope": "target",
        "target_file": "Upkeeper",
        "repair_target_file": "Upkeeper",
        "reason": "BLOCKED",
    },
]
for record in records:
    (open_dir / f"{record['id']}.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

  selected_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" \
      bash -c 'source "$1"; automation_select_open_obligation_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.status' <<<"$selected_json")" == "ok" ]] ||
    fail "automation obligation root boundary did not leave current-root obligation selectable"
  [[ "$(jq -r '.id' <<<"$selected_json")" == "current-root-obligation" ]] ||
    fail "automation obligation selection chose a foreign-root obligation"
  [[ "$(jq -r '.deferred_foreign_root_count' <<<"$selected_json")" == "1" ]] ||
    fail "automation obligation selection did not report deferred foreign-root obligations"

  rm -f "$temp_dir/obligations/open/current-root-obligation.json"
  selected_after_current_removed="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" \
      bash -c 'source "$1"; automation_select_open_obligation_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.status' <<<"$selected_after_current_removed")" == "foreign_root_deferred" ]] ||
    fail "automation obligation selection did not explicitly defer all-foreign obligation sets"
  [[ "$(jq -r '.deferred_foreign_root_count' <<<"$selected_after_current_removed")" == "1" ]] ||
    fail "automation obligation selection lost foreign-root count on deferred result"

  rm -r "$temp_dir"
}

check_automation_obligation_reconciliation_contract() {
  local temp_dir reconciliation_json open_count resolved_count owner_file duplicate_file selected_json

  log "checking automation obligation reconciliation contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-obligation-reconcile.XXXXXX)"
  mkdir -p "$temp_dir/obligations/open"

  python3 - "$ROOT_DIR" "$temp_dir/obligations/open" <<'PY'
import json
import pathlib
import sys

root = sys.argv[1]
open_dir = pathlib.Path(sys.argv[2])

records = [
    {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": "owner-current",
        "created_at": "2026-05-22T01:00:00-0700",
        "kind": "missing_status_marker",
        "severity": "high",
        "summary": "owner current duplicate group",
        "root": root,
        "target_scope": "target",
        "target_file": "tools/upkeeper_lattice.py",
        "repair_target_file": "tools/upkeeper_lattice.py",
        "issue_number": "146",
        "reason": "MISSING_STATUS_MARKER",
        "fingerprint": "missing-status:lattice:146",
    },
    {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": "duplicate-current",
        "created_at": "2026-05-22T02:00:00-0700",
        "kind": "missing_status_marker",
        "severity": "high",
        "summary": "duplicate current duplicate group",
        "root": root,
        "target_scope": "target",
        "target_file": "tools/upkeeper_lattice.py",
        "repair_target_file": "tools/upkeeper_lattice.py",
        "issue_number": "146",
        "reason": "MISSING_STATUS_MARKER",
        "fingerprint": "missing-status:lattice:146",
    },
    {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": "distinct-current",
        "created_at": "2026-05-22T03:00:00-0700",
        "kind": "blocked",
        "severity": "medium",
        "summary": "distinct current obligation",
        "root": root,
        "target_scope": "target",
        "target_file": "Upkeeper",
        "repair_target_file": "Upkeeper",
        "reason": "BLOCKED",
    },
    {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": "foreign-current-shaped",
        "created_at": "2026-05-22T04:00:00-0700",
        "kind": "missing_status_marker",
        "severity": "high",
        "summary": "foreign duplicate-shaped obligation",
        "root": "/tmp/upkeeper-foreign-fixture/client",
        "target_scope": "target",
        "target_file": "tools/upkeeper_lattice.py",
        "repair_target_file": "tools/upkeeper_lattice.py",
        "issue_number": "146",
        "reason": "MISSING_STATUS_MARKER",
        "fingerprint": "missing-status:lattice:146",
    },
]
for record in records:
    (open_dir / f"{record['id']}.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

  reconciliation_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" \
      bash -c 'source "$1"; automation_reconcile_open_obligations_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.status' <<<"$reconciliation_json")" == "reconciled" ]] ||
    fail "automation obligation reconciliation did not report reconciled status"
  [[ "$(jq -r '.current_root_open_before' <<<"$reconciliation_json")" == "3" ]] ||
    fail "automation obligation reconciliation counted the wrong current-root input"
  [[ "$(jq -r '.current_root_open_after' <<<"$reconciliation_json")" == "2" ]] ||
    fail "automation obligation reconciliation left the wrong current-root output"
  [[ "$(jq -r '.deferred_foreign_root_count' <<<"$reconciliation_json")" == "1" ]] ||
    fail "automation obligation reconciliation lost foreign-root evidence count"
  [[ "$(jq -r '.duplicates_resolved' <<<"$reconciliation_json")" == "1" ]] ||
    fail "automation obligation reconciliation did not resolve one duplicate"

  open_count="$(find "$temp_dir/obligations/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  resolved_count="$(find "$temp_dir/obligations/resolved" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  [[ "$open_count" == "3" ]] || fail "automation obligation reconciliation removed wrong open count"
  [[ "$resolved_count" == "1" ]] || fail "automation obligation reconciliation did not preserve one resolved duplicate"
  owner_file="$temp_dir/obligations/open/owner-current.json"
  duplicate_file="$temp_dir/obligations/resolved/duplicate-current.json"
  [[ "$(jq -r '.occurrence_count' "$owner_file")" == "2" ]] ||
    fail "automation obligation reconciliation did not update owner occurrence count"
  jq -e '.duplicate_obligation_ids | index("duplicate-current")' "$owner_file" >/dev/null ||
    fail "automation obligation reconciliation did not record duplicate id on owner"
  [[ "$(jq -r '.status' "$duplicate_file")" == "resolved_duplicate" ]] ||
    fail "automation obligation reconciliation did not mark duplicate resolved"
  [[ "$(jq -r '.duplicate_of' "$duplicate_file")" == "owner-current" ]] ||
    fail "automation obligation reconciliation did not point duplicate at owner"
  ! jq -e 'has("_path") or has("_foreign_root")' "$owner_file" >/dev/null ||
    fail "automation obligation reconciliation leaked private helper fields onto owner"
  ! jq -e 'has("_path") or has("_foreign_root")' "$duplicate_file" >/dev/null ||
    fail "automation obligation reconciliation leaked private helper fields onto duplicate"

  selected_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" \
      bash -c 'source "$1"; automation_select_open_obligation_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.id' <<<"$selected_json")" == "owner-current" ]] ||
    fail "automation obligation selection did not select reconciled owner"
  [[ "$(jq -r '.deferred_foreign_root_count' <<<"$selected_json")" == "1" ]] ||
    fail "automation obligation selection lost foreign count after reconciliation"

  rm -r "$temp_dir"
}

check_automation_obligation_churn_contract() {
  local temp_dir reconciliation_json selected_json attempt_json

  log "checking automation obligation anti-churn contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-obligation-churn.XXXXXX)"
  mkdir -p "$temp_dir/obligations/open"

  python3 - "$ROOT_DIR" "$temp_dir/obligations/open" <<'PY'
import json
import pathlib
import sys

root = sys.argv[1]
open_dir = pathlib.Path(sys.argv[2])

records = [
    {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": "quoted-fixture",
        "created_at": "2026-05-23T01:00:00-0700",
        "kind": "prior_run_anomaly",
        "severity": "high",
        "summary": "quoted backend fixture",
        "root": root,
        "target_scope": "target",
        "target_file": "lib/upkeeper/previous_run_anomalies.bash",
        "repair_target_file": "lib/upkeeper/previous_run_anomalies.bash",
        "reason": "PRIOR_RUN_ANOMALY",
        "evidence": {
            "source": "backlog_loop_log",
            "kind": "page_error",
            "normalized_excerpt": "INFO [ERROR] Upkeeper: primary: printf '%s [WARN] cycle=prior run_hash=abc startup_anomaly.gate_unresolved\\n' \"$stamp\" >>\"$log_file\"",
        },
    },
    {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": "operator-guide-stale",
        "created_at": "2026-05-23T01:01:00-0700",
        "kind": "prior_run_anomaly",
        "severity": "medium",
        "summary": "stale guide",
        "root": root,
        "target_scope": "target",
        "target_file": "Upkeeper",
        "repair_target_file": "Upkeeper",
        "reason": "PRIOR_RUN_ANOMALY",
        "evidence": {
            "source": "backlog_loop_log",
            "kind": "warning_line",
            "normalized_excerpt": "INFO [WARN] operator_guide.stale path=docs/scripts/upkeeper.md guide_version=v0 current_version=v1 action=manual_refresh_preserve_local_notes",
        },
    },
    {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": "quoted-source-fixture-aggregate",
        "created_at": "2026-05-23T01:01:30-0700",
        "kind": "prior_run_anomaly",
        "severity": "high",
        "summary": "quoted backend source fixture aggregate",
        "root": root,
        "target_scope": "target",
        "target_file": "Upkeeper",
        "repair_target_file": "Upkeeper",
        "reason": "PRIOR_RUN_ANOMALY",
        "evidence": {
            "source": "backlog_loop_log",
            "kind": "page_error",
            "normalized_excerpt": "2026-05-23T17:30:22 PAGE [ERROR] Upkeeper: primary: except Exception as exc:\\n2026-05-23T17:30:22 PAGE [ERROR] Upkeeper: primary: except Exception as exc:",
        },
    },
    {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": "cooling-down",
        "created_at": "2026-05-23T01:02:00-0700",
        "kind": "prior_run_anomaly",
        "severity": "high",
        "summary": "cooling down",
        "root": root,
        "target_scope": "target",
        "target_file": "Upkeeper",
        "repair_target_file": "Upkeeper",
        "reason": "PRIOR_RUN_ANOMALY",
        "next_retry_epoch": 2000,
        "blocked_attempt_count": 3,
    },
    {
        "schema": 1,
        "record_type": "automation_obligation",
        "status": "open",
        "id": "eligible",
        "created_at": "2026-05-23T01:03:00-0700",
        "kind": "prior_run_anomaly",
        "severity": "high",
        "summary": "eligible",
        "root": root,
        "target_scope": "target",
        "target_file": "tools/upkeeper_lattice.py",
        "repair_target_file": "tools/upkeeper_lattice.py",
        "reason": "PRIOR_RUN_ANOMALY",
    },
]
for record in records:
    (open_dir / f"{record['id']}.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

  reconciliation_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" \
      bash -c 'source "$1"; automation_reconcile_open_obligations_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.obsolete_resolved' <<<"$reconciliation_json")" == "3" ]] ||
    fail "automation obligation reconciliation did not resolve deterministic obsolete findings"
  [[ "$(find "$temp_dir/obligations/resolved" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')" == "3" ]] ||
    fail "automation obligation reconciliation did not preserve obsolete findings as resolved evidence"

  selected_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" UPKEEPER_AUTOMATION_NOW_EPOCH=1000 \
      bash -c 'source "$1"; automation_select_open_obligation_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.id' <<<"$selected_json")" == "eligible" ]] ||
    fail "automation obligation selector did not skip a cooling obligation when another is eligible"
  [[ "$(jq -r '.cooldown_deferred_count' <<<"$selected_json")" == "1" ]] ||
    fail "automation obligation selector did not report cooling obligations"

  rm -f "$temp_dir/obligations/open/eligible.json"
  selected_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" UPKEEPER_AUTOMATION_NOW_EPOCH=1000 \
      bash -c 'source "$1"; automation_select_open_obligation_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.status' <<<"$selected_json")" == "cooldown_deferred" ]] ||
    fail "automation obligation selector did not stop issue work when every obligation is cooling down"

  rm -f "$temp_dir/obligations/open/cooling-down.json"
  cat >"$temp_dir/obligations/open/attempt.json" <<JSON
{"schema":1,"record_type":"automation_obligation","status":"open","id":"attempt","created_at":"2026-05-23T01:04:00-0700","kind":"prior_run_anomaly","severity":"high","summary":"attempt","root":"$ROOT_DIR","target_scope":"target","target_file":"Upkeeper","repair_target_file":"Upkeeper","reason":"PRIOR_RUN_ANOMALY"}
JSON
  selected_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" UPKEEPER_AUTOMATION_NOW_EPOCH=3000 \
      bash -c 'source "$1"; automation_select_open_obligation_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.id' <<<"$selected_json")" == "attempt" ]] ||
    fail "automation obligation selector did not choose the non-cooling attempt fixture"
  attempt_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" UPKEEPER_OBLIGATION_RETRY_LIMIT=2 UPKEEPER_OBLIGATION_RETRY_COOLDOWN_SECONDS=600 UPKEEPER_AUTOMATION_NOW_EPOCH=3000 \
      bash -c 'source "$1"; automation_record_obligation_attempt_json "$2" blocked 2 "blocked once"' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash" "$selected_json"
  )"
  [[ "$(jq -r '.cooldown_applied' <<<"$attempt_json")" == "false" ]] ||
    fail "automation obligation attempt cooldown triggered before retry limit"
  attempt_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" UPKEEPER_OBLIGATION_RETRY_LIMIT=2 UPKEEPER_OBLIGATION_RETRY_COOLDOWN_SECONDS=600 UPKEEPER_AUTOMATION_NOW_EPOCH=3001 \
      bash -c 'source "$1"; automation_record_obligation_attempt_json "$2" blocked 2 "blocked twice"' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash" "$selected_json"
  )"
  [[ "$(jq -r '.cooldown_applied' <<<"$attempt_json")" == "true" ]] ||
    fail "automation obligation attempt cooldown did not trigger at retry limit"
  [[ "$(jq -r '.next_retry_epoch' <<<"$attempt_json")" == "3601" ]] ||
    fail "automation obligation attempt cooldown wrote wrong next retry epoch"

  rm -r "$temp_dir"
}

check_automation_obligation_issue_report_contract() {
  local temp_dir sync_json fake_bin record_file umbrella_file closed_file open_file report_file gh_args

  log "checking automation obligation issue-report bridge contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-obligation-issue-report.XXXXXX)"
  mkdir -p "$temp_dir/obligations/open" "$temp_dir/bin"
  record_file="$temp_dir/obligations/open/report-me.json"
  cat >"$record_file" <<JSON
{"schema":1,"record_type":"automation_obligation","status":"open","id":"report-me","created_at":"2026-05-23T02:00:00-0700","kind":"prior_run_anomaly","severity":"high","summary":"PAGE error was observed during unattended loop","root":"$ROOT_DIR","target_scope":"target","target_file":"Upkeeper","repair_target_file":"Upkeeper","reason":"PRIOR_RUN_ANOMALY","source_cycle_id":"cycle-a","source_run_hash":"hash-a","occurrence_count":4,"evidence":{"source":"backlog_loop_log","excerpt":"$ROOT_DIR/Upkeeper PAGE [ERROR] example","normalized_excerpt":"Upkeeper PAGE [ERROR] example"},"required_resolution":["patch the wrapper","add deterministic validation"]}
JSON
  umbrella_file="$temp_dir/obligations/open/umbrella-linked.json"
  cat >"$umbrella_file" <<JSON
{"schema":1,"record_type":"automation_obligation","status":"open","id":"umbrella-linked","created_at":"2026-05-23T02:00:30-0700","kind":"prior_run_anomaly","severity":"high","summary":"PAGE error kept an umbrella issue link","root":"$ROOT_DIR","target_scope":"target","target_file":"Upkeeper","repair_target_file":"Upkeeper","reason":"PRIOR_RUN_ANOMALY","issue_number":"418","github_issue_number":"418","issue_title":"High priority bug: non-perfect automated runs need mandatory local remediation custody","evidence":{"source":"backlog_loop_log","excerpt":"$ROOT_DIR/Upkeeper PAGE [ERROR] stale umbrella","normalized_excerpt":"Upkeeper PAGE [ERROR] stale umbrella"}}
JSON
  cat >"$temp_dir/obligations/open/foreign.json" <<JSON
{"schema":1,"record_type":"automation_obligation","status":"open","id":"foreign","created_at":"2026-05-23T02:01:00-0700","kind":"prior_run_anomaly","severity":"high","summary":"foreign root","root":"$temp_dir/foreign-root","target_scope":"target","target_file":"Upkeeper","repair_target_file":"Upkeeper","reason":"PRIOR_RUN_ANOMALY"}
JSON
  closed_file="$temp_dir/obligations/open/closed-linked.json"
  cat >"$closed_file" <<JSON
{"schema":1,"record_type":"automation_obligation","status":"open","id":"closed-linked","created_at":"2026-05-23T02:02:00-0700","kind":"blocked","severity":"medium","summary":"blocked obligation kept a closed issue link","root":"$ROOT_DIR","target_scope":"target","target_file":"Upkeeper","repair_target_file":"Upkeeper","reason":"BLOCKED","issue_number":"111","github_issue_number":"111","github_issue_url":"https://github.com/example/upkeeper/issues/111"}
JSON
  open_file="$temp_dir/obligations/open/open-linked.json"
  cat >"$open_file" <<JSON
{"schema":1,"record_type":"automation_obligation","status":"open","id":"open-linked","created_at":"2026-05-23T02:03:00-0700","kind":"blocked","severity":"medium","summary":"blocked obligation kept an open issue link","root":"$ROOT_DIR","target_scope":"target","target_file":"Upkeeper","repair_target_file":"Upkeeper","reason":"BLOCKED","issue_number":"222","github_issue_number":"222","github_issue_url":"https://github.com/example/upkeeper/issues/222"}
JSON

  sync_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" UPKEEPER_OBLIGATION_ISSUE_REPORT_DIR="$temp_dir/reports" \
      bash -c 'source "$1"; automation_sync_obligation_issue_reports_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.current_root_open' <<<"$sync_json")" == "4" ]] ||
    fail "automation obligation issue-report bridge did not scope to current root"
  [[ "$(jq -r '.drafted' <<<"$sync_json")" == "4" ]] ||
    fail "automation obligation issue-report bridge did not draft the current obligation"
  [[ "$(jq -r '.umbrella_unlinked' <<<"$sync_json")" == "1" ]] ||
    fail "automation obligation issue-report bridge did not unlink stale umbrella issues"
  report_file="$(jq -r '.issue_report_path' "$record_file")"
  [[ -f "$report_file" ]] || fail "automation obligation issue-report bridge did not write report file"
  grep -Fq "## Impact" "$report_file" || fail "automation obligation report missing impact section"
  grep -Fq "## Evidence" "$report_file" || fail "automation obligation report missing evidence section"
  grep -Fq "<repo-root>/Upkeeper" "$report_file" || fail "automation obligation report did not redact repo root"
  if grep -Fq "$ROOT_DIR" "$report_file"; then
    fail "automation obligation report leaked absolute repo root"
  fi
  [[ "$(jq -r '.issue_report_state' "$record_file")" == "issue_ready_only" ]] ||
    fail "automation obligation record did not record local issue-ready state"
  [[ "$(jq -r '.issue_number' "$umbrella_file")" == "" ]] ||
    fail "automation obligation issue-report bridge kept the stale umbrella issue number"
  [[ "$(jq -r '.github_issue_number' "$umbrella_file")" == "" ]] ||
    fail "automation obligation issue-report bridge kept the stale umbrella GitHub issue number"
  [[ "$(jq -r '.owner_issue_number' "$umbrella_file")" == "418" ]] ||
    fail "automation obligation issue-report bridge did not preserve umbrella issue as policy owner"
  [[ "$(jq -r '.specific_issue_required' "$umbrella_file")" == "true" ]] ||
    fail "automation obligation issue-report bridge did not require a specific issue"

  cat >"$temp_dir/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$UPKEEPER_FAKE_GH_ARGS"
if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  case "${3:-}" in
    111)
      printf '{"state":"CLOSED","title":"closed fixture","url":"https://github.com/example/upkeeper/issues/111"}\n'
      ;;
    222)
      printf '{"state":"OPEN","title":"open fixture","url":"https://github.com/example/upkeeper/issues/222"}\n'
      ;;
    *)
      printf '{"state":"OPEN","title":"existing fixture","url":"https://github.com/example/upkeeper/issues/%s"}\n' "${3:-0}"
      ;;
  esac
else
  printf 'https://github.com/example/upkeeper/issues/987\n'
fi
SH
  chmod 700 "$temp_dir/bin/gh"
  gh_args="$temp_dir/gh-args.txt"
  sync_json="$(
    PATH="$temp_dir/bin:$PATH" UPKEEPER_FAKE_GH_ARGS="$gh_args" \
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" UPKEEPER_OBLIGATION_ISSUE_REPORT_DIR="$temp_dir/reports" \
    UPKEEPER_OBLIGATION_GITHUB_ISSUE_WRITE=1 UPKEEPER_OBLIGATION_GITHUB_ISSUE_LABELS=bug \
      bash -c 'source "$1"; automation_sync_obligation_issue_reports_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.github_created' <<<"$sync_json")" == "3" ]] ||
    fail "automation obligation issue-report bridge did not create opted-in GitHub issue"
  [[ "$(jq -r '.github_existing' <<<"$sync_json")" == "1" ]] ||
    fail "automation obligation issue-report bridge did not preserve verified open GitHub issue links"
  [[ "$(jq -r '.closed_issue_unlinked' <<<"$sync_json")" == "1" ]] ||
    fail "automation obligation issue-report bridge did not unlink closed GitHub issue custody"
  [[ "$(jq -r '.github_issue_number' "$record_file")" == "987" ]] ||
    fail "automation obligation record did not store created GitHub issue number"
  [[ "$(jq -r '.issue_number' "$record_file")" == "987" ]] ||
    fail "automation obligation record did not store created issue number for selection"
  [[ "$(jq -r '.github_issue_number' "$umbrella_file")" == "987" ]] ||
    fail "automation obligation record did not create a specific GitHub issue after unlinking umbrella"
  [[ "$(jq -r '.issue_number' "$umbrella_file")" == "987" ]] ||
    fail "automation obligation record did not store a specific issue number after unlinking umbrella"
  [[ "$(jq -r '.stale_github_issue_number' "$closed_file")" == "111" ]] ||
    fail "automation obligation record did not preserve stale closed issue evidence"
  [[ "$(jq -r '.stale_github_issue_state' "$closed_file")" == "CLOSED" ]] ||
    fail "automation obligation record did not record stale closed issue state"
  [[ "$(jq -r '.github_issue_number' "$closed_file")" == "987" ]] ||
    fail "automation obligation record did not create a fresh issue after closed issue link"
  [[ "$(jq -r '.github_issue_number' "$open_file")" == "222" ]] ||
    fail "automation obligation record did not preserve verified open issue link"
  [[ "$(jq -r '.issue_report_state' "$open_file")" == "github_existing" ]] ||
    fail "automation obligation record did not mark verified open issue link as existing"
  grep -Fq "issue create" "$gh_args" || fail "automation obligation GitHub issue command was not invoked"
  grep -Fq "issue view 111" "$gh_args" || fail "automation obligation GitHub issue state was not checked for closed fixture"
  grep -Fq "issue view 222" "$gh_args" || fail "automation obligation GitHub issue state was not checked for open fixture"

  rm -r "$temp_dir"
}

check_backlog_batch_validation_obligation_contract() {
  log "checking backlog batch-validation obligation contract"
  grep -Fq 'run_batch_validation_phase "batch_validation.quick_validator"' orchestration/backlog.sh ||
    fail "backlog batch validation does not route quick-validator failures through the obligation wrapper"
  grep -Fq 'backlog_open_batch_validation_obligation' orchestration/backlog.sh ||
    fail "backlog launcher cannot open obligations for local batch-validation failures"
  grep -Fq 'backlog_batch_validation_repeated_failure' orchestration/backlog.sh ||
    fail "backlog launcher cannot short-circuit repeated batch-validation failures"
  grep -Fq 'local_validation_failure' tests/backlog_batch_validation_obligation_test.bash ||
    fail "batch-validation obligation test does not assert local validation failure kind"
  grep -Fq 'second identical validation failure reran command' tests/backlog_batch_validation_obligation_test.bash ||
    fail "batch-validation obligation test does not prove retry guard avoids rerunning the failed command"
  bash tests/backlog_batch_validation_obligation_test.bash
}

check_backlog_local_ahead_guard_contract() {
  log "checking backlog local-ahead branch push guard contract"

  grep -Fq 'backlog_ensure_local_branch_pushed' orchestration/backlog.sh ||
    fail "backlog launcher does not define a local-ahead branch push guard"
  grep -Fq 'pre_batch_merge' orchestration/backlog.sh ||
    fail "backlog launcher does not guard local-ahead branches before batch merge"
  grep -Fq 'post_branch_sync' orchestration/backlog.sh ||
    fail "backlog launcher does not guard local-ahead branches after branch sync"
  [[ -s tests/backlog_local_ahead_guard_test.bash ]] ||
    fail "backlog local-ahead guard tests are missing or empty"
  bash tests/backlog_local_ahead_guard_test.bash
}

check_backlog_merge_steward_contract() {
  log "checking backlog merge-steward contract"

  [[ -x tools/backlog_merge_steward.py ]] || fail "backlog merge steward is missing or not executable"
  [[ -s tests/backlog_merge_steward_test.bash ]] || fail "backlog merge steward tests are missing or empty"
  grep -Fq "CODEX_ALLOW_PR_MERGE" tools/backlog_merge_steward.py || fail "merge steward does not use guarded merge authorization"
  grep -Fq -- "--delete-branch" tools/backlog_merge_steward.py || fail "merge steward does not request branch deletion through gh"
  grep -Fq "dirty_main_worktree" tools/backlog_merge_steward.py || fail "merge steward does not block dirty secondary main worktrees"
  grep -Fq "tools/backlog_merge_steward.py" docs/scripts/upkeeper.md || fail "operator guide missing merge steward command"
  grep -Fq "merge_ready=yes|no" docs/compatibility.md || fail "compatibility docs missing merge steward output contract"
  bash tests/backlog_merge_steward_test.bash
}

check_backlog_pr_watch_contract() {
  log "checking backlog PR-watch helper contract"

  [[ -x orchestration/watch-pr.sh ]] || fail "backlog PR watcher is missing or not executable"
  [[ -s tests/watch_pr_test.bash ]] || fail "backlog PR watcher tests are missing or empty"
  grep -Fq 'gh pr checks "$pr_number" --watch=false --json' orchestration/watch-pr.sh ||
    fail "backlog PR watcher does not use local gh PR check inspection"
  grep -Fq 'gh pr view --json number --jq' orchestration/watch-pr.sh ||
    fail "backlog PR watcher cannot infer the current branch PR"
  grep -Fq -- '--once' orchestration/watch-pr.sh ||
    fail "backlog PR watcher does not expose one-shot mode"
  grep -Fq -- '--interval' orchestration/watch-pr.sh ||
    fail "backlog PR watcher does not expose polling interval control"
  grep -Fq 'backlog_log_pr_watch_hint' orchestration/backlog.sh ||
    fail "backlog launcher does not print the PR watcher helper after PR updates"
  grep -Fq './orchestration/watch-pr.sh' docs/scripts/upkeeper.md ||
    fail "operator guide missing PR watcher command"
  grep -Fq 'status=pass|pending|fail' docs/compatibility.md ||
    fail "compatibility docs missing PR watcher output contract"
  bash tests/watch_pr_test.bash
}

check_backlog_triage_contract() {
  log "checking backlog stopped-loop triage contract"

  [[ -x tools/backlog_triage.py ]] || fail "backlog triage command is missing or not executable"
  [[ -s tests/backlog_triage_test.bash ]] || fail "backlog triage tests are missing or empty"
  grep -Fq "safe_to_restart" tools/backlog_triage.py || fail "backlog triage does not emit safe_to_restart"
  grep -Fq "unknown_log_error" tools/backlog_triage.py || fail "backlog triage does not fail closed on unknown log errors"
  grep -Fq "backlog-triage-" tools/backlog_triage.py || fail "backlog triage does not leave visible obligation evidence"
  grep -Fq "tools/backlog_triage.py" docs/scripts/upkeeper.md || fail "operator guide missing backlog triage command"
  grep -Fq "safe_to_restart=yes|no|wait" docs/compatibility.md || fail "compatibility docs missing backlog triage output contract"
  bash tests/backlog_triage_test.bash
}

check_backlog_quota_hibernation_contract() {
  local temp_dir status output hard_marker_root hard_marker_epoch

  log "checking backlog quota hibernation contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-backlog-quota-hibernate.XXXXXX)"

  if ! BACKLOG_SOURCE_ONLY=1 \
    BACKLOG_QUOTA_HIBERNATE_GRACE_SECONDS=60 \
    BACKLOG_QUOTA_HIBERNATE_POLL_SECONDS=600 \
    BACKLOG_TEST_NOW_EPOCH=1000 \
    BACKLOG_TEST_FAKE_SLEEP=1 \
    BACKLOG_TEST_SLEEP_LOG="$temp_dir/sleeps.log" \
    BACKLOG_LOOP_LOG_FILE="$temp_dir/loop.log" \
    bash -lc '
      set -euo pipefail
      cd "$1"
      source ./orchestration/backlog.sh
      status=0
      backlog_hibernate_until_epoch 1300 primary "projected 5-hour left 0.0 <= 0" quota_snapshot || status="$?"
      [[ "$status" == "3" ]] || {
        printf "unexpected hibernation status: %s\n" "$status" >&2
        exit 1
      }
      [[ "$BACKLOG_TEST_NOW_EPOCH" == "1360" ]] || {
        printf "fake clock did not advance to wake time: %s\n" "$BACKLOG_TEST_NOW_EPOCH" >&2
        exit 1
      }
      [[ "$(cat "$2/sleeps.log")" == "360" ]] || {
        printf "unexpected sleep log: %s\n" "$(cat "$2/sleeps.log")" >&2
        exit 1
      }
    ' bash "$ROOT_DIR" "$temp_dir" >"$temp_dir/hibernate.out" 2>"$temp_dir/hibernate.err"; then
    cat "$temp_dir/hibernate.err" >&2
    fail "backlog quota hibernation fake-clock check failed"
  fi

  grep -Fq "quota preflight: quota blocked bucket=primary" "$temp_dir/hibernate.err" ||
    fail "backlog quota hibernation did not explain the blocked bucket"
  grep -Fq "wake=" "$temp_dir/hibernate.err" ||
    fail "backlog quota hibernation did not report the wake time"
  grep -Fq "quota hibernation complete" "$temp_dir/hibernate.err" ||
    fail "backlog quota hibernation did not report completion"

  set +e
  output="$(BACKLOG_SOURCE_ONLY=1 BACKLOG_TEST_NOW_EPOCH=1000 bash -lc '
    set -euo pipefail
    cd "$1"
    source ./orchestration/backlog.sh
    backlog_hibernate_until_epoch 1e999 primary malformed quota_marker
  ' bash "$ROOT_DIR" 2>&1)"
  status=$?
  set -e
  [[ "$status" -eq 4 ]] || fail "malformed quota hibernation input exited $status output=$output"
  grep -Fq "hibernation unavailable; invalid blocked_until_epoch=1e999" <<<"$output" ||
    fail "malformed quota hibernation input did not fail closed plainly"

  hard_marker_root="$temp_dir/hard-marker-root"
  hard_marker_epoch="$(($(date '+%s') + 120))"
  mkdir -p "$hard_marker_root/cycle-hard"
  chmod 700 "$hard_marker_root" "$hard_marker_root/cycle-hard"
  cat >"$hard_marker_root/cycle-hard/primary-quota-blocked-until.txt" <<EOF
primary_model: gpt-hard
blocked_bucket: backend_usage_limit
blocked_until_epoch: $hard_marker_epoch
reason: backend_usage_limit
hard_block: 1
EOF
  if ! BACKLOG_SOURCE_ONLY=1 \
    BACKLOG_CODEX_MODEL=gpt-hard \
    BACKLOG_QUOTA_COOLDOWN_BYPASS=1 \
    BACKLOG_TEST_NOW_EPOCH="$(date '+%s')" \
    BACKLOG_TEST_FAKE_SLEEP=1 \
    BACKLOG_TEST_SLEEP_LOG="$temp_dir/hard-marker-sleeps.log" \
    BACKLOG_LOOP_LOG_FILE="$temp_dir/hard-marker-loop.log" \
    UPKEEPER_QUOTA_PRIMARY_BLOCK_MARKER_DIR="$hard_marker_root" \
    bash -lc '
      set -euo pipefail
      cd "$1"
      source ./orchestration/backlog.sh
      status=0
      quota_preflight_allows_backlog_run || status="$?"
      [[ "$status" == "3" ]] || {
        printf "unexpected hard marker preflight status: %s\n" "$status" >&2
        exit 1
      }
    ' bash "$ROOT_DIR" >"$temp_dir/hard-marker.out" 2>"$temp_dir/hard-marker.err"; then
    cat "$temp_dir/hard-marker.err" >&2
    fail "backlog did not honor hard backend usage-limit marker under cooldown bypass"
  fi
  grep -Fq "quota blocked bucket=backend_usage_limit" "$temp_dir/hard-marker.err" ||
    fail "hard backend usage-limit marker did not drive quota hibernation"

  bash tests/backlog_stale_quota_obligation_test.bash

  rm -r "$temp_dir"
}

check_backlog_autoshelve_contract() {
  local temp_dir output rc autoshelve_branch second_autoshelve_branch active_validation_pid

  log "checking backlog dirty-worktree autoshelve contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-backlog-autoshelve.XXXXXX)"
  mkdir -p "$temp_dir/orchestration"
  cp orchestration/backlog.sh "$temp_dir/orchestration/backlog.sh"
  chmod +x "$temp_dir/orchestration/backlog.sh"

  (
    cd "$temp_dir"
    git init -q -b main
    git config user.name "Upkeeper Validation"
    git config user.email "validation@example.invalid"
    printf 'baseline\n' >README.md
    git add README.md orchestration/backlog.sh
    git commit -q -m "baseline"
    printf 'dirty local work\n' >>README.md

    set +e
    output="$(BACKLOG_ALLOW_INTERACTIVE_STDIO=1 BACKLOG_AUTOSHELVE_PROBE=1 BACKLOG_STATE_ROOT="$temp_dir-state" ./orchestration/backlog.sh 2>&1)"
    rc=$?
    set -e

    [[ "$rc" -eq 0 ]] || fail "backlog autoshelve probe exited $rc output=$output"
    [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "backlog autoshelve did not return to main"
    [[ -z "$(git status --short)" ]] || fail "backlog autoshelve did not restore a clean worktree"
    autoshelve_branch="$(git for-each-ref --format='%(refname:short)' 'refs/heads/wip/backlog-autoshelve/*' | sed -n '1p')"
    [[ -n "$autoshelve_branch" ]] || fail "backlog autoshelve did not create a shelve branch"
    grep -Fq "autoshelved local changes on $autoshelve_branch" <<<"$output" || fail "backlog autoshelve did not report the shelve branch"
    git show "$autoshelve_branch:README.md" | grep -Fq 'dirty local work' || fail "backlog autoshelve branch did not preserve dirty work"
    ! git show HEAD:README.md | grep -Fq 'dirty local work' || fail "ordinary dirty work was promoted onto the backlog branch"

    printf 'dirty local work after control-plane change\n' >>README.md
    printf '\n# validation control-plane dirty marker\n' >>orchestration/backlog.sh

    set +e
    output="$(BACKLOG_ALLOW_INTERACTIVE_STDIO=1 BACKLOG_AUTOSHELVE_PROBE=1 BACKLOG_STATE_ROOT="$temp_dir-state" ./orchestration/backlog.sh 2>&1)"
    rc=$?
    set -e

    [[ "$rc" -eq 0 ]] || fail "backlog control-plane autoshelve probe exited $rc output=$output"
    [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "control-plane autoshelve did not return to main"
    [[ -z "$(git status --short)" ]] || fail "control-plane autoshelve did not leave a clean worktree"
    second_autoshelve_branch="$(git for-each-ref --format='%(refname:short)' 'refs/heads/wip/backlog-autoshelve/*' | sort | tail -1)"
    [[ -n "$second_autoshelve_branch" && "$second_autoshelve_branch" != "$autoshelve_branch" ]] ||
      fail "control-plane autoshelve did not create a second shelve branch"
    grep -Fq "Upkeeper remediation path(s)" <<<"$output" || fail "control-plane autoshelve did not report local remediation"
    grep -Fq "applied autoshelved Upkeeper control-plane changes" <<<"$output" || fail "control-plane autoshelve did not report applied remediation"
    git show HEAD:orchestration/backlog.sh | grep -Fq 'validation control-plane dirty marker' ||
      fail "control-plane autoshelve did not apply the launcher fix to main"
    git log -1 --format=%s | grep -Fq 'Apply autoshelved Upkeeper control-plane changes' ||
      fail "control-plane autoshelve did not leave an explicit remediation commit"
    ! git show HEAD:README.md | grep -Fq 'dirty local work after control-plane change' ||
      fail "control-plane autoshelve promoted unrelated dirty README work"
    git show "$second_autoshelve_branch:README.md" | grep -Fq 'dirty local work after control-plane change' ||
      fail "control-plane autoshelve branch did not preserve unrelated dirty work"
    git show "$second_autoshelve_branch:orchestration/backlog.sh" | grep -Fq 'validation control-plane dirty marker' ||
      fail "control-plane autoshelve branch did not preserve the dirty launcher fix"

    printf '\n# validation control-plane active-reader race marker\n' >>orchestration/backlog.sh
    (
      cd "$temp_dir"
      bash -c 'while true; do sleep 1; done' tools/validate_upkeeper.sh >/dev/null 2>&1 &
      printf '%s\n' "$!" >"$temp_dir/active_validation_reader.pid"
    )
    active_validation_pid="$(cat "$temp_dir/active_validation_reader.pid")"
    trap 'kill "$active_validation_pid" 2>/dev/null || true; wait "$active_validation_pid" 2>/dev/null || true' RETURN

    set +e
    output="$(BACKLOG_ALLOW_INTERACTIVE_STDIO=1 BACKLOG_AUTOSHELVE_PROBE=1 BACKLOG_STATE_ROOT="$temp_dir-state" BACKLOG_AUTOSHELVE_ACTIVE_VALIDATOR_WAIT_SECONDS=1 BACKLOG_AUTOSHELVE_ACTIVE_VALIDATOR_POLL_SECONDS=1 ./orchestration/backlog.sh 2>&1)"
    rc=$?
    set -e
    [[ "$rc" -eq 4 ]] || fail "backlog autoshelve did not block on active validation readers rc=$rc output=$output"
    grep -Fq "active validation process" <<<"$output" ||
      fail "backlog autoshelve did not report active validation-process blocking"
    [[ -n "$(git status --short)" ]] && fail "backlog autoshelve left unexpected git state while blocked on validation readers"
    ! git show HEAD:orchestration/backlog.sh | grep -Fq 'validation control-plane active-reader race marker' ||
      fail "blocked autoshelve unexpectedly applied dirty launcher fix while validation reader was active"

  )

  rm -r "$temp_dir"
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

check_prompt_module_contract() {
  local prompt_path module_id

  log "checking reusable review-module structure"
  [[ -s prompts/_review-module-template.md ]] || fail "prompt module template is missing or empty"
  for prompt_path in prompts/p[0-9][0-9]-*.md; do
    module_id="$(basename "$prompt_path" | sed -n 's/^p\([0-9][0-9]\)-.*/\1/p')"
    [[ -n "$module_id" ]] || continue
    [[ -s "$prompt_path" ]] || fail "prompt module is missing or empty: $prompt_path"

    grep -Eq "^#\\s*P${module_id}([[:space:]]|-|:)" "$prompt_path" ||
      fail "prompt module missing title/header for $module_id: $prompt_path"
    grep -Eiq "P${module_id}: [a-z ]*applic" "$prompt_path" ||
      fail "prompt module missing applicability statement for $module_id: $prompt_path"
    grep -Eiq "\\bscope\\b" "$prompt_path" ||
      fail "prompt module missing scope wording for $module_id: $prompt_path"
    grep -Eiq "\\bboundar(y|ies)\\b|non-goal|out of scope|does not apply|not in scope" "$prompt_path" ||
      fail "prompt module missing non-goal/boundary wording for $module_id: $prompt_path"
    grep -Eiq "verification" "$prompt_path" ||
      fail "prompt module missing verification guidance wording for $module_id: $prompt_path"
    grep -Eiq "output contract|required output" "$prompt_path" ||
      fail "prompt module missing output contract wording for $module_id: $prompt_path"
    grep -Eiq "UPKEEPER_STATUS|final status|final marker|status contract" "$prompt_path" ||
      fail "prompt module missing final marker/status wording for $module_id: $prompt_path"
  done
}

check_review_module_registry_contract() {
  local expected_modules module_id prompt_path title aliases help_summary
  local normalized resolved_prompt_path

  log "checking review-module registry contract"
  [[ -s lib/upkeeper/review_modules.bash ]] || fail "review module registry module is missing or empty"
  grep -Fq '"review_modules.bash"' Upkeeper || fail "module map does not load review_modules.bash"
  grep -Fq '`review_modules.bash`' lib/upkeeper/README.md || fail "module README missing review_modules.bash ownership"
  grep -Fq "review_module_registry_rows" lib/upkeeper/codex_io.bash &&
    fail "codex I/O should consume registry helpers, not registry rows directly"
  grep -Fq "case \"\$module\"" lib/upkeeper/prompt_compile.bash &&
    fail "prompt compilation still has a review-module case block"
  grep -Fq "review_module_prompt_path" lib/upkeeper/prompt_compile.bash ||
    fail "prompt compilation no longer consumes the review-module prompt helper"
  grep -Fq "review_module_flag_help_lines" lib/upkeeper/help_selection.bash ||
    fail "help text does not consume review-module help registry"

  expected_modules="p24,p25,p26,p27,p28,p29,p30"
  [[ "$(review_module_ids_csv)" == "$expected_modules" ]] ||
    fail "review module registry ids drifted from expected list"
  [[ "$(review_module_ids_pipe)" == "p24|p25|p26|p27|p28|p29|p30" ]] ||
    fail "review module registry pipe list drifted"

  while IFS='|' read -r module_id prompt_path title aliases help_summary; do
    [[ -n "$module_id" && -n "$prompt_path" && -n "$title" && -n "$help_summary" ]] ||
      fail "review module registry row has empty required fields for $module_id"
    [[ -s "$prompt_path" ]] || fail "registered review module prompt missing: $prompt_path"
    normalized="$(normalize_review_module "$module_id")" ||
      fail "registry id does not normalize: $module_id"
    [[ "$normalized" == "$module_id" ]] || fail "registry id normalized to $normalized, expected $module_id"
    resolved_prompt_path="$(review_module_prompt_relative_path "$module_id")" ||
      fail "registry prompt lookup failed for $module_id"
    [[ "$resolved_prompt_path" == "$prompt_path" ]] ||
      fail "registry prompt lookup for $module_id returned $resolved_prompt_path, expected $prompt_path"
    grep -Fq -- "--review-module=$module_id" docs/scripts/upkeeper.md ||
      fail "operator guide missing registered module flag: $module_id"
  done < <(review_module_registry_rows)

  [[ "$(normalize_review_module library-reuse)" == "p29" ]] ||
    fail "p29 library-reuse alias did not normalize"
  [[ "$(normalize_review_module STARK_PROTOCOL)" == "p30" ]] ||
    fail "p30 uppercase underscore alias did not normalize"
}

check_embedded_behavior_table_contracts() {
  log "checking embedded behavior table contracts"
  python3 - "$ROOT_DIR" <<'PY' || fail "embedded behavior table contract check failed"
import ast
import importlib.util
import re
import shlex
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
issues: list[str] = []


def read(rel: str) -> str:
    return (root / rel).read_text(encoding="utf-8")


def add_issue(message: str) -> None:
    issues.append(message)


def literal_assignments(text: str, name: str) -> list[object]:
    pattern = re.compile(rf"^[ \t]*{re.escape(name)}\s*=\s*(\{{.*?\}}|\(.*?\))", re.M | re.S)
    values: list[object] = []
    for match in pattern.finditer(text):
        try:
            values.append(ast.literal_eval(match.group(1)))
        except (SyntaxError, ValueError) as exc:
            add_issue(f"{name} assignment is not a literal: {exc}")
    return values


def function_blocks(text: str, name: str) -> list[str]:
    lines = text.splitlines()
    blocks: list[str] = []
    for index, line in enumerate(lines):
        if not line.startswith(f"def {name}("):
            continue
        block = [line]
        for next_line in lines[index + 1 :]:
            if next_line and not next_line.startswith((" ", "\t")):
                break
            block.append(next_line)
        blocks.append("\n".join(block))
    return blocks


def compile_command_kind_functions() -> list[tuple[str, object]]:
    functions: list[tuple[str, object]] = []
    for rel in (
        "Upkeeper",
        "lib/upkeeper/tool_failure_queue.bash",
        "lib/upkeeper/transcript_output.bash",
    ):
        for ordinal, block in enumerate(function_blocks(read(rel), "command_kind"), start=1):
            namespace: dict[str, object] = {}
            try:
                exec("import re\n" + block, namespace)
            except Exception as exc:  # noqa: BLE001 - validator reports source drift.
                add_issue(f"{rel} command_kind #{ordinal} did not compile: {exc}")
                continue
            fn = namespace.get("command_kind")
            if not callable(fn):
                add_issue(f"{rel} command_kind #{ordinal} did not define callable function")
                continue
            functions.append((f"{rel}#{ordinal}", fn))
    return functions


def review_module_rows() -> list[list[str]]:
    command = (
        f"cd {shlex.quote(str(root))}; "
        "source lib/upkeeper/review_modules.bash; review_module_registry_rows"
    )
    output = subprocess.check_output(["bash", "-lc", command], text=True)
    rows = [line.split("|") for line in output.splitlines() if line.strip()]
    return rows


def load_lattice_module():
    spec = importlib.util.spec_from_file_location(
        "upkeeper_lattice_contract",
        root / "tools/upkeeper_lattice.py",
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load tools/upkeeper_lattice.py spec")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


worktree_state = read("lib/upkeeper/worktree_state.bash")
allowed_exact_blocks = literal_assignments(worktree_state, "allowed_exact")
allowed_prefix_blocks = literal_assignments(worktree_state, "allowed_prefixes")
if len(allowed_exact_blocks) < 2:
    add_issue("startup anomaly allowed_exact blocks missing")
elif allowed_exact_blocks[0] != allowed_exact_blocks[1]:
    add_issue("startup anomaly allowed_exact blocks drifted from each other")
if len(allowed_prefix_blocks) < 2:
    add_issue("startup anomaly allowed_prefixes blocks missing")
elif tuple(allowed_prefix_blocks[0]) != tuple(allowed_prefix_blocks[1]):
    add_issue("startup anomaly allowed_prefixes blocks drifted from each other")

if allowed_exact_blocks and allowed_prefix_blocks:
    allowed_exact = set(allowed_exact_blocks[0])
    allowed_prefixes = tuple(allowed_prefix_blocks[0])

    def startup_allowed(path: str) -> bool:
        return (
            path in allowed_exact
            or re.fullmatch(r"change_notes_[0-9]{4}\.md", path) is not None
            or any(path.startswith(prefix) for prefix in allowed_prefixes)
        )

    startup_fixtures = {
        "Upkeeper": True,
        "Upkeeper.conf": True,
        "change_notes_2026.md": True,
        "change_notes_2027.md": True,
        "docs/scripts/upkeeper.md": True,
        "lib/upkeeper/worktree_state.bash": True,
        "prompts/default-review.md": True,
        "templates/example.md": True,
        "launcher_examples/run.sh": True,
        "tests/wrapper_contract_test.bash": False,
        "docs/security.md": False,
        "runtime/upkeeper-file-manifest.json": False,
        ".git/config": False,
        "secrets.env": False,
    }
    for path, expected in startup_fixtures.items():
        actual = startup_allowed(path)
        if actual != expected:
            add_issue(f"startup anomaly allowlist fixture {path!r} returned {actual}, expected {expected}")

help_selection = read("lib/upkeeper/help_selection.bash")
help_prefix_blocks = literal_assignments(help_selection, "excluded_prefixes")
if not help_prefix_blocks:
    add_issue("source-safe excluded_prefixes table missing from help_selection")
else:
    prefixes = tuple(help_prefix_blocks[0])
    for expected in (".git/", "runtime/"):
        if expected not in prefixes:
            add_issue(f"source-safe excluded_prefixes missing {expected}")

file_manifest = read("lib/upkeeper/file_manifest.bash")
manifest_excluded_dirs = literal_assignments(file_manifest, "excluded_dirs")
if not manifest_excluded_dirs:
    add_issue("file manifest excluded_dirs table missing")
else:
    excluded_dirs = set(manifest_excluded_dirs[0])
    for expected in (".git", "runtime"):
        if expected not in excluded_dirs:
            add_issue(f"file manifest excluded_dirs missing {expected}")

default_prompt = read("prompts/default-review.md")
for expected in ("  - .git/", "  - runtime/"):
    if expected not in default_prompt:
        add_issue(f"default prompt missing explicit source-safe exclusion {expected.strip()}")

command_examples = {
    "bash -n Upkeeper": "check",
    "git diff --check": "check",
    "tools/validate_upkeeper.sh --quick": "validation",
    "python -m pytest tests": "tests",
    "npm test": "tests",
    "npm run build": "build",
    "git status --short": "search",
    "git commit -m msg": "git",
    "command -v jq": "command",
    "rg -n TODO Upkeeper": "search",
}
command_kind_functions = compile_command_kind_functions()
if len(command_kind_functions) < 4:
    add_issue(f"expected at least four command_kind classifier copies, found {len(command_kind_functions)}")
for source, fn in command_kind_functions:
    for command, expected in command_examples.items():
        try:
            actual = fn(command)
        except Exception as exc:  # noqa: BLE001 - validator reports source drift.
            add_issue(f"{source} command_kind raised for {command!r}: {exc}")
            continue
        if actual != expected:
            add_issue(f"{source} command_kind({command!r})={actual!r}, expected {expected!r}")

rows = review_module_rows()
review_module_ids = [row[0] for row in rows if row]
expected_review_module_ids = [f"p{i}" for i in range(24, 31)]
if review_module_ids != expected_review_module_ids:
    add_issue(f"review module ids drifted: {review_module_ids!r}")

try:
    lattice_module = load_lattice_module()
except Exception as exc:  # noqa: BLE001 - validator reports import drift.
    add_issue(f"could not import Lattice registry: {exc}")
else:
    registry_issues = lattice_module.validate_pass_registry_contract()
    if registry_issues:
        add_issue("Lattice pass registry contract failed: " + "; ".join(registry_issues))
    lattice_module_ids = [
        str(item.get("pass_code", "")).lower()
        for item in lattice_module.PASS_REGISTRY
        if item.get("module_prompt") is True
    ]
    if lattice_module_ids != review_module_ids:
        add_issue(
            "review module ids drifted from Lattice module passes: "
            f"review={review_module_ids!r} lattice={lattice_module_ids!r}"
        )

lattice_wrapper = read("lib/upkeeper/lattice.bash")
lattice_case_mappings = dict(
    re.findall(r"\b(p[0-9]+)\)\s+passes\+=\((P[0-9]+)\)", lattice_wrapper)
)
for module_id in review_module_ids:
    expected = module_id.upper()
    actual = lattice_case_mappings.get(module_id)
    if actual != expected:
        add_issue(f"lattice planned pass mapping for {module_id} is {actual!r}, expected {expected!r}")

for rel in ("docs/scripts/upkeeper.md", "docs/compatibility.md", "change_notes_2026.md"):
    text = read(rel)
    if "embedded behavior table" not in text and "embedded control-plane table" not in text:
        add_issue(f"{rel} missing embedded behavior table ownership wording")

if issues:
    for issue in issues:
        print(issue, file=sys.stderr)
    raise SystemExit(1)
PY
}

review_module_specs() {
  local module_id prompt_path title aliases help_summary applicability terms

  while IFS='|' read -r module_id prompt_path title aliases help_summary; do
    case "$module_id" in
      p24)
        applicability="P24: not applicable"
        terms="no loss of operator-facing function;without material new runtime cost"
        ;;
      p25)
        applicability="P25: not applicable"
        terms="central-first;operator-visible behavior;smallest sufficient"
        ;;
      p26)
        applicability="P26: not applicable"
        terms="current checked-in state as the delivered product"
        ;;
      p27)
        applicability="P27: not applicable"
        terms="P27 After-Action Review:;Outcome:;What went right:;What went wrong:;What was wasteful:;Reusable learning:"
        ;;
      p28)
        applicability="P28: not applicable"
        terms="without backend model quota"
        ;;
      p29)
        applicability="P29: not applicable"
        terms="stable contract;generic \"utils.bash\" dumping ground;generic \"utility dumping ground\" functions;Relationship to P12, P24, P25, and P28;Wrong Abstraction Check;Shell Reuse Safety Gates;Command Reuse Rule;Registry Preference;Reuse Debt Output;ShellCheck Integration Policy"
        ;;
      p30)
        applicability="P30: not applicable"
        terms="same weakness cannot get us twice;Permanent hardening test;Non-regression evidence;same weakness cannot silently recur"
        ;;
      *)
        fail "review module registry has no validation terms for $module_id"
        ;;
    esac
    printf '%s|%s|%s|%s|%s\n' "$module_id" "$prompt_path" "$title" "$applicability" "$terms"
  done < <(review_module_registry_rows)
}

review_module_alias_specs() {
  local module_id prompt_path title aliases help_summary

  while IFS='|' read -r module_id prompt_path title aliases help_summary; do
    [[ -n "$aliases" ]] || continue
    printf '%s|%s\n' "$module_id" "$aliases"
  done < <(review_module_registry_rows)
}

review_module_list_csv() {
  review_module_ids_csv
}

check_prompt_template() {
  local p31_term
  local module_id prompt_path module_title module_applicability module_terms
  local term

  log "checking prompt templates"
  [[ -s prompts/default-review.md ]] || fail "prompts/default-review.md is missing or empty"
  [[ -s prompts/p23-data-contract-negative-fixture-audit.md ]] || fail "P23 standalone prompt is missing or empty"
  while IFS='|' read -r module_id prompt_path module_title module_applicability module_terms; do
    [[ -s "$prompt_path" ]] || fail "review module prompt is missing or empty: $prompt_path"
    grep -Fq "$module_title" "$prompt_path" || fail "${module_id} prompt title missing"
    grep -Fq "$module_applicability" "$prompt_path" || fail "${module_id} applicability gate missing"
    if [[ -n "$module_terms" ]]; then
      IFS=';' read -r -a module_terms <<< "$module_terms"
      for term in "${module_terms[@]}"; do
        [[ -n "$term" ]] || continue
        grep -Fq "$term" "$prompt_path" || fail "${module_id} module contract term missing: $term"
      done
    fi
  done < <(review_module_specs)
  [[ -s prompts/p31-fault-injection-review.md ]] || fail "P31 fault-injection contract prompt is missing or empty"
  [[ -x tools/upkeeper_lattice.py ]] || fail "Lattice tool is missing or not executable"
  [[ -s lib/upkeeper/lattice.bash ]] || fail "Lattice wrapper module is missing or empty"
  [[ -s lib/upkeeper/precontact_backup.bash ]] || fail "pre-contact backup module is missing or empty"
  [[ -s tests/lattice_test.bash ]] || fail "Lattice test is missing or empty"
  [[ -s tests/precontact_backup_test.bash ]] || fail "pre-contact backup test is missing or empty"
  [[ -s docs/lattice.md ]] || fail "Lattice documentation is missing or empty"
  [[ -x tools/upkeeper_precontact_bootstrap.sh ]] || fail "pre-contact bootstrap helper is missing or not executable"
  [[ -x tools/upkeeper_precontact_restore.sh ]] || fail "pre-contact restore helper is missing or not executable"
  [[ -x FlameOn ]] || fail "FlameOn launcher is missing or not executable"
  [[ -x ChimneySweep ]] || fail "ChimneySweep launcher is missing or not executable"
  [[ -s completions/upkeeper.bash ]] || fail "Bash completion helper is missing or empty"
  [[ -s .upkeeperignore ]] || fail ".upkeeperignore is missing or empty"
  [[ -s Upkeeper.conf ]] || fail "root Upkeeper.conf is missing or empty"
  [[ -s configurations/default.conf ]] || fail "configurations/default.conf is missing or empty"
  [[ -x tools/stress_upkeeper_corpus.sh ]] || fail "stress corpus harness is missing or not executable"
  grep -Fq "# P31 Fault-Injection Review" prompts/p31-fault-injection-review.md || fail "P31 prompt title missing"
  grep -Fq "P31: not applicable" prompts/p31-fault-injection-review.md || fail "P31 applicability gate missing"
  for p31_term in \
    "Component:" \
    "Function protected:" \
    "Assumption challenged:" \
    "Injected fault:" \
    "Fault trigger:" \
    "Expected internal error state:" \
    "Expected externally visible behavior:" \
    "Containment behavior:" \
    "Operator diagnostic:" \
    "Cleanup expectation:" \
    "Recovery expectation:" \
    "Oracle classes:" \
    "Control run:" \
    "Injection run:" \
    "Recovery run:" \
    "Scenario registry action:" \
    "Fault: the injected broken condition" \
    "Error: invalid internal state" \
    "Failure: externally visible wrong behavior" \
    "Containment: behavior that prevents operator damage" \
    "Exit oracle" \
    "Reason oracle" \
    "Log oracle" \
    "Terminal oracle" \
    "Artifact oracle" \
    "Mutation oracle" \
    "Cleanup oracle" \
    "Recovery oracle" \
    "Non-oracle declaration" \
    "no oracle is invalid" \
    "next invocation is not poisoned" \
    "not fuzzing, mutation testing"; do
    grep -Fq "$p31_term" prompts/p31-fault-injection-review.md || fail "P31 contract missing required term: $p31_term"
  done
  grep -Fq "UPKEEPER_PASS_RESULT" prompts/default-review.md || fail "default prompt missing pass-result marker contract"
  check_prompt_module_contract
  grep -Fq "for \`prompts/pNN-*.md\`" prompts/_review-module-template.md ||
    fail "template missing guidance for reusable pNN module targeting"
  grep -Fq "Purpose and Scope" prompts/_review-module-template.md || fail "template missing Purpose and Scope section"
  grep -Fq "Trigger / Applicability" prompts/_review-module-template.md || fail "template missing trigger/applicability section"
  grep -Fq "Verification Guidance" prompts/_review-module-template.md || fail "template missing verification guidance section"
  grep -Fq "Output Contract" prompts/_review-module-template.md || fail "template missing output contract section"
  grep -Fq "Final Marker Discipline" prompts/_review-module-template.md || fail "template missing final marker section"
  grep -Fq "Discoverability and Compatibility" prompts/_review-module-template.md || fail "template missing discoverability section"
  grep -Fq "UPKEEPER_LATTICE_ENABLED" Upkeeper.conf || fail "root config missing Lattice defaults"
  grep -Fq "UPKEEPER_LATTICE_ENABLED" configurations/default.conf || fail "default profile missing Lattice defaults"
  grep -Fq "UPKEEPER_IGNORE_FILE" Upkeeper.conf || fail "root config missing .upkeeperignore default"
  grep -Fq "UPKEEPER_IGNORE_FILE" configurations/default.conf || fail "default profile missing .upkeeperignore default"
  grep -Fq "UPKEEPER_BUG_REPORT_ONLY" Upkeeper.conf || fail "root config missing bug-report-only default"
  grep -Fq "UPKEEPER_BREADCRUMB_GATE_ENABLED" Upkeeper.conf || fail "root config missing breadcrumb gate default"
  grep -Fq "UPKEEPER_AUDIT_ONLY" Upkeeper.conf || fail "root config missing audit-only default"
  grep -Fq "UPKEEPER_FIX_NEXT_ISSUE" Upkeeper.conf || fail "root config missing issue-fix default"
  grep -Fq "UPKEEPER_FIX_ISSUE" Upkeeper.conf || fail "root config missing explicit issue-fix default"
  grep -Fq "UPKEEPER_PRECONTACT_BACKUP_ENABLED" Upkeeper.conf || fail "root config missing pre-contact backup defaults"
  grep -Fq "UPKEEPER_BUG_REPORT_ONLY" configurations/default.conf || fail "default profile missing bug-report-only default"
  grep -Fq "UPKEEPER_BREADCRUMB_GATE_ENABLED" configurations/default.conf || fail "default profile missing breadcrumb gate default"
  grep -Fq "UPKEEPER_AUDIT_ONLY" configurations/default.conf || fail "default profile missing audit-only default"
  grep -Fq "UPKEEPER_FIX_NEXT_ISSUE" configurations/default.conf || fail "default profile missing issue-fix default"
  grep -Fq "UPKEEPER_FIX_ISSUE" configurations/default.conf || fail "default profile missing explicit issue-fix default"
  grep -Fq "UPKEEPER_PRECONTACT_BACKUP_ENABLED" configurations/default.conf || fail "default profile missing pre-contact backup defaults"
  grep -Fq "local SQLite evidence ledger" docs/lattice.md || fail "Lattice docs missing local SQLite summary"
  grep -Fq "source-safe live eligibility remains authoritative" docs/lattice.md || fail "Lattice docs missing live eligibility boundary"
  grep -Fq ".upkeeperignore" docs/lattice.md || fail "Lattice docs missing .upkeeperignore candidate boundary"
  grep -Fq "Reusable Asset Ownership" lib/upkeeper/README.md || fail "module README missing reusable asset ownership map"
  grep -Fq "code-comment clarity" README.md || fail "README missing P26 summary"
  grep -Fq "after-action reviews" README.md || fail "README missing P27 summary"
  grep -Fq "unit-test harvesting" README.md || fail "README missing P28 summary"
  grep -Fq "reuse harvesting" README.md || fail "README missing P29 summary"
  grep -Fq "Stark Protocol" README.md || fail "README missing P30 summary"
  grep -Fq "Fault-injection review is reserved for future P31 work" README.md || fail "README missing P31 fault-injection numbering decision"
  grep -Fq "Fault-injection review is reserved for future P31 work" prompts/README.md || fail "prompt index missing P31 fault-injection numbering decision"
  grep -Fq "fault-injection review is reserved for future" docs/compatibility.md || fail "compatibility docs missing fault-injection numbering decision"
  grep -Fq "Fault-injection review is reserved for future P31 work" docs/scripts/upkeeper.md || fail "operator guide missing fault-injection numbering decision"
  grep -Fq "Fault-injection review is reserved for future P31 work" lib/upkeeper/help_selection.bash || fail "help text missing fault-injection numbering decision"
  grep -Fq "Upkeeper.conf" README.md || fail "README missing config file summary"
  grep -Fq "tools/stress_upkeeper_corpus.sh --local" README.md || fail "README missing stress corpus command"
  grep -Fq ".upkeeperignore" README.md || fail "README missing .upkeeperignore docs"
  grep -Fq ".upkeeperignore" docs/scripts/upkeeper.md || fail "operator guide missing .upkeeperignore docs"
  grep -Fq ".upkeeperignore" docs/compatibility.md || fail "compatibility docs missing .upkeeperignore contract"
  grep -Fq ".upkeeperignore" docs/security.md || fail "security docs missing .upkeeperignore boundary"
  grep -Fq "pre-contact backup" docs/security.md || fail "security docs missing pre-contact backup boundary"
  grep -Fq "tools/upkeeper_precontact_bootstrap.sh" docs/scripts/upkeeper.md || fail "operator guide missing pre-contact bootstrap helper"
  grep -Fq "UPKEEPER_LOCAL_ENV_FILE" docs/scripts/upkeeper.md || fail "operator guide missing machine-local env contract"
  grep -Fq "tools/upkeeper_precontact_bootstrap.sh" docs/security.md || fail "security docs missing pre-contact bootstrap helper"
  grep -Fq "UPKEEPER_LOCAL_ENV_FILE" docs/security.md || fail "security docs missing machine-local env contract"
  grep -Fq "age" docs/dependencies.md || fail "dependency docs missing age optional dependency"
  grep -Fq "tools/upkeeper_precontact_restore.sh" docs/scripts/upkeeper.md || fail "operator guide missing pre-contact restore helper"
  grep -Fq "tools/stress_upkeeper_corpus.sh --local" docs/stress-corpus.md || fail "stress corpus docs missing implemented command"
  grep -Fq "public project material" docs/public-documentation-policy.md || fail "public documentation policy missing public-by-default rule"
}

check_prompt_public_lint_contract() {
  local prompt_path

  log "checking public prompt lint contract"

  for prompt_path in prompts/default-review.md prompts/caretaking_23_items.md; do
    [[ -s "$prompt_path" ]] || fail "prompt missing or empty: $prompt_path"
    if grep -Fq "Read this FULL prompt before starting in" "$prompt_path"; then
      fail "prompt contains incomplete startup sentence: $prompt_path"
    fi
    if grep -Fq "It it oldest" "$prompt_path"; then
      fail "prompt contains known oldest-selection typo: $prompt_path"
    fi
    if grep -Eq 'Random poo([^l]|$)' "$prompt_path"; then
      fail "prompt contains known random-pool typo: $prompt_path"
    fi
    grep -Fq "Read this FULL prompt before starting." "$prompt_path" ||
      fail "prompt missing corrected startup sentence: $prompt_path"
    grep -Fq "Is it a script? Is it the oldest? It counts." "$prompt_path" ||
      fail "prompt missing corrected oldest-selection wording: $prompt_path"
    grep -Fq "Dependency audit        Manifest        Random pool" "$prompt_path" ||
      fail "prompt missing corrected dependency-audit pool wording: $prompt_path"
  done
}

check_fault_injection_registry_contract() {
  local registry_path

  log "checking fault-injection scenario registry contract"
  registry_path="docs/fault-injection-scenarios.md"
  [[ -s "$registry_path" ]] || fail "fault-injection scenario registry is missing or empty"
  grep -Fq "docs/fault-injection-scenarios.md" README.md || fail "README missing fault-injection registry link"
  grep -Fq "docs/fault-injection-scenarios.md" prompts/p31-fault-injection-review.md || fail "P31 prompt missing fault-injection registry link"
  grep -Fq "## Injector Catalog" "$registry_path" || fail "fault-injection registry missing injector catalog"
  grep -Fq "## Flakiness Bans And Restrictions" "$registry_path" || fail "fault-injection registry missing flakiness rules"
  grep -Fq "## Injector Catalog" prompts/p31-fault-injection-review.md || fail "P31 prompt missing injector catalog"
  grep -Fq "## Flakiness Bans And Restrictions" prompts/p31-fault-injection-review.md || fail "P31 prompt missing flakiness rules"
  grep -Fq "P31: not applicable" prompts/p31-fault-injection-review.md || fail "P31 prompt missing not-applicable line"
  grep -Fq "## Fault-Injection Boundary" docs/stress-corpus.md || fail "stress corpus docs missing fault-injection boundary"
  grep -Fq "Scenario registry" docs/stress-corpus.md || fail "stress corpus docs missing scenario registry boundary"
  grep -Fq "Oracle classes" docs/stress-corpus.md || fail "stress corpus docs missing oracle classes boundary"

  python3 - "$registry_path" <<'PY' || fail "fault-injection scenario registry contract failed"
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

required_columns = [
    "scenario_id",
    "module_or_file",
    "fault_surface",
    "injected_fault",
    "expected_reason",
    "expected_exit",
    "expected_log_event",
    "cleanup_required",
    "recovery_run_required",
    "validation_command",
    "quick_or_full",
    "lattice_ready_tags",
    "severity",
    "likelihood",
    "detectability",
    "fixture_cost",
    "priority",
]
required_surfaces = {
    "Review module wiring",
    "Prompt compilation",
    "Fake backend",
    "Transcript artifacts",
    "Status markers",
    "Review summary parser",
    "Quota/session JSONL",
    "Active lock",
    "Wrapper health",
    "Fallback artifacts",
    "Fallback orchestration",
    "Screen fallback",
    "Worktree state",
    "Selection",
    "Tool failure queue",
    "Config/env",
    "Dependency surface",
    "Operator diagnostics",
    "Cleanup",
}

lines = text.splitlines()
try:
    header_line = next(line for line in lines if line.startswith("| scenario_id |"))
except StopIteration:
    raise SystemExit("registry table header missing")

headers = [cell.strip() for cell in header_line.strip().strip("|").split("|")]
missing_columns = [column for column in required_columns if column not in headers]
if missing_columns:
    raise SystemExit(f"missing required columns: {', '.join(missing_columns)}")

rows = []
for line in lines:
    if not re.match(r"^[|] FI-[0-9]{3} [|]", line):
        continue
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    if len(cells) != len(headers):
        raise SystemExit(f"row has {len(cells)} cells but header has {len(headers)}: {line}")
    rows.append(dict(zip(headers, cells)))

if not rows:
    raise SystemExit("registry has no scenario rows")

seen_ids = set()
seen_surfaces = set()
for row in rows:
    scenario_id = row["scenario_id"]
    if not re.fullmatch(r"FI-[0-9]{3}", scenario_id):
        raise SystemExit(f"invalid scenario id: {scenario_id}")
    if scenario_id in seen_ids:
        raise SystemExit(f"duplicate scenario id: {scenario_id}")
    seen_ids.add(scenario_id)
    seen_surfaces.add(row["fault_surface"])

    if row["quick_or_full"] not in {"quick", "full"}:
        raise SystemExit(f"{scenario_id} has invalid quick_or_full: {row['quick_or_full']}")
    if row["cleanup_required"] not in {"yes", "no"}:
        raise SystemExit(f"{scenario_id} has invalid cleanup_required: {row['cleanup_required']}")
    if row["recovery_run_required"] not in {"yes", "no"}:
        raise SystemExit(f"{scenario_id} has invalid recovery_run_required: {row['recovery_run_required']}")
    if row["priority"] not in {"high", "medium", "low", "deferred", "retired"}:
        raise SystemExit(f"{scenario_id} has invalid priority: {row['priority']}")
    if "surface:" not in row["lattice_ready_tags"] or "status:" not in row["lattice_ready_tags"]:
        raise SystemExit(f"{scenario_id} lattice_ready_tags lack surface/status namespaces")
    if "oracle:" not in row["lattice_ready_tags"]:
        raise SystemExit(f"{scenario_id} lattice_ready_tags lack oracle namespace")

covered_full = {
    row["scenario_id"]
    for row in rows
    if "status:covered-by-full-validation" in row["lattice_ready_tags"]
}
for scenario_id in ["FI-020", "FI-021", "FI-022", "FI-023"]:
    if scenario_id not in covered_full:
        raise SystemExit(f"{scenario_id} must be marked covered by full validation")

missing_surfaces = sorted(required_surfaces - seen_surfaces)
if missing_surfaces:
    raise SystemExit(f"missing required surfaces: {', '.join(missing_surfaces)}")

for required_section in [
    "## Required Columns",
    "## Priority Fields",
    "## Injector Catalog",
    "## Flakiness Bans And Restrictions",
    "## Initial Matrix",
    "## Implemented Local Scenarios",
    "## Lattice Import Naming",
]:
    if required_section not in text:
        raise SystemExit(f"missing section: {required_section}")

for required_term in ["Control run", "Injection run", "Recovery run", "Oracle classes", "Scenario registry"]:
    if required_term not in text:
        raise SystemExit(f"missing implemented scenario term: {required_term}")
PY
}

check_default_prompt_target_isolation_contract() {
  log "checking default prompt target isolation contract"
  if grep -Fq -- "- select the next oldest eligible file" "$ROOT_DIR/prompts/default-review.md"; then
    fail "default review prompt still grants unconditional replacement-target authority"
  fi
  grep -Fq -- "report \`STOPPED_ON_BLOCKER\` instead of" "$ROOT_DIR/prompts/default-review.md" ||
    fail "default review prompt does not preserve STOPPED_ON_BLOCKER guidance for preselected targets"
}

check_help_and_diff() {
  local help validation_help
  local module_id selection_review_modules

  log "checking help and whitespace"
  help="$(./Upkeeper --help)"
  validation_help="$(tools/validate_upkeeper.sh --help)"
  while IFS='|' read -r module_id _; do
    grep -Fq -- "--review-module=$module_id" <<<"$help" || fail "help missing --review-module=$module_id"
    grep -Fq -- "--$module_id" <<<"$help" || fail "help missing --$module_id"
  done < <(review_module_specs)
  grep -Fq -- "--config-file=PATH" <<<"$help" || fail "help missing --config-file"
  grep -Fq -- "--no-config" <<<"$help" || fail "help missing --no-config"
  grep -Fq -- "--target-root=PATH" <<<"$help" || fail "help missing --target-root"
  grep -Fq -- "--selection-source=manifest|enumerate" <<<"$help" || fail "help missing --selection-source"
  grep -Fq -- "--selection-order=oldest|newest|random" <<<"$help" || fail "help missing --selection-order"
  grep -Fq -- "--select-untracked" <<<"$help" || fail "help missing --select-untracked"
  grep -Fq -- "--tracked-only" <<<"$help" || fail "help missing --tracked-only"
  grep -Fq -- "--refresh-manifest" <<<"$help" || fail "help missing --refresh-manifest"
  grep -Fq -- "--manifest-file=PATH" <<<"$help" || fail "help missing --manifest-file"
  grep -Fq -- "--include-glob=PATTERN" <<<"$help" || fail "help missing --include-glob"
  grep -Fq -- "--include-globs=a,b" <<<"$help" || fail "help missing --include-globs"
  grep -Fq -- "--exclude-glob=PATTERN" <<<"$help" || fail "help missing --exclude-glob"
  grep -Fq -- "--exclude-globs=a,b" <<<"$help" || fail "help missing --exclude-globs"
  selection_review_modules="$(review_module_list_csv)"
  grep -Fq -- "--selection-review-modules=$selection_review_modules" <<<"$help" || fail "help missing --selection-review-modules"
  grep -Fq -- "--ignore-failure-queue" <<<"$help" || fail "help missing --ignore-failure-queue"
  grep -Fq -- "--backup-queue" <<<"$help" || fail "help missing --backup-queue"
  grep -Fq -- "--max-cover" <<<"$help" || fail "help missing --max-cover"
  grep -Fq -- "--bug-report-only" <<<"$help" || fail "help missing --bug-report-only"
  grep -Fq -- "--audit-only" <<<"$help" || fail "help missing --audit-only"
  grep -Fq -- "--review-only" <<<"$help" || fail "help missing --review-only alias"
  grep -Fq -- "--no-fix" <<<"$help" || fail "help missing --no-fix alias"
  grep -Fq -- "--read-only" <<<"$help" || fail "help missing --read-only alias"
  grep -Fq -- "--fix-next-issue" <<<"$help" || fail "help missing --fix-next-issue"
  grep -Fq -- "--fix-issue=NUMBER" <<<"$help" || fail "help missing --fix-issue"
  grep -Fq -- "--issue-workflow-stage=comment|review|apply" <<<"$help" || fail "help missing issue workflow stage"
  grep -Fq -- "5.3-codex-spark_xhigh" <<<"$help" || fail "help missing Spark model override"
  grep -Fq -- "--smoke" <<<"$validation_help" || fail "validator help missing --smoke"
  grep -Fq -- "--profile" <<<"$validation_help" || fail "validator help missing --profile"
  grep -Fq -- "UPKEEPER_MAX_COVER" <<<"$help" || fail "help missing UPKEEPER_MAX_COVER"
  grep -Fq -- "UPKEEPER_BUG_REPORT_ONLY" <<<"$help" || fail "help missing UPKEEPER_BUG_REPORT_ONLY"
  grep -Fq -- "UPKEEPER_BREADCRUMB_GATE_ENABLED" <<<"$help" || fail "help missing UPKEEPER_BREADCRUMB_GATE_ENABLED"
  grep -Fq -- "UPKEEPER_BREADCRUMB_STATE_DIR" <<<"$help" || fail "help missing UPKEEPER_BREADCRUMB_STATE_DIR"
  grep -Fq -- "UPKEEPER_AUDIT_ONLY" <<<"$help" || fail "help missing UPKEEPER_AUDIT_ONLY"
  grep -Fq -- "UPKEEPER_AUDIT_REPORT_DIR" <<<"$help" || fail "help missing UPKEEPER_AUDIT_REPORT_DIR"
  grep -Fq -- "UPKEEPER_FIX_NEXT_ISSUE" <<<"$help" || fail "help missing UPKEEPER_FIX_NEXT_ISSUE"
  grep -Fq -- "UPKEEPER_FIX_ISSUE" <<<"$help" || fail "help missing UPKEEPER_FIX_ISSUE"
  grep -Fq -- "UPKEEPER_ISSUE_WORKFLOW_STAGE" <<<"$help" || fail "help missing UPKEEPER_ISSUE_WORKFLOW_STAGE"
  grep -Fq -- "UPKEEPER_LOCAL_ENV_FILE" <<<"$help" || fail "help missing UPKEEPER_LOCAL_ENV_FILE"
  grep -Fq -- "tools/upkeeper_precontact_bootstrap.sh" <<<"$help" || fail "help missing pre-contact bootstrap helper"
  grep -Fq -- "UPKEEPER_PRECONTACT_BACKUP_ENABLED" <<<"$help" || fail "help missing UPKEEPER_PRECONTACT_BACKUP_ENABLED"
  grep -Fq -- "pre-contact backup" <<<"$help" || fail "help missing pre-contact backup summary"
  local flameon_cmd
  flameon_cmd="$(FLAMEON_DRY_RUN=1 ./FlameOn)"
  grep -Fq -- "--max-cover" <<<"$flameon_cmd" || fail "FlameOn dry-run missing --max-cover"
  grep -Fq -- "--bug-report-only" <<<"$flameon_cmd" || fail "FlameOn dry-run missing --bug-report-only"
  grep -Fq -- "UPKEEPER_LATTICE_REQUIRED=1" <<<"$flameon_cmd" || fail "FlameOn dry-run missing required Lattice full-burn default"
  grep -Fq -- "UPKEEPER_PRECONTACT_BACKUP_MODE=age" <<<"$flameon_cmd" || fail "FlameOn dry-run missing age backup full-burn default"
  grep -Fq -- "UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=1" <<<"$flameon_cmd" || fail "FlameOn dry-run missing encrypted backup full-burn default"
  grep -Fq -- "CODEX_WEEK_STOP_PERCENT=0" <<<"$flameon_cmd" || fail "FlameOn dry-run missing spend-to-zero quota full-burn default"
  grep -Fq -- "CODEX_QUOTA_GUARDRAIL_BYPASS=1" <<<"$flameon_cmd" || fail "FlameOn dry-run missing quota guardrail bypass"
  grep -Fq -- "CODEX_QUOTA_COOLDOWN_BYPASS=1" <<<"$flameon_cmd" || fail "FlameOn dry-run missing quota cooldown bypass"
  flameon_cmd="$(FLAMEON_DRY_RUN=1 ./FlameOn --model gpt-5.3-codex-spark --reasoning-effort xhigh)"
  grep -Fq -- "--model-override=5.3-codex-spark_xhigh" <<<"$flameon_cmd" || fail "FlameOn dry-run missing Spark shortcut override"
  git diff --check
  git diff --cached --check
}

check_gitignore_contract() {
  local output path

  log "checking Git ignore contract"
  for path in Upkeeper.log runtime/example runtime/upkeeper-file-manifest.json out out/tmp; do
    output="$(
      GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
        git -c core.excludesfile=/dev/null check-ignore -v --no-index -- "$path"
    )" || fail "Git ignore contract does not ignore $path"
    [[ "$output" == .gitignore:* ]] || fail "Git ignore contract ignores $path outside .gitignore: $output"
  done

  for path in docs/out docs/out/tmp; do
    if output="$(
      GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
        git -c core.excludesfile=/dev/null check-ignore -v --no-index -- "$path"
    )"; then
      fail "Git ignore contract should not ignore nested source path $path: $output"
    fi
  done
}

check_force_added_gitignored_target_selection() {
  local temp_dir client manifest_path rc lattice_db_path

  log "checking force-added Git-ignored target exclusion"
  temp_dir="$(mktemp -d /tmp/upkeeper-gitignored-target.XXXXXX)"
  client="$temp_dir/client"
  manifest_path="$client/runtime/upkeeper-file-manifest-validation.json"
  lattice_db_path="$temp_dir/client/runtime/upkeeper-lattice/lattice-direct.sqlite3"
  mkdir -p "$client"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/10/fake-session.jsonl" "gpt-5.5"

  (
    cd "$client"
    git init -q
    git config user.name "Upkeeper Validation"
    git config user.email "upkeeper-validation@example.invalid"
    printf 'secrets.sh\n' >.gitignore
    printf '#!/usr/bin/env bash\nprintf "ignored fixture\\n"\n' >secrets.sh
    chmod +x secrets.sh
    git add -f secrets.sh
    ln -s "$ROOT_DIR/Upkeeper" Upkeeper
  )

  run_gitignored_target_dry_run() {
    local log_file="$1"
    shift
    (
      cd "$client"
      CODEX_HOME="$temp_dir/codex-home" \
        CODEX_LOG_FILE="$log_file" \
        CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
        CODEX_ACTIVE_LOCK_DIR="$(validation_active_lock_dir "$client" "gitignored-target")" \
        CODEX_POSTMORTEM_DIR="$temp_dir/postmortems" \
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
        CODEX_TOOL_FAILURE_QUEUE_DIR="$temp_dir/failures" \
        UPKEEPER_LATTICE_DB="$temp_dir/lattice.sqlite3" \
        UPKEEPER_DRY_RUN=1 \
        ./Upkeeper "$@"
    ) >"$temp_dir/out.txt" 2>"$temp_dir/err.txt"
  }

  set +e
  run_gitignored_target_dry_run "$temp_dir/explicit.log" --target-file=secrets.sh
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || fail "explicit force-added ignored target exited $rc, expected 3"
  grep -Fq "reason=TARGET_FILE_NOT_ELIGIBLE" "$temp_dir/explicit.log" || fail "force-added ignored target did not fail as ineligible"
  grep -Fq "ignored\\ by\\ git" "$temp_dir/explicit.log" || fail "force-added ignored target did not name Git ignore reason"

  run_gitignored_target_dry_run "$temp_dir/enumerate.log" --selection-source=enumerate
  grep -Fq "review.preselect.none reason=no_eligible_script_tool" "$temp_dir/enumerate.log" || fail "force-added ignored target was not excluded from enumerate selection"
  if grep -Fq "review.preselect path=secrets.sh" "$temp_dir/enumerate.log"; then
    fail "enumerate selection chose a force-added ignored target"
  fi

  run_gitignored_target_dry_run "$temp_dir/manifest.log" --selection-source=manifest --refresh-manifest
  jq -e 'all(.files[]?; .rel_path != "secrets.sh")' "$manifest_path" >/dev/null ||
    fail "manifest included a force-added ignored target"
  grep -Fq "review.preselect.none reason=no_eligible_script_tool" "$temp_dir/manifest.log" || fail "force-added ignored target was not excluded from manifest selection"

  "$ROOT_DIR/tools/upkeeper_lattice.py" \
    --root "$client" \
    --db "$lattice_db_path" \
    init >"$temp_dir/lattice-init.json"
  "$ROOT_DIR/tools/upkeeper_lattice.py" \
    --root "$client" \
    --db "$lattice_db_path" \
    query selection-candidates --mode max-cover --format jsonl >"$temp_dir/lattice-candidates.jsonl"
  python3 - "$temp_dir/lattice-candidates.jsonl" <<'PY' ||
import json
import sys

seen_secret = False
for line in open(sys.argv[1], encoding="utf-8"):
    row = json.loads(line)
    if row.get("path") == "secrets.sh":
        seen_secret = True
        assert row.get("candidate_state") == "excluded", row
        assert row.get("exclusion_reason") == "gitignore", row
assert seen_secret, "secrets.sh was not represented in Lattice candidate diagnostics"
PY
    fail "Lattice did not exclude the force-added ignored target"

  rm -r "$temp_dir"
}

check_symlink_target_selection_guard() {
  local temp_dir client manifest_path outside_target rc lattice_db_path

  log "checking symlink target selection guard"
  temp_dir="$(mktemp -d /tmp/upkeeper-symlink-target.XXXXXX)"
  client="$temp_dir/client"
  manifest_path="$client/runtime/upkeeper-file-manifest-validation.json"
  outside_target="$temp_dir/outside-sentinel.txt"
  lattice_db_path="$temp_dir/client/runtime/upkeeper-lattice/lattice-direct.sqlite3"
  mkdir -p "$client"
  printf 'outside sentinel\n' >"$outside_target"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/10/fake-session.jsonl" "gpt-5.5"

  (
    cd "$client"
    git init -q
    git config user.name "Upkeeper Validation"
    git config user.email "upkeeper-validation@example.invalid"
    mkdir -p tools
    ln -s "$outside_target" tools/review.sh
    git add tools/review.sh
    ln -s "$ROOT_DIR/Upkeeper" Upkeeper
  )

  run_symlink_target_dry_run() {
    local log_file="$1"
    shift
    (
      cd "$client"
      CODEX_HOME="$temp_dir/codex-home" \
        CODEX_LOG_FILE="$log_file" \
        CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
        CODEX_ACTIVE_LOCK_DIR="$(validation_active_lock_dir "$client" "symlink-target")" \
        CODEX_POSTMORTEM_DIR="$temp_dir/postmortems" \
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
        CODEX_TOOL_FAILURE_QUEUE_DIR="$temp_dir/failures" \
        UPKEEPER_LATTICE_DB="$temp_dir/lattice.sqlite3" \
        UPKEEPER_DRY_RUN=1 \
        ./Upkeeper "$@"
    ) >"$temp_dir/out.txt" 2>"$temp_dir/err.txt"
  }

  set +e
  run_symlink_target_dry_run "$temp_dir/explicit.log" --target-file=tools/review.sh
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || fail "explicit symlink target exited $rc, expected 3"
  grep -Fq "reason=TARGET_FILE_NOT_ELIGIBLE" "$temp_dir/explicit.log" || fail "symlink target did not fail as ineligible"
  grep -Fq "target\\ path\\ is\\ a\\ symlink" "$temp_dir/explicit.log" || fail "symlink target did not name symlink reason"

  run_symlink_target_dry_run "$temp_dir/enumerate.log" --selection-source=enumerate
  grep -Fq "review.preselect.none reason=no_eligible_script_tool" "$temp_dir/enumerate.log" || fail "symlink target was not excluded from enumerate selection"
  if grep -Fq "review.preselect path=tools/review.sh" "$temp_dir/enumerate.log"; then
    fail "enumerate selection chose a symlink target"
  fi

  run_symlink_target_dry_run "$temp_dir/manifest.log" --selection-source=manifest --refresh-manifest
  jq -e 'all(.files[]?; .rel_path != "tools/review.sh")' "$manifest_path" >/dev/null ||
    fail "manifest included a symlink target"
  grep -Fq "review.preselect.none reason=no_eligible_script_tool" "$temp_dir/manifest.log" || fail "symlink target was not excluded from manifest selection"

  "$ROOT_DIR/tools/upkeeper_lattice.py" \
    --root "$client" \
    --db "$lattice_db_path" \
    init >"$temp_dir/lattice-init.json"
  "$ROOT_DIR/tools/upkeeper_lattice.py" \
    --root "$client" \
    --db "$lattice_db_path" \
    query selection-candidates --mode max-cover --format jsonl >"$temp_dir/lattice-candidates.jsonl"
  python3 - "$temp_dir/lattice-candidates.jsonl" <<'PY' ||
import json
import sys

seen_link = False
for line in open(sys.argv[1], encoding="utf-8"):
    row = json.loads(line)
    if row.get("path") == "tools/review.sh":
        seen_link = True
        assert row.get("candidate_state") == "excluded", row
        assert row.get("exclusion_reason") == "symlink", row
assert seen_link, "tools/review.sh was not represented in Lattice candidate diagnostics"
PY
    fail "Lattice did not exclude the symlink target"

  grep -Fqx "outside sentinel" "$outside_target" || fail "symlink target sentinel content changed"
  rm -r "$temp_dir"
}

check_validation_environment_isolation() {
  local helper_call_count

  log "checking validation environment isolation"

  [[ "$CODEX_5H_STOP_PERCENT" == "5" ]] || fail "validation inherited CODEX_5H_STOP_PERCENT=$CODEX_5H_STOP_PERCENT"
  [[ "$CODEX_SPARK_5H_STOP_PERCENT" == "0" ]] || fail "validation inherited CODEX_SPARK_5H_STOP_PERCENT=$CODEX_SPARK_5H_STOP_PERCENT"
  [[ "$CODEX_WEEK_STOP_PERCENT" == "15" ]] || fail "validation inherited CODEX_WEEK_STOP_PERCENT=$CODEX_WEEK_STOP_PERCENT"
  [[ "$CODEX_WEEK_STOP_BUFFER_PERCENT" == "0" ]] || fail "validation inherited CODEX_WEEK_STOP_BUFFER_PERCENT=$CODEX_WEEK_STOP_BUFFER_PERCENT"
  [[ "$CODEX_SPARK_WEEK_STOP_BUFFER_PERCENT" == "5" ]] || fail "validation inherited CODEX_SPARK_WEEK_STOP_BUFFER_PERCENT=$CODEX_SPARK_WEEK_STOP_BUFFER_PERCENT"
  [[ "$CODEX_QUOTA_GUARDRAIL_BYPASS" == "0" ]] || fail "validation inherited CODEX_QUOTA_GUARDRAIL_BYPASS=$CODEX_QUOTA_GUARDRAIL_BYPASS"
  [[ "$CODEX_QUOTA_COOLDOWN_BYPASS" == "0" ]] || fail "validation inherited CODEX_QUOTA_COOLDOWN_BYPASS=$CODEX_QUOTA_COOLDOWN_BYPASS"
  [[ "$UPKEEPER_LATTICE_REQUIRED" == "0" ]] || fail "validation inherited UPKEEPER_LATTICE_REQUIRED=$UPKEEPER_LATTICE_REQUIRED"
  [[ "$UPKEEPER_PRECONTACT_BACKUP_MODE" == "auto" ]] || fail "validation inherited UPKEEPER_PRECONTACT_BACKUP_MODE=$UPKEEPER_PRECONTACT_BACKUP_MODE"
  [[ "$UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED" == "0" ]] || fail "validation inherited UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=$UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED"
  [[ -z "$UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT" ]] || fail "validation inherited UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT"
  [[ "$UPKEEPER_AUTOMATION_LEDGER_DIR" == "$VALIDATION_TMP_ROOT/automation-ledger" ]] || fail "validation automation ledger is not isolated: $UPKEEPER_AUTOMATION_LEDGER_DIR"
  [[ "$UPKEEPER_OBLIGATION_DIR" == "$VALIDATION_TMP_ROOT/automation-obligations" ]] || fail "validation obligation root is not isolated: $UPKEEPER_OBLIGATION_DIR"
  grep -Fq "run_upkeeper_validation_cycle()" tools/validate_upkeeper.sh ||
    fail "validation dry-run helper is missing"
  grep -Fq '>"$out_file" 2>"$err_file"' tools/validate_upkeeper.sh ||
    fail "validation dry-run helper does not preserve stdout/stderr split"
  grep -Fq '"CODEX_HOME=$code_home"' tools/validate_upkeeper.sh ||
    fail "validation dry-run helper does not set isolated CODEX_HOME"
  grep -Fq '"UPKEEPER_DRY_RUN=$dry_run"' tools/validate_upkeeper.sh ||
    fail "validation dry-run helper does not force dry-run mode by default"
  helper_call_count="$(grep -Fc "run_upkeeper_validation_cycle" tools/validate_upkeeper.sh)"
  [[ "$helper_call_count" -ge 10 ]] ||
    fail "validation dry-run helper is not used by enough dry-run fixtures"
}

validation_quota_state_for_home() {
  local codex_home="$1"
  local model="${2:-gpt-5.5}"
  local log_file="${3:-$codex_home/Upkeeper.log}"

  CODEX_HOME_DIR="$codex_home" CODEX_SESSION_SCAN_LIMIT=200 LOG_FILE="$log_file" \
    bash -lc 'cd "$1"; source lib/upkeeper/quota_state.bash; quota_state_json "$2"' \
    bash "$ROOT_DIR" "$model"
}

check_validation_quota_session_fixture_contract() {
  local temp_dir state diagnostics agent_messages reached_type
  local current_home stale_home wrong_home nonfinite_home missing_home
  local malformed_session empty_session empty_state

  log "checking validation quota/session fixtures"
  temp_dir="$(mktemp -d /tmp/upkeeper-validation-fixtures.XXXXXX)"

  current_home="$temp_dir/current/codex-home"
  write_validation_current_quota_snapshot "$current_home/sessions/2026/05/07/current.jsonl" "gpt-5.5"
  state="$(validation_quota_state_for_home "$current_home" "gpt-5.5" "$temp_dir/current.log")"
  [[ "$(jq -r '.snapshot_is_current' <<<"$state")" == "true" ]] ||
    fail "current quota fixture did not parse as current"
  [[ "$(jq -r '.snapshot.snapshot_stale_after_reset' <<<"$state")" == "false" ]] ||
    fail "current quota fixture parsed as stale"

  stale_home="$temp_dir/stale/codex-home"
  write_validation_stale_quota_snapshot "$stale_home/sessions/2026/05/07/stale.jsonl" "gpt-5.5"
  state="$(validation_quota_state_for_home "$stale_home" "gpt-5.5" "$temp_dir/stale.log")"
  [[ "$(jq -r '.snapshot.snapshot_stale_after_reset' <<<"$state")" == "true" ]] ||
    fail "stale quota fixture did not parse as stale-after-reset"
  [[ "$(jq -r '.snapshot.primary_reset_expired' <<<"$state")" == "true" ]] ||
    fail "stale quota fixture did not mark primary reset expired"

  wrong_home="$temp_dir/wrong-model/codex-home"
  write_validation_wrong_model_quota_snapshot "$wrong_home/sessions/2026/05/07/wrong.jsonl" "gpt-5.4"
  state="$(validation_quota_state_for_home "$wrong_home" "gpt-5.5" "$temp_dir/wrong.log")"
  [[ "$(jq -r '.snapshot_selection' <<<"$state")" == "overall_fallback" ]] ||
    fail "wrong-model quota fixture did not parse as fallback evidence"
  [[ "$(jq -r '.snapshot.model_hint' <<<"$state")" == "gpt-5.4" ]] ||
    fail "wrong-model quota fixture lost model hint"

  nonfinite_home="$temp_dir/nonfinite/codex-home"
  write_validation_nonfinite_quota_snapshot "$nonfinite_home/sessions/2026/05/07/nonfinite.jsonl" "gpt-5.5"
  state="$(validation_quota_state_for_home "$nonfinite_home" "gpt-5.5" "$temp_dir/nonfinite.log")"
  [[ "$(jq -r '.error // ""' <<<"$state")" == "no_rate_limit_snapshot_found" ]] ||
    fail "nonfinite quota fixture should not produce a usable snapshot"

  missing_home="$temp_dir/missing-fields/codex-home"
  write_validation_missing_rate_limit_fields_snapshot "$missing_home/sessions/2026/05/07/missing.jsonl" "gpt-5.5"
  state="$(validation_quota_state_for_home "$missing_home" "gpt-5.5" "$temp_dir/missing.log")"
  [[ "$(jq -r '.error // ""' <<<"$state")" == "no_rate_limit_snapshot_found" ]] ||
    fail "missing-field quota fixture should not produce a usable snapshot"

  malformed_session="$temp_dir/malformed/session.jsonl"
  write_validation_malformed_session_jsonl "$malformed_session"
  state="$(bash -lc 'cd "$1"; source lib/upkeeper/status_session.bash; parse_session_end_state "$2"' bash "$ROOT_DIR" "$malformed_session")"
  [[ "$state" == "turn_aborted:rate_limit_retry" ]] || fail "malformed session fixture state was $state"
  diagnostics="$(bash -lc 'cd "$1"; source lib/upkeeper/status_session.bash; session_diagnostics_json "$2"' bash "$ROOT_DIR" "$malformed_session")"
  agent_messages="$(jq -r '.agent_message_count' <<<"$diagnostics")"
  reached_type="$(jq -r '.last_rate_limit_reached_type' <<<"$diagnostics")"
  [[ "$agent_messages" == "1" ]] || fail "malformed session fixture agent message count was $agent_messages"
  [[ "$reached_type" == "unknown" ]] || fail "malformed session fixture rate-limit sentinel was $reached_type"

  empty_session="$temp_dir/empty/session.jsonl"
  write_validation_empty_session_jsonl "$empty_session"
  empty_state="$(bash -lc 'cd "$1"; source lib/upkeeper/status_session.bash; parse_session_end_state "$2"' bash "$ROOT_DIR" "$empty_session")"
  [[ "$empty_state" == "none" ]] || fail "empty session fixture state was $empty_state"

  rm -r "$temp_dir"
}

check_dependency_guidance_contract() {
  log "checking dependency guidance contract"

  grep -Fq "Supported Platforms And Portability" docs/dependencies.md ||
    fail "dependency docs missing supported platform boundary"
  grep -Fq "Linux with a GNU userland" docs/dependencies.md ||
    fail "dependency docs missing Linux/GNU support baseline"
  grep -Fq "WSL2 is supported as a Linux environment" docs/dependencies.md ||
    fail "dependency docs missing WSL2 support boundary"
  grep -Fq "macOS is deferred" docs/dependencies.md ||
    fail "dependency docs missing macOS deferred boundary"
  grep -Fq "macos-latest" docs/dependencies.md ||
    fail "dependency docs missing deferred macOS CI condition"
  grep -Fq "Start with Ubuntu. Add macos-latest" .github/workflows/ci.yml ||
    fail "CI workflow missing macOS deferral note"
  grep -Fq "platform_support_status_line" tools/validate_upkeeper.sh ||
    fail "validator missing platform support status helper"
  grep -Fq "require_supported_platform" tools/validate_upkeeper.sh ||
    fail "validator missing unsupported-platform fail-fast guard"
  grep -Fq '`jq` remains a required runtime and validation dependency' docs/dependencies.md ||
    fail "dependency docs missing explicit jq decision"
  grep -Fq 'sudo apt-get install -y jq' docs/dependencies.md ||
    fail "dependency docs missing Debian/Ubuntu jq install command"
  grep -Fq 'sudo dnf install -y jq' docs/dependencies.md ||
    fail "dependency docs missing Fedora/RHEL jq install command"
  grep -Fq 'sudo pacman -S --needed jq' docs/dependencies.md ||
    fail "dependency docs missing Arch jq install command"
  grep -Fq 'brew install jq' docs/dependencies.md ||
    fail "dependency docs missing Homebrew jq install command"
  grep -Fq 'JSON assignment bridges' docs/dependencies.md ||
    fail "dependency docs missing future jq removal condition"
  grep -Fq 'docs=docs/dependencies.md action=install_dependency' lib/upkeeper/codex_io.bash ||
    fail "runtime missing-command diagnostics do not point at dependency docs"
  grep -Fq 'missing required command: $command_name; see docs/dependencies.md' tools/validate_upkeeper.sh ||
    fail "validator missing-command diagnostics do not point at dependency docs"
  grep -Fq '`jq` is intentionally still a required runtime dependency' README.md ||
    fail "README missing explicit jq dependency decision"
  grep -Fq 'jq` remains required' docs/security.md ||
    fail "security docs missing jq dependency decision"
}

check_release_readiness_docs_contract() {
  log "checking release-readiness docs contract"

  for doc_path in docs/prd.md docs/roadmap.md docs/release-checklist.md docs/known-issues.md; do
    [[ -s "$doc_path" ]] || fail "release-readiness doc missing or empty: $doc_path"
    grep -Fq "$doc_path" README.md || fail "README missing release-readiness doc link: $doc_path"
  done

  grep -Fq "Product Goal" docs/prd.md || fail "PRD missing product goal"
  grep -Fq "Non-Goals" docs/prd.md || fail "PRD missing non-goals"
  grep -Fq "## Now" docs/roadmap.md || fail "roadmap missing Now section"
  grep -Fq "## Next" docs/roadmap.md || fail "roadmap missing Next section"
  grep -Fq "tools/validate_upkeeper.sh --full" docs/release-checklist.md ||
    fail "release checklist missing full validation command"
  grep -Fq "tools/validate_upkeeper.sh --quick" docs/release-checklist.md ||
    fail "release checklist missing quick validation command"
  grep -Fq "tools/validate_upkeeper.sh --deps" docs/release-checklist.md ||
    fail "release checklist missing deps validation command"
  grep -Fq "tools/stress_upkeeper_corpus.sh --local" docs/release-checklist.md ||
    fail "release checklist missing local stress-corpus command"
  grep -Fq "no real Codex" docs/release-checklist.md ||
    fail "release checklist missing no-real-backend release-gate requirement"
  grep -Fq "Taxonomy and Release Gate" docs/release-checklist.md ||
    fail "release checklist missing issue taxonomy section"
  grep -Fq "Current Major Risk Areas" docs/known-issues.md ||
    fail "known issues missing major risk section"
  grep -Fq "p0-release-blocker" docs/compatibility.md docs/release-checklist.md docs/scripts/upkeeper.md ||
    fail "issue taxonomy labels for release gate are undocumented"
}

check_governance_docs_contract() {
  log "checking governance docs contract"

  for doc_path in \
    docs/ownership.md \
    docs/decisions/README.md \
    docs/risk-register.md; do
    [[ -s "$doc_path" ]] || fail "governance doc missing or empty: $doc_path"
    grep -Fq "$doc_path" README.md || fail "README missing governance doc link: $doc_path"
  done
  [[ -s docs/decisions/0001-upkeeper-baseline-contracts.md ]] ||
    fail "governance decision missing or empty: docs/decisions/0001-upkeeper-baseline-contracts.md"
  grep -Fq "0001-upkeeper-baseline-contracts.md" docs/decisions/README.md ||
    fail "decision log index missing baseline decision link"

  grep -Fq "Product behavior" docs/ownership.md || fail "ownership doc missing product behavior area"
  grep -Fq "Shell architecture" docs/ownership.md || fail "ownership doc missing shell architecture area"
  grep -Fq "Prompts and review modules" docs/ownership.md || fail "ownership doc missing prompt area"
  grep -Fq "Validation" docs/ownership.md || fail "ownership doc missing validation area"
  grep -Fq "Security and privacy" docs/ownership.md || fail "ownership doc missing security area"
  grep -Fq "Compatibility" docs/ownership.md || fail "ownership doc missing compatibility area"
  grep -Fq "Releases" docs/ownership.md || fail "ownership doc missing release area"
  grep -Fq "Shell-sourced config is trusted local input only" docs/decisions/0001-upkeeper-baseline-contracts.md ||
    fail "baseline decision missing trusted config contract"
  grep -Fq "central-first symlink model" docs/decisions/0001-upkeeper-baseline-contracts.md ||
    fail "baseline decision missing symlink model"
  grep -Fq "Validation does not run real Codex backend work by default" docs/decisions/0001-upkeeper-baseline-contracts.md ||
    fail "baseline decision missing no-backend validation contract"
  grep -Fq "Local runtime evidence is ignored by Git" docs/decisions/0001-upkeeper-baseline-contracts.md ||
    fail "baseline decision missing runtime evidence contract"
  grep -Fq "Fallback and postmortem" docs/decisions/0001-upkeeper-baseline-contracts.md ||
    fail "baseline decision missing fallback/postmortem contract"
  grep -Fq "Quota snapshots are parsed from local" docs/decisions/0001-upkeeper-baseline-contracts.md ||
    fail "baseline decision missing quota snapshot contract"
  grep -Fq "Lattice integrity blockers" docs/risk-register.md ||
    fail "risk register missing Lattice integrity risk"
  grep -Fq "Parallel worker collisions" docs/risk-register.md ||
    fail "risk register missing parallel worker risk"
}

check_negative_space_testing_contract() {
  local doc_path="docs/negative-space-testing.md"
  local linked_path invariant_id phrase

  log "checking negative-space testing contract"

  [[ -s "$doc_path" ]] || fail "negative-space testing docs are missing or empty"
  for linked_path in README.md docs/security.md docs/compatibility.md docs/scripts/upkeeper.md; do
    grep -Fq "$doc_path" "$linked_path" || fail "$linked_path does not link the negative-space testing contract"
  done

  for invariant_id in NS-001 NS-002 NS-003 NS-004 NS-005 NS-006 NS-007 NS-008; do
    grep -Fq "$invariant_id" "$doc_path" || fail "negative-space catalog missing $invariant_id"
  done
  for phrase in \
    "must not select runtime artifacts" \
    "must not reveal the backup vault root" \
    "must not replace a selected target" \
    "must not leave tracked-source mutations" \
    "must not be accepted as clean absence or successful work" \
    "must not spend real backend quota" \
    "must not be treated as safe" \
    "must not be accepted as active protection"; do
    grep -Fq "$phrase" "$doc_path" || fail "negative-space catalog missing phrase: $phrase"
  done

  grep -Fq "runtime_path_rejected" tests/precontact_backup_test.bash ||
    fail "negative-space proof missing runtime target rejection fixture"
  grep -Fq "compiled prompt leaked vault root" tests/precontact_backup_test.bash ||
    fail "negative-space proof missing vault-root leak fixture"
  grep -Fq "Replacement target selection is wrapper-only" tests/precontact_backup_test.bash ||
    fail "negative-space proof missing replacement-authority fixture"
  grep -Fq "source_mutation_guard.violation" Upkeeper ||
    fail "negative-space proof missing source mutation guard"
  grep -Fq "BUG_REPORT_ONLY_MUTATION_VIOLATION" Upkeeper ||
    fail "negative-space proof missing bug-report-only mutation reason"
  grep -Fq "test_status_marker_rejects_decorated_or_ambiguous_candidates" tests/wrapper_contract_test.bash ||
    fail "negative-space proof missing malformed status-marker fixture"
  grep -Fq "No mode launches a real Codex backend task" tools/validate_upkeeper.sh ||
    fail "negative-space proof missing no-backend validation contract"
  grep -Fq "config file must not be a symlink" Upkeeper ||
    fail "negative-space proof missing unsafe config preflight"
  grep -Fq "Genie Protocol requires sandboxed backend Codex execution" tests/wrapper_contract_test.bash ||
    fail "negative-space proof missing unsafe backend mode fixture"
}

check_serious_finding_repro_contract() {
  local doc_path="docs/negative-space-testing.md"
  local issue_template=".github/ISSUE_TEMPLATE/serious-finding.yml"
  local pr_template=".github/pull_request_template.md"
  local phrase

  log "checking serious finding repro contract"

  [[ -s "$issue_template" ]] || fail "serious finding issue template is missing or empty"
  [[ -s "$pr_template" ]] || fail "pull request template is missing or empty"

  for phrase in \
    "Serious Finding Repro Contract" \
    "security boundary" \
    "filesystem writes/deletes" \
    "Lattice import/export/recovery" \
    "target selection" \
    "quota/fallback behavior" \
    "status marker parsing" \
    "failure queue" \
    "runtime cleanup" \
    "cross-platform assumptions" \
    "local deterministic repro fixture" \
    "cloud audit repro" \
    "explicit documented non-repro rationale" \
    "For serious issues opened before this template existed, the backfill rule is" \
    "Release review treats missing repro status" \
    "pre-existing serious issues as unfinished validation work"; do
    grep -Fq "$phrase" "$doc_path" || fail "serious finding repro policy missing phrase: $phrase"
  done

  grep -Fq "Repro fixture status" "$issue_template" ||
    fail "serious finding issue template does not ask for repro fixture status"
  grep -Fq "local deterministic repro fixture included or planned" "$issue_template" ||
    fail "serious finding issue template missing local fixture status option"
  grep -Fq "cloud audit repro included or planned" "$issue_template" ||
    fail "serious finding issue template missing cloud audit status option"
  grep -Fq "explicit non-repro rationale included" "$issue_template" ||
    fail "serious finding issue template missing non-repro rationale option"
  grep -Fq "Serious Finding Repro Status" "$pr_template" ||
    fail "pull request template does not ask for serious finding repro status"
  grep -Fq "Local deterministic repro fixture" "$pr_template" ||
    fail "pull request template missing local fixture checkbox"
  grep -Fq "Cloud audit repro" "$pr_template" ||
    fail "pull request template missing cloud audit checkbox"
  grep -Fq "Explicit non-repro rationale" "$pr_template" ||
    fail "pull request template missing non-repro rationale checkbox"
  grep -Fq "Serious security, data-integrity" docs/release-checklist.md ||
    fail "release checklist missing serious finding repro release gate"
}

check_after_action_review_contract() {
  local prompt_path="prompts/p27-educational-debrief-review.md"
  local pr_template=".github/pull_request_template.md"
  local phrase

  log "checking after-action review contract"

  [[ -s "$prompt_path" ]] || fail "P27 after-action review prompt is missing or empty"
  [[ -s "$pr_template" ]] || fail "pull request template is missing or empty"

  for phrase in \
    "# P27 After-Action Review" \
    "Self-optimization is part of this module" \
    "outcome summary" \
    "what went right" \
    "what went wrong" \
    "what was wasteful" \
    "whether the system learned anything reusable" \
    "P27 After-Action Review:" \
    "Outcome:" \
    "What went right:" \
    "What went wrong:" \
    "What was wasteful:" \
    "What can improve next time:" \
    "Reusable learning:"; do
    grep -Fq "$phrase" "$prompt_path" "$pr_template" docs/public-documentation-policy.md README.md ||
      fail "after-action review contract missing phrase: $phrase"
  done

  grep -Fq "after-action review pass" docs/public-documentation-policy.md ||
    fail "public documentation policy missing after-action review wording"
  grep -Fq "P27 review module for concise saved after-action reviews" README.md ||
    fail "README missing after-action review prompt summary"
  grep -Fq "central P27 after-action review" docs/scripts/upkeeper.md ||
    fail "operator guide missing P27 after-action wording"
}

check_client_link_tools_contract() {
  log "checking client link tools contract"

  for tool_path in \
    tools/install_client_link.sh \
    tools/update_client_link.sh \
    tools/uninstall_client_link.sh \
    tools/doctor_upkeeper.sh \
    tools/upkeeper_client_link_common.sh; do
    [[ -x "$tool_path" ]] || fail "client link helper missing or not executable: $tool_path"
  done

  for tool_path in \
    tools/install_client_link.sh \
    tools/update_client_link.sh \
    tools/uninstall_client_link.sh \
    tools/doctor_upkeeper.sh; do
    grep -Fq "$tool_path" README.md || fail "README missing client link helper link: $tool_path"
  done

  [[ -s tests/client_link_tools_test.bash ]] || fail "client link focused test missing"
  grep -Fq "doctor_upkeeper.sh" tests/client_link_tools_test.bash ||
    fail "client link test does not exercise doctor helper"
  grep -Fq "install_client_link.sh --repo=CLIENT" docs/scripts/upkeeper.md ||
    fail "operator guide missing install helper workflow"
  grep -Fq "doctor_upkeeper.sh --repo=CLIENT" docs/scripts/upkeeper.md ||
    fail "operator guide missing doctor helper workflow"
  grep -Fq "git-path info/exclude" tools/upkeeper_client_link_common.sh ||
    fail "client link helpers do not use local Git exclude state"
  grep -Fq "docs/scripts/upkeeper.md" tools/upkeeper_client_link_common.sh ||
    fail "client link helpers do not ignore operator guide state"
  grep -Fq "UPKEEPER_DRY_RUN=1" tools/doctor_upkeeper.sh ||
    fail "doctor helper does not enforce dry-run startup"
  grep -Fq "CODEX_QUOTA_GUARDRAIL_BYPASS=1" tools/doctor_upkeeper.sh ||
    fail "doctor helper does not keep dry-run quota-free"
  grep -Fq 'CODEX_HOME="$DOCTOR_CODEX_HOME"' tools/doctor_upkeeper.sh ||
    fail "doctor helper does not isolate dry-run quota evidence"
  grep -Fq "UPKEEPER_PRECONTACT_BACKUP_MODE=off" tools/doctor_upkeeper.sh ||
    fail "doctor helper does not keep link diagnostics out of backup custody"
}

check_validation_mode_boundary_contract() {
  log "checking validation mode boundary contract"

  python3 - "$ROOT_DIR/tools/validate_upkeeper.sh" <<'PY' || fail "validation mode boundary contract is not enforced"
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
quick_exit = text.rindex('\nif [[ "$MODE" == "quick" ]]; then')
full_gate = text.rindex('\nif [[ "$MODE" == "full" ]]; then')
heavy_checks = [
    "review_module_flags",
    "config_file_support",
    "cycle_start_log_contract",
    "file_manifest_selection",
    "tool_failure_queue",
    "lattice_contract",
]
for name in heavy_checks:
    marker = f"run_bounded_check {name}"
    pos = text.index(marker)
    if pos < quick_exit:
        raise SystemExit(f"{name} runs before quick exit")
    if pos > full_gate:
        raise SystemExit(f"{name} is not in the integration block before full-only extras")
if 'fail "check $name exceeded ${timeout_seconds}s timeout"' not in text:
    raise SystemExit("bounded timeout failure diagnostic missing")
PY
}

check_wrapper_contract_tests() {
  log "checking focused wrapper contract tests"
  bash tests/wrapper_contract_test.bash
}

prepare_validation_session_file() {
  local session_file="$1"
  local session_root

  mkdir -p "$(dirname -- "$session_file")"
  if [[ "$session_file" == */sessions/* ]]; then
    session_root="${session_file%%/sessions/*}/sessions"
    chmod 700 "$session_root" 2>/dev/null || true
  fi
}

write_validation_quota_snapshot() {
  local session_file="$1"
  local model="$2"
  local primary_reset_offset="${3:-3600}"
  local secondary_reset_offset="${4:-86400}"

  prepare_validation_session_file "$session_file"
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

write_validation_current_quota_snapshot() {
  write_validation_quota_snapshot "$1" "${2:-gpt-5.5}" 3600 86400
}

write_validation_stale_quota_snapshot() {
  write_validation_quota_snapshot "$1" "${2:-gpt-5.5}" -3600 -7200
}

write_validation_wrong_model_quota_snapshot() {
  write_validation_quota_snapshot "$1" "${2:-gpt-5.4}" 3600 86400
}

write_validation_nonfinite_quota_snapshot() {
  local session_file="$1"
  local model="${2:-gpt-5.5}"

  prepare_validation_session_file "$session_file"
  python3 - "$session_file" "$model" <<'PY'
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
model = sys.argv[2]
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
                "primary": {"used_percent": 10.0, "window_minutes": 300, "resets_at": "not-finite"},
                "secondary": {"used_percent": 10.0, "window_minutes": 10080, "resets_at": "not-finite"},
            },
        },
    },
]
with path.open("w", encoding="utf-8") as handle:
    for row in rows:
        print(json.dumps(row, separators=(",", ":")), file=handle)
PY
}

write_validation_missing_rate_limit_fields_snapshot() {
  local session_file="$1"
  local model="${2:-gpt-5.5}"

  prepare_validation_session_file "$session_file"
  python3 - "$session_file" "$model" <<'PY'
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
model = sys.argv[2]
event_timestamp = datetime.fromtimestamp(int(time.time()), timezone.utc).isoformat().replace("+00:00", "Z")
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
            },
        },
    },
]
with path.open("w", encoding="utf-8") as handle:
    for row in rows:
        print(json.dumps(row, separators=(",", ":")), file=handle)
PY
}

write_validation_malformed_session_jsonl() {
  local session_file="$1"

  prepare_validation_session_file "$session_file"
  printf '%s\n' \
    '[]' \
    '{"type":"event_msg","payload":"not-an-object"}' \
    '{"type":"event_msg","payload":{"type":"turn_aborted","reason":"rate limit / retry"}}' \
    '{"type":"response_item","payload":{"type":"message","role":"assistant"}}' \
    '{"type":"event_msg","payload":{"type":"token_count","rate_limits":"not-an-object"}}' \
    >"$session_file"
}

write_validation_empty_session_jsonl() {
  local session_file="$1"

  prepare_validation_session_file "$session_file"
  : >"$session_file"
}

check_cycle_start_log_contract() {
  local temp_dir code_home_q rc

  log "checking cycle.start log quoting"
  temp_dir="$(mktemp -d /tmp/upkeeper-log-contract.XXXXXX)"
  write_validation_quota_snapshot "$temp_dir/codex home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"
  printf -v code_home_q '%q' "$temp_dir/codex home"

  set +e
  VALIDATION_CYCLE_CODEX_MODE='--sandbox workspace-write' \
    VALIDATION_CYCLE_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    VALIDATION_CYCLE_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    run_upkeeper_validation_cycle "$ROOT_DIR" "cycle-start-default" "$temp_dir/codex home" \
      "$temp_dir/Upkeeper.log" "$temp_dir/transcripts" "$temp_dir/out.txt" "$temp_dir/err.txt"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "cycle.start log contract dry-run exited $rc"
  grep -Fq 'verbose_metadata=0' "$temp_dir/Upkeeper.log" || fail "cycle.start default path did not log verbose_metadata=0"
  grep -Fq 'code_home_hash=' "$temp_dir/Upkeeper.log" || fail "cycle.start default path did not record code_home_hash"
  if grep -Fq ' mode=--sandbox\ workspace-write' "$temp_dir/Upkeeper.log"; then
    fail "cycle.start default path leaked raw CODEX_MODE"
  fi
  if grep -Fq " code_home=$code_home_q" "$temp_dir/Upkeeper.log"; then
    fail "cycle.start default path leaked raw CODEX_HOME"
  fi
  grep -Fq "reason=DRY_RUN" "$temp_dir/Upkeeper.log" || fail "cycle.start log contract dry-run did not finish cleanly"

  : >"$temp_dir/Upkeeper.log"
  set +e
  VALIDATION_CYCLE_CODEX_MODE='--sandbox workspace-write' \
    VALIDATION_CYCLE_VERBOSE_METADATA=1 \
    VALIDATION_CYCLE_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    VALIDATION_CYCLE_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    run_upkeeper_validation_cycle "$ROOT_DIR" "cycle-start-verbose" "$temp_dir/codex home" \
      "$temp_dir/Upkeeper.log" "$temp_dir/transcripts" "$temp_dir/out-verbose.txt" "$temp_dir/err-verbose.txt"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "cycle.start verbose log contract dry-run exited $rc"
  grep -Fq 'verbose_metadata=1' "$temp_dir/Upkeeper.log" || fail "cycle.start verbose path did not log verbose_metadata=1"
  grep -Fq 'mode=--sandbox\ workspace-write' "$temp_dir/Upkeeper.log" || fail "cycle.start verbose path did not quote CODEX_MODE with spaces"
  grep -Fq "code_home=$code_home_q" "$temp_dir/Upkeeper.log" || fail "cycle.start verbose path did not quote CODEX_HOME with spaces"
  rm -r "$temp_dir"
}

check_log_path_symlink_guard() {
  local temp_dir outside_target before_size after_size rc

  log "checking unsafe Upkeeper.log symlink rejection"
  temp_dir="$(mktemp -d /tmp/upkeeper-log-symlink.XXXXXX)"
  outside_target="$temp_dir/outside-target.txt"
  printf 'sentinel\n' >"$outside_target"
  before_size="$(wc -c <"$outside_target")"

  ln -s "$ROOT_DIR/Upkeeper" "$temp_dir/Upkeeper.sh"
  ln -s "$outside_target" "$temp_dir/Upkeeper.log"

  set +e
  (
    cd "$temp_dir"
    UPKEEPER_DRY_RUN=1 \
      CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
      CODEX_TERMINAL_VERBOSITY=quiet \
      ./Upkeeper.sh >out.txt 2>err.txt
  )
  rc=$?
  set -e

  [[ "$rc" -eq 3 ]] || fail "symlinked Upkeeper.log guard exited $rc"
  grep -Fq "reason=symlink_log_file" "$temp_dir/err.txt" || fail "symlinked Upkeeper.log rejection reason missing"
  after_size="$(wc -c <"$outside_target")"
  [[ "$after_size" == "$before_size" ]] || fail "symlinked Upkeeper.log target was modified"
  grep -Fqx "sentinel" "$outside_target" || fail "symlinked Upkeeper.log target content changed"

  rm -r "$temp_dir"
}

check_custom_log_path_rotation_boundary() {
  local temp_dir log_dir log_file archive_path rc

  log "checking custom log path does not grant archive pruning"
  temp_dir="$(mktemp -d /tmp/upkeeper-custom-log-boundary.XXXXXX)"
  log_dir="$temp_dir/logs"
  log_file="$log_dir/Upkeeper.log"
  archive_path="$log_dir/Upkeeper.log.old.zip"
  mkdir -p "$log_dir"
  chmod 700 "$log_dir"
  printf 'sentinel archive\n' >"$archive_path"
  chmod 600 "$archive_path"
  touch -d '10 days ago' "$archive_path"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  set +e
  VALIDATION_CYCLE_LOG_ROTATE_KEEP_HOURS=1 \
    VALIDATION_CYCLE_LOG_ROTATE_AFTER_HOURS=1 \
    VALIDATION_CYCLE_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    VALIDATION_CYCLE_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    run_upkeeper_validation_cycle "$ROOT_DIR" "custom-log-boundary" "$temp_dir/codex-home" \
      "$log_file" "$temp_dir/transcripts" "$temp_dir/out.txt" "$temp_dir/err.txt" \
      --target-file=Upkeeper
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "custom log path boundary dry-run exited $rc"
  [[ -s "$log_file" ]] || fail "custom CODEX_LOG_FILE was not honored as the live log sink"
  grep -Fq "log.rotate_blocked reason=custom_log_path_without_explicit_override" "$log_file" ||
    fail "custom log path did not block archive rotation without explicit override"
  [[ -f "$archive_path" ]] || fail "custom log path allowed pruning of a sibling archive"
  grep -Fqx "sentinel archive" "$archive_path" || fail "custom log path archive sentinel changed"

  rm -r "$temp_dir"
}

check_disk_preflight_log_contract() {
  local temp_dir path_with_token path_q default_output debug_output extracted_free synthetic_free

  log "checking disk preflight log redaction"
  temp_dir="$(mktemp -d /tmp/upkeeper-disk-preflight.XXXXXX)"
  path_with_token="$temp_dir/path with spaces/free_percent=999"
  mkdir -p "$path_with_token"

  if ! default_output="$(
    bash -c '
      set -euo pipefail
      shell_quote() { printf "%q" "$1"; }
      terminal_mode() { printf "basic"; }
      upkeeper_verbose_metadata_enabled() { return 1; }
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

  if ! debug_output="$(
    bash -c '
      set -euo pipefail
      shell_quote() { printf "%q" "$1"; }
      terminal_mode() { printf "debug1"; }
      upkeeper_verbose_metadata_enabled() { return 1; }
      source "$1"
      disk_space_fields "arg0 tmp" "$2"
    ' bash "$ROOT_DIR/lib/upkeeper/disk_preflight.bash" "$path_with_token"
  )"; then
    fail "disk preflight debug log contract check failed"
  fi

  printf -v path_q '%q' "$path_with_token"
  grep -Fq "label=arg0\\ tmp" <<<"$default_output" || fail "disk preflight label was not shell-quoted"
  grep -Fq "path_hash=" <<<"$default_output" || fail "disk preflight default output did not redact the path"
  grep -Fq "mount_hash=" <<<"$default_output" || fail "disk preflight default output did not redact the mount"
  grep -Fq "probe_path_hash=" <<<"$default_output" || fail "disk preflight default output did not redact the probe path"
  grep -Fq "path_redacted=1" <<<"$default_output" || fail "disk preflight default output did not mark path redaction"
  grep -Fq "mount_redacted=1" <<<"$default_output" || fail "disk preflight default output did not mark mount redaction"
  grep -Fq "probe_path_redacted=1" <<<"$default_output" || fail "disk preflight default output did not mark probe-path redaction"
  ! grep -Fq "path=$path_q" <<<"$default_output" || fail "disk preflight default output leaked the raw path"
  grep -Fq "path=$path_q" <<<"$debug_output" || fail "disk preflight debug output did not include the raw path"
  ! grep -Fq "path_hash=" <<<"$debug_output" || fail "disk preflight debug output still used redacted path fields"
  extracted_free="$(sed -n 's/^extracted_free=//p' <<<"$default_output")"
  [[ -n "$extracted_free" ]] || fail "disk preflight free_percent extraction returned empty"
  [[ "$extracted_free" != "999" ]] || fail "disk preflight free_percent extraction used the path token"
  [[ "$extracted_free" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || fail "disk preflight free_percent was not numeric: $extracted_free"
  synthetic_free="$(sed -n 's/^synthetic_free=//p' <<<"$default_output")"
  [[ "$synthetic_free" == "88" ]] || fail "disk preflight free_percent parser did not use the intended field"

  rm -r "$temp_dir"
}

check_disk_preflight_prompt_note_contract() {
  local temp_dir existing_path missing_path output note_block

  log "checking disk preflight prompt-note redaction"
  temp_dir="$(mktemp -d /tmp/upkeeper-disk-preflight-note.XXXXXX)"
  existing_path="$temp_dir/existing path/free_percent=999"
  missing_path="$temp_dir/missing path/free_percent=998/nope"
  mkdir -p "$existing_path"

  if ! output="$(
    bash -c '
      set -euo pipefail
      shell_quote() { printf "%q" "$1"; }
      log_line() { printf "%s\n" "$2"; }
      append_startup_anomaly_reason() { :; }
      terminal_mode() { printf "basic"; }
      upkeeper_verbose_metadata_enabled() { return 1; }
      source "$1"
      EXISTING_PATH="$2"
      MISSING_PATH="$3"
      CODEX_DISK_MIN_FREE_PERCENT=101
      DISK_SPACE_PROMPT_NOTE=""
      STARTUP_ANOMALY_GATE=0
      disk_preflight_path_specs() {
        printf "existing_label\t%s\n" "$EXISTING_PATH"
        printf "missing_label\t%s\n" "$MISSING_PATH"
      }
      check_disk_space_preflight
      printf "NOTE_BEGIN\n%s\nNOTE_END\n" "$DISK_SPACE_PROMPT_NOTE"
    ' bash "$ROOT_DIR/lib/upkeeper/disk_preflight.bash" "$existing_path" "$missing_path"
  )"; then
    fail "disk preflight prompt-note contract check failed"
  fi

  note_block="$(awk '/^NOTE_BEGIN$/,/^NOTE_END$/' <<<"$output")"
  grep -Fq -- "- disk.preflight low_space label=existing_label free_percent=" <<<"$note_block" || fail "disk preflight prompt note did not retain the existing_label low-space note"
  grep -Fq -- "- disk.preflight low_space label=missing_label free_percent=" <<<"$note_block" || fail "disk preflight prompt note did not retain the missing_label low-space note"
  ! grep -Fq "$temp_dir" <<<"$note_block" || fail "disk preflight prompt note leaked a raw path"
  ! grep -Fq "mount=" <<<"$note_block" || fail "disk preflight prompt note leaked mount metadata"
  ! grep -Fq "path=" <<<"$note_block" || fail "disk preflight prompt note leaked path metadata"
  ! grep -Fq "probe_path=" <<<"$note_block" || fail "disk preflight prompt note leaked probe-path metadata"
  ! grep -Fq "size_kb=" <<<"$note_block" || fail "disk preflight prompt note leaked size metadata"
  ! grep -Fq "used_kb=" <<<"$note_block" || fail "disk preflight prompt note leaked usage metadata"
  ! grep -Fq "avail_kb=" <<<"$note_block" || fail "disk preflight prompt note leaked free-space metadata"
  ! grep -Fq "used_percent=" <<<"$note_block" || fail "disk preflight prompt note leaked used-percent metadata"

  rm -r "$temp_dir"
}

check_arg0_tmp_cleanup_contract() {
  local temp_dir arg0_root quarantine_root output marker_name

  log "checking Codex arg0 temp cleanup contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-arg0-cleanup.XXXXXX)"
  arg0_root="$temp_dir/arg0"
  quarantine_root="$temp_dir/quarantine"
  marker_name=".upkeeper-arg0.owner"

  mkdir -p "$arg0_root/codex-arg0-owned" "$arg0_root/codex-arg0-unmarked" "$arg0_root/unmanaged-cache"
  printf 'upkeeper-arg0-owner-v1\n' >"$arg0_root/codex-arg0-owned/$marker_name"
  chmod 600 "$arg0_root/codex-arg0-owned/$marker_name"
  printf 'shim\n' >"$arg0_root/codex-arg0-owned/shim"
  printf 'unknown\n' >"$arg0_root/codex-arg0-unmarked/unknown"
  printf 'keep\n' >"$arg0_root/unmanaged-cache/keep"
  touch -t 202001010000 "$arg0_root/codex-arg0-owned" "$arg0_root/codex-arg0-unmarked" "$arg0_root/unmanaged-cache"

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

  [[ "$output" == ok\ removed=1\ quarantined=1\ quarantine_paths=*missing_marker:* ]] || fail "arg0 cleanup returned unexpected output: $output"
  [[ ! -e "$arg0_root/codex-arg0-owned" ]] || fail "owned stale codex-arg0 shim directory was not removed"
  [[ ! -e "$arg0_root/codex-arg0-unmarked" ]] || fail "unmarked stale codex-arg0 directory remained in the live arg0 root"
  find "$quarantine_root" -mindepth 1 -maxdepth 1 -type d -name 'codex-arg0-unmarked-*' | grep -q . ||
    fail "unmarked stale codex-arg0 directory was not quarantined"
  [[ -f "$arg0_root/unmanaged-cache/keep" ]] || fail "non-codex stale directory was modified"

  rm -r "$temp_dir"
}

check_automation_obligation_framework() {
  local temp_dir run_record obligation_count obligation_file obligation_id resolved_file selected_json prompt_file machine_file

  log "checking automation obligation framework"
  temp_dir="$(mktemp -d /tmp/upkeeper-automation-obligations.XXXXXX)"
  printf 'transcript\n' >"$temp_dir/transcript.log"

  (
    cd "$ROOT_DIR"
    ROOT_DIR="$ROOT_DIR"
    SCRIPT_NAME="Upkeeper"
    CYCLE_ID="validation-automation"
    CYCLE_RUN_HASH="validationhashautomation"
    LOG_FILE="$temp_dir/Upkeeper.log"
    CODEX_TERMINAL_VERBOSITY="silent"
    UPKEEPER_AUTOMATION_LEDGER_DIR="$temp_dir/ledger"
    UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations"
    UPKEEPER_AUTOMATION_LAUNCHER="ChimneySweep"
    UPKEEPER_AUTOMATION_VARIANT="issue-repair"
    UPKEEPER_AUTOMATION_POLICY="own-bug-queue"
    UPKEEPER_AUTOMATION_WORKFLOW="comment-review-apply"
    CODEX_ISSUE_WORKFLOW_STAGE="review"
    CODEX_ISSUE_FIX_NUMBER="125"
    CODEX_ISSUE_FIX_TITLE="High security validation fixture"
    CODEX_TARGET_FILE="Upkeeper"
    RUN_SELECTED_REVIEW_PATH="lib/upkeeper/session_store_preflight.bash"
    RUN_TRANSCRIPT_FILE="$temp_dir/transcript.log"
    RUN_AUTOMATION_RECORD_FILE=""
    source lib/upkeeper/runtime_foundation.bash
    source lib/upkeeper/automation_obligations.bash
    automation_record_cycle_start
    automation_record_cycle_finish 2 BLOCKED WARN BLOCKED 0 1 "$RUN_SELECTED_REVIEW_PATH"
  )

  run_record="$temp_dir/ledger/runs/validation-automation.json"
  [[ -f "$run_record" ]] || fail "automation run record was not written"
  [[ "$(jq -r '.status' "$run_record")" == "finished" ]] || fail "automation run record was not finalized"
  [[ "$(jq -r '.launcher' "$run_record")" == "ChimneySweep" ]] || fail "automation run record lost launcher identity"
  [[ "$(jq -r '.variant' "$run_record")" == "issue-repair" ]] || fail "automation run record lost variant"
  [[ "$(jq -r '.policy' "$run_record")" == "own-bug-queue" ]] || fail "automation run record lost policy"
  [[ "$(jq -r '.workflow' "$run_record")" == "comment-review-apply" ]] || fail "automation run record lost workflow"
  [[ "$(jq -r '.stage' "$run_record")" == "review" ]] || fail "automation run record lost stage"
  [[ "$(jq -r '.selected_target' "$run_record")" == "lib/upkeeper/session_store_preflight.bash" ]] || fail "automation run record lost selected target"
  [[ "$(jq -r '.exit_code' "$run_record")" == "2" ]] || fail "automation run record lost exit code"

  obligation_count="$(find "$temp_dir/obligations/open" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$obligation_count" == "1" ]] || fail "automation obligation count was $obligation_count, expected 1"
  obligation_file="$(find "$temp_dir/obligations/open" -maxdepth 1 -type f -name '*.json' | head -1)"
  obligation_id="$(jq -r '.id' "$obligation_file")"
  [[ "$(jq -r '.kind' "$obligation_file")" == "blocked" ]] || fail "automation obligation did not record blocked kind"
  [[ "$(jq -r '.launcher' "$obligation_file")" == "ChimneySweep" ]] || fail "automation obligation lost launcher identity"
  [[ "$(jq -r '.target_file' "$obligation_file")" == "lib/upkeeper/session_store_preflight.bash" ]] || fail "automation obligation lost target file"
  grep -Fq "automation.obligation.open" "$temp_dir/Upkeeper.log" || fail "automation obligation open event was not logged"

  selected_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" \
      bash -c 'source "$1"; automation_select_open_obligation_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.status' <<<"$selected_json")" == "ok" ]] || fail "automation obligation selector did not find open obligation"
  [[ "$(jq -r '.id' <<<"$selected_json")" == "$obligation_id" ]] || fail "automation obligation selector returned the wrong obligation"
  [[ "$(jq -r '.repair_target_file' <<<"$selected_json")" == "lib/upkeeper/session_store_preflight.bash" ]] || fail "automation obligation selector changed an already-eligible repair target"
  prompt_file="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" \
      bash -c 'source "$1"; automation_prepare_obligation_prompt_file "$2"' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash" "$selected_json"
  )"
  [[ -f "$prompt_file" ]] || fail "automation obligation prompt file was not written"
  grep -Fq "Upkeeper automation obligation repair task." "$prompt_file" || fail "automation obligation prompt file missing task header"

  (
    cd "$ROOT_DIR"
    ROOT_DIR="$ROOT_DIR"
    SCRIPT_NAME="Upkeeper"
    CYCLE_ID="validation-automation-resolve"
    CYCLE_RUN_HASH="validationhashresolve"
    LOG_FILE="$temp_dir/resolve.log"
    CODEX_TERMINAL_VERBOSITY="silent"
    UPKEEPER_AUTOMATION_LEDGER_DIR="$temp_dir/ledger"
    UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations"
    UPKEEPER_AUTOMATION_LAUNCHER="ChimneySweep"
    UPKEEPER_AUTOMATION_VARIANT="issue-repair"
    UPKEEPER_AUTOMATION_POLICY="own-bug-queue"
    UPKEEPER_AUTOMATION_WORKFLOW="obligation-repair"
    UPKEEPER_AUTOMATION_OBLIGATION_ID="$obligation_id"
    UPKEEPER_AUTOMATION_OBLIGATION_PATH="$obligation_file"
    RUN_SELECTED_REVIEW_PATH="lib/upkeeper/session_store_preflight.bash"
    RUN_TRANSCRIPT_FILE="$temp_dir/transcript.log"
    RUN_AUTOMATION_RECORD_FILE=""
    source lib/upkeeper/runtime_foundation.bash
    source lib/upkeeper/automation_obligations.bash
    automation_record_cycle_start
    automation_record_cycle_finish 0 WORK_DONE INFO WORK_DONE 0 1 "$RUN_SELECTED_REVIEW_PATH"
  )

  [[ ! -e "$obligation_file" ]] || fail "automation obligation was not removed from open after clean selected cycle"
  resolved_file="$temp_dir/obligations/resolved/$obligation_id.json"
  [[ -f "$resolved_file" ]] || fail "automation obligation was not moved to resolved after clean selected cycle"
  [[ "$(jq -r '.status' "$resolved_file")" == "resolved" ]] || fail "resolved automation obligation status was not resolved"
  [[ "$(jq -r '.resolved_by_cycle_id' "$resolved_file")" == "validation-automation-resolve" ]] || fail "resolved automation obligation lost resolver cycle"

  mkdir -p "$temp_dir/obligations/open"
  cat >"$temp_dir/obligations/open/runtime-target.json" <<'JSON'
{"schema":1,"record_type":"automation_obligation","status":"open","id":"runtime-target","created_at":"2026-05-10T00:00:00-0700","kind":"target_file_not_eligible","severity":"medium","summary":"Runtime target fixture","target_file":"runtime/upkeeper-explicit-target-fixture.txt","launcher":"ChimneySweep","workflow":"obligation-repair"}
JSON
  selected_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" \
      bash -c 'source "$1"; automation_select_open_obligation_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.repair_target_file' <<<"$selected_json")" == "ChimneySweep" ]] || fail "automation obligation selector did not remap a poisoned runtime target to ChimneySweep"

  machine_file="$temp_dir/obligations/open/precontact-machine.json"
  cat >"$machine_file" <<'JSON'
{"schema":1,"record_type":"automation_obligation","status":"open","id":"precontact-machine","created_at":"2026-05-10T00:00:00-0700","kind":"precontact_backup_prereq_missing","severity":"high","summary":"Machine-local backup bootstrap is required before normal automation can continue","target_scope":"machine","target_file":"","repair_target_file":"tools/upkeeper_precontact_bootstrap.sh","reason":"PRECONTACT_BACKUP_PREREQ_MISSING","required_resolution":["bootstrap encrypted backup locally"]}
JSON
  selected_json="$(
    ROOT_DIR="$ROOT_DIR" UPKEEPER_OBLIGATION_DIR="$temp_dir/obligations" \
      bash -c 'source "$1"; automation_select_open_obligation_json' bash "$ROOT_DIR/lib/upkeeper/automation_obligations.bash"
  )"
  [[ "$(jq -r '.status' <<<"$selected_json")" == "operator_action_required" ]] || fail "machine-health obligation selector did not stop normal automation"
  [[ "$(jq -r '.repair_target_file' <<<"$selected_json")" == "tools/upkeeper_precontact_bootstrap.sh" ]] || fail "machine-health obligation selector lost bootstrap repair target"
  [[ "$(jq -r '.target_scope' <<<"$selected_json")" == "machine" ]] || fail "machine-health obligation selector lost target_scope"

  rm -r "$temp_dir"
}

check_session_store_preflight_contract() {
  local temp_dir session_dir sentinel output rc

  log "checking Codex session store preflight contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-session-store-preflight.XXXXXX)"
  session_dir="$temp_dir/codex-home/sessions"

  if ! output="$(
    CODEX_HOME_DIR="$temp_dir/codex-home" \
      bash -c 'umask 077; source "$1"; codex_session_store_write_check' bash "$ROOT_DIR/lib/upkeeper/session_store_preflight.bash"
  )"; then
    fail "session store preflight failed for a normal private session root"
  fi

  [[ "$output" == "ok" ]] || fail "session store preflight returned unexpected output: $output"
  if compgen -G "$session_dir/.upkeeper-write-test.*" >/dev/null; then
    fail "session store preflight left a probe directory behind"
  fi

  sentinel="$temp_dir/sentinel-target"
  printf 'sentinel data\n' >"$sentinel"
  if ! output="$(
    CODEX_HOME_DIR="$temp_dir/codex-home" \
      bash -c '
        source "$1"
        mkdir -p -- "$CODEX_HOME_DIR/sessions"
        legacy_path="$CODEX_HOME_DIR/sessions/.upkeeper-write-test.$$"
        ln -s -- "$2" "$legacy_path"
        result="$(codex_session_store_write_check)" || exit 41
        [[ -L "$legacy_path" ]] || exit 42
        printf "%s" "$result"
      ' bash "$ROOT_DIR/lib/upkeeper/session_store_preflight.bash" "$sentinel"
  )"; then
    fail "session store preflight followed or removed a predictable symlink marker"
  fi

  [[ "$output" == "ok" ]] || fail "session store preflight returned unexpected symlink-probe output: $output"
  [[ "$(cat "$sentinel")" == "sentinel data" ]] || fail "session store preflight truncated the predictable symlink target"

  rm -r -- "$temp_dir/codex-home"
  mkdir -p -- "$temp_dir/codex-home" "$temp_dir/real-sessions"
  ln -s -- "$temp_dir/real-sessions" "$temp_dir/codex-home/sessions"
  set +e
  output="$(
    CODEX_HOME_DIR="$temp_dir/codex-home" \
      bash -c 'source "$1"; codex_session_store_write_check' bash "$ROOT_DIR/lib/upkeeper/session_store_preflight.bash"
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 1 ]] || fail "session store symlink check exited $rc, expected 1"
  [[ "$output" == unsafe_symlink:* ]] || fail "session store symlink check returned unexpected output: $output"
  if compgen -G "$temp_dir/real-sessions/.upkeeper-write-test.*" >/dev/null; then
    fail "session store symlink check probed through the symlinked sessions directory"
  fi

  rm -r -- "$temp_dir/codex-home" "$temp_dir/real-sessions"
  mkdir -p -- "$temp_dir/codex-home/sessions"
  chmod 0777 "$temp_dir/codex-home/sessions"
  set +e
  output="$(
    CODEX_HOME_DIR="$temp_dir/codex-home" \
      bash -c 'source "$1"; codex_session_store_write_check' bash "$ROOT_DIR/lib/upkeeper/session_store_preflight.bash"
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 1 ]] || fail "session store owned weak-mode rejection exited $rc, expected 1"
  [[ "$output" == unsafe_permissions:* ]] || fail "session store owned weak-mode rejection returned unexpected output: $output"
  [[ "$(stat -c '%a' "$temp_dir/codex-home/sessions")" == "777" ]] || fail "session store owned weak-mode rejection changed directory permissions"
  if compgen -G "$temp_dir/codex-home/sessions/.upkeeper-write-test.*" >/dev/null; then
    fail "session store owned weak-mode rejection left a probe directory behind"
  fi

  rm -r -- "$temp_dir"
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

  VALIDATION_CYCLE_WRAPPER_HEALTH_STATE_DIR="$health_dir" \
    VALIDATION_CYCLE_WRAPPER_HEALTH_ARCHIVE_DIR="$archive_dir" \
    VALIDATION_CYCLE_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    run_upkeeper_validation_cycle "$ROOT_DIR" "wrapper-health-initial" "$temp_dir/codex home" \
      "$temp_dir/Upkeeper.log" "$temp_dir/transcripts" "$temp_dir/first.out" "$temp_dir/first.err" \
      --target-file=Upkeeper

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
  VALIDATION_CYCLE_WRAPPER_HEALTH_STATE_DIR="$health_dir" \
    VALIDATION_CYCLE_WRAPPER_HEALTH_ARCHIVE_DIR="$archive_dir" \
    VALIDATION_CYCLE_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    run_upkeeper_validation_cycle "$ROOT_DIR" "wrapper-health-archive" "$temp_dir/codex home" \
      "$temp_dir/Upkeeper.log" "$temp_dir/transcripts" "$temp_dir/second.out" "$temp_dir/second.err" \
      --target-file=Upkeeper
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
    CODEX_ACTIVE_LOCK_DIR="$(validation_active_lock_dir "$ROOT_DIR" "operator-guide")"
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
  local temp_dir active_lock_dir rc

  log "checking active lock incomplete-acquisition guard"
  temp_dir="$(mktemp -d /tmp/upkeeper-active-lock.XXXXXX)"
  active_lock_dir="$(validation_active_lock_dir "$ROOT_DIR" "active-lock-incomplete")"
  mkdir "$active_lock_dir"

  set +e
  VALIDATION_CYCLE_ACTIVE_LOCK_DIR="$active_lock_dir" \
    VALIDATION_CYCLE_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    VALIDATION_CYCLE_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    run_upkeeper_validation_cycle "$ROOT_DIR" "active-lock-incomplete" "$temp_dir/codex-home" \
      "$temp_dir/Upkeeper.log" "$temp_dir/transcripts" "$temp_dir/out.txt" "$temp_dir/err.txt" \
      --target-file=Upkeeper
  rc=$?
  set -e

  [[ "$rc" -eq 7 ]] || fail "incomplete active lock exited $rc, expected 7"
  grep -Fq "active_lock.incomplete" "$temp_dir/Upkeeper.log" || fail "incomplete active lock was not logged"
  grep -Fq "reason=UPKEEPER_ACTIVE_LOCK_HELD" "$temp_dir/Upkeeper.log" || fail "incomplete active lock did not use held exit reason"
  [[ -d "$active_lock_dir" ]] || fail "incomplete active lock guard removed a fresh lock directory"
  rm -rf "$active_lock_dir"
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
    CODEX_ACTIVE_LOCK_DIR="$(validation_active_lock_dir "$ROOT_DIR" "quota-fallback")" \
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

check_fallback_postmortem_guardrail_contract() {
  log "checking fallback/postmortem guardrail contract"

  grep -Fq "## Fallback And Postmortem Guardrails" docs/security.md ||
    fail "security doc missing fallback/postmortem guardrail section"
  grep -Fq "Fallback is allowed only when all of these are true" docs/security.md ||
    fail "security doc missing fallback allowed criteria"
  grep -Fq "Fallback is forbidden or skipped when any of these are true" docs/security.md ||
    fail "security doc missing fallback forbidden criteria"
  grep -Fq "A fallback child may mutate files only within the same mode and task boundary" docs/security.md ||
    fail "security doc missing fallback mutation boundary"
  grep -Fq "Fallback is not a dirty-worktree bypass" docs/security.md ||
    fail "security doc missing dirty-worktree fallback boundary"
  grep -Fq "Disable all recovery model work with" docs/security.md ||
    fail "security doc missing full recovery disablement guidance"
  grep -Fq "CODEX_FALLBACK_SCREEN_MAX_CHILDREN" docs/security.md ||
    fail "security doc missing screen child limit"
  grep -Fq "CODEX_FALLBACK_SCREEN_MAX_SECONDS" docs/security.md ||
    fail "security doc missing screen time limit"
  grep -Fq "Fallback evidence is separated from primary evidence" docs/security.md ||
    fail "security doc missing evidence separation"
  grep -Fq "Fallback success means" docs/security.md ||
    fail "security doc missing fallback success criteria"

  grep -Fq "fallback/postmortem guardrail contract" docs/scripts/upkeeper.md ||
    fail "operator guide missing fallback guardrail contract"
  grep -Fq "CODEX_POSTMORTEM_HARDENING_OPT_IN" docs/scripts/upkeeper.md ||
    fail "operator guide missing postmortem hardening opt-in"
  grep -Fq "keeps hardening report-only unless CODEX_POSTMORTEM_HARDENING_OPT_IN=1" docs/scripts/upkeeper.md ||
    fail "operator guide does not state hardening is opt-in"
  grep -Fq "CODEX_FALLBACK_ENABLED=0 CODEX_FALLBACK_SCREEN_ENABLED=0 CODEX_POSTMORTEM_ENABLED=0" docs/scripts/upkeeper.md ||
    fail "operator guide missing full recovery disablement command"
  grep -Fq "CODEX_POSTMORTEM_HARDENING_OPT_IN" lib/upkeeper/help_selection.bash ||
    fail "help text missing postmortem hardening opt-in"

  grep -Fq "CODEX_FALLBACK_ENABLED=0," Upkeeper.conf ||
    fail "default config missing fallback disablement comment"
  grep -Fq "CODEX_FALLBACK_SCREEN_ENABLED=0" configurations/default.conf ||
    fail "default profile missing screen fallback disablement knob"
  grep -Fq "Fallback and postmortem guardrails are part of the stable operator surface" docs/compatibility.md ||
    fail "compatibility doc missing stable fallback guardrail surface"

  grep -Fq "fallback_would_rediscover_dirty_block" lib/upkeeper/fallback_availability.bash ||
    fail "fallback availability missing dirty rediscovery guard"
  grep -Fq "CODEX_FALLBACK_ENABLED=0" lib/upkeeper/fallback_orchestration.bash ||
    fail "direct fallback child does not disable recursive fallback"
  grep -Fq "CODEX_POSTMORTEM_ENABLED=0" lib/upkeeper/fallback_orchestration.bash ||
    fail "direct fallback child does not disable recursive postmortem"
  grep -Fq "CODEX_FALLBACK_ENABLED=0" lib/upkeeper/fallback_screen.bash ||
    fail "screen fallback child does not disable recursive fallback"
  grep -Fq "CODEX_POSTMORTEM_ENABLED=0" lib/upkeeper/fallback_screen.bash ||
    fail "screen fallback child does not disable recursive postmortem"
}

check_review_module_flags() {
  local temp_dir output rc module_id module_aliases
  local -a module_flags alias_flags

  log "checking review module flags"
  temp_dir="$(mktemp -d /tmp/upkeeper-review-modules.XXXXXX)"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  VALIDATION_CYCLE_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    VALIDATION_CYCLE_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    run_upkeeper_validation_cycle "$ROOT_DIR" "review-modules" "$temp_dir/codex-home" \
      "$temp_dir/Upkeeper.log" "$temp_dir/transcripts" "$temp_dir/out.txt" "$temp_dir/err.txt" \
      --target-file=Upkeeper --review-modules="$(review_module_list_csv)"

  grep -Fq "review_modules_hash=" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not record selected modules metadata"
  while IFS='|' read -r module_id _; do
    grep -Fq "review.module_prompt enabled module=$module_id" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not append $module_id"
  done < <(review_module_specs)
  grep -Fq "cycle.exit exit_code=0 reason=DRY_RUN" "$temp_dir/Upkeeper.log" || fail "review module dry-run did not finish cleanly"

  module_flags=()
  while IFS='|' read -r module_id _; do
    module_flags+=("--$module_id")
  done < <(review_module_specs)
  output="$(./Upkeeper "${module_flags[@]}" --version)"
  [[ "$output" == "Upkeeper $(sed -n 's/^UPKEEPER_VERSION="\([^"]*\)"/\1/p' Upkeeper)" ]] || fail "review module shorthand flags broke --version"

  while IFS='|' read -r module_id module_aliases; do
    IFS=',' read -r -a alias_flags <<< "$module_aliases"
    for i in "${!alias_flags[@]}"; do
      alias_flags[$i]="--review-module=${alias_flags[$i]}"
    done
    output="$(./Upkeeper "${alias_flags[@]}" --version)"
    [[ "$output" == "Upkeeper $(sed -n 's/^UPKEEPER_VERSION="\([^"]*\)"/\1/p' Upkeeper)" ]] || fail "$module_id alias shorthand broke --version"
  done < <(review_module_alias_specs)

  set +e
  output="$(
    CODEX_LOG_FILE="$temp_dir/invalid-review-module.log" \
      ./Upkeeper --review-module=nope --version 2>&1
  )"
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || fail "invalid review module exited $rc, expected 3"
  grep -Fq "unknown review module: nope" <<<"$output" || fail "invalid review module error was not clear"

  rm -r "$temp_dir"
}

check_config_file_support() {
  local temp_dir profile output rc secure_parent

  log "checking config file support"
  secure_parent="${XDG_STATE_HOME:-$HOME/.local/state}/upkeeper-validation"
  mkdir -p "$secure_parent"
  chmod 700 "$secure_parent" 2>/dev/null || true
  temp_dir="$(mktemp -d "$secure_parent/config-file.XXXXXX")"
  chmod 700 "$temp_dir" 2>/dev/null || true
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
  chmod 600 "$profile" 2>/dev/null || true

  VALIDATION_CYCLE_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    VALIDATION_CYCLE_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    run_upkeeper_validation_cycle "$ROOT_DIR" "config-file" "$temp_dir/codex-home" \
      "$temp_dir/Upkeeper.log" "$temp_dir/transcripts" "$temp_dir/config.out" "$temp_dir/config.err" \
      --config-file="$profile"

  grep -Fq "config_loaded=1" "$temp_dir/Upkeeper.log" || fail "config dry-run did not record loaded config"
  grep -Fq "config_file_hash=" "$temp_dir/Upkeeper.log" || fail "config dry-run did not record config metadata"
  grep -Fq "model=gpt-5.5" "$temp_dir/Upkeeper.log" || fail "config dry-run did not apply model"
  grep -Fq "review.preselect path_hmac=path-hmac-sha256:" "$temp_dir/Upkeeper.log" || fail "config dry-run did not apply target file"
  grep -Fq "path_redacted=1" "$temp_dir/Upkeeper.log" || fail "config dry-run did not redact target path"
  grep -Fq "prompt_pass=all" "$temp_dir/Upkeeper.log" || fail "config dry-run did not apply prompt pass"
  grep -Fq "review.module_prompt enabled module=p28" "$temp_dir/Upkeeper.log" || fail "config dry-run did not append P28"

  : >"$temp_dir/Upkeeper.log"
  VALIDATION_CYCLE_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    VALIDATION_CYCLE_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    run_upkeeper_validation_cycle "$ROOT_DIR" "config-cli-override" "$temp_dir/codex-home" \
      "$temp_dir/Upkeeper.log" "$temp_dir/transcripts" "$temp_dir/override.out" "$temp_dir/override.err" \
      --config-file="$profile" --target-file=lib/upkeeper/codex_io.bash --p26

  grep -Fq "review.preselect path_hmac=path-hmac-sha256:" "$temp_dir/Upkeeper.log" || fail "CLI target did not override config target"
  grep -Fq "selection_mode=explicit_target" "$temp_dir/Upkeeper.log" || fail "CLI target did not use explicit target selection"
  grep -Fq "review.module_prompt enabled module=p26" "$temp_dir/Upkeeper.log" || fail "CLI review module did not override config modules"
  if grep -Fq "review.module_prompt enabled module=p28" "$temp_dir/Upkeeper.log"; then
    fail "config review module leaked after CLI override"
  fi

  : >"$temp_dir/Upkeeper.log"
  UPKEEPER_CONFIG_FILE="$profile" \
    CODEX_HOME="$temp_dir/codex-home" \
    CODEX_LOG_FILE="$temp_dir/Upkeeper.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$(validation_active_lock_dir "$ROOT_DIR" "config-env")" \
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
  local temp_dir manifest_path output rc lattice_db_path unsafe_manifest_path untracked_candidate untracked_name

  log "checking file manifest selection"
  temp_dir="$(mktemp -d /tmp/upkeeper-file-manifest.XXXXXX)"
  manifest_path="runtime/upkeeper-file-manifest-validation-${temp_dir##*/}.json"
  unsafe_manifest_path="$temp_dir/unsafe-manifest.json"
  lattice_db_path="runtime/upkeeper-lattice/file-manifest-${temp_dir##*/}.sqlite3"
  untracked_name="upkeeper-untracked-select-${temp_dir##*/}.bash"
  untracked_candidate="lib/upkeeper/$untracked_name"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"
  mkdir -p runtime/upkeeper-lattice
  printf '#!/usr/bin/env bash\nprintf "untracked selection fixture\\n"\n' >"$untracked_candidate"
  touch -d '2001-01-01T00:00:00Z' "$untracked_candidate"

  run_manifest_dry_run() {
    local log_file="$1"
    shift
    CODEX_HOME="$temp_dir/codex-home" \
      CODEX_LOG_FILE="$log_file" \
      CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
      CODEX_ACTIVE_LOCK_DIR="$(validation_active_lock_dir "$ROOT_DIR" "file-manifest")" \
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
      CODEX_TOOL_FAILURE_QUEUE_DIR="$temp_dir/failures" \
      UPKEEPER_PRECONTACT_BACKUP_ENABLED=0 \
      UPKEEPER_SELECTION_RANDOM_SEED=validation-file-manifest-selection \
      UPKEEPER_LATTICE_DB="$lattice_db_path" \
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
  jq -e '.schema_version == 2 and ((.root_hash // "") | length == 64) and (has("root") | not) and (.files | length) > 0 and ((.files[0].rel_path // "") | length > 0) and ([.files[] | select(has("abs_path"))] | length == 0)' "$manifest_path" >/dev/null || fail "manifest JSON contract is invalid"

  mkdir -p "$temp_dir/breadcrumbs/open"
  cat >"$temp_dir/breadcrumbs/open/high.json" <<'JSON'
{"schema":1,"record_type":"upkeeper_breadcrumb","status":"open","id":"high-fixture","kind":"page_error","severity":"high","reason":"fixture severe breadcrumb"}
JSON
  UPKEEPER_BREADCRUMB_STATE_DIR="$temp_dir/breadcrumbs" run_manifest_dry_run "$temp_dir/breadcrumb-gate.log" \
    --target-root=docs \
    --selection-source=enumerate
  grep -Fq "breadcrumb.gate status=blocking action=force_target target_file=Upkeeper" "$temp_dir/breadcrumb-gate.log" ||
    fail "high-severity breadcrumb did not force the gate target"
  grep -Fq "review.preselect path_hmac=" "$temp_dir/breadcrumb-gate.log" ||
    fail "high-severity breadcrumb gate did not produce a redacted preselect log"
  grep -Fq "selection_mode=explicit_target" "$temp_dir/breadcrumb-gate.log" ||
    fail "high-severity breadcrumb gate did not use explicit target selection"
  grep -Fq "basis=operator\\ --target-file=Upkeeper" "$temp_dir/breadcrumb-gate.log" ||
    fail "high-severity breadcrumb gate did not redirect normal rotation to Upkeeper"

  (
    # Keep the unsafe-path contract covered without adding another expensive
    # dry-run invocation to this already broad full-validation fixture.
    source "$ROOT_DIR/lib/upkeeper/codex_io.bash"
    source "$ROOT_DIR/lib/upkeeper/file_manifest.bash"
    manifest_path_is_safe "$manifest_path" 0 || exit 1
    ! manifest_path_is_safe "$unsafe_manifest_path" 0 || exit 2
    manifest_path_is_safe "$unsafe_manifest_path" 1 || exit 3
  ) || fail "manifest path safety helper did not enforce runtime-local default and explicit unsafe override"

  python3 - "$manifest_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
with path.open("r", encoding="utf-8") as handle:
    payload = json.load(handle)

files = payload.get("files")
if not isinstance(files, list):
    raise SystemExit(1)
files.extend(
    [
        {
            "rel_path": "/tmp/poisoned-absolute.sh",
            "mtime_ns": 1,
            "size": 1,
            "mode": "0644",
            "mtime": 1,
        },
        {
            "rel_path": "../poisoned-parent.sh",
            "mtime_ns": 2,
            "size": 2,
            "mode": "0644",
            "mtime": 2,
        },
    ]
)
with path.open("w", encoding="utf-8") as handle:
    json.dump(payload, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
PY

  run_manifest_dry_run "$temp_dir/newest.log" \
    --target-root=lib/upkeeper \
    --target-depth=1 \
    --selection-source=manifest \
    --selection-order=newest

  if grep -Fq "file_manifest.ready action=reused reason=current" "$temp_dir/newest.log"; then
    log "manifest reuse check passed on healthy manifest cache state"
  elif grep -Fq "file_manifest.ready action=rebuilt reason=missing_or_invalid" "$temp_dir/newest.log"; then
    jq -e 'all(.files[]?; if (.rel_path | type) != "string" then false else ((.rel_path | test("^/")) | not) and ((.rel_path | test("(^|/)\\.{2}(/|$)")) | not) end)' "$manifest_path" >/dev/null || fail "poisoned manifest entries were not rebuilt out"
  else
    local manifest_fingerprint newest_fingerprint
    manifest_fingerprint="$(sed -n 's/.*file_manifest.ready .* fingerprint=\([^ ]*\).*/\1/p' "$temp_dir/manifest.log" | tail -1)"
    newest_fingerprint="$(sed -n 's/.*file_manifest.ready .* fingerprint=\([^ ]*\).*/\1/p' "$temp_dir/newest.log" | tail -1)"
    if grep -Fq "file_manifest.ready action=rebuilt reason=fingerprint_changed" "$temp_dir/newest.log" &&
      [[ -n "$manifest_fingerprint" && -n "$newest_fingerprint" && "$manifest_fingerprint" != "$newest_fingerprint" ]]; then
      log "manifest reuse check observed fingerprint drift during validation; continuing"
    else
      fail "current manifest was not reused"
    fi
  fi
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

  run_manifest_dry_run "$temp_dir/untracked-default.log" \
    --selection-source=enumerate \
    --selection-order=oldest \
    --include-glob="$untracked_name"
  grep -Fq "content_state=untracked" "$temp_dir/untracked-default.log" || fail "default selection did not include a non-ignored untracked candidate"
  grep -Fq "select_untracked=1" "$temp_dir/untracked-default.log" || fail "default selection did not log select_untracked=1"
  grep -Eq 'review\.preselect .* select_untracked=1( |$)' "$temp_dir/untracked-default.log" || fail "default selection did not carry select_untracked=1 into preselect evidence"

  run_manifest_dry_run "$temp_dir/untracked-tracked-only.log" \
    --selection-source=enumerate \
    --selection-order=oldest \
    --tracked-only \
    --include-glob="$untracked_name"
  grep -Fq "select_untracked=0" "$temp_dir/untracked-tracked-only.log" || fail "tracked-only selection was not logged at cycle start"
  grep -Fq "review.preselect.none reason=no_eligible_script_tool" "$temp_dir/untracked-tracked-only.log" || fail "tracked-only selection did not exclude untracked candidates"
  if grep -Fq "content_state=untracked" "$temp_dir/untracked-tracked-only.log"; then
    fail "tracked-only normal selection still selected an untracked candidate"
  fi

  run_manifest_dry_run "$temp_dir/untracked-explicit.log" \
    --selection-source=enumerate \
    --tracked-only \
    --target-file="$untracked_candidate"
  grep -Fq "selection_mode=explicit_target" "$temp_dir/untracked-explicit.log" || fail "tracked-only mode incorrectly weakened explicit target selection"
  grep -Fq "content_state=untracked" "$temp_dir/untracked-explicit.log" || fail "explicit untracked target was not preserved in tracked-only mode"
  grep -Eq 'review\.preselect .* select_untracked=0( |$)' "$temp_dir/untracked-explicit.log" || fail "explicit tracked-only selection did not carry select_untracked=0 into preselect evidence"

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
  grep -Fq "review.preselect path_hmac=path-hmac-sha256:" "$temp_dir/forced.log" || fail "--target-file did not override target-root selection filter"
  grep -Fq "selection_mode=explicit_target" "$temp_dir/forced.log" || fail "--target-file was not logged as explicit target mode"

  run_manifest_dry_run "$temp_dir/docs-target.log" \
    --target-file=docs/scripts/upkeeper.md \
    --review-modules=p26,p28 \
    --prompt-pass=all
  grep -Fq "review.preselect path_hmac=path-hmac-sha256:" "$temp_dir/docs-target.log" || fail "explicit docs target was not accepted"
  grep -Fq "selection_mode=explicit_target" "$temp_dir/docs-target.log" || fail "explicit docs target was not logged as explicit target mode"
  grep -Fq "cycle.exit exit_code=0 reason=DRY_RUN" "$temp_dir/docs-target.log" || fail "explicit docs target dry-run did not finish cleanly"

  printf 'docs/scripts/upkeeper.md\ntemplates/**\n' >"$temp_dir/upkeeperignore"
  set +e
  CODEX_UPKEEPER_IGNORE_FILE="$temp_dir/upkeeperignore" run_manifest_dry_run "$temp_dir/upkeeperignore-target.log" \
    --target-file=docs/scripts/upkeeper.md
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || fail "explicit .upkeeperignore target exited $rc, expected 3"
  grep -Fq "reason=TARGET_FILE_NOT_ELIGIBLE" "$temp_dir/upkeeperignore-target.log" || fail ".upkeeperignore explicit target did not fail as ineligible"
  grep -Fq ".upkeeperignore" "$temp_dir/upkeeperignore-target.log" || fail ".upkeeperignore explicit target did not name ignore reason"

  CODEX_UPKEEPER_IGNORE_FILE="$temp_dir/upkeeperignore" run_manifest_dry_run "$temp_dir/upkeeperignore-max-cover.log" \
    --max-cover \
    --target-root=templates \
    --include-glob='*.md'
  grep -Fq "review.preselect.none reason=no_eligible_script_tool" "$temp_dir/upkeeperignore-max-cover.log" || fail ".upkeeperignore did not block max-cover template candidates"

  (
    export UPKEEPER_TARGET_FILE="docs/scripts/upkeeper.md"
    export UPKEEPER_REVIEW_MODULES="p26,p28"
    export UPKEEPER_PROMPT_PASS="all"
    run_manifest_dry_run "$temp_dir/docs-config-target.log"
  )
  grep -Fq "review.preselect path_hmac=path-hmac-sha256:" "$temp_dir/docs-config-target.log" || fail "configured explicit docs target was not accepted"
  if grep -Eq '(^| )review_modules_hash=none( |$)' "$temp_dir/docs-config-target.log"; then
    fail "configured review modules were not applied"
  fi
  grep -Fq "prompt_pass=all" "$temp_dir/docs-config-target.log" || fail "configured prompt pass was not applied"

  run_manifest_dry_run "$temp_dir/docs-auto.log" \
    --selection-source=enumerate \
    --target-root=docs/scripts \
    --include-glob='*.md'
  grep -Fq "review.preselect.none reason=no_eligible_script_tool" "$temp_dir/docs-auto.log" || fail "automatic docs-only selection did not report no eligible script/tool"
  if grep -Fq "review.preselect path=docs/scripts/upkeeper.md" "$temp_dir/docs-auto.log"; then
    fail "automatic rotation selected a docs-only target"
  fi

  run_manifest_dry_run "$temp_dir/max-cover.log" \
    --max-cover \
    --target-root=docs \
    --include-glob='*.md'
  grep -Fq "selection_mode=lattice_max_cover" "$temp_dir/max-cover.log" || fail "max-cover did not use Lattice max-cover selection"
  grep -Fq "prompt_pass=all" "$temp_dir/max-cover.log" || fail "max-cover did not force all prompt passes"
  if grep -Eq '(^| )review_modules_hash=none( |$)' "$temp_dir/max-cover.log"; then
    fail "max-cover did not append P24-P30"
  fi
  grep -Fq "max_cover=1" "$temp_dir/max-cover.log" || fail "max-cover was not recorded in cycle.start"

  run_manifest_dry_run "$temp_dir/bug-report-only.log" \
    --target-file=Upkeeper \
    --bug-report-only
  grep -Fq "bug_report_only=1" "$temp_dir/bug-report-only.log" || fail "bug-report-only was not recorded in cycle.start"
  grep -Fq "bug_report_only.prompt appended" "$temp_dir/bug-report-only.log" || fail "bug-report-only prompt addendum was not appended"
  run_manifest_dry_run "$temp_dir/audit-only.log" \
    --target-file=Upkeeper \
    --audit-only
  grep -Fq "bug_report_only=1" "$temp_dir/audit-only.log" || fail "audit-only did not enable the no-fix report contract"
  grep -Fq "audit_only=1" "$temp_dir/audit-only.log" || fail "audit-only was not recorded in cycle.start"
  grep -Fq "bug_report_only.draft.destination mode=audit_only" "$temp_dir/audit-only.log" || fail "audit-only did not use the audit report destination"
  grep -Fq "bug_report_only.prompt appended" "$temp_dir/audit-only.log" || fail "audit-only prompt addendum was not appended"
  bash tests/bug_report_only_test.bash

  mkdir -p "$temp_dir/bin"
  cat >"$temp_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  label=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --label)
        label="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  case "$label" in
    security)
      cat <<'JSON'
[
  {"number":910,"title":"High: fake security issue in `lib/upkeeper/codex_io.bash`","url":"https://example.invalid/issues/910","createdAt":"2026-05-01T00:00:00Z","labels":[{"name":"bug"},{"name":"security"}]},
  {"number":911,"title":"Newer security issue","url":"https://example.invalid/issues/911","createdAt":"2026-05-02T00:00:00Z","labels":[{"name":"bug"},{"name":"security"}]}
]
JSON
      ;;
    data-integrity|bug)
      printf '[]\n'
      ;;
    *)
      printf '[]\n'
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  case "${3:-}" in
    910)
      cat <<'JSON'
{"body":"Repro points at `lib/upkeeper/codex_io.bash:1` and should infer that repo-local file."}
JSON
      ;;
    912)
      cat <<'JSON'
{"number":912,"title":"Explicit issue points at `lib/upkeeper/help_selection.bash`","url":"https://example.invalid/issues/912","createdAt":"2026-05-03T00:00:00Z","state":"OPEN","labels":[{"name":"bug"}],"body":"Fix `lib/upkeeper/help_selection.bash:1` for the explicit handoff."}
JSON
      ;;
    913)
      cat <<'JSON'
{"number":913,"title":"Explicit issue points at runtime manifest state","url":"https://example.invalid/issues/913","createdAt":"2026-05-04T00:00:00Z","state":"OPEN","labels":[{"name":"bug"}],"body":"Fix `runtime/upkeeper-file-manifest.json` handling without reviewing runtime state directly."}
JSON
      ;;
    *)
      printf '{"body":""}\n'
      ;;
  esac
  exit 0
fi

printf 'unexpected fake gh invocation: %s\n' "$*" >&2
exit 2
EOF
  chmod +x "$temp_dir/bin/gh"
  PATH="$temp_dir/bin:$PATH" run_manifest_dry_run "$temp_dir/fix-next-issue.log" \
    --fix-next-issue
  grep -Fq "issue.fix_next selected number=910" "$temp_dir/fix-next-issue.log" || fail "fix-next-issue did not select the oldest security issue"
  grep -Fq "selected_label=security" "$temp_dir/fix-next-issue.log" || fail "fix-next-issue did not use security priority first"
  grep -Fq "issue_fix.target ignored reason=untrusted_inferred_source" "$temp_dir/fix-next-issue.log" || fail "fix-next-issue did not report an untrusted inferred source"
  grep -Fq "target_file=none" "$temp_dir/fix-next-issue.log" || fail "fix-next-issue did not keep target file unpinned for inferred source"
  grep -Fq "issue.fix_prompt appended number=910" "$temp_dir/fix-next-issue.log" || fail "fix-next-issue prompt addendum was not appended"

  PATH="$temp_dir/bin:$PATH" run_manifest_dry_run "$temp_dir/fix-explicit-issue.log" \
    --fix-issue=912
  grep -Fq "issue.fix_issue selected number=912" "$temp_dir/fix-explicit-issue.log" || fail "fix-issue did not lock the explicit issue"
  grep -Fq "selected_label=explicit" "$temp_dir/fix-explicit-issue.log" || fail "fix-issue did not mark explicit selection"
  grep -Fq "target_file=lib/upkeeper/help_selection.bash" "$temp_dir/fix-explicit-issue.log" || fail "fix-issue did not infer the explicit issue target"
  grep -Fq "review.preselect path_hmac=path-hmac-sha256:" "$temp_dir/fix-explicit-issue.log" || fail "fix-issue did not pin the explicit inferred target"
  grep -Fq "issue.fix_prompt appended number=912" "$temp_dir/fix-explicit-issue.log" || fail "fix-issue prompt addendum was not appended"

  PATH="$temp_dir/bin:$PATH" run_manifest_dry_run "$temp_dir/fix-explicit-runtime-issue.log" \
    --fix-issue=913
  grep -Fq "issue.fix_issue selected number=913" "$temp_dir/fix-explicit-runtime-issue.log" || fail "fix-issue did not lock the explicit runtime issue"
  grep -Fq "issue_fix.target ignored reason=ineligible_explicit_issue_target" "$temp_dir/fix-explicit-runtime-issue.log" || fail "fix-issue did not reject the ineligible explicit runtime target"
  grep -Fq "target_file=none" "$temp_dir/fix-explicit-runtime-issue.log" || fail "fix-issue pinned an ineligible runtime target"
  if grep -Fq "reason=TARGET_FILE_NOT_ELIGIBLE" "$temp_dir/fix-explicit-runtime-issue.log"; then
    fail "fix-issue reached preselection with an ineligible runtime target"
  fi

  PATH="$temp_dir/bin:$PATH" run_manifest_dry_run "$temp_dir/fix-comment-stage.log" \
    --fix-issue=912 \
    --issue-workflow-stage=comment
  grep -Fq "issue.workflow_prompt appended stage=comment number=912" "$temp_dir/fix-comment-stage.log" || fail "issue comment stage prompt addendum was not appended"
  grep -Fq "issue.workflow_comment.destination stage=comment number=912" "$temp_dir/fix-comment-stage.log" || fail "issue comment stage wrapper destination was not prepared"
  grep -Fq "issue_workflow_stage=comment" "$temp_dir/fix-comment-stage.log" || fail "issue workflow stage was not logged at cycle start"
  if grep -Fq 'gh issue comment "$CODEX_ISSUE_FIX_NUMBER"' "$ROOT_DIR/lib/upkeeper/prompt_compile.bash"; then
    fail "issue comment stage prompt still relies on an unexported issue-number environment variable"
  fi
  if grep -Fq 'Post the comment with `gh issue comment' "$ROOT_DIR/lib/upkeeper/prompt_compile.bash"; then
    fail "issue workflow stage prompt still asks Codex to post GitHub comments directly"
  fi
  grep -Fq 'issue_workflow_comment_transport=final_message_block' "$ROOT_DIR/lib/upkeeper/prompt_compile.bash" || fail "issue workflow stage prompt does not declare final-message comment transport"
  grep -Fq 'UPKEEPER_ISSUE_COMMENT_DRAFT_START' "$ROOT_DIR/lib/upkeeper/prompt_compile.bash" || fail "issue workflow stage prompt does not require a final-message draft block"
  if grep -Fq 'issue_workflow_comment_file=%s' "$ROOT_DIR/lib/upkeeper/prompt_compile.bash"; then
    fail "issue workflow stage prompt still exposes a backend-writable comment file"
  fi
  grep -Fq 'wrapper-fetched recent issue comments' "$ROOT_DIR/lib/upkeeper/prompt_compile.bash" || fail "issue workflow stage prompt does not use wrapper-fetched comments"

  mkdir -p runtime
  printf 'runtime explicit target fixture\n' >runtime/upkeeper-explicit-target-fixture.txt
  set +e
  run_manifest_dry_run "$temp_dir/runtime-target.log" \
    --target-file=runtime/upkeeper-explicit-target-fixture.txt
  rc=$?
  set -e
  rm -f runtime/upkeeper-explicit-target-fixture.txt
  [[ "$rc" -eq 3 ]] || fail "explicit runtime target exited $rc, expected 3"
  grep -Fq "reason=TARGET_FILE_NOT_ELIGIBLE" "$temp_dir/runtime-target.log" || fail "explicit runtime target did not fail as ineligible"

  set +e
  run_manifest_dry_run "$temp_dir/git-target.log" \
    --target-file=.git/config
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || fail "explicit .git target exited $rc, expected 3"
  grep -Fq "reason=TARGET_FILE_NOT_ELIGIBLE" "$temp_dir/git-target.log" || fail "explicit .git target did not fail as ineligible"

  set +e
  output="$(
    CODEX_LOG_FILE="$temp_dir/invalid-selection-review-module.log" \
      ./Upkeeper --selection-review-modules=nope --version 2>&1
  )"
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || fail "invalid selection review module exited $rc, expected 3"
  grep -Fq "unknown review module filter: nope" <<<"$output" || fail "invalid selection review module error was not clear"

  rm -f "$manifest_path" "$manifest_path".tmp
  rm -f "$lattice_db_path" "$lattice_db_path-journal" "$lattice_db_path-wal" "$lattice_db_path-shm"
  rm -f "$untracked_candidate"
  rm -r "$temp_dir"
}

check_tool_failure_queue() {
  local temp_dir transcript addressed_transcript clean_transcript marker_path open_count resolved_count marker_id tool_failure_queue_signing_key

  log "checking tool failure queue"
  temp_dir="$(mktemp -d /tmp/upkeeper-tool-failure-queue.XXXXXX)"
  transcript="$temp_dir/failure-transcript.log"
  clean_transcript="$temp_dir/clean-transcript.log"
  tool_failure_queue_signing_key="validation-tool-failure-queue-key"

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
  marker_id="$(python3 - <<'PY'
import hashlib
print(hashlib.sha1(b"lib/upkeeper/codex_io.bash").hexdigest()[:24])
PY
)"
  [[ "$(jq -r '.failure_count // 0' "$marker_path")" == "1" ]] || fail "tool failure queue did not initialize one failure"
  grep -Fq "tool_failure_queue.open" "$temp_dir/Upkeeper.log" || fail "tool failure queue open event not logged"

  (
    cd "$ROOT_DIR"
    LOG_FILE="$temp_dir/open_replay.log"
    CODEX_TERMINAL_VERBOSITY=silent
    CODEX_TOOL_FAILURE_QUEUE_ENABLED=1
    CODEX_TOOL_FAILURE_QUEUE_DIR="$temp_dir/failures"
    CODEX_TOOL_FAILURE_QUEUE_BYPASS=0
    CYCLE_ID="validation-open-replay"
    CYCLE_RUN_HASH="validationhashopen2"
    RUN_SELECTED_FAILURE_MARKER_PATH=""
    source lib/upkeeper/fallback_artifacts.bash
    source lib/upkeeper/runtime_foundation.bash
    source lib/upkeeper/tool_failure_queue.bash
    tool_failure_queue_finalize_run "lib/upkeeper/codex_io.bash" "$transcript" 0 "BLOCKED"
  )
  marker_path_replay="$temp_dir/failures/open/$marker_id.json"
  [[ "$(jq -r '.failure_count // 0' "$marker_path_replay")" == "1" ]] || fail "tool failure queue inflated failure_count on transcript replay"

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

  addressed_transcript="$temp_dir/addressed-transcript.log"
  cat >"$addressed_transcript" <<'EOF'
codex
exec
/bin/bash -lc 'tools/validate_upkeeper.sh --quick'
exited 2 in 490ms:
exec
/bin/bash -lc 'tools/validate_upkeeper.sh --quick'
succeeded in 28695ms:
UPKEEPER_STATUS: BLOCKED
EOF

  (
    cd "$ROOT_DIR"
    LOG_FILE="$temp_dir/addressed.log"
    CODEX_TERMINAL_VERBOSITY=silent
    CODEX_TOOL_FAILURE_QUEUE_ENABLED=1
    CODEX_TOOL_FAILURE_QUEUE_DIR="$temp_dir/addressed-failures"
    CODEX_TOOL_FAILURE_QUEUE_BYPASS=0
    CYCLE_ID="validation-addressed-blocked"
    CYCLE_RUN_HASH="validationhashaddressed"
    RUN_SELECTED_FAILURE_MARKER_PATH=""
    source lib/upkeeper/fallback_artifacts.bash
    source lib/upkeeper/runtime_foundation.bash
    source lib/upkeeper/tool_failure_queue.bash
    tool_failure_queue_finalize_run "lib/upkeeper/help_selection.bash" "$addressed_transcript" 0 "BLOCKED"
  )
  open_count="$(find "$temp_dir/addressed-failures/open" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$open_count" == "0" ]] || fail "tool failure queue kept an open marker for same-run addressed BLOCKED evidence"
  resolved_count="$(find "$temp_dir/addressed-failures/resolved" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$resolved_count" == "1" ]] || fail "tool failure queue did not resolve same-run addressed BLOCKED evidence"
  grep -Fq "tool_failure_queue.resolved" "$temp_dir/addressed.log" || fail "tool failure queue did not log addressed BLOCKED resolution"
  grep -Fq "later_success_after_detected_failure" "$temp_dir/addressed-failures/resolved/"*.json || fail "tool failure queue did not record addressed BLOCKED resolution reason"

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
  python3 - "$temp_dir/selection-failures/open/$marker_id.json" "$marker_id" "$tool_failure_queue_signing_key" <<'PY'
import hashlib
import hmac
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
marker_id = sys.argv[2]
signing_key = sys.argv[3].encode("utf-8", "surrogateescape")
payload = {
    "version": 1,
    "status": "open",
    "marker_id": marker_id,
    "target_path": "lib/upkeeper/codex_io.bash",
    "first_seen_epoch": 1,
    "first_seen_cycle": "validation-selection",
    "failure_count": 2,
    "first_failure_kind": "validation",
    "first_failure_exit_line": "exited 1 in 0.1s",
}
encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8", "surrogateescape")
payload["marker_auth_hmac"] = f"hmac-sha256:{hmac.new(signing_key, encoded, hashlib.sha256).hexdigest()}"
path.write_text(json.dumps(payload, sort_keys=True) + "\n", encoding="utf-8")
PY
  chmod 600 "$temp_dir/selection-failures/open/$marker_id.json"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  CODEX_HOME="$temp_dir/codex-home" \
    CODEX_LOG_FILE="$temp_dir/selection.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$(validation_active_lock_dir "$ROOT_DIR" "failure-queue")" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    CODEX_TOOL_FAILURE_QUEUE_DIR="$temp_dir/selection-failures" \
    UPKEEPER_TOOL_FAILURE_QUEUE_SIGNING_KEY="$tool_failure_queue_signing_key" \
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

  grep -Fq "review.preselect path_hmac=path-hmac-sha256:" "$temp_dir/selection.log" || fail "failure queue did not force marked target"
  grep -Fq "failure_queue_selected=1" "$temp_dir/selection.log" || fail "failure queue selection was not logged"

  CODEX_HOME="$temp_dir/codex-home" \
    CODEX_LOG_FILE="$temp_dir/bypass.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts-bypass" \
    CODEX_ACTIVE_LOCK_DIR="$(validation_active_lock_dir "$ROOT_DIR" "failure-queue-bypass")" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health-bypass" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates-bypass" \
    CODEX_TOOL_FAILURE_QUEUE_DIR="$temp_dir/selection-failures" \
    UPKEEPER_TOOL_FAILURE_QUEUE_SIGNING_KEY="$tool_failure_queue_signing_key" \
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

check_issue_workflow_comment_relay() {
  local temp_dir draft_file posted_file last_message_file expected_file

  log "checking issue workflow comment relay"
  temp_dir="$(mktemp -d /tmp/upkeeper-issue-workflow-relay.XXXXXX)"
  draft_file="$temp_dir/comment.md"
  posted_file="$temp_dir/posted.md"
  last_message_file="$temp_dir/last-message.txt"
  expected_file="$temp_dir/expected.md"
  mkdir -p "$temp_dir/bin"
  cat >"$temp_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "comment" && "${3:-}" == "125" && "${4:-}" == "--body-file" ]]; then
  cp -- "$5" "$UPKEEPER_TEST_POSTED_FILE"
  exit 0
fi

printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 2
EOF
  chmod +x "$temp_dir/bin/gh"
  : >"$draft_file"
  cat >"$last_message_file" <<'EOF'
Issue comment draft follows.
UPKEEPER_ISSUE_COMMENT_DRAFT_START
Upkeeper ChimneySweep proposal:

Relay-posted body.
UPKEEPER_ISSUE_COMMENT_DRAFT_END
UPKEEPER_STATUS: WORK_DONE
EOF
  cat >"$expected_file" <<'EOF'
Upkeeper ChimneySweep proposal:

Relay-posted body.
EOF

  (
    cd "$ROOT_DIR"
    PATH="$temp_dir/bin:$PATH"
    LOG_FILE="$temp_dir/Upkeeper.log"
    CODEX_TERMINAL_VERBOSITY=silent
    CYCLE_ID="validation-issue-workflow-relay"
    CYCLE_RUN_HASH="validationhashrelay"
    CODEX_ISSUE_WORKFLOW_STAGE=comment
    CODEX_ISSUE_FIX_NUMBER=125
    RUN_ISSUE_WORKFLOW_COMMENT_FILE="$draft_file"
    RUN_LAST_MESSAGE_FILE="$last_message_file"
    UPKEEPER_TEST_POSTED_FILE="$posted_file"
    export UPKEEPER_TEST_POSTED_FILE
    source lib/upkeeper/fallback_artifacts.bash
    source lib/upkeeper/runtime_foundation.bash
    source lib/upkeeper/codex_io.bash
    upkeeper_issue_workflow_post_comment
  )

  cmp -s "$expected_file" "$posted_file" || fail "issue workflow comment relay did not post the extracted final-message body"
  grep -Fq "issue.workflow_comment.extracted stage=comment number=125" "$temp_dir/Upkeeper.log" || fail "issue workflow comment relay did not log final-message extraction"
  grep -Fq "issue.workflow_comment.posted stage=comment number=125" "$temp_dir/Upkeeper.log" || fail "issue workflow comment relay did not log success"

  draft_file="$temp_dir/review.md"
  posted_file="$temp_dir/posted-review.md"
  last_message_file="$temp_dir/last-message-review.txt"
  expected_file="$temp_dir/expected-review.md"
  : >"$draft_file"
  : >"$temp_dir/Upkeeper.log"
  cat >"$last_message_file" <<'EOF'
Review draft follows.
UPKEEPER_ISSUE_COMMENT_DRAFT_START
Upkeeper ChimneySweep review: revise

Decision: revise. Rotation still needs the same no-follow safety boundary.
UPKEEPER_ISSUE_COMMENT_DRAFT_END
UPKEEPER_STATUS: WORK_DONE
EOF
  cat >"$expected_file" <<'EOF'
Upkeeper ChimneySweep review: revise

Decision: revise. Rotation still needs the same no-follow safety boundary.
EOF

  (
    cd "$ROOT_DIR"
    PATH="$temp_dir/bin:$PATH"
    LOG_FILE="$temp_dir/Upkeeper.log"
    CODEX_TERMINAL_VERBOSITY=silent
    CYCLE_ID="validation-issue-workflow-review-relay"
    CYCLE_RUN_HASH="validationhashreviewrelay"
    CODEX_ISSUE_WORKFLOW_STAGE=review
    CODEX_ISSUE_FIX_NUMBER=125
    RUN_ISSUE_WORKFLOW_COMMENT_FILE="$draft_file"
    RUN_LAST_MESSAGE_FILE="$last_message_file"
    UPKEEPER_TEST_POSTED_FILE="$posted_file"
    export UPKEEPER_TEST_POSTED_FILE
    source lib/upkeeper/fallback_artifacts.bash
    source lib/upkeeper/runtime_foundation.bash
    source lib/upkeeper/codex_io.bash
    upkeeper_issue_workflow_post_comment
  )

  cmp -s "$expected_file" "$posted_file" || fail "issue workflow review relay did not accept inline review decision prefix"
  grep -Fq "issue.workflow_comment.extracted stage=review number=125" "$temp_dir/Upkeeper.log" || fail "issue workflow review relay did not log final-message extraction"
  grep -Fq "issue.workflow_comment.posted stage=review number=125" "$temp_dir/Upkeeper.log" || fail "issue workflow review relay did not log success"

  rm -r "$temp_dir"
}

check_issue_workflow_backend_mode_contract() {
  local temp_dir
  local -a backend_mode_args=()

  log "checking issue workflow backend mode contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-issue-workflow-mode.XXXXXX)"

  (
    cd "$ROOT_DIR"
    RUN_TMP_DIR="$temp_dir/run"
    CODEX_ISSUE_WORKFLOW_STAGE=comment
    CODEX_MODE_ARGS=(--sandbox workspace-write)
    mkdir -p "$RUN_TMP_DIR"
    source lib/upkeeper/codex_io.bash
    mapfile -d '' -t backend_mode_args < <(upkeeper_backend_mode_args_for_current_stage)

    [[ "${#backend_mode_args[@]}" -eq 2 ]] || fail "comment stage backend mode did not produce two args"
    [[ "${backend_mode_args[0]}" == "--sandbox" ]] || fail "comment stage backend mode missing --sandbox"
    [[ "${backend_mode_args[1]}" == "read-only" ]] || fail "comment stage backend mode was not read-only"

    CODEX_ISSUE_WORKFLOW_STAGE=apply
    mapfile -d '' -t backend_mode_args < <(upkeeper_backend_mode_args_for_current_stage)
    [[ "${#backend_mode_args[@]}" -eq 2 ]] || fail "apply stage backend mode did not preserve configured mode"
    [[ "${backend_mode_args[0]}" == "--sandbox" ]] || fail "apply stage backend mode lost configured sandbox option"
    [[ "${backend_mode_args[1]}" == "workspace-write" ]] || fail "apply stage backend mode lost configured workspace-write value"
  )

  rm -r "$temp_dir"
}

check_genie_protocol_backend_boundary() {
  local temp_dir prompt_file transcript_file rc

  log "checking Genie Protocol backend boundary"
  temp_dir="$(mktemp -d /tmp/upkeeper-genie-boundary.XXXXXX)"
  prompt_file="$temp_dir/prompt.txt"
  transcript_file="$temp_dir/transcript.log"
  mkdir -p "$temp_dir/host-bin"

  cat >"$temp_dir/host-bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'host gh should not be reachable\n' >&2
exit 0
EOF
  chmod +x "$temp_dir/host-bin/gh"

cat >"$temp_dir/fake-backend" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

out_dir="${UPKEEPER_GENIE_TEST_OUTPUT_DIR:?}"

for name in GITHUB_TOKEN GH_TOKEN GITHUB_PAT GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN CODEX_GITHUB_PERSONAL_ACCESS_TOKEN GITHUB_API_URL GITHUB_GRAPHQL_URL; do
  if [[ -n "${!name:-}" ]]; then
    printf 'leaked %s\n' "$name" >&2
    exit 10
  fi
done

case "${GH_CONFIG_DIR:-}" in
  */genie-gh-config) ;;
  *)
    printf 'GH_CONFIG_DIR was not brokered: %s\n' "${GH_CONFIG_DIR:-unset}" >&2
    exit 11
    ;;
esac

for command_name in gh curl wget hub; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'missing blocker command: %s\n' "$command_name" >&2
    exit 20
  fi
  set +e
  "$command_name" --version >"$out_dir/$command_name.out" 2>&1
  command_rc=$?
  set -e
  if [[ "$command_rc" -ne 126 ]]; then
    printf 'command was not blocked: %s rc=%s\n' "$command_name" "$command_rc" >&2
    cat "$out_dir/$command_name.out" >&2
    exit 21
  fi
  grep -Fq "Genie Protocol" "$out_dir/$command_name.out" || {
    printf 'blocker message missing for %s\n' "$command_name" >&2
    cat "$out_dir/$command_name.out" >&2
    exit 22
  }
done

if [[ -x /usr/bin/gh ]]; then
  set +e
  /usr/bin/gh auth status >/tmp/upkeeper-genie-gh-auth-status.out 2>&1
  absolute_gh_rc=$?
  set -e
  if [[ "$absolute_gh_rc" -eq 0 ]]; then
    printf 'absolute gh retained authenticated GitHub state\n' >&2
    exit 30
  fi
fi

printf 'GENIE_BOUNDARY_OK\n'
EOF
  chmod +x "$temp_dir/fake-backend"
  printf 'test prompt\n' >"$prompt_file"

  set +e
  (
    cd "$ROOT_DIR"
    PATH="$temp_dir/host-bin:$PATH"
    LOG_FILE="$temp_dir/Upkeeper.log"
    CODEX_TERMINAL_VERBOSITY=full
    CYCLE_ID="validation-genie"
    CYCLE_RUN_HASH="validationhashgenie"
    RUN_TMP_DIR=""
    RUN_GENIE_BIN_DIR=""
    RUN_GENIE_GH_CONFIG_DIR=""
    GITHUB_TOKEN="should-not-leak"
    GH_TOKEN="should-not-leak"
    GITHUB_PAT="should-not-leak"
    GH_ENTERPRISE_TOKEN="should-not-leak"
    GITHUB_ENTERPRISE_TOKEN="should-not-leak"
    CODEX_GITHUB_PERSONAL_ACCESS_TOKEN="should-not-leak"
    GITHUB_API_URL="https://api.github.com"
    GITHUB_GRAPHQL_URL="https://api.github.com/graphql"
    UPKEEPER_GENIE_TEST_OUTPUT_DIR="$temp_dir"
    export GITHUB_TOKEN GH_TOKEN GITHUB_PAT GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
    export CODEX_GITHUB_PERSONAL_ACCESS_TOKEN GITHUB_API_URL GITHUB_GRAPHQL_URL
    export UPKEEPER_GENIE_TEST_OUTPUT_DIR
    source lib/upkeeper/fallback_artifacts.bash
    source lib/upkeeper/runtime_foundation.bash
    source lib/upkeeper/codex_io.bash
    run_codex_exec_capture "genie-validation" "$transcript_file" "$prompt_file" "$temp_dir/fake-backend"
  )
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "Genie Protocol backend boundary fixture exited $rc"
  grep -Fq "GENIE_BOUNDARY_OK" "$transcript_file" || fail "Genie Protocol boundary fixture did not complete"
  grep -Fq "genie_protocol.ready broker=wrapper github_direct=blocked" "$temp_dir/Upkeeper.log" || fail "Genie Protocol boundary readiness was not logged"

  rm -r "$temp_dir"
}

check_lattice_contract() {
  log "checking Upkeeper Lattice"
  grep -Fq "lattice_unavailable_detail_summary" lib/upkeeper/lattice.bash ||
    fail "Lattice wrapper no longer summarizes unavailable details before logging"
  ! grep -Fq 'detail=$(shell_quote "$detail")' lib/upkeeper/lattice.bash ||
    fail "Lattice wrapper still logs raw unavailable detail payloads"
  bash tests/lattice_test.bash
  if rg -n '\b(curl|gh|requests|urllib3|urllib\.request|urllib\.error|http\.client|GITHUB_TOKEN)\b' tools/upkeeper_lattice.py lib/upkeeper/lattice.bash >/dev/null; then
    fail "Lattice implementation contains a default network/token surface"
  fi
}

check_public_docs_policy() {
  local temp_dir output rc

  log "checking public documentation policy"
  tools/check_public_docs.sh --quick

  temp_dir="$(mktemp -d /tmp/upkeeper-public-docs-git.XXXXXX)"
  mkdir -p "$temp_dir/tools"
  cp tools/check_public_docs.sh "$temp_dir/tools/check_public_docs.sh"
  set +e
  output="$(
    cd "$temp_dir" &&
      bash tools/check_public_docs.sh --quick 2>&1
  )"
  rc=$?
  set -e
  rm -r "$temp_dir"
  [[ "$rc" -ne 0 ]] || fail "public docs check unexpectedly passed outside a Git worktree"
  grep -Fq "not a Git worktree:" <<<"$output" ||
    fail "public docs outside-Git diagnostic was not clear: $output"
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
  chmod 700 "$state_dir"
  python3 - "$state_dir/bad state.state" <<'PY'
from hashlib import sha256
from hmac import new as hmac_new
from pathlib import Path
import sys

path = Path(sys.argv[1])
secret = b"startup-anomaly-test-key"
fields = {
    "active_reasons": "manual reason",
    "created_epoch": "123 extra=bad",
    "cycle_id": "cycle with spaces",
    "detail": "private detail",
    "reason": "manual reason",
    "root_dir": "/private/customer/project",
    "run_hash": "hash with spaces",
    "self_path": "/private/customer/project/Upkeeper",
    "owner": "upkeeper_startup_anomaly_gate",
    "schema_version": "1",
    "state_path": str(path),
    "status": "unresolved",
    "updated_epoch": "456",
}
payload = "".join(f"{key}={fields.get(key, '')}\n" for key in sorted(fields))
signature = hmac_new(secret, f"startup_anomaly_state\0{payload}".encode("utf-8", "surrogateescape"), sha256).hexdigest()
path.write_text(payload + f"state_signature={signature}\n", encoding="utf-8")
path.chmod(0o600)
PY

  output="$(
    cd "$ROOT_DIR"
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$state_dir" bash -c 'source lib/upkeeper/startup_anomaly_state.bash; startup_anomaly_state_lines'
  )"

  grep -Fq 'state_id=state-hmac-sha256:' <<<"$output" || fail "startup anomaly state id HMAC missing"
  grep -Fq 'state_file_hmac=path-hmac-sha256:' <<<"$output" || fail "startup anomaly state path HMAC missing"
  grep -Fq 'reason_class=manual_reason' <<<"$output" || fail "startup anomaly reason class missing"
  grep -Fq 'detail_redacted=1' <<<"$output" || fail "startup anomaly detail redaction marker missing"
  grep -Eq 'created_epoch=[0-9]+ ' <<<"$output" || fail "startup anomaly fallback epoch missing"
  if grep -Fq 'extra=bad' <<<"$output"; then
    fail "startup anomaly parser accepted malformed created_epoch as log fields"
  fi
  if grep -Fq 'startup gates' <<<"$output" || grep -Fq 'manual reason' <<<"$output" || grep -Fq 'hash with spaces' <<<"$output"; then
    fail "startup anomaly parser emitted raw whitespace in log field values"
  fi

  rm -r "$temp_dir"
}

check_previous_run_anomaly_summary_contract() {
  local temp_dir state_dir log_file stamp basic_output debug_output

  log "checking previous-run anomaly summary contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-previous-run-summary.XXXXXX)"
  state_dir="$temp_dir/states"
  log_file="$temp_dir/Upkeeper.log"
  mkdir -p "$state_dir"
  stamp="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  cat >"$log_file" <<EOF
$stamp [INFO] cycle=prior-missing run_hash=aaa111 cycle.start selected_file=Upkeeper boot_id=boot-prior
$stamp [INFO] cycle=prior-missing run_hash=aaa111 run.start role=primary boot_id=boot-prior
$stamp [WARN] cycle=prior-gate run_hash=bbb222 startup_anomaly.gate_unresolved reason=missing_log_review boot_id=boot-prior
EOF
  chmod 700 "$state_dir"
  python3 - "$state_dir/unresolved.state" <<'PY'
from hashlib import sha256
from hmac import new as hmac_new
from pathlib import Path
import sys

path = Path(sys.argv[1])
secret = b"startup-anomaly-test-key"
fields = {
    "active_reasons": "previous_run_anomaly",
    "created_epoch": "123",
    "cycle_id": "state-cycle",
    "detail": "changed path violation",
    "reason": "changed path violation",
    "root_dir": "/private/customer/project",
    "run_hash": "state-hash",
    "self_path": "/private/customer/project/Upkeeper",
    "owner": "upkeeper_startup_anomaly_gate",
    "schema_version": "1",
    "state_path": str(path),
    "status": "unresolved",
    "updated_epoch": "456",
}
payload = "".join(f"{key}={fields.get(key, '')}\n" for key in sorted(fields))
signature = hmac_new(secret, f"startup_anomaly_state\0{payload}".encode("utf-8", "surrogateescape"), sha256).hexdigest()
path.write_text(payload + f"state_signature={signature}\n", encoding="utf-8")
path.chmod(0o600)
PY

  run_summary_fixture() {
    local mode="$1"
    cd "$ROOT_DIR"
    CODEX_TERMINAL_VERBOSITY="$mode" \
      CODEX_PREVIOUS_RUN_SCAN_MINUTES=240 \
      CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$state_dir" \
      LOG_FILE="$log_file" \
      CYCLE_ID=current-cycle \
      bash <<'BASH'
system_boot_id() { printf 'boot-current'; }
system_uptime_seconds() { printf '123.45'; }
log_line() { printf '%s %s\n' "$1" "$2"; }
append_startup_anomaly_reason() {
  STARTUP_ANOMALY_REASONS="${STARTUP_ANOMALY_REASONS:+$STARTUP_ANOMALY_REASONS,}$1"
}
terminal_wants_verbose_output() {
  [[ "${CODEX_TERMINAL_VERBOSITY:-basic}" == "verbose" || "${CODEX_TERMINAL_VERBOSITY:-basic}" == "debug1" ]]
}
terminal_wants_full_output() {
  [[ "${CODEX_TERMINAL_VERBOSITY:-basic}" == "full" ]]
}
source lib/upkeeper/startup_anomaly_state.bash
source lib/upkeeper/previous_run_anomalies.bash
scan_previous_run_anomalies
printf 'GATE=%s\n' "${STARTUP_ANOMALY_GATE:-}"
printf 'REASONS=%s\n' "${STARTUP_ANOMALY_REASONS:-}"
printf 'PROMPT_DETAILS<<%s>>\n' "$PREVIOUS_RUN_ANOMALIES"
BASH
  }

  basic_output="$(run_summary_fixture basic)"
  grep -Fq 'WARN previous_run.anomaly_summary ' <<<"$basic_output" || fail "previous-run anomaly summary missing"
  grep -Fq 'listed_total=3' <<<"$basic_output" || fail "previous-run anomaly summary count missing"
  grep -Fq 'prior_cycle_count=2' <<<"$basic_output" || fail "previous-run anomaly prior-cycle count missing"
  grep -Fq 'state_count=1' <<<"$basic_output" || fail "previous-run anomaly state count missing"
  grep -Fq 'details=local_log_state_and_prompt' <<<"$basic_output" || fail "previous-run anomaly summary evidence pointer missing"
  grep -Fq 'action=force_upkeeper_self_review' <<<"$basic_output" || fail "previous-run anomaly summary action missing"
  grep -Fq 'INFO previous_run.anomaly_detail previous_cycle=prior-missing' <<<"$basic_output" || fail "previous-run anomaly detail was not preserved in local log stream"
  grep -Fq 'PROMPT_DETAILS<<- previous_cycle=prior-missing' <<<"$basic_output" || fail "previous-run anomaly prompt detail missing"
  grep -Fq 'state_id=state-hmac-sha256:' <<<"$basic_output" || fail "previous-run anomaly state detail missing"
  grep -Fq 'GATE=1' <<<"$basic_output" || fail "previous-run anomaly gate was not activated"
  grep -Fq 'REASONS=previous_run_anomaly' <<<"$basic_output" || fail "previous-run anomaly gate reason missing"
  if grep -Fq 'WARN previous_run.anomaly_detail previous_cycle=' <<<"$basic_output"; then
    fail "normal previous-run anomaly output would still burst warning details"
  fi
  if grep -Fq 'WARN previous_run.anomaly previous_cycle=' <<<"$basic_output"; then
    fail "normal previous-run anomaly output still emits legacy warning details"
  fi

  debug_output="$(run_summary_fixture debug1)"
  grep -Fq 'WARN previous_run.anomaly_detail previous_cycle=prior-missing' <<<"$debug_output" || fail "debug previous-run anomaly detail missing"

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
    source lib/upkeeper/runtime_foundation.bash
    source lib/upkeeper/runtime_format_json.bash
    source lib/upkeeper/report_analysis.bash
    source lib/upkeeper/fallback_artifacts.bash
    source lib/upkeeper/status_session.bash
    source lib/upkeeper/quota_guardrails.bash
    source lib/upkeeper/quota_state.bash
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
  grep -Fq "primary_before_snapshot_source_hmac:" "$context_path" || fail "context did not redact snapshot source"
  if grep -Fq "primary_before_snapshot_source: " "$context_path"; then
    fail "context retained raw snapshot source in non-debug mode"
  fi
  grep -Fq -- "- incident_classification: CONTROLLED_QUOTA_HANDOFF" "$bug_record_path" || fail "bug record did not classify recovered fallback marker as controlled handoff"
  grep -Fq -- "- fallback_child_status_marker: WORK_DONE" "$bug_record_path" || fail "bug record did not record recovered fallback marker"
  grep -Fq -- "- fallback_child_status_marker_source: recovered_malformed_candidate" "$bug_record_path" || fail "bug record did not record recovered marker source"

  rm -r "$temp_dir"
}

check_postmortem_sequence_marker_contract() {
  local temp_dir case_name case_dir rc expected_status expected_log

  log "checking postmortem sequence marker contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-postmortem-sequence.XXXXXX)"

  for case_name in report_missing_marker hardening_missing_marker report_and_hardening_success; do
    case_dir="$temp_dir/$case_name"
    mkdir -p "$case_dir/tmp"

    if ! CODEX_LOG_FILE="$case_dir/Upkeeper.log" \
      CODEX_POSTMORTEM_DIR="$case_dir/postmortems" \
      CODEX_TRANSCRIPT_DIR="$case_dir/transcripts" \
      CODEX_ACTIVE_LOCK_DIR="$(validation_active_lock_dir "$ROOT_DIR" "postmortem-$case_name")" \
      CODEX_WRAPPER_HEALTH_STATE_DIR="$case_dir/health" \
      CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
      CODEX_TERMINAL_VERBOSITY=silent \
      TMPDIR="$case_dir/tmp" \
      bash -lc '
        set -euo pipefail
        cd "$1"
        case_dir="$2"
        case_name="$3"

        if [[ "$case_name" == "report_missing_marker" ]]; then
          export CODEX_POSTMORTEM_HARDENING_OPT_IN=0
        else
          export CODEX_POSTMORTEM_HARDENING_OPT_IN=1
        fi

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
          local prompt_path="$5"
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
            postmortem.report:report_and_hardening_success)
              {
                printf "# Upkeeper Postmortem\n"
                printf "## Incident Summary\n"
                printf "Report fixture with complete markers.\n"
                printf "## Action Plan\n"
                printf "No outstanding action items.\n"
              } >"$POSTMORTEM_REPORT_PATH"
              printf "CODEX_POSTMORTEM_STATUS: REPORT_WRITTEN\n" >"$last_message_path"
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
              cp "$prompt_path" "$case_dir/hardening-prompt.txt"
              printf "hardening fixture omitted required marker\n" >"$last_message_path"
              return 0
              ;;
            postmortem.hardening:report_and_hardening_success)
              cp "$prompt_path" "$case_dir/hardening-prompt.txt"
              printf "CODEX_POSTMORTEM_STATUS: HARDENING_DONE\n" >"$last_message_path"
              return 0
              ;;
          esac

          printf "unexpected auxiliary phase: %s for %s\n" "$phase_label" "$case_name" >&2
          return 64
        }

        set +e
        run_postmortem_sequence "failure" "marker contract" "0" >"$case_dir/sequence.out" 2>"$case_dir/sequence.err"
        rc=$?

        printf "%s\n" "$rc" >"$case_dir/rc.txt"
        printf "%s\n" "$POSTMORTEM_SEQUENCE_STATUS" >"$case_dir/status.txt"
      ' bash "$ROOT_DIR" "$case_dir" "$case_name" >"$case_dir/bash.out" 2>"$case_dir/bash.err"; then
      cat "$case_dir/bash.err" >&2
      fail "postmortem sequence marker contract setup failed for $case_name"
    fi

    rc="$(tr -d '[:space:]' <"$case_dir/rc.txt")"
    if [[ "$case_name" == "report_and_hardening_success" ]]; then
      [[ "$rc" == "0" ]] || fail "$case_name exited $rc, expected 0"
    else
      [[ "$rc" == "8" ]] || fail "$case_name exited $rc, expected 8"
    fi

    case "$case_name" in
      report_missing_marker)
        expected_status="report_failed"
        expected_log="postmortem.report failed exit_code=0 marker=missing expected_marker=REPORT_WRITTEN"
        ;;
      hardening_missing_marker)
        expected_status="hardening_failed"
        expected_log="postmortem.hardening failed exit_code=0 marker=missing expected_marker=HARDENING_DONE"
        ;;
      report_and_hardening_success)
        expected_status="complete"
        expected_log="postmortem.report.finish exit_code=0 marker=REPORT_WRITTEN"
        ;;
      *)
        fail "unknown marker contract case: $case_name"
        ;;
    esac

    grep -Fxq "$expected_status" "$case_dir/status.txt" || fail "$case_name status was not $expected_status"
    grep -Fq "$expected_log" "$case_dir/Upkeeper.log" || fail "$case_name did not log expected marker failure"
    if grep -Fq "Report fixture" "$case_dir/sequence.out"; then
      fail "$case_name postmortem summary leaked raw report prose"
    fi
    grep -Fq "report_sha256:" "$case_dir/sequence.out" || fail "$case_name postmortem summary did not emit report metadata"
    pm_root="$case_dir/postmortems/validation-$case_name"
    [[ "$(stat -c %a "$pm_root")" == "700" ]] || fail "$case_name postmortem root permissions were not private"
    [[ "$(stat -c %a "$pm_root/incident-context.txt")" == "600" ]] || fail "$case_name incident context permissions were not private"
    [[ "$(stat -c %a "$pm_root/incident-log.txt")" == "600" ]] || fail "$case_name incident log permissions were not private"
    [[ "$(stat -c %a "$pm_root/bug-record.md")" == "600" ]] || fail "$case_name bug record permissions were not private"
    [[ "$(stat -c %a "$pm_root/primary-last-message.meta")" == "600" ]] || fail "$case_name primary last-message metadata permissions were not private"
    if [[ "$case_name" != "report_missing_marker" ]]; then
      [[ -s "$case_dir/hardening-prompt.txt" ]] || fail "$case_name did not preserve the hardening prompt for validation"
      grep -Fq "Deterministic post-mortem report summary:" "$case_dir/hardening-prompt.txt" || fail "$case_name hardening prompt did not include deterministic report summary"
      grep -Fq "report_present=1" "$case_dir/hardening-prompt.txt" || fail "$case_name hardening prompt did not include report presence"
      grep -Fq "report_sha256=" "$case_dir/hardening-prompt.txt" || fail "$case_name hardening prompt did not include report digest"
      grep -Fq "report_headings=Incident Summary" "$case_dir/hardening-prompt.txt" || fail "$case_name hardening prompt did not include sanitized report structure"
      if grep -Fq "$pm_root/postmortem.md" "$case_dir/hardening-prompt.txt"; then
        fail "$case_name hardening prompt leaked the untrusted report path"
      fi
      if grep -Fq "Report fixture" "$case_dir/hardening-prompt.txt"; then
        fail "$case_name hardening prompt leaked raw report prose"
      fi
      if grep -Fq "read the existing post-mortem report at" "$case_dir/hardening-prompt.txt"; then
        fail "$case_name hardening prompt still instructs reading the untrusted report"
      fi
    fi
  done

  rm -r "$temp_dir"
}

check_postmortem_privacy_contract() {
  local temp_dir report_path metadata_path marker_path

  log "checking postmortem privacy contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-postmortem-privacy.XXXXXX)"
  report_path="$temp_dir/postmortem.md"
  metadata_path="$temp_dir/primary-last-message.meta"
  marker_path="$temp_dir/aux-marker.txt"

  (
    cd "$ROOT_DIR"
    source ./Upkeeper
    CYCLE_ID="privacy-check"
    CYCLE_RUN_HASH="privacyhash"
    LOG_FILE="$temp_dir/Upkeeper.log"
    CODEX_POSTMORTEM_DIR="$temp_dir/postmortems"
    POSTMORTEM_CONTEXT_PATH="$temp_dir/postmortems/privacy-check/incident-context.txt"
    POSTMORTEM_INCIDENT_LOG_PATH="$temp_dir/postmortems/privacy-check/incident-log.txt"
    POSTMORTEM_BUG_RECORD_PATH="$temp_dir/postmortems/privacy-check/bug-record.md"
    postmortem_private_dir "$temp_dir/postmortems/privacy-check"
    cat >"$temp_dir/last-message.txt" <<'EOF'
Selected File: lib/upkeeper/postmortem_sequence.bash
Findings: leaked secret token abc123 and operator email admin@example.com
Changes Made: sanitized /tmp/private-root/runtime/secret.log
Verification: none
REVIEWED_AND_REPORTED
EOF
    write_postmortem_last_message_metadata "$temp_dir/last-message.txt" "$metadata_path"
    cat >"$report_path" <<'EOF'
# Upkeeper Postmortem
## Incident Summary
Leaked /tmp/private-root/runtime/secret.log with admin@example.com and https://secret.example.invalid/token
## Action Plan
Remove the leak.
EOF
    postmortem_set_private_file_mode "$report_path"
    emit_postmortem_summary "$report_path" "failure" "complete"
    write_aux_environment_blocked_marker "postmortem.report" "gpt-test" "$marker_path" "session store write probe failed for /tmp/private-root/codex-home/sessions"
  ) >"$temp_dir/out.txt"

  grep -Fq "sha256:" "$metadata_path" || fail "postmortem metadata did not record a hash"
  if grep -Fq "admin@example.com" "$metadata_path"; then
    fail "postmortem metadata leaked raw last-message content"
  fi
  if grep -Fq "/tmp/private-root/runtime/secret.log" "$temp_dir/out.txt"; then
    fail "postmortem summary leaked a private path"
  fi
  if grep -Fq "admin@example.com" "$temp_dir/out.txt"; then
    fail "postmortem summary leaked an email address"
  fi
  grep -Fq "report_sha256:" "$temp_dir/out.txt" || fail "postmortem summary did not emit report metadata"
  grep -Fq "code_home:" "$marker_path" || fail "private auxiliary marker lost raw environment evidence"

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
ERROR secret=sk-testsecret123456 path=/home/joe/private/customer.txt email=ada@example.com Bearer abcdefghijklmnop
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
  grep -Fq "[redacted-secret]" "$temp_dir/live-verbose.err" || fail "verbose live output did not redact model secret text"
  grep -Fq "path-hmac-sha256:" "$temp_dir/live-verbose.err" || fail "verbose live output did not redact private paths"
  [[ "$(grep -Fc "[INFO] Upkeeper: validation status: UPKEEPER_STATUS: WORK_DONE" "$temp_dir/live-verbose.err")" -eq 1 ]] || fail "verbose live output repeated duplicate status markers"
  if grep -Eq "sk-testsecret123456|/home/joe/private/customer[.]txt|ada@example[.]com|Bearer abcdefghijklmnop" "$temp_dir/live-verbose.err"; then
    fail "verbose live output leaked raw model-derived sensitive text"
  fi
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
  if grep -Eq "sk-testsecret123456|/home/joe/private/customer[.]txt|ada@example[.]com|Bearer abcdefghijklmnop" "$temp_dir/live-basic.err"; then
    fail "basic live output leaked raw model-derived sensitive text"
  fi
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
  if grep -Eq '^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9][+-][0-9][0-9][0-9][0-9] ' \
    "$temp_dir/live-verbose.err" "$temp_dir/live-basic.err" "$temp_dir/live-quiet.err"; then
    fail "live output column-one timestamps still include timezone suffixes"
  fi

  CODEX_LOG_FILE="$temp_dir/Upkeeper.log" CYCLE_ID=validation CYCLE_RUN_HASH=filter-test \
    CODEX_TERMINAL_VERBOSITY=basic \
    bash -lc 'cd "$1"; source ./Upkeeper; emit_codex_transcript_summary validation "$2" 1' bash "$ROOT_DIR" "$temp_dir/transcript.log" \
      >"$temp_dir/summary.out" 2>"$temp_dir/summary.err"
  if grep -Eq '^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9][+-][0-9][0-9][0-9][0-9] ' "$temp_dir/summary.err"; then
    fail "transcript summary terminal output still includes timezone suffixes"
  fi
  grep -Fq "codex.transcript.signal label=validation text=exited\\ 1\\ in\\ 0.1s" "$temp_dir/Upkeeper.log" || fail "transcript summary did not report runtime failure"
  grep -Fq "[redacted-secret]" "$temp_dir/Upkeeper.log" || fail "transcript summary did not redact model secret text"
  grep -Fq "path-hmac-sha256:" "$temp_dir/Upkeeper.log" || fail "transcript summary did not redact private paths"
  if grep -Eq "sk-testsecret123456|/home/joe/private/customer[.]txt|ada@example[.]com|Bearer abcdefghijklmnop" "$temp_dir/Upkeeper.log" "$temp_dir/summary.err"; then
    fail "transcript summary leaked raw model-derived sensitive text"
  fi
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

check_entrypoint_internal_self_tests() {
  log "checking entrypoint internal self-tests"
  UPKEEPER_CONFIG_DISABLE=1 UPKEEPER_INTERNAL_LIVE_OUTPUT_CUSTODY_FILTER_SELF_TEST=1 ./Upkeeper |
    grep -Fxq "live_output_custody_filter_self_test=pass" ||
    fail "live output custody self-test failed"
  UPKEEPER_CONFIG_DISABLE=1 UPKEEPER_INTERNAL_REVIEW_SUMMARY_SELF_TEST=1 ./Upkeeper |
    grep -Fxq "review_summary_self_test=pass" ||
    fail "review summary self-test failed"
  UPKEEPER_CONFIG_DISABLE=1 UPKEEPER_INTERNAL_PRECONTACT_BACKUP_HMAC_SELF_TEST=1 ./Upkeeper |
    grep -Fxq "precontact_backup_hmac_self_test=pass" ||
    fail "pre-contact backup HMAC self-test failed"
}

check_review_summary_parser() {
  local temp_dir summary selected_file outcome coverage_json coverage_status coverage_present coverage_missing

  log "checking review summary parser"
  temp_dir="$(mktemp -d /tmp/upkeeper-review-summary.XXXXXX)"
  cat >"$temp_dir/last-message.txt" <<'EOF'
REVIEWED_AND_FIXED

Selected `lib/upkeeper/codex_io.bash` from the authoritative preselection.

Implemented:
- [lib/upkeeper/codex_io.bash](/home/joe/projects/Upkeeper/main/lib/upkeeper/codex_io.bash): hardened JSON assignment handling.

Verification passed:
- `tools/validate_upkeeper.sh --quick`

UPKEEPER_LOG_REVIEW: CHECKED cycle=validation anomalies=none log_sha256=0000000000000000000000000000000000000000000000000000000000000000
UPKEEPER_STATUS: WORK_DONE
EOF

  summary="$(bash -lc 'cd "$1"; source ./Upkeeper; review_report_summary_json "$2"' bash "$ROOT_DIR" "$temp_dir/last-message.txt")"
  selected_file="$(printf '%s' "$summary" | jq -r '.selected_file')"
  outcome="$(printf '%s' "$summary" | jq -r '.outcome')"
  [[ "$selected_file" == "lib/upkeeper/codex_io.bash" ]] || fail "review summary selected_file was $selected_file"
  [[ "$outcome" == "REVIEWED_AND_FIXED" ]] || fail "review summary outcome was $outcome"

  cat >"$temp_dir/last-message.txt" <<'EOF'
REVIEWED_AND_REPORTED for `lib/upkeeper/codex_io.bash`

Findings:
- Confirmed a report-only bug.

Issue filed:
- https://github.com/example/repo/issues/910

UPKEEPER_STATUS: WORK_DONE
EOF

  summary="$(bash -lc 'cd "$1"; source ./Upkeeper; review_report_summary_json "$2"' bash "$ROOT_DIR" "$temp_dir/last-message.txt")"
  selected_file="$(printf '%s' "$summary" | jq -r '.selected_file')"
  outcome="$(printf '%s' "$summary" | jq -r '.outcome')"
  [[ "$selected_file" == "lib/upkeeper/codex_io.bash" ]] || fail "reported review summary selected_file was $selected_file"
  [[ "$outcome" == "REVIEWED_AND_REPORTED" ]] || fail "reported review summary outcome was $outcome"

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

  cat >"$temp_dir/last-message.txt" <<'EOF'
REVIEWED_AND_FIXED for [templates/README.md](/tmp/root/templates/README.md:1).

Selected target baseline: epoch `1777826501`, `2026-05-03 09:41:41 -0700`, age `129h 54m`.

Changed `templates/README.md` to name `prompt-template.md` as the scaffold.

UPKEEPER_STATUS: WORK_DONE
EOF

  summary="$(bash -lc 'cd "$1"; source ./Upkeeper; review_report_summary_json "$2"' bash "$ROOT_DIR" "$temp_dir/last-message.txt")"
  selected_file="$(printf '%s' "$summary" | jq -r '.selected_file')"
  [[ "$selected_file" == "/tmp/root/templates/README.md" ]] || fail "review summary baseline line contaminated selected file: $selected_file"

  cat >"$temp_dir/last-message.txt" <<'EOF'
REVIEWED_AND_FIXED

Findings:
- The selected target was omitted from the final message.

Changed:
- Preserved wrapper evidence instead of reporting unknown.

Verification:
- quick validator fixture

UPKEEPER_STATUS: WORK_DONE
EOF

  CODEX_TERMINAL_VERBOSITY=silent CODEX_PROMPT_PASS=default \
    bash -lc 'cd "$1"; source ./Upkeeper; LOG_FILE="$2"; RUN_SELECTED_REVIEW_PATH="lib/upkeeper/session_store_preflight.bash"; log_review_report_summary "$3" WORK_DONE 0' bash "$ROOT_DIR" "$temp_dir/Upkeeper.log" "$temp_dir/last-message.txt"
  grep -Fq "review.summary" "$temp_dir/Upkeeper.log" || fail "review summary fallback did not write a summary log"
  grep -Fq "selected_file=lib/upkeeper/session_store_preflight.bash" "$temp_dir/Upkeeper.log" || fail "review summary fallback did not use wrapper-selected target"

  cat >"$temp_dir/last-message.txt" <<'EOF'
REVIEWED_AND_FIXED

Findings:
- Model prose included secret=sk-reviewsecret123456 and path /home/joe/private/customer.txt for ada@example.com.

Changed:
- Removed Bearer abcdefghijklmnop from logs.

Verification:
- Checked /home/joe/private/customer.txt stayed private.

UPKEEPER_STATUS: WORK_DONE
EOF

  : >"$temp_dir/Upkeeper.log"
  CODEX_TERMINAL_VERBOSITY=basic CODEX_PROMPT_PASS=default \
    bash -lc 'cd "$1"; source ./Upkeeper; LOG_FILE="$2"; RUN_SELECTED_REVIEW_PATH="lib/upkeeper/session_store_preflight.bash"; log_review_report_summary "$3" WORK_DONE 0' bash "$ROOT_DIR" "$temp_dir/Upkeeper.log" "$temp_dir/last-message.txt" \
      >"$temp_dir/summary-redaction.out" 2>"$temp_dir/summary-redaction.err"
  grep -Fq "redacted-secret" "$temp_dir/Upkeeper.log" || fail "review summary log did not redact model-derived secret text"
  grep -Fq "path-hmac-sha256:" "$temp_dir/Upkeeper.log" || fail "review summary log did not redact model-derived private path"
  grep -Fq "[redacted-secret]" "$temp_dir/summary-redaction.err" || fail "review summary terminal did not redact model-derived secret text"
  if grep -Eq "sk-reviewsecret123456|/home/joe/private/customer[.]txt|ada@example[.]com|Bearer abcdefghijklmnop" "$temp_dir/Upkeeper.log" "$temp_dir/summary-redaction.err"; then
    fail "review summary leaked raw model-derived sensitive text"
  fi

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

  cat >"$temp_dir/pass-results.txt" <<'EOF'
`UPKEEPER_PASS_RESULT: pass=P1 file=Upkeeper applicable=1 outcome=clean changed=0 regression=0`
- `UPKEEPER_PASS_RESULT: pass=P2 file=Upkeeper applicable=1 outcome=clean changed=0 regression=0`
UPKEEPER_PASS_RESULT: pass=P3 file=Upkeeper applicable=1 outcome=clean changed=0 regression=0
EOF

  coverage_json="$(bash -lc 'cd "$1"; source ./Upkeeper; review_pass_coverage_json "$2"' bash "$ROOT_DIR" "$temp_dir/pass-results.txt")"
  coverage_status="$(printf '%s' "$coverage_json" | jq -r '.status')"
  coverage_present="$(printf '%s' "$coverage_json" | jq -r '.present')"
  coverage_missing="$(printf '%s' "$coverage_json" | jq -r '.missing')"
  [[ "$coverage_status" == "incomplete" ]] || fail "pass coverage parser status was $coverage_status"
  [[ "$coverage_present" == "3" ]] || fail "pass coverage parser present count was $coverage_present"
  [[ "$coverage_missing" == P4,* ]] || fail "pass coverage parser missing list was $coverage_missing"

  CODEX_TERMINAL_VERBOSITY=silent CODEX_PROMPT_PASS=all \
    bash -lc 'cd "$1"; source ./Upkeeper; LOG_FILE="$2"; prompt_pass_coverage_gate "$3" 1 || [[ "$?" -eq 2 ]]' bash "$ROOT_DIR" "$temp_dir/pass-coverage.log" "$temp_dir/pass-results.txt"
  grep -Fq "review.pass_coverage prompt_pass=all status=incomplete expected=23 present=3" "$temp_dir/pass-coverage.log" || fail "pass coverage gate did not log decorated marker coverage"

  rm -r "$temp_dir"
}

check_prompt_pass_coverage_enforcement() {
  local temp_dir

  log "checking prompt-pass coverage enforcement"
  temp_dir="$(mktemp -d /tmp/upkeeper-pass-coverage.XXXXXX)"
  cat >"$temp_dir/last-message.txt" <<'EOF'
REVIEWED_CLEAN

No code changes were required.

UPKEEPER_LOG_REVIEW: CHECKED cycle=validation anomalies=none log_sha256=0000000000000000000000000000000000000000000000000000000000000000
UPKEEPER_STATUS: WORK_DONE
EOF

  CODEX_TERMINAL_VERBOSITY=silent CODEX_PROMPT_PASS=all \
    bash -lc 'cd "$1"; source ./Upkeeper; LOG_FILE="$2"; \
      status_marker="WORK_DONE"; status_marker_source="exact"; codex_exit=0; \
      prompt_pass_coverage_gate "$3" 0 || rc=$?; \
      if [[ "${rc:-0}" -eq 2 || "${rc:-0}" -eq 3 ]]; then \
        status_marker="BLOCKED"; status_marker_source="prompt_pass_coverage"; \
      fi; \
      printf "%s\t%s\n" "$status_marker" "$status_marker_source"' bash "$ROOT_DIR" "$temp_dir/pass-enforcement.log" "$temp_dir/last-message.txt" \
      >"$temp_dir/pass-enforcement.out"
  grep -Fxq $'BLOCKED\tprompt_pass_coverage' "$temp_dir/pass-enforcement.out" || fail "prompt-pass coverage enforcement did not force BLOCKED"

  rm -r "$temp_dir"
}

check_log_self_review_target_boundary() {
  log "checking log self-review target boundary"
  grep -Fq 'leave that file unchanged in this cycle and report BLOCKED with the affected repo-relative path plus enough detail for a follow-up wrapper-selected run' \
    "$ROOT_DIR/lib/upkeeper/prompt_compile.bash" ||
    fail "log self-review prompt still permits unselected Upkeeper self-repair"
  grep -Fq 'Do not repair or edit any unselected Upkeeper control-plane file during log-review self-verification' \
    "$ROOT_DIR/lib/upkeeper/prompt_compile.bash" ||
    fail "log self-review prompt does not forbid unselected Upkeeper control-plane edits"
}

check_status_session_jsonl_contract() {
  local temp_dir session_file state diagnostics agent_messages reached_type

  log "checking status session JSONL contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-status-session.XXXXXX)"
  session_file="$temp_dir/session.jsonl"
  write_validation_malformed_session_jsonl "$session_file"

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

check_central_dry_runs() {
  local temp_dir

  log "checking central dry-run startup"
  temp_dir="$(mktemp -d /tmp/upkeeper-central-dry-run.XXXXXX)"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  VALIDATION_CYCLE_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    VALIDATION_CYCLE_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    run_upkeeper_validation_cycle "$ROOT_DIR" "central-dry-run-target" "$temp_dir/codex-home" \
      "$temp_dir/Upkeeper.log" "$temp_dir/transcripts" /dev/null "$temp_dir/target.err"

  VALIDATION_CYCLE_WRAPPER_HEALTH_STATE_DIR="$temp_dir/health" \
    VALIDATION_CYCLE_STARTUP_ANOMALY_GATE_STATE_DIR="$temp_dir/startup-gates" \
    run_upkeeper_validation_cycle "$ROOT_DIR" "central-dry-run-default" "$temp_dir/codex-home" \
      "$temp_dir/Upkeeper.log" "$temp_dir/transcripts" /dev/null "$temp_dir/default.err" \
      --prompt-pass=all

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
    grep -Fq "implementation_hash=value-hmac-sha256:" Upkeeper.log
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
  chmod 0700 "$temp_dir/codex-home/sessions"

  cat >"$temp_dir/bin/codex" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "exec" ]]; then
  cat >/dev/null
  exit 101
fi
exit 101
SH
  chmod +x "$temp_dir/bin/codex"

  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  set +e
  PATH="$temp_dir/bin:$PATH" \
    CODEX_HOME="$temp_dir/codex-home" \
    CODEX_LOG_FILE="$temp_dir/Upkeeper.log" \
    CODEX_TRANSCRIPT_DIR="$temp_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$(validation_active_lock_dir "$ROOT_DIR" "fake-backend")" \
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

check_upkeeper_log_invariants() {
  python3 tools/check_upkeeper_log_invariants.py "$@"
}

write_fault_injection_fake_codex() {
  local bin_dir="$1"

  mkdir -p "$bin_dir"
  cat >"$bin_dir/codex" <<'SH'
#!/usr/bin/env bash
mode="${UPKEEPER_FAKE_CODEX_MODE:-success}"
out_file=""
model="gpt-5.5"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -o)
      out_file="${2:-}"
      shift 2
      ;;
    -m)
      model="${2:-$model}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

case "$mode" in
  success)
    if [[ -n "$out_file" ]]; then
      printf 'UPKEEPER_STATUS: WORK_DONE\n' >"$out_file"
    fi
    printf 'UPKEEPER_STATUS: WORK_DONE\n'
    exit 0
    ;;
  empty-zero)
    if [[ -n "$out_file" ]]; then
      : >"$out_file"
    fi
    exit 0
    ;;
  usage-limit)
    if [[ -n "$out_file" ]]; then
      : >"$out_file"
    fi
    reset_epoch="$(($(date '+%s') + 3600))"
    reset_text="$(date -d "@$reset_epoch" '+%B %-d, %Y %-I:%M %p')"
    session_dir="${CODEX_HOME:-$HOME/.codex}/sessions/2026/05/07"
    mkdir -p "$session_dir"
    session_file="$session_dir/usage-limit-$$.jsonl"
    now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    cat >"$session_file" <<EOF
{"type":"turn_context","payload":{"model":"$model"}}
{"timestamp":"$now_iso","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"validation-$model","limit_name":"$model validation","plan_type":"validation","rate_limit_reached_type":"primary","primary":{"used_percent":100.0,"window_minutes":300,"resets_at":$reset_epoch},"secondary":{"used_percent":10.0,"window_minutes":10080,"resets_at":$((reset_epoch + 86400))}}}}
{"timestamp":"$now_iso","type":"event_msg","payload":{"type":"task_complete","last_agent_message":null}}
EOF
    printf 'Reading prompt from stdin...\n'
    printf 'OpenAI Codex v0.130.0\n'
    printf 'ERROR: You'\''ve hit your usage limit for %s. Switch to another model now, or try again at %s.\n' "$model" "$reset_text"
    exit 1
    ;;
  *)
    printf 'unknown fake codex mode: %s\n' "$mode" >&2
    exit 101
    ;;
esac
SH
  chmod +x "$bin_dir/codex"
}

prepare_fault_injection_wrapper_tree() {
  local temp_dir="$1"

  cp Upkeeper "$temp_dir/Upkeeper"
  chmod +x "$temp_dir/Upkeeper"
  cp -R lib "$temp_dir/lib"
  cp -R prompts "$temp_dir/prompts"
  mkdir -p "$temp_dir/docs/scripts"
  cp docs/scripts/upkeeper.md "$temp_dir/docs/scripts/upkeeper.md"
  git -C "$temp_dir" init -q
  cat >"$temp_dir/tool.sh" <<'SH'
#!/usr/bin/env bash
printf 'fixture\n'
SH
  chmod +x "$temp_dir/tool.sh"
}

run_fault_injection_dry_run() {
  local fixture_dir="$1"
  local phase="$2"
  shift 2

  (
    cd "$fixture_dir"
    CODEX_HOME="$fixture_dir/codex-home" \
      CODEX_LOG_FILE="$fixture_dir/$phase.log" \
      CODEX_TRANSCRIPT_DIR="$fixture_dir/transcripts" \
      CODEX_ACTIVE_LOCK_DIR="$(validation_active_lock_dir "$fixture_dir" "$phase")" \
      CODEX_WRAPPER_HEALTH_STATE_DIR="$fixture_dir/health" \
      CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$fixture_dir/startup-gates" \
      CODEX_TOOL_FAILURE_QUEUE_DIR="$fixture_dir/failures" \
      CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
      CODEX_TERMINAL_VERBOSITY=quiet \
      CODEX_MODEL=gpt-5.5 \
      CODEX_REASONING_EFFORT=xhigh \
      CODEX_FALLBACK_ENABLED=0 \
      CODEX_FALLBACK_SCREEN_ENABLED=0 \
      CODEX_POSTMORTEM_ENABLED=0 \
      UPKEEPER_DRY_RUN=1 \
      ./Upkeeper "$@" >"$fixture_dir/$phase.out" 2>"$fixture_dir/$phase.err"
  )
}

run_fault_injection_fake_backend() {
  local fixture_dir="$1"
  local phase="$2"
  local fake_mode="$3"
  shift 3

  PATH="$fixture_dir/bin:$PATH" \
    UPKEEPER_FAKE_CODEX_MODE="$fake_mode" \
    CODEX_HOME="$fixture_dir/codex-home" \
    CODEX_LOG_FILE="$fixture_dir/$phase.log" \
    CODEX_TRANSCRIPT_DIR="$fixture_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$(validation_active_lock_dir "$ROOT_DIR" "fault-injection-$phase")" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$fixture_dir/health" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$fixture_dir/startup-gates" \
    CODEX_TOOL_FAILURE_QUEUE_DIR="$fixture_dir/failures" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    CODEX_TERMINAL_VERBOSITY=quiet \
    CODEX_MODEL=gpt-5.5 \
    CODEX_REASONING_EFFORT=xhigh \
    CODEX_FALLBACK_ENABLED=0 \
    CODEX_FALLBACK_SCREEN_ENABLED=0 \
    CODEX_POSTMORTEM_ENABLED=0 \
    "$ROOT_DIR/Upkeeper" "$@" >"$fixture_dir/$phase.out" 2>"$fixture_dir/$phase.err"
}

run_fault_injection_root_dry_run() {
  local fixture_dir="$1"
  local phase="$2"
  shift 2

  CODEX_HOME="$fixture_dir/codex-home" \
    CODEX_LOG_FILE="$fixture_dir/$phase.log" \
    CODEX_TRANSCRIPT_DIR="$fixture_dir/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$(validation_active_lock_dir "$ROOT_DIR" "fault-injection-root-$phase")" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$fixture_dir/health" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$fixture_dir/startup-gates" \
    CODEX_TOOL_FAILURE_QUEUE_DIR="$fixture_dir/failures" \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    CODEX_TERMINAL_VERBOSITY=quiet \
    CODEX_MODEL=gpt-5.5 \
    CODEX_REASONING_EFFORT=xhigh \
    CODEX_FALLBACK_ENABLED=0 \
    CODEX_FALLBACK_SCREEN_ENABLED=0 \
    CODEX_POSTMORTEM_ENABLED=0 \
    UPKEEPER_DRY_RUN=1 \
      "$ROOT_DIR/Upkeeper" "$@" >"$fixture_dir/$phase.out" 2>"$fixture_dir/$phase.err"
}

check_backend_usage_limit_contract() {
  local temp_dir rc marker_path

  log "checking backend usage-limit cooldown contract"
  temp_dir="$(mktemp -d /tmp/upkeeper-backend-usage-limit.XXXXXX)"
  chmod 700 "$temp_dir" 2>/dev/null || true
  write_fault_injection_fake_codex "$temp_dir/bin"
  write_validation_quota_snapshot "$temp_dir/codex-home/sessions/2026/05/07/before-session.jsonl" "gpt-5.5"

  set +e
  run_fault_injection_fake_backend "$temp_dir" injection usage-limit --target-file=launcher_examples/spark_5.3_burn_out_xhigh.sh
  rc=$?
  set -e

  [[ "$rc" -eq 7 ]] || fail "backend usage-limit injection exited $rc, expected 7"
  grep -Fq "primary.backend_usage_limit_detected" "$temp_dir/injection.log" || fail "backend usage-limit transcript was not classified"
  grep -Fq "quota.blocked_marker target_model=gpt-5.5" "$temp_dir/injection.log" || fail "backend usage-limit marker was not logged"
  grep -Fq "blocked_bucket=backend_usage_limit" "$temp_dir/injection.log" || fail "backend usage-limit marker did not identify hard bucket"
  grep -Fq "cycle.exit exit_code=7 reason=PRIMARY_BACKEND_USAGE_LIMIT" "$temp_dir/injection.log" || fail "backend usage-limit did not exit with quota cooldown reason"
  if grep -Fq "automation.obligation.open" "$temp_dir/injection.log"; then
    fail "backend usage-limit opened a target repair obligation"
  fi
  marker_path="$(find "$temp_dir/codex-home/upkeeper/quota-primary-block-markers" -name primary-quota-blocked-until.txt -print -quit)"
  [[ -s "$marker_path" ]] || fail "backend usage-limit did not write private quota marker"
  grep -Fxq "blocked_bucket: backend_usage_limit" "$marker_path" || fail "backend usage-limit marker missing hard bucket"
  grep -Fxq "hard_block: 1" "$marker_path" || fail "backend usage-limit marker missing hard_block"
  check_upkeeper_log_invariants "$temp_dir/injection.log" --scan "$temp_dir/injection.out" --scan "$temp_dir/injection.err"
  rm -r "$temp_dir"
}

check_fault_injection_first_scenarios() {
  local temp_dir fixture_dir rc lock_dir stale_epoch
  local -a quarantined_locks

  log "checking first deterministic fault-injection scenarios"
  temp_dir="$(mktemp -d /tmp/upkeeper-fault-injection.XXXXXX)"
  chmod 700 "$temp_dir" 2>/dev/null || true

  fixture_dir="$temp_dir/review-module-prompt"
  mkdir -p "$fixture_dir"
  chmod 700 "$fixture_dir" 2>/dev/null || true
  prepare_fault_injection_wrapper_tree "$fixture_dir"
  write_validation_quota_snapshot "$fixture_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  run_fault_injection_dry_run "$fixture_dir" control --target-file=tool.sh --review-module=p29
  grep -Fq "cycle.exit exit_code=0 reason=DRY_RUN" "$fixture_dir/control.log" || fail "FI-020 control dry-run did not finish cleanly"
  check_upkeeper_log_invariants "$fixture_dir/control.log" --scan "$fixture_dir/control.out" --scan "$fixture_dir/control.err"

  rm "$fixture_dir/prompts/p29-reuse-harvesting-review.md"
  set +e
  run_fault_injection_dry_run "$fixture_dir" injection --target-file=tool.sh --review-module=p29
  rc=$?
  set -e
  [[ "$rc" -eq 70 ]] || fail "FI-020 injection exited $rc, expected 70"
  grep -Fq "review.module_prompt_missing module=p29" "$fixture_dir/injection.log" || fail "FI-020 did not log missing review module prompt"
  grep -Fq "cycle.exit exit_code=70 reason=REVIEW_MODULE_PROMPT_MISSING codex_exec_started=0" "$fixture_dir/injection.log" || fail "FI-020 did not fail closed before backend launch"
  check_upkeeper_log_invariants "$fixture_dir/injection.log" --scan "$fixture_dir/injection.out" --scan "$fixture_dir/injection.err"

  cp "$ROOT_DIR/prompts/p29-reuse-harvesting-review.md" "$fixture_dir/prompts/p29-reuse-harvesting-review.md"
  run_fault_injection_dry_run "$fixture_dir" recovery --target-file=tool.sh --review-module=p29
  grep -Fq "cycle.exit exit_code=0 reason=DRY_RUN" "$fixture_dir/recovery.log" || fail "FI-020 recovery dry-run did not finish cleanly"
  check_upkeeper_log_invariants "$fixture_dir/recovery.log" --scan "$fixture_dir/recovery.out" --scan "$fixture_dir/recovery.err"

  fixture_dir="$temp_dir/fake-backend-empty-zero"
  mkdir -p "$fixture_dir"
  chmod 700 "$fixture_dir" 2>/dev/null || true
  write_fault_injection_fake_codex "$fixture_dir/bin"
  write_validation_quota_snapshot "$fixture_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  run_fault_injection_fake_backend "$fixture_dir" control success --target-file=launcher_examples/spark_5.3_burn_out_xhigh.sh
  grep -Fq "cycle.exit exit_code=0 reason=WORK_DONE" "$fixture_dir/control.log" || fail "FI-021 control fake backend did not finish cleanly"
  check_upkeeper_log_invariants "$fixture_dir/control.log" --scan "$fixture_dir/control.out" --scan "$fixture_dir/control.err"

  set +e
  run_fault_injection_fake_backend "$fixture_dir" injection empty-zero --target-file=launcher_examples/spark_5.3_burn_out_xhigh.sh
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || fail "FI-021 injection exited $rc, expected 3"
  grep -Fq "run.finish plane=llm waiting_for=codex_backend_review wait_result=completed execution_origin=primary codex_exit=0" "$fixture_dir/injection.log" || fail "FI-021 did not record a zero-exit backend finish"
  grep -Fq "transcript_bytes=0 transcript_lines=0" "$fixture_dir/injection.log" || fail "FI-021 did not record empty transcript evidence"
  grep -Fq "cycle.exit exit_code=3 reason=MISSING_STATUS_MARKER" "$fixture_dir/injection.log" || fail "FI-021 did not reject empty successful backend output"
  check_upkeeper_log_invariants "$fixture_dir/injection.log" --scan "$fixture_dir/injection.out" --scan "$fixture_dir/injection.err"

  run_fault_injection_fake_backend "$fixture_dir" recovery success --target-file=launcher_examples/spark_5.3_burn_out_xhigh.sh
  grep -Fq "cycle.exit exit_code=0 reason=WORK_DONE" "$fixture_dir/recovery.log" || fail "FI-021 recovery fake backend did not finish cleanly"
  check_upkeeper_log_invariants "$fixture_dir/recovery.log" --scan "$fixture_dir/recovery.out" --scan "$fixture_dir/recovery.err"

  fixture_dir="$temp_dir/active-lock-stale-not-empty"
  mkdir -p "$fixture_dir"
  chmod 700 "$fixture_dir" 2>/dev/null || true
  write_validation_quota_snapshot "$fixture_dir/codex-home/sessions/2026/05/07/fake-session.jsonl" "gpt-5.5"

  run_fault_injection_root_dry_run "$fixture_dir" control --target-file=Upkeeper
  grep -Fq "cycle.exit exit_code=0 reason=DRY_RUN" "$fixture_dir/control.log" || fail "FI-022 control dry-run did not finish cleanly"
  check_upkeeper_log_invariants "$fixture_dir/control.log" --scan "$fixture_dir/control.out" --scan "$fixture_dir/control.err"

  lock_dir="$(validation_active_lock_dir "$ROOT_DIR" "fault-injection-root-injection")"
  mkdir -p "$lock_dir"
  {
    printf 'cycle_id=stale-fixture\n'
    printf 'run_hash=stale-fixture\n'
    printf 'pid=999999999\n'
    printf 'wrapper_start=stale-fixture\n'
    printf 'boot_id=unknown\n'
  } >"$lock_dir/state"
  {
    printf 'root_dir=%s\n' "$ROOT_DIR"
    printf 'self_path=%s\n' "$ROOT_DIR/Upkeeper"
    printf 'created_epoch=%s\n' "$(date '+%s')"
  } >"$lock_dir/.upkeeper_active_lock.owner"
  printf 'unexpected child\n' >"$lock_dir/unexpected-child"
  stale_epoch="$(($(date '+%s') - 120))"
  python3 - "$lock_dir" "$stale_epoch" <<'PY'
import os
import sys

path = sys.argv[1]
epoch = int(sys.argv[2])
os.utime(path, (epoch, epoch))
PY

  set +e
  UPKEEPER_VERBOSE_METADATA=1 run_fault_injection_root_dry_run "$fixture_dir" injection --target-file=Upkeeper
  rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || fail "FI-022 injection exited $rc, expected 0"
  grep -Fq "active_lock.stale_quarantined" "$fixture_dir/injection.log" || fail "FI-022 did not log stale lock quarantine"
  grep -Fq "reason=owned_lock_not_empty_after_cleanup" "$fixture_dir/injection.log" || fail "FI-022 did not report owned residue quarantine"
  grep -Fq "cycle.exit exit_code=0 reason=DRY_RUN codex_exec_started=0" "$fixture_dir/injection.log" || fail "FI-022 did not complete dry-run after quarantine"
  shopt -s nullglob
  quarantined_locks=("$lock_dir".stale.*)
  shopt -u nullglob
  [[ "${#quarantined_locks[@]}" -eq 1 ]] || fail "FI-022 did not create exactly one quarantine directory"
  [[ -f "${quarantined_locks[0]}/unexpected-child" ]] || fail "FI-022 quarantine did not preserve unexpected child evidence"
  check_upkeeper_log_invariants "$fixture_dir/injection.log" --scan "$fixture_dir/injection.out" --scan "$fixture_dir/injection.err"

  rm -rf "$lock_dir"
  run_fault_injection_root_dry_run "$fixture_dir" recovery --target-file=Upkeeper
  grep -Fq "cycle.exit exit_code=0 reason=DRY_RUN" "$fixture_dir/recovery.log" || fail "FI-022 recovery dry-run did not finish cleanly"
  check_upkeeper_log_invariants "$fixture_dir/recovery.log" --scan "$fixture_dir/recovery.out" --scan "$fixture_dir/recovery.err"

  fixture_dir="$temp_dir/log-invariants"
  mkdir -p "$fixture_dir"
  chmod 700 "$fixture_dir" 2>/dev/null || true
  cat >"$fixture_dir/bad.log" <<'EOF'
2026-05-15T00:00:00-0700 [INFO] cycle=fi-log run_hash=fi-log cycle.start model=gpt-5.5
EOF
  set +e
  check_upkeeper_log_invariants "$fixture_dir/bad.log" >"$fixture_dir/bad.out" 2>"$fixture_dir/bad.err"
  rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || fail "FI-023 bad log exited $rc, expected 1"
  grep -Fq "cycle fi-log has 1 cycle.start events and 0 cycle.exit events" "$fixture_dir/bad.err" || fail "FI-023 did not report missing cycle.exit"

  rm -r "$temp_dir"
}

check_stress_corpus_harness() {
  log "checking local stress corpus harness"
  tools/stress_upkeeper_corpus.sh --local
}

if [[ "$MODE" != "deps" ]]; then
  require_supported_platform
fi

require_commands
if [[ "$MODE" == "deps" ]]; then
  check_dependencies
  log "dependency validation passed"
  exit 0
fi

run_check syntax check_syntax
run_check version_consistency check_version_consistency
run_check module_map check_module_map
run_check prompt_template check_prompt_template
run_check review_module_registry_contract check_review_module_registry_contract
run_check embedded_behavior_table_contracts check_embedded_behavior_table_contracts
run_check log_line_source_length_contract check_log_line_source_length_contract
run_check prompt_public_lint_contract check_prompt_public_lint_contract
run_check fault_injection_registry_contract check_fault_injection_registry_contract
run_check issue_fix_private_packet_contract check_issue_fix_private_packet_contract
run_check authority_control_docs_contract check_authority_control_docs_contract
run_check policy_decisions_contract check_policy_decisions_contract
run_check schema_compatibility_contract check_schema_compatibility_contract
run_check default_prompt_target_isolation_contract check_default_prompt_target_isolation_contract
run_check help_and_diff check_help_and_diff
run_check validation_environment_isolation check_validation_environment_isolation
run_check validation_quota_session_fixture_contract check_validation_quota_session_fixture_contract
run_check dependency_guidance_contract check_dependency_guidance_contract
run_check release_readiness_docs_contract check_release_readiness_docs_contract
run_check governance_docs_contract check_governance_docs_contract
run_check negative_space_testing_contract check_negative_space_testing_contract
run_check serious_finding_repro_contract check_serious_finding_repro_contract
run_check after_action_review_contract check_after_action_review_contract
run_check client_link_tools_contract check_client_link_tools_contract
run_check validation_mode_boundary_contract check_validation_mode_boundary_contract
run_check test_invocation_mode_contract check_test_invocation_mode_contract
run_check wrapper_contract_tests check_wrapper_contract_tests
run_check public_docs_policy check_public_docs_policy
run_check private_artifact_umask_contract check_private_artifact_umask_contract
run_check runtime_format_json_helpers check_runtime_format_json_helpers
run_check startup_anomaly_state_parser_contract check_startup_anomaly_state_parser_contract
run_check previous_run_anomaly_summary_contract check_previous_run_anomaly_summary_contract
run_check postmortem_context_marker_classification check_postmortem_context_marker_classification
run_check postmortem_sequence_marker_contract check_postmortem_sequence_marker_contract
run_check postmortem_privacy_contract check_postmortem_privacy_contract
run_check fallback_postmortem_guardrail_contract check_fallback_postmortem_guardrail_contract
run_check entrypoint_internal_self_tests check_entrypoint_internal_self_tests
run_check live_output_filter_pipe check_live_output_filter_pipe
run_check review_summary_parser check_review_summary_parser
run_check status_session_jsonl_contract check_status_session_jsonl_contract
run_check process_control_guards check_process_control_guards
run_check prior_run_anomaly_custody_contract check_prior_run_anomaly_custody_contract
run_check breadcrumb_audit_contract check_breadcrumb_audit_contract
run_check lattice_custody_policy_contract check_lattice_custody_policy_contract
run_check automation_obligation_root_boundary_contract check_automation_obligation_root_boundary_contract
run_check automation_obligation_reconciliation_contract check_automation_obligation_reconciliation_contract
run_check automation_obligation_churn_contract check_automation_obligation_churn_contract
run_check automation_obligation_issue_report_contract check_automation_obligation_issue_report_contract
run_check backlog_launcher_contract check_backlog_launcher_contract
run_check backlog_batch_validation_obligation_contract check_backlog_batch_validation_obligation_contract
run_check backlog_local_ahead_guard_contract check_backlog_local_ahead_guard_contract
run_check backlog_merge_steward_contract check_backlog_merge_steward_contract
run_check backlog_pr_watch_contract check_backlog_pr_watch_contract
run_check backlog_triage_contract check_backlog_triage_contract
run_check backlog_quota_hibernation_contract check_backlog_quota_hibernation_contract
run_check backlog_autoshelve_contract check_backlog_autoshelve_contract
run_bounded_check backend_usage_limit_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_backend_usage_limit_contract

if [[ "$MODE" == "smoke" ]]; then
  log "$MODE validation passed"
  exit 0
fi

if [[ "$MODE" == "quick" ]]; then
  log "$MODE validation passed"
  exit 0
fi

run_bounded_check review_module_flags "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_review_module_flags
run_bounded_check config_file_support "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_config_file_support
run_bounded_check gitignore_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_gitignore_contract
run_bounded_check force_added_gitignored_target_selection "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_force_added_gitignored_target_selection
run_bounded_check symlink_target_selection_guard "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_symlink_target_selection_guard
run_bounded_check cycle_start_log_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_cycle_start_log_contract
run_bounded_check log_path_symlink_guard "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_log_path_symlink_guard
run_bounded_check custom_log_path_rotation_boundary "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_custom_log_path_rotation_boundary
run_bounded_check disk_preflight_log_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_disk_preflight_log_contract
run_bounded_check disk_preflight_prompt_note_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_disk_preflight_prompt_note_contract
run_bounded_check arg0_tmp_cleanup_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_arg0_tmp_cleanup_contract
run_bounded_check automation_obligation_framework "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_automation_obligation_framework
run_bounded_check session_store_preflight_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_session_store_preflight_contract
run_bounded_check bwrap_tmp_preflight_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_bwrap_tmp_preflight_contract
run_bounded_check wrapper_health_log_quoting "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_wrapper_health_log_quoting
run_bounded_check operator_guide_bootstrap_race "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_operator_guide_bootstrap_race
run_bounded_check active_lock_incomplete_guard "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_active_lock_incomplete_guard
run_bounded_check quota_fallback_exit_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_quota_fallback_exit_contract
run_bounded_check file_manifest_selection "$VALIDATION_FILE_MANIFEST_TIMEOUT_SECONDS" check_file_manifest_selection
run_bounded_check issue_workflow_comment_relay "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_issue_workflow_comment_relay
run_bounded_check issue_workflow_backend_mode_contract "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_issue_workflow_backend_mode_contract
run_bounded_check genie_protocol_backend_boundary "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_genie_protocol_backend_boundary
run_bounded_check prompt_pass_coverage_enforcement "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_prompt_pass_coverage_enforcement
run_bounded_check log_self_review_target_boundary "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_log_self_review_target_boundary
run_bounded_check tool_failure_queue "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_tool_failure_queue
run_bounded_check lattice_contract "$VALIDATION_FULL_TIMEOUT_SECONDS" check_lattice_contract
run_bounded_check fallback_artifact_helpers "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_fallback_artifact_helpers

if [[ "$MODE" == "full" ]]; then
  run_bounded_check central_dry_runs "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_central_dry_runs
  run_bounded_check symlinked_client "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_symlinked_client
  run_bounded_check missing_module_failure "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_missing_module_failure
  run_bounded_check missing_prompt_failure "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_missing_prompt_failure
  run_bounded_check empty_transcript_failure "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_empty_transcript_failure
  run_bounded_check fault_injection_first_scenarios "$VALIDATION_INTEGRATION_TIMEOUT_SECONDS" check_fault_injection_first_scenarios
  run_bounded_check stress_corpus_harness "$VALIDATION_FULL_TIMEOUT_SECONDS" check_stress_corpus_harness
fi

log "$MODE validation passed"
