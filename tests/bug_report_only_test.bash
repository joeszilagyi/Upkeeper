#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-bug-report-only.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

reset_bug_report_env() {
  RUN_BUG_REPORT_DRAFT_FILE=""
  RUN_GENIE_BIN_DIR=""
  RUN_GENIE_GH_CONFIG_DIR=""
  RUN_GENIE_REAL_GH_BIN=""
  RUN_TMP_DIR="$TEST_TMP_ROOT/run-tmp"
  CODEX_BUG_REPORT_ONLY=1
  CODEX_AUDIT_ONLY=0
  UPKEEPER_BUG_REPORT_ONLY=1
  UPKEEPER_AUDIT_ONLY=0
  UPKEEPER_AUDIT_REPORT_DIR=""
  CYCLE_ID="bug-report-only-test"
  CYCLE_RUN_HASH="hash"
  export ROOT_DIR="$PROJECT_ROOT"
}

test_bug_report_draft_extracts_issue_ready_block() {
  local last_message_file draft_file

  reset_bug_report_env
  last_message_file="$TEST_TMP_ROOT/last-message.txt"
  draft_file="$TEST_TMP_ROOT/draft.md"
  cat >"$last_message_file" <<'EOF'
Observed a reproducible wrapper bug.
UPKEEPER_BUG_REPORT_DRAFT_START
Title: Bug-report-only preserves a local issue draft
Labels: bug,data-integrity
## Summary
The wrapper should persist this report locally.
UPKEEPER_BUG_REPORT_DRAFT_END
REVIEWED_AND_REPORTED
EOF

  upkeeper_bug_report_extract_draft_from_last_message "$last_message_file" "$draft_file" >/dev/null \
    || fail "bug-report draft materialization failed"
  grep -Fq 'Title: Bug-report-only preserves a local issue draft' "$draft_file" \
    || fail "materialized draft missing title"
  grep -Fq 'Labels: bug,data-integrity' "$draft_file" \
    || fail "materialized draft missing labels"
}

test_bug_report_finalize_requires_draft_for_reported_outcome() {
  reset_bug_report_env
  RUN_LAST_MESSAGE_FILE="$TEST_TMP_ROOT/reported-last-message.txt"
  RUN_BUG_REPORT_DRAFT_FILE="$TEST_TMP_ROOT/reported-draft.md"
  cat >"$RUN_LAST_MESSAGE_FILE" <<'EOF'
UPKEEPER_BUG_REPORT_DRAFT_START
Title: Bug-report-only finalize writes draft
## Summary
Confirmed issue.
UPKEEPER_BUG_REPORT_DRAFT_END
REVIEWED_AND_REPORTED
EOF

  upkeeper_bug_report_finalize >/dev/null || fail "bug-report finalize rejected a valid reported draft"
  grep -Fq 'Title: Bug-report-only finalize writes draft' "$RUN_BUG_REPORT_DRAFT_FILE" \
    || fail "finalize did not persist the draft"

  reset_bug_report_env
  RUN_LAST_MESSAGE_FILE="$TEST_TMP_ROOT/missing-draft-last-message.txt"
  RUN_BUG_REPORT_DRAFT_FILE="$TEST_TMP_ROOT/missing-draft.md"
  cat >"$RUN_LAST_MESSAGE_FILE" <<'EOF'
REVIEWED_AND_REPORTED
EOF

  if upkeeper_bug_report_finalize >/dev/null 2>&1; then
    fail "bug-report finalize succeeded without a required draft block"
  fi
}

test_bug_report_gh_gate_blocks_issue_create_by_default_and_allows_explicit_opt_in() {
  local real_gh stub_gh blocked_output allowed_output blocked_rc

  reset_bug_report_env
  real_gh="$TEST_TMP_ROOT/gh"
  cat >"$real_gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "repo" && "${2:-}" == "view" ]]; then
  printf 'private\n'
  exit 0
fi

printf 'REAL_GH'
for arg in "$@"; do
  printf ' %s' "$arg"
done
printf '\n'
EOF
  chmod 700 "$real_gh"
  PATH="$TEST_TMP_ROOT:$PATH"
  export PATH
  export UPKEEPER_REAL_GH_BIN="$real_gh"
  export UPKEEPER_ALLOW_GH_ISSUE_WRITE=0

  prepare_genie_protocol_env
  stub_gh="$RUN_GENIE_BIN_DIR/gh"
  [[ -x "$stub_gh" ]] || fail "bug-report gh stub was not created"

  set +e
  blocked_output="$("$stub_gh" issue create --title example 2>&1)"
  blocked_rc="$?"
  set -e
  [[ "$blocked_rc" -eq 126 ]] || fail "bug-report gh gate did not block issue creation by default"
  [[ "$blocked_output" == *"UPKEEPER_ALLOW_GH_ISSUE_WRITE=1"* ]] \
    || fail "bug-report gh gate did not explain the explicit opt-in requirement"

  export UPKEEPER_ALLOW_GH_ISSUE_WRITE=1
  allowed_output="$("$stub_gh" issue create --title example 2>&1)" \
    || fail "bug-report gh gate did not allow explicitly opted-in issue creation"
  [[ "$allowed_output" == *"repo_visibility=private"* ]] \
    || fail "bug-report gh gate did not report repo visibility on explicit issue creation"
  [[ "$allowed_output" == *"REAL_GH issue create --title example"* ]] \
    || fail "bug-report gh gate did not forward to the real gh binary"
}

test_audit_only_reuses_no_fix_guard_and_runtime_report_root() {
  reset_bug_report_env
  CODEX_BUG_REPORT_ONLY=0
  CODEX_AUDIT_ONLY=1
  UPKEEPER_AUDIT_REPORT_DIR="$TEST_TMP_ROOT/audits"

  upkeeper_audit_only_enabled || fail "audit-only predicate did not enable"
  upkeeper_bug_report_only_enabled || fail "audit-only did not reuse bug-report-only report contract"
  [[ "$(upkeeper_source_mutation_guard_mode)" == "audit_only" ]] ||
    fail "audit-only did not select the audit source mutation guard mode"

  prepare_bug_report_draft_artifact || fail "audit-only draft artifact preparation failed"
  [[ "$RUN_BUG_REPORT_DRAFT_FILE" == "$TEST_TMP_ROOT/audits/"* ]] ||
    fail "audit-only did not use the audit report root"
  [[ -d "$TEST_TMP_ROOT/audits" ]] || fail "audit-only report root was not created"
}

export PROJECT_ROOT
export ROOT_DIR="$PROJECT_ROOT"
export UPROOT="$PROJECT_ROOT"
export CODEX_LOG_FILE="$TEST_TMP_ROOT/Upkeeper.log"
export UPKEEPER_CONFIG_DISABLE=1
source "$PROJECT_ROOT/Upkeeper"

test_bug_report_draft_extracts_issue_ready_block
test_bug_report_finalize_requires_draft_for_reported_outcome
test_bug_report_gh_gate_blocks_issue_create_by_default_and_allows_explicit_opt_in
test_audit_only_reuses_no_fix_guard_and_runtime_report_root

printf 'bug_report_only_test: ok\n'
