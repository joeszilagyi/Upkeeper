#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-bug-fix-batch.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

shell_quote() {
  printf '%q' "$1"
}

timestamp_now() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

log_line() {
  :
}

finish_cycle() {
  local exit_code="$1"
  local reason="$2"
  local level="$3"
  shift 3
  local capture_file="${STARTUP_FINISH_CAPTURE:-}"
  if [[ -n "$capture_file" ]]; then
    printf '%s\n' "exit_code=$exit_code reason=$reason level=$level detail=$*" >"$capture_file"
  fi
  exit "$exit_code"
}

make_git_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git config user.name "Upkeeper Test"
    git config user.email "upkeeper-test@localhost"
  )
}

# Source minimal dependencies needed by targeted helpers.
source "$PROJECT_ROOT/lib/upkeeper/runtime_format_json.bash"
source "$PROJECT_ROOT/lib/upkeeper/startup_anomaly_state.bash"
source "$PROJECT_ROOT/lib/upkeeper/report_analysis.bash"
source "$PROJECT_ROOT/lib/upkeeper/codex_io.bash"
source "$PROJECT_ROOT/lib/upkeeper/lattice.bash"
source "$PROJECT_ROOT/lib/upkeeper/help_selection.bash"

test_record_startup_anomaly_gate_review_rejects_missing_log_review_marker() {
  local repo="$TEST_TMP_ROOT/startup-gate"
  local state_file
  make_git_repo "$repo"
  mkdir -p "$repo/runtime"

  LOG_FILE="$repo/session.log"
  LAST_MESSAGE_FILE="$repo/last-message.txt"
  STARTUP_FINISH_CAPTURE="$repo/finish.txt"
  CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$repo/state"
  STARTUP_ANOMALY_GATE="1"
  STARTUP_ANOMALY_REASONS="none"
  STARTUP_ANOMALY_GATE_CHANGED_PATH_VIOLATION="0"
  STARTUP_ANOMALY_GATE_RESOLVED=""
  CYCLE_ID="cycle-startup-288"
  CYCLE_RUN_HASH="run-startup-288"
  ROOT_DIR="$repo"
  SELF_PATH="$PROJECT_ROOT/Upkeeper"

  mkdir -p "$CODEX_STARTUP_ANOMALY_GATE_STATE_DIR"
  state_file="$CODEX_STARTUP_ANOMALY_GATE_STATE_DIR/$CYCLE_RUN_HASH.state"
  : >"$LOG_FILE"
  printf '%s [INFO] cycle.start cycle=%s\n' "$(timestamp_now)" "$CYCLE_ID" >>"$LOG_FILE"
  printf '%s [INFO] run.start cycle=%s\n' "$(timestamp_now)" "$CYCLE_ID" >>"$LOG_FILE"
  printf '%s [INFO] run.finish cycle=%s\n' "$(timestamp_now)" "$CYCLE_ID" >>"$LOG_FILE"
  printf '%s [INFO] cycle.exit cycle=%s\n' "$(timestamp_now)" "$CYCLE_ID" >>"$LOG_FILE"
  : >"$LAST_MESSAGE_FILE"

  record_startup_anomaly_gate_review "$LAST_MESSAGE_FILE" "REVIEWED_CLEAN" "0"

  [[ -z "$STARTUP_ANOMALY_GATE_RESOLVED" ]] || fail "startup gate resolved without a log review marker"
  [[ -f "$state_file" ]] || fail "startup anomaly state file was not written"
  grep -Fq 'status=unresolved' "$state_file" || fail "startup anomaly state was not marked unresolved"
  grep -Fq 'reason=missing_current_cycle_log_review_evidence' "$state_file" || fail "startup anomaly unresolved for wrong reason"
}

