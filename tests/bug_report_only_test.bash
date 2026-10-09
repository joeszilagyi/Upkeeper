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
  UPKEEPER_ALLOW_GH_ISSUE_WRITE=0
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

test_backend_gh_gate_always_blocks_issue_create() {
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
  [[ "$blocked_output" == *"backend gh issue create is always blocked"* ]] \
    || fail "bug-report gh gate did not explain wrapper-owned filing"

  export UPKEEPER_ALLOW_GH_ISSUE_WRITE=1
  set +e
  allowed_output="$("$stub_gh" issue create --title example 2>&1)"
  blocked_rc="$?"
  set -e
  [[ "$blocked_rc" -eq 126 ]] || fail "bug-report gh gate allowed backend issue creation after wrapper opt-in"
  [[ "$allowed_output" == *"backend gh issue create is always blocked"* ]] \
    || fail "bug-report gh gate changed behavior when wrapper filing was enabled"
  [[ "$allowed_output" != *"REAL_GH issue create"* ]] \
    || fail "bug-report gh gate forwarded backend issue creation"
}

test_wrapper_bug_report_filing_honors_opt_in_and_dedupe() {
  local wrapper_bin gh_args posted_body

  reset_bug_report_env
  wrapper_bin="$TEST_TMP_ROOT/wrapper-bin"
  gh_args="$TEST_TMP_ROOT/wrapper-gh-args.txt"
  posted_body="$TEST_TMP_ROOT/wrapper-posted-body.md"
  mkdir -p "$wrapper_bin" "$RUN_TMP_DIR"
  cat >"$wrapper_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == issue && "${2:-}" == list ]]; then
  printf '%s\n' "${UPKEEPER_TEST_OPEN_ISSUES_JSON:-[]}"
  exit 0
fi
if [[ "${1:-}" == issue && "${2:-}" == create ]]; then
  printf '%s\n' "$*" >"$UPKEEPER_TEST_GH_ARGS"
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == --body-file ]]; then
      cp -- "$2" "$UPKEEPER_TEST_POSTED_BODY"
      break
    fi
    shift
  done
  printf 'https://github.example/issues/777\n'
  exit 0
fi
printf 'unexpected wrapper gh invocation: %s\n' "$*" >&2
exit 2
EOF
  chmod +x "$wrapper_bin/gh"
  PATH="$wrapper_bin:$PATH"
  export PATH
  export UPKEEPER_TEST_GH_ARGS="$gh_args"
  export UPKEEPER_TEST_POSTED_BODY="$posted_body"
  export UPKEEPER_TEST_OPEN_ISSUES_JSON='[]'

  RUN_LAST_MESSAGE_FILE="$TEST_TMP_ROOT/wrapper-report-last-message.txt"
  RUN_BUG_REPORT_DRAFT_FILE="$TEST_TMP_ROOT/wrapper-report-draft.md"
  cat >"$RUN_LAST_MESSAGE_FILE" <<'EOF'
UPKEEPER_BUG_REPORT_DRAFT_START
Title: Wrapper-owned issue filing test
Labels: bug,security

## Summary
The wrapper should own this transport.
UPKEEPER_BUG_REPORT_DRAFT_END
REVIEWED_AND_REPORTED
EOF

  UPKEEPER_ALLOW_GH_ISSUE_WRITE=0
  upkeeper_bug_report_finalize WORK_DONE 0 unchanged || fail "disabled wrapper filing rejected a valid local draft"
  [[ ! -e "$gh_args" ]] || fail "disabled wrapper filing contacted issue-create transport"

  UPKEEPER_ALLOW_GH_ISSUE_WRITE=1
  upkeeper_bug_report_finalize WORK_DONE 0 unchanged || fail "enabled wrapper filing rejected a valid draft"
  grep -Fq 'issue create --title Wrapper-owned issue filing test --body-file' "$gh_args" ||
    fail "wrapper issue-create transport did not receive parsed title/body"
  grep -Fq -- '--label bug --label security' "$gh_args" || fail "wrapper issue-create transport did not receive parsed labels"
  grep -Fq '## Summary' "$posted_body" || fail "wrapper issue-create body omitted report content"
  if grep -Fq 'Title:' "$posted_body" || grep -Fq 'Labels:' "$posted_body"; then
    fail "wrapper issue-create body retained draft metadata headers"
  fi

  rm -f -- "$gh_args" "$posted_body"
  if upkeeper_bug_report_finalize BLOCKED 0 unchanged >/dev/null 2>&1; then
    fail "wrapper filing accepted non-success runtime evidence"
  fi
  [[ ! -e "$gh_args" ]] || fail "runtime-evidence refusal reached issue-create transport"

  export UPKEEPER_TEST_OPEN_ISSUES_JSON='[{"number":44,"title":"Wrapper-owned issue filing test"}]'
  upkeeper_bug_report_finalize WORK_DONE 0 unchanged || fail "wrapper duplicate suppression failed"
  [[ ! -e "$gh_args" ]] || fail "wrapper filing created an exact-title duplicate"
  grep -Fq 'bug_report_only.issue_created transport=wrapper' "$CODEX_LOG_FILE" ||
    fail "wrapper filing did not log successful creation transport"
  grep -Fq 'bug_report_only.issue_write_blocked transport=wrapper' "$CODEX_LOG_FILE" ||
    fail "wrapper filing did not log a policy/evidence refusal"
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
test_backend_gh_gate_always_blocks_issue_create
test_wrapper_bug_report_filing_honors_opt_in_and_dedupe
test_audit_only_reuses_no_fix_guard_and_runtime_report_root

printf 'bug_report_only_test: ok\n'
