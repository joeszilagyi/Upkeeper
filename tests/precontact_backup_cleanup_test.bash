#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cleanup_root_record="$(mktemp "${TMPDIR:-/tmp}/upkeeper-precontact-cleanup-root.XXXXXX")"
trap 'rm -f -- "$cleanup_root_record"' EXIT

run_cleanup_case() {
  local test_group="$1"
  local expected_rc="$2"
  local cleanup_command cleanup_root rc

  : >"$cleanup_root_record"
  printf -v cleanup_command 'env UPKEEPER_PRECONTACT_TEST_GROUP=%q bash %q' \
    "$test_group" "$ROOT_DIR/tests/precontact_backup_test.bash"

  set +e
  timeout --kill-after=5s 10s \
    env UPKEEPER_PRECONTACT_TEST_CLEANUP_ROOT_RECORD="$cleanup_root_record" \
    script -qfec "$cleanup_command" /dev/null </dev/null
  rc=$?
  set -e

  if [[ "$expected_rc" == success ]]; then
    [[ "$rc" -eq 0 ]] || {
      printf 'precontact_backup_cleanup_test: successful cleanup exited %s\n' "$rc" >&2
      exit 1
    }
  else
    [[ "$rc" -ne 0 && "$rc" -ne 124 ]] || {
      printf 'precontact_backup_cleanup_test: failing cleanup exited %s\n' "$rc" >&2
      exit 1
    }
  fi

  cleanup_root="$(<"$cleanup_root_record")"
  [[ -n "$cleanup_root" && ! -e "$cleanup_root" ]] || {
    printf 'precontact_backup_cleanup_test: cleanup left read-only fixture root=%s\n' "$cleanup_root" >&2
    exit 1
  }
}

# The pseudo-terminal reproduces rm's write-protected-file prompt; stdin is
# closed so an interactive cleanup would block or leave its root behind.
run_cleanup_case cleanup success
run_cleanup_case cleanup-failure failure

printf 'precontact_backup_cleanup_test: ok\n'