test_record_startup_anomaly_gate_review_requires_matching_log_review_marker() {
  local repo="$TEST_TMP_ROOT/startup-gate-288-marker"
  local state_file
  make_git_repo "$repo"
  mkdir -p "$repo/runtime"

  LOG_FILE="$repo/session.log"
  LAST_MESSAGE_FILE="$repo/last-message.txt"
  STARTUP_FINISH_CAPTURE="$repo/finish.txt"
  CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$repo/state"
  STARTUP_ANOMALY_GATE="1"
  STARTUP_ANOMALY_REASONS="none"
  STARTUP_ANOMALY_GATE_CHANGED_PATH_VIOLATION="0"
  STARTUP_ANOMALY_GATE_RESOLVED=""
  CYCLE_ID="cycle-startup-288-marker"
  CYCLE_RUN_HASH="run-startup-288-marker"
  ROOT_DIR="$repo"
  SELF_PATH="$PROJECT_ROOT/Upkeeper"

  mkdir -p "$CODEX_STARTUP_ANOMALY_GATE_STATE_DIR"
  state_file="$CODEX_STARTUP_ANOMALY_GATE_STATE_DIR/$CYCLE_RUN_HASH.state"
  : >"$LOG_FILE"
  printf '%s [INFO] cycle.start cycle=%s\n' "$(timestamp_now)" "$CYCLE_ID" >>"$LOG_FILE"
  printf '%s [INFO] run.start cycle=%s\n' "$(timestamp_now)" "$CYCLE_ID" >>"$LOG_FILE"
  printf '%s [INFO] run.finish cycle=%s\n' "$(timestamp_now)" "$CYCLE_ID" >>"$LOG_FILE"
  printf '%s [INFO] cycle.exit cycle=%s\n' "$(timestamp_now)" "$CYCLE_ID" >>"$LOG_FILE"
  printf 'UPKEEPER_LOG_REVIEW: CHECKED cycle=%s anomalies=none log_sha256=%s\n' \
    "$CYCLE_ID" "0000000000000000000000000000000000000000000000000000000000000000" \
    >"$LAST_MESSAGE_FILE"

  record_startup_anomaly_gate_review "$LAST_MESSAGE_FILE" "REVIEWED_CLEAN" "0"

  [[ -z "$STARTUP_ANOMALY_GATE_RESOLVED" ]] || fail "startup gate resolved from mismatched log review marker"
  [[ -f "$state_file" ]] || fail "startup anomaly state file was not written"
  grep -Fq 'status=unresolved' "$state_file" || fail "startup anomaly state was not marked unresolved"
  grep -Fq 'reason=missing_current_cycle_log_review_evidence' "$state_file" || fail "startup anomaly unresolved for wrong reason"
}

test_source_mutation_fingerprint_tracks_ref_and_reflog_changes() {
  local repo="$TEST_TMP_ROOT/source-mutation-fingerprint"
  local before after
  local before_head before_branch before_index_tree
  local after_head after_branch after_index_tree
  make_git_repo "$repo"

  cd "$repo"
  printf '# base\n' >tracked.txt
  git add tracked.txt
  git commit -q -m "base fixture"

  before="$(upkeeper_source_mutation_fingerprint)"
  before_head="$(git rev-parse --verify HEAD)"
  before_branch="$(git symbolic-ref --short -q HEAD)"
  before_index_tree="$(git write-tree)"

  [[ -n "$before_head" ]] || fail "baseline source mutation setup lacked HEAD"
  [[ -n "$before_branch" ]] || fail "baseline source mutation setup lacked branch"
  [[ -n "$before_index_tree" ]] || fail "baseline source mutation setup lacked index-tree"

  printf 'mutated\n' >>tracked.txt
  git add tracked.txt
  git commit -q -m "committed history update"
  after="$(upkeeper_source_mutation_fingerprint)"
  cd - >/dev/null

  [[ -n "$before" ]] || fail "baseline source mutation fingerprint was empty"
  [[ -n "$after" ]] || fail "post-commit source mutation fingerprint was empty"
  [[ "$before" != "$after" ]] || fail "source mutation fingerprint did not change after committed git history mutation"
  after_head="$(git -C "$repo" rev-parse --verify HEAD)"
  after_branch="$(git -C "$repo" symbolic-ref --short -q HEAD)"
  after_index_tree="$(git -C "$repo" write-tree)"
  [[ -n "$after_head" ]] || fail "post-commit source mutation fingerprint setup lacked HEAD"
  [[ "$after_head" != "$before_head" ]] || fail "HEAD was unchanged after committed git history mutation"
  [[ -n "$after_index_tree" ]] || fail "post-commit source mutation fingerprint setup lacked index-tree"
  [[ "$after_index_tree" != "$before_index_tree" ]] || fail "index-tree was unchanged after committed git history mutation"
  [[ "$after_branch" == "$before_branch" ]] || fail "branch changed after local commit in baseline test"
}

