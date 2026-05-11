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

test_record_startup_anomaly_gate_review_ignores_model_attestation() {
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

  [[ "$STARTUP_ANOMALY_GATE_RESOLVED" == "1" ]] || fail "startup gate did not resolve from wrapper log evidence"
  [[ -f "$state_file" ]] || fail "startup anomaly state file was not written"
  grep -Fxq 'status=resolved' "$state_file" || fail "startup anomaly state was not marked resolved"
  if grep -q 'status=unresolved' "$state_file"; then
    fail "startup anomaly state remained unresolved"
  fi
}

test_source_mutation_fingerprint_tracks_ref_and_reflog_changes() {
  local repo="$TEST_TMP_ROOT/source-mutation-fingerprint"
  local before after
  make_git_repo "$repo"

  cd "$repo"
  printf '# base\n' >tracked.txt
  git add tracked.txt
  git commit -q -m "base fixture"

  before="$(upkeeper_source_mutation_fingerprint)"

  printf 'mutated\n' >>tracked.txt
  git add tracked.txt
  git commit -q -m "committed history update"
  after="$(upkeeper_source_mutation_fingerprint)"
  cd - >/dev/null

  [[ -n "$before" ]] || fail "baseline source mutation fingerprint was empty"
  [[ -n "$after" ]] || fail "post-commit source mutation fingerprint was empty"
  [[ "$before" != "$after" ]] || fail "source mutation fingerprint did not change after committed git history mutation"
}

test_manifest_selection_uses_live_file_mtime_instead_of_manifest_mtime() {
  local repo="$TEST_TMP_ROOT/selection-mtime"
  local manifest output error_capture selected
  make_git_repo "$repo"
  (
    cd "$repo"
    printf '#!/usr/bin/env bash\necho fresh candidate\n' >fresh.sh
    printf '#!/usr/bin/env bash\necho stale candidate\n' >stale.sh
    touch -d '@1700000000' fresh.sh
    touch -d '@1600000000' stale.sh
    git add fresh.sh stale.sh
    git commit -q -m "selection fixture"
  )

  manifest="$repo/runtime-manifest.json"
  : >"$repo/.upkeeperignore"
  cat >"$manifest" <<EOF
{
  "schema_version": 1,
  "root": "$(realpath "$repo")",
  "files": [
    {"rel_path": "fresh.sh", "mtime": 1},
    {"rel_path": "stale.sh", "mtime": 100}
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
  [[ "$selected" == "stale.sh" ]] || fail "manifest-based selection used stale manifest mtime; expected stale.sh by live file mtime"
}

test_record_startup_anomaly_gate_review_ignores_model_attestation
test_source_mutation_fingerprint_tracks_ref_and_reflog_changes
test_manifest_selection_uses_live_file_mtime_instead_of_manifest_mtime
printf 'bug_fix_batch_288_287_284_test: ok\n'
