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
  chmod 0700 "$marker_dir"
  ln -s "$fixed_probe_target" "$marker_dir/.upkeeper-write-test.2669967"
  CODEX_HOME_DIR="$codex_home"

  output="$(codex_session_store_write_check || true)"
  [[ "$output" == "ok" ]] || fail "session store write check failed: $output"
  [[ -L "$marker_dir/.upkeeper-write-test.2669967" ]] || fail "old fixed-name probe symlink was removed"
  [[ "$(cat "$fixed_probe_target")" == "preserve" ]] || fail "old fixed-name probe symlink target was truncated"
}

test_codex_session_store_write_check_rejects_weak_session_dir() {
  local codex_home marker_dir output status

  codex_home="$TEST_TMP_ROOT/weak-mode-codex-home"
  marker_dir="$codex_home/sessions"
  mkdir -p "$marker_dir"
  chmod 0777 "$marker_dir"
  CODEX_HOME_DIR="$codex_home"

  set +e
  output="$(codex_session_store_write_check)"
  status=$?
  set -e

  [[ "$status" -eq 1 ]] || fail "weak-mode session store exited $status, expected 1"
  [[ "$output" == unsafe_permissions:* ]] || fail "weak-mode session store returned unexpected output: $output"
  [[ "$(stat -c '%a' "$marker_dir")" == "777" ]] || fail "weak-mode session store permissions were modified"
  if compgen -G "$marker_dir/.upkeeper-write-test.*" >/dev/null; then
    fail "weak-mode session store was probed after rejection"
  fi
}

test_codex_session_store_write_check_creates_missing_session_dir_private() {
  local codex_home marker_dir output

  codex_home="$TEST_TMP_ROOT/missing-session-codex-home"
  marker_dir="$codex_home/sessions"
  CODEX_HOME_DIR="$codex_home"

  output="$(
    umask 002
    codex_session_store_write_check
  )"

  [[ "$output" == "ok" ]] || fail "missing session store creation failed: $output"
  [[ -d "$marker_dir" ]] || fail "missing session store was not created"
  [[ "$(stat -c '%a' "$marker_dir")" == "700" ]] || fail "missing session store was not created private"
}

test_codex_session_store_write_check_uses_random_probe_name
test_codex_session_store_write_check_rejects_weak_session_dir
test_codex_session_store_write_check_creates_missing_session_dir_private
printf 'ok - session_store_preflight\n'
