#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-obligation-identity.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

ROOT_DIR="$PROJECT_ROOT"
SCRIPT_NAME="Upkeeper"
LOG_FILE="$TEST_TMP_ROOT/Upkeeper.log"
CODEX_TERMINAL_VERBOSITY="silent"
UPKEEPER_AUTOMATION_LEDGER_DIR="$TEST_TMP_ROOT/ledger"
UPKEEPER_OBLIGATION_DIR="$TEST_TMP_ROOT/obligations"
UPKEEPER_AUTOMATION_LAUNCHER="Upkeeper"
UPKEEPER_AUTOMATION_VARIANT="standard"
UPKEEPER_AUTOMATION_POLICY="one-cycle"
UPKEEPER_AUTOMATION_WORKFLOW=""
CODEX_ISSUE_WORKFLOW_STAGE=""
CODEX_ISSUE_FIX_NUMBER=""
CODEX_ISSUE_FIX_TITLE=""
CODEX_TARGET_FILE="Upkeeper"
RUN_SELECTED_REVIEW_PATH="Upkeeper"
RUN_AUTOMATION_RECORD_FILE=""
RUN_TRANSCRIPT_FILE=""

source "$PROJECT_ROOT/lib/upkeeper/runtime_foundation.bash"
source "$PROJECT_ROOT/lib/upkeeper/automation_obligations.bash"

CYCLE_ID="identity-cycle-one"
CYCLE_RUN_HASH="identity-run-one"
automation_open_cycle_obligation 2 BLOCKED WARN BLOCKED 0 1 Upkeeper

mapfile -t obligation_files < <(find "$UPKEEPER_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | sort)
[[ "${#obligation_files[@]}" == "1" ]] || fail "first failure did not create exactly one obligation"
obligation_file="${obligation_files[0]}"
obligation_id="$(jq -r '.id' "$obligation_file")"
[[ "$(jq -r '.occurrence_count' "$obligation_file")" == "1" ]] || fail "first occurrence count was not one"
jq '.repair_attempt_count=2 | .blocked_attempt_count=2 | .next_retry_epoch=4102444800 | .issue_number="669"' \
  "$obligation_file" >"$TEST_TMP_ROOT/obligation-with-custody.json"
mv "$TEST_TMP_ROOT/obligation-with-custody.json" "$obligation_file"

CYCLE_ID="identity-cycle-two"
CYCLE_RUN_HASH="identity-run-two"
automation_open_cycle_obligation 2 BLOCKED WARN BLOCKED 0 1 Upkeeper

mapfile -t obligation_files < <(find "$UPKEEPER_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | sort)
[[ "${#obligation_files[@]}" == "1" ]] || fail "repeatable failure created a second open obligation"
[[ "$(jq -r '.id' "$obligation_file")" == "$obligation_id" ]] || fail "repeatable failure changed stable obligation id"
[[ "$(jq -r '.occurrence_count' "$obligation_file")" == "2" ]] || fail "repeatable failure did not increment occurrence count"
[[ "$(jq -r '.first_source_cycle_id' "$obligation_file")" == "identity-cycle-one" ]] || fail "first cycle evidence was not retained"
[[ "$(jq -r '.source_cycle_id' "$obligation_file")" == "identity-cycle-two" ]] || fail "latest cycle evidence was not updated"
[[ "$(jq -r '.occurrences | length' "$obligation_file")" == "2" ]] || fail "bounded occurrence history did not retain both observations"
[[ "$(jq -r '.occurrences[0].source_run_hash' "$obligation_file")" == "identity-run-one" ]] || fail "first run observation was lost"
[[ "$(jq -r '.occurrences[1].source_run_hash' "$obligation_file")" == "identity-run-two" ]] || fail "latest run observation was lost"
[[ "$(jq -r '.repair_attempt_count' "$obligation_file")" == "2" ]] || fail "repeat occurrence reset repair attempts"
[[ "$(jq -r '.next_retry_epoch' "$obligation_file")" == "4102444800" ]] || fail "repeat occurrence reset retry custody"
[[ "$(jq -r '.issue_number' "$obligation_file")" == "669" ]] || fail "repeat occurrence lost issue custody"
grep -Fq 'automation.obligation.open' "$LOG_FILE" || fail "obligation publication was not logged"
grep -Fq 'action=created occurrence_count=1' "$LOG_FILE" || fail "new obligation action was not logged"
grep -Fq 'action=updated_existing occurrence_count=2' "$LOG_FILE" || fail "updated obligation action was not logged"

CYCLE_ID="identity-cycle-three"
CYCLE_RUN_HASH="identity-run-three"
automation_open_cycle_obligation 2 BLOCKED WARN BLOCKED 0 1 README.md
automation_open_cycle_obligation 2 LATTICE_TIMEOUT WARN BLOCKED 0 1 Upkeeper
obligation_count="$(find "$UPKEEPER_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
[[ "$obligation_count" == "3" ]] || fail "distinct target/reason identities were incorrectly coalesced"

mkdir -p "$TEST_TMP_ROOT/other-root"
ROOT_DIR="$TEST_TMP_ROOT/other-root"
automation_open_cycle_obligation 2 BLOCKED WARN BLOCKED 0 1 Upkeeper
ROOT_DIR="$PROJECT_ROOT"
obligation_count="$(find "$UPKEEPER_OBLIGATION_DIR/open" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
[[ "$obligation_count" == "4" ]] || fail "shared obligation root coalesced different repositories"

! automation_obligation_requires_per_run_identity BLOCKED || fail "repeatable wrapper failure unexpectedly requires per-run identity"

printf 'automation obligation identity tests passed\n'
