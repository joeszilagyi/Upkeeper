#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "$ROOT_DIR/lib/upkeeper/session_store_preflight.bash"

TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-session-store-test.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_codex_session_store_write_check_uses_random_probe_name() {
  local codex_home marker_dir fixed_probe_target output

  codex_home="$TEST_TMP_ROOT/codex-home"
  marker_dir="$codex_home/sessions"
  fixed_probe_target="$TEST_TMP_ROOT/fixed-probe-target.txt"
  printf 'preserve\n' >"$fixed_probe_target"
  mkdir -p "$marker_dir"
  ln -s "$fixed_probe_target" "$marker_dir/.upkeeper-write-test.2669967"
  CODEX_HOME_DIR="$codex_home"

  output="$(codex_session_store_write_check || true)"
  [[ "$output" == "ok" ]] || fail "session store write check failed: $output"
  [[ -L "$marker_dir/.upkeeper-write-test.2669967" ]] || fail "old fixed-name probe symlink was removed"
  [[ "$(cat "$fixed_probe_target")" == "preserve" ]] || fail "old fixed-name probe symlink target was truncated"
}

test_codex_session_store_write_check_uses_random_probe_name
printf 'ok - session_store_preflight\n'
