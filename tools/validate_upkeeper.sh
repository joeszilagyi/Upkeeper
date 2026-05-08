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

No mode launches a Codex backend task. Full mode uses UPKEEPER_DRY_RUN=1.
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
  for command_name in bash chmod cp diff find git grep ln mkdir mktemp rm sed sort touch tr wc; do
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

if [[ "$MODE" == "full" ]]; then
  check_central_dry_runs
  check_symlinked_client
  check_missing_module_failure
  check_missing_prompt_failure
fi

log "$MODE validation passed"
