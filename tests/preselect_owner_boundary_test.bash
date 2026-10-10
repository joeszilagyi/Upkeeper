#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'preselect_owner_boundary_test: %s\n' "$*" >&2
  exit 1
}

UPKEEPER_CONFIG_DISABLE=1 UPKEEPER_LOCAL_ENV_DISABLE=1 bash -s <<'SH' || exit $?
set -euo pipefail
source ./Upkeeper

declare -F upkeeper_preselect_review_target_base >/dev/null || {
  printf 'missing module-owned base selector\n' >&2
  exit 1
}
declare -F preselect_review_target >/dev/null || {
  printf 'missing public selector\n' >&2
  exit 1
}
! declare -F upkeeper_preselect_review_target_original >/dev/null || {
  printf 'entrypoint retained a cloned selector implementation\n' >&2
  exit 1
}

CODEX_TOOL_FAILURE_QUEUE_ENABLED=0
upkeeper_preselect_review_target_base() {
  cat <<'EOF'
path=fixture.sh
epoch=1700000000
mtime=fixture-mtime
age=fixture-age
git_status=tracked
content_state=matches_head
head_blob=fixture-head
worktree_hash=fixture-worktree
eligible_count=1
selection_mode=oldest_mtime
selection_source=manifest
manifest_status=ready
selection_order=oldest
select_untracked=1
target_root=none
target_max_depth=none
include_globs=none
exclude_globs=none
selection_review_modules=none
self_review_threshold_days=7
failure_queue_selected=0
selection_basis=fixture
EOF
}

selection="$(preselect_review_target)"
[[ "$selection" == *$'path=fixture.sh\n'* ]] || {
  printf 'public selector did not invoke the module-owned base: %s\n' "$selection" >&2
  exit 1
}
[[ "$selection" == *'failure_queue_selected=0'* ]] || {
  printf 'public selector lost canonical queue state: %s\n' "$selection" >&2
  exit 1
}

upkeeper_preselect_review_target_base() {
  printf 'partial-selector-output\n'
  return 7
}
set +e
failed_output="$(preselect_review_target)"
rc=$?
set -e
[[ "$rc" -eq 7 ]] || {
  printf 'base selector failure returned %s, expected 7\n' "$rc" >&2
  exit 1
}
[[ "$failed_output" == 'partial-selector-output' ]] || {
  printf 'base selector failure output was not preserved: %s\n' "$failed_output" >&2
  exit 1
}
SH

printf 'preselect_owner_boundary_test: ok\n'