test_manifest_selection_prefers_manifest_mtime_ns() {
  local repo="$TEST_TMP_ROOT/selection-mtime"
  local manifest output error_capture selected manifest_root_hash
  make_git_repo "$repo"
  (
    cd "$repo"
    printf '#!/usr/bin/env bash\necho new candidate\n' >a_newer.sh
    printf '#!/usr/bin/env bash\necho old candidate\n' >z_older.sh
    touch -d '@1700000000' a_newer.sh
    touch -d '@1700000000' z_older.sh
    git add a_newer.sh z_older.sh
    git commit -q -m "selection fixture"
  )

  manifest_root_hash="$(python3 - "$repo" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
print(hashlib.sha256(str(root).encode("utf-8")).hexdigest())
PY
)"
  manifest="$repo/runtime-manifest.json"
  : >"$repo/.upkeeperignore"
  cat >"$manifest" <<EOF
{
  "schema_version": 2,
  "root_hash": "$manifest_root_hash",
  "files": [
    {"rel_path": "a_newer.sh", "mtime": 1700000000, "mtime_ns": 1700000000250000000},
    {"rel_path": "z_older.sh", "mtime": 1700000000, "mtime_ns": 1700000000000000000}
  ]
}
EOF

  CYCLE_ID="cycle-mtime-284"
  CYCLE_RUN_HASH="run-mtime-284"
  ROOT_DIR="$repo"
  SELF_PATH="$PROJECT_ROOT/Upkeeper"
  CODEX_UPKEEPER_SELF_REVIEW_AFTER_DAYS="7"
  STARTUP_ANOMALY_GATE="0"
  CODEX_STARTUP_ANOMALY_FORCE_UPKEEPER="0"
  CODEX_TARGET_FILE=""
  CODEX_TOOL_FAILURE_QUEUE_DIR="$repo/.upkeeper-tool-failure-queue"
  CODEX_TOOL_FAILURE_QUEUE_ENABLED="0"
  CODEX_TOOL_FAILURE_QUEUE_BYPASS="0"
  CODEX_SELECTION_SOURCE="manifest"
  CODEX_FILE_MANIFEST_PATH="$manifest"
  CODEX_SELECTION_ORDER="oldest"
  CODEX_TARGET_ROOT=""
  CODEX_TARGET_MAX_DEPTH=""
  CODEX_SELECTION_INCLUDE_GLOBS=""
  CODEX_SELECTION_EXCLUDE_GLOBS=""
  CODEX_SELECTION_REVIEW_MODULES=""
  CODEX_SELECTION_RANDOM_SEED=""
  CODEX_MAX_COVER_MODE="0"
  UPKEEPER_LATTICE_ENABLED="0"
  UPKEEPER_LATTICE_SELECTION_MODE="oldest"
  UPKEEPER_IMPLEMENTATION_DIR="$PROJECT_ROOT"
  UPKEEPER_LATTICE_DB="$repo/runtime/upkeeper-lattice.sqlite3"
  UPKEEPER_LATTICE_SQLITE_JOURNAL_MODE="wal"
  CODEX_UPKEEPER_IGNORE_FILE="$repo/.upkeeperignore"
  error_capture="$repo/preselect.err"

  output="$(preselect_review_target 2>"$error_capture")"
  selected="$(sed -n 's/^path=//p' <<<"$output" | head -n 1)"
  if [[ -z "$selected" ]]; then
    fail "selection output empty; see preselect error capture at $error_capture"
  fi
  [[ "$selected" == "z_older.sh" ]] || fail "manifest-based selection did not prefer smaller mtime_ns; expected z_older.sh"
}

test_record_startup_anomaly_gate_review_rejects_missing_log_review_marker
test_record_startup_anomaly_gate_review_requires_matching_log_review_marker
test_source_mutation_fingerprint_tracks_ref_and_reflog_changes
test_manifest_selection_prefers_manifest_mtime_ns
printf 'bug_fix_batch_288_287_284_test: ok\n'
