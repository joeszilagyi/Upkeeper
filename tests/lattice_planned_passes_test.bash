#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-lattice-planned-passes.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

shell_quote() {
  printf '%q' "$1"
}

log_line() {
  :
}

log_line_parts() {
  :
}

ROOT_DIR="$PROJECT_ROOT"
UPKEEPER_IMPLEMENTATION_DIR="$PROJECT_ROOT"
UPKEEPER_LATTICE_DB="$TEST_TMP_ROOT/lattice.sqlite3"
UPKEEPER_LATTICE_SQLITE_JOURNAL_MODE="delete"
UPKEEPER_LATTICE_SERVICE_ENABLED="0"
UPKEEPER_LATTICE_COMMAND_TIMEOUT_SECONDS="30"
UPKEEPER_LATTICE_TIMEOUT_KILL_AFTER_SECONDS="2"
declare -a CODEX_REVIEW_MODULES=()

source "$PROJECT_ROOT/lib/upkeeper/lattice.bash"

default_expected="P1,P3,P4,P5,P6,P7,P9,P10,P11,P12,P13,P14,P15,P17,P18,P19,P20,P21,P22,P23"
all_expected="P1,P2,P3,P4,P5,P6,P7,P8,P9,P10,P11,P12,P13,P14,P15,P16,P17,P18,P19,P20,P21,P22,P23"

default_output="$(python3 "$PROJECT_ROOT/tools/upkeeper_lattice.py" --root "$PROJECT_ROOT" planned-passes)"
[[ "$default_output" == "$default_expected" ]] || fail "registry default projection drifted: $default_output"

all_output="$(python3 "$PROJECT_ROOT/tools/upkeeper_lattice.py" --root "$PROJECT_ROOT" planned-passes --prompt-pass all)"
[[ "$all_output" == "$all_expected" ]] || fail "registry all-pass projection drifted: $all_output"

module_output="$(
  python3 "$PROJECT_ROOT/tools/upkeeper_lattice.py" --root "$PROJECT_ROOT" \
    planned-passes --review-module p24 --review-module P30
)"
[[ "$module_output" == "$default_expected,P24,P30" ]] || fail "registry module projection drifted: $module_output"

if python3 "$PROJECT_ROOT/tools/upkeeper_lattice.py" --root "$PROJECT_ROOT" planned-passes --review-module p31 >"$TEST_TMP_ROOT/p31.out" 2>"$TEST_TMP_ROOT/p31.err"; then
  fail "reserved P31 was projected as an active review module"
fi
grep -Fq 'unknown or inactive review module pass: p31' "$TEST_TMP_ROOT/p31.err" || fail "reserved P31 rejection was not explicit"

CODEX_PROMPT_PASS=""
CODEX_REVIEW_MODULES=(p24 p30)
lattice_prepare_planned_passes || fail "Bash wrapper could not consume registry projection"
[[ "$(lattice_planned_passes_csv)" == "$default_expected,P24,P30" ]] || fail "Bash wrapper changed registry projection"

CODEX_PROMPT_PASS="all"
CODEX_REVIEW_MODULES=()
lattice_prepare_planned_passes || fail "Bash wrapper could not consume all-pass registry projection"
[[ "$(lattice_planned_passes_csv)" == "$all_expected" ]] || fail "Bash wrapper changed all-pass registry projection"

! grep -Eq '\bp[0-9]+\)[[:space:]]+passes\+=' "$PROJECT_ROOT/lib/upkeeper/lattice.bash" || fail "Bash wrapper still hardcodes review-module pass mappings"
grep -Fq 'planned-passes' "$PROJECT_ROOT/lib/upkeeper/lattice.bash" || fail "Bash wrapper no longer consumes the registry projection command"

printf 'lattice planned-pass projection tests passed\n'
