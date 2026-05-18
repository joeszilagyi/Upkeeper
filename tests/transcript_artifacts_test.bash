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

test_transcript_prune_skips_unowned_directory
test_transcript_prune_allows_owned_directory

printf 'transcript_artifacts_test: ok\n'
