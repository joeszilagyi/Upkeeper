#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-transcripts-test.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT
TEST_LOG_FILE="$TEST_TMP_ROOT/Upkeeper.log"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

expected_negative_fixture_begin() {
  printf '__UPKEEPER_BACKLOG_EXPECTED_NEGATIVE_FIXTURE__:begin:%s\n' "$1" >&2
}

expected_negative_fixture_end() {
  printf '__UPKEEPER_BACKLOG_EXPECTED_NEGATIVE_FIXTURE__:end:%s\n' "$1" >&2
}

run_prune_once() {
  local transcript_dir="$1"
  local rc=0

  set +e
  UPROOT="$PROJECT_ROOT" \
  CODEX_LOG_FILE="$TEST_LOG_FILE" \
  CODEX_TRANSCRIPT_DIR="$transcript_dir" \
  CODEX_TRANSCRIPT_KEEP_HOURS=0 \
  CODEX_TRANSCRIPT_KEEP_MAX_MB=1 \
  UPKEEPER_CONFIG_DISABLE=1 \
  bash -c 'set +e; source "$UPROOT/Upkeeper"; prune_transcript_artifacts'
  rc="$?"
  set -e

  return "$rc"
}

run_new_transcript_file() {
  local transcript_dir="$1"
  local rc=0

  set +e
  NEW_TRANSCRIPT_FILE="$(UPROOT="$PROJECT_ROOT" \
  CODEX_LOG_FILE="$TEST_LOG_FILE" \
  CODEX_TRANSCRIPT_DIR="$transcript_dir" \
  CODEX_TRANSCRIPT_KEEP_HOURS=0 \
  CODEX_TRANSCRIPT_KEEP_MAX_MB=1 \
  UPKEEPER_CONFIG_DISABLE=1 \
  bash -c 'set +e; source "$UPROOT/Upkeeper"; new_transcript_file')"
  rc="$?"
  set -e

  NEW_TRANSCRIPT_FILE_RC="$rc"
}

calc_transcript_marker() {
  local transcript_dir="$1"
  UPROOT="$PROJECT_ROOT" \
  CODEX_LOG_FILE="$TEST_LOG_FILE" \
  UPKEEPER_CONFIG_DISABLE=1 \
  bash -c 'set +e; source "$UPROOT/Upkeeper"; transcript_artifacts_marker_expected "$1"' _ "$transcript_dir"
}

test_transcript_prune_skips_unowned_directory() {
  local transcript_dir="$TEST_TMP_ROOT/custom-unowned-transcripts"
  local legacy_log="$transcript_dir/unrelated.log"
  mkdir -p "$transcript_dir"

  : >"$legacy_log"
  truncate -s "$((1024 * 1024 + 1))" "$legacy_log"

  run_prune_once "$transcript_dir"

  if [[ ! -f "$legacy_log" ]]; then
    fail "unowned transcript directory was pruned"
  fi
  if [[ -f "$transcript_dir/.upkeeper-transcript-artifacts.marker" ]]; then
    fail "unexpected marker file was written"
  fi
}

test_transcript_prune_allows_owned_directory() {
  local transcript_dir="$TEST_TMP_ROOT/custom-owned-transcripts"
  local legacy_log="$transcript_dir/unrelated.log"
  local marker

  mkdir -p "$transcript_dir"
  marker="$(calc_transcript_marker "$transcript_dir")"
  printf '%s\n' "$marker" >"$transcript_dir/.upkeeper-transcript-artifacts.marker"
  chmod 600 "$transcript_dir/.upkeeper-transcript-artifacts.marker"

  : >"$legacy_log"
  truncate -s "$((1024 * 1024 + 1))" "$legacy_log"

  run_prune_once "$transcript_dir"

  if [[ -f "$legacy_log" ]]; then
    fail "owned transcript directory was not pruned"
  fi
}

test_new_transcript_file_rejects_symlink_directory() {
  local transcript_dir="$TEST_TMP_ROOT/transcripts-src"
  local transcript_link="$TEST_TMP_ROOT/transcripts-link"
  local rc

  mkdir -p "$transcript_dir"
  ln -s "$transcript_dir" "$transcript_link"

  expected_negative_fixture_begin "transcript_artifacts.symlink_directory"
  run_new_transcript_file "$transcript_link"
  expected_negative_fixture_end "transcript_artifacts.symlink_directory"
  rc="$NEW_TRANSCRIPT_FILE_RC"

  [[ "$rc" != "0" ]] || fail "new transcript file accepted a symlink directory"
}

test_new_transcript_file_rejects_non_directory() {
  local transcript_dir="$TEST_TMP_ROOT/transcripts-file"
  local rc

  printf 'not-a-directory' >"$transcript_dir"

  expected_negative_fixture_begin "transcript_artifacts.non_directory"
  run_new_transcript_file "$transcript_dir"
  expected_negative_fixture_end "transcript_artifacts.non_directory"
  rc="$NEW_TRANSCRIPT_FILE_RC"

  [[ "$rc" != "0" ]] || fail "new transcript file accepted a non-directory transcript path"
}

test_new_transcript_file_repairs_owned_directory_mode() {
  local transcript_dir="$TEST_TMP_ROOT/transcripts-no-write"
  local mode
  local rc

  mkdir -p "$transcript_dir"
  chmod 555 "$transcript_dir"

  run_new_transcript_file "$transcript_dir"
  rc="$NEW_TRANSCRIPT_FILE_RC"

  [[ "$rc" == "0" ]] || fail "new transcript file rejected an owner-repairable directory mode"
  [[ -f "$NEW_TRANSCRIPT_FILE" ]] || fail "new transcript file was not created after repairing directory mode"
  mode="$(stat -Lc '%a' -- "$transcript_dir" 2>/dev/null || printf '')"
  [[ "$mode" == "700" ]] || fail "new transcript file did not repair directory mode to 700"
}

test_transcript_prune_skips_unowned_directory
test_transcript_prune_allows_owned_directory
test_new_transcript_file_rejects_symlink_directory
test_new_transcript_file_rejects_non_directory
test_new_transcript_file_repairs_owned_directory_mode

printf 'transcript_artifacts_test: ok\n'
