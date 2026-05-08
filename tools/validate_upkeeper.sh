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
  log "checking default prompt template"
  [[ -s prompts/default-review.md ]] || fail "prompts/default-review.md is missing or empty"
}

check_help_and_diff() {
  log "checking help and whitespace"
  ./Upkeeper --help >/dev/null
  git diff --check
  git diff --cached --check
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
  grep -Eq "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ search started: /bin/bash -lc 'rg ERROR change_notes.md'" "$temp_dir/live-verbose.err" || fail "verbose live output did not report search command start"
  grep -Eq '\[INFO\] Upkeeper: validation cmd#[0-9]+ search started: /bin/bash -lc "nl -ba tools/validate_upkeeper[.]sh' "$temp_dir/live-verbose.err" || fail "verbose live output did not classify source file view as search"
  grep -Eq '\[INFO\] Upkeeper: validation cmd#[0-9]+ search started: /bin/bash -lc "git ls-files' "$temp_dir/live-verbose.err" || fail "verbose live output did not classify git ls-files discovery as search"
  grep -Eq "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ search exited nonzero: exited 1 in 0ms:" "$temp_dir/live-verbose.err" || fail "verbose live output did not report git ls-files discovery as non-error search failure"
  grep -Eq "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ search exited nonzero: exited 2 in 104ms:" "$temp_dir/live-verbose.err" || fail "verbose live output did not report non-error search failure"
  grep -Eq "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ check started: /bin/bash -lc 'bash -n launcher_examples/[*][.]sh'" "$temp_dir/live-verbose.err" || fail "verbose live output did not report successful check start"
  grep -Eq "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ check passed: succeeded in 0ms:" "$temp_dir/live-verbose.err" || fail "verbose live output did not report successful check completion"
  grep -Eq "\\[INFO\\] Upkeeper: validation cmd#[0-9]+ tests started: python -m pytest" "$temp_dir/live-verbose.err" || fail "verbose live output did not report interesting command"
  grep -Eq "\\[ERROR\\] Upkeeper: validation cmd#[0-9]+ tests failed: exited 1 in 0.1s" "$temp_dir/live-verbose.err" || fail "verbose live output did not report failed command"
  [[ "$(grep -Fc "[INFO] Upkeeper: validation status: UPKEEPER_STATUS: WORK_DONE" "$temp_dir/live-verbose.err")" -eq 1 ]] || fail "verbose live output repeated duplicate status markers"
  if grep -Eq "broad except|ValueError|Python traceback|change-note output|source-view output|diff-block output|ERROR .*exited 1 in 0ms|ERROR .*exited 2|ERROR .*exited 64|tests failed: exited 1 in 0ms|Final prose mentions|validation command completed" "$temp_dir/live-verbose.err"; then
    fail "verbose live output reported prompt, uninteresting command output, or Codex prose as runtime signal"
  fi

  run_live_filter_mode basic
  grep -Eq "\\[INFO\\] Upkeeper: validation running check cmd#[0-9]+: /bin/bash -lc 'bash -n launcher_examples/[*][.]sh'" "$temp_dir/live-basic.err" || fail "basic live output did not report check start"
  grep -Eq "\\[INFO\\] Upkeeper: validation finished check cmd#[0-9]+: succeeded in 0ms:" "$temp_dir/live-basic.err" || fail "basic live output did not report check completion"
  grep -Eq "\\[ERROR\\] Upkeeper: validation cmd#[0-9]+ tests failed: exited 1 in 0.1s" "$temp_dir/live-basic.err" || fail "basic live output did not report failed command"
  if grep -Eq "search started|search exited nonzero|change-note output|source-view output|diff-block output|Final prose mentions" "$temp_dir/live-basic.err"; then
    fail "basic live output reported verbose search chatter or filtered text"
  fi

  run_live_filter_mode quiet
  grep -Eq "\\[ERROR\\] Upkeeper: validation cmd#[0-9]+ tests failed: exited 1 in 0.1s" "$temp_dir/live-quiet.err" || fail "quiet live output did not report failed command"
  [[ "$(grep -Fc "[INFO] Upkeeper: validation status: UPKEEPER_STATUS: WORK_DONE" "$temp_dir/live-quiet.err")" -eq 1 ]] || fail "quiet live output did not report one status marker"
  if grep -Eq "search started|running check|finished check|tests started|change-note output|source-view output" "$temp_dir/live-quiet.err"; then
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
  log "checking central dry-run startup"
  CODEX_TERMINAL_VERBOSITY=quiet UPKEEPER_DRY_RUN=1 ./Upkeeper >/dev/null
  CODEX_TERMINAL_VERBOSITY=quiet UPKEEPER_DRY_RUN=1 ./Upkeeper --prompt-pass=all >/dev/null
}

check_symlinked_client() {
  local temp_dir

  log "checking symlinked client behavior"
  temp_dir="$(mktemp -d /tmp/upkeeper-symlink.XXXXXX)"

  git -C "$temp_dir" init -q
  touch "$temp_dir/tool.sh"
  chmod +x "$temp_dir/tool.sh"
  ln -s "$ROOT_DIR/Upkeeper" "$temp_dir/Upkeeper.sh"

  (
    cd "$temp_dir"
    ./Upkeeper.sh --version >/dev/null
    CODEX_TERMINAL_VERBOSITY=quiet UPKEEPER_DRY_RUN=1 ./Upkeeper.sh >/dev/null
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

  (
    cd "$temp_dir"
    set +e
    CODEX_TERMINAL_VERBOSITY=quiet UPKEEPER_DRY_RUN=1 ./Upkeeper >out.txt 2>err.txt
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
check_fallback_artifact_helpers
check_live_output_filter_pipe
check_review_summary_parser
check_process_control_guards

if [[ "$MODE" == "full" ]]; then
  check_central_dry_runs
  check_symlinked_client
  check_missing_module_failure
  check_missing_prompt_failure
  check_empty_transcript_failure
fi

log "$MODE validation passed"
