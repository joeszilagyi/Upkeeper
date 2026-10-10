#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-local-fix-lane.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

source "$ROOT_DIR/lib/upkeeper/change_scope.bash"
source "$ROOT_DIR/lib/upkeeper/local_fix_lane.bash"

fail() { printf 'local_fix_lane_test: %s\n' "$*" >&2; exit 1; }
LOG_LINES=()
log_line() { LOG_LINES+=("$2"); }
shell_quote() { printf '%q' "$1"; }
upkeeper_issue_fix_next_enabled() { return 0; }

UPKEEPER_LOCAL_FIX_LANE_ENABLED=1
UPKEEPER_DRY_RUN=0
CODEX_ISSUE_FIX_LABELS="bug"
CODEX_REASONING_EFFORT="low"
UPKEEPER_TASK_PROFILE_GRADE="docs-only"
CODEX_ISSUE_FIX_SELECTED_LABEL="explicit"
CODEX_ISSUE_FIX_TARGET_FILE="README.md"
RUN_SELECTED_REVIEW_PATH="README.md"
CODEX_TARGET_FILE="README.md"

upkeeper_local_fix_lane_changed_paths() { printf 'README.md\n'; }
upkeeper_local_fix_lane_run_docs_gate() { :; }

if ! upkeeper_local_fix_lane_docs_change_is_complete; then
  fail "docs-only applied change did not complete locally"
fi
[[ "${LOG_LINES[*]}" == *"lane=local effort=none"* ]] || fail "local completion was not logged"

CODEX_ISSUE_FIX_SELECTED_LABEL="priority-high"
if upkeeper_local_fix_lane_docs_change_is_complete; then
  fail "inferred target entered local completion"
fi
CODEX_ISSUE_FIX_SELECTED_LABEL="explicit"

CODEX_ISSUE_FIX_LABELS="security"
if upkeeper_local_fix_lane_docs_change_is_complete; then
  fail "security-labelled work entered local completion"
fi
[[ "${LOG_LINES[*]}" == *"lane=backend effort=low"* ]] || fail "backend escalation effort was not logged"

CODEX_ISSUE_FIX_LABELS="bug"
upkeeper_local_fix_lane_changed_paths() { printf 'README.md\nUpkeeper\n'; }
if upkeeper_local_fix_lane_docs_change_is_complete; then
  fail "mixed change entered local completion"
fi

upkeeper_local_fix_lane_changed_paths() { :; }
if upkeeper_local_fix_lane_docs_change_is_complete; then
  fail "empty change entered local completion"
fi

upkeeper_local_fix_lane_changed_paths() { printf 'README.md\n'; }
upkeeper_local_fix_lane_run_docs_gate() { return 1; }
if upkeeper_local_fix_lane_docs_change_is_complete; then
  fail "failed docs validation entered local completion"
fi

UPKEEPER_DRY_RUN=1
upkeeper_local_fix_lane_run_docs_gate() { :; }
if upkeeper_local_fix_lane_docs_change_is_complete; then
  fail "dry run entered local completion"
fi
UPKEEPER_DRY_RUN=0

UPKEEPER_LOCAL_FIX_LANE_ENABLED=0
if upkeeper_local_fix_lane_docs_change_is_complete; then
  fail "disabled local lane entered local completion"
fi

printf 'local_fix_lane_test: ok\n'
