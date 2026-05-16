#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-client-link-test.XXXXXX")"
trap 'rm -r "$TEST_TMP_ROOT" 2>/dev/null || true' EXIT
chmod 700 "$TEST_TMP_ROOT"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

resolve_abs() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).resolve(strict=False))
PY
}

init_client_repo() {
  local repo="$1"

  mkdir -p "$repo"
  chmod 700 "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "client-link-test@example.invalid"
  git -C "$repo" config user.name "Client Link Test"
  printf '#!/usr/bin/env bash\nprintf client-tool\\n\n' >"$repo/client-tool.sh"
  chmod +x "$repo/client-tool.sh"
  git -C "$repo" add client-tool.sh
  git -C "$repo" commit -qm "add client tool"
}

install_fake_age() {
  mkdir -p "$TEST_TMP_ROOT/bin"
  cat >"$TEST_TMP_ROOT/bin/age" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exit 0
SH
  chmod +x "$TEST_TMP_ROOT/bin/age"
}

assert_local_ignores() {
  local repo="$1"

  git -C "$repo" check-ignore --no-index -q -- Upkeeper.sh ||
    fail "Upkeeper.sh was not ignored"
  git -C "$repo" check-ignore --no-index -q -- Upkeeper.log ||
    fail "Upkeeper.log was not ignored"
  git -C "$repo" check-ignore --no-index -q -- runtime/probe ||
    fail "runtime/ was not ignored"
  git -C "$repo" check-ignore --no-index -q -- docs/scripts/upkeeper.md ||
    fail "docs/scripts/upkeeper.md was not ignored"
}

test_install_and_doctor_client_link() {
  local repo="$TEST_TMP_ROOT/install-client"
  local link_target

  init_client_repo "$repo"
  install_fake_age

  "$PROJECT_ROOT/tools/install_client_link.sh" --repo="$repo" >/dev/null
  [[ -L "$repo/Upkeeper.sh" ]] || fail "install did not create Upkeeper.sh symlink"
  link_target="$(resolve_abs "$repo/Upkeeper.sh")"
  [[ "$link_target" == "$(resolve_abs "$PROJECT_ROOT/Upkeeper")" ]] ||
    fail "installed symlink target mismatch: $link_target"
  assert_local_ignores "$repo"

  PATH="$TEST_TMP_ROOT/bin:$PATH" \
    CODEX_HOME="$TEST_TMP_ROOT/missing-codex-home" \
    "$PROJECT_ROOT/tools/doctor_upkeeper.sh" --repo="$repo" >/dev/null
  "$PROJECT_ROOT/tools/install_client_link.sh" --repo="$repo" >/dev/null
  [[ -L "$repo/Upkeeper.sh" ]] || fail "idempotent reinstall removed symlink"
}

test_install_refuses_overwrite_without_force() {
  local repo="$TEST_TMP_ROOT/overwrite-client"
  local rc

  init_client_repo "$repo"
  printf 'old wrapper copy\n' >"$repo/Upkeeper.sh"

  set +e
  "$PROJECT_ROOT/tools/install_client_link.sh" --repo="$repo" >/dev/null 2>"$TEST_TMP_ROOT/install-refuse.err"
  rc="$?"
  set -e

  [[ "$rc" -ne 0 ]] || fail "install overwrote existing path without --force"
  grep -Fq "refusing to overwrite" "$TEST_TMP_ROOT/install-refuse.err" ||
    fail "install refusal did not explain overwrite guard"
  grep -Fq "old wrapper copy" "$repo/Upkeeper.sh" ||
    fail "install modified existing path after refusing"

  "$PROJECT_ROOT/tools/install_client_link.sh" --repo="$repo" --force >/dev/null
  [[ -L "$repo/Upkeeper.sh" ]] || fail "install --force did not replace untracked file"
}

test_update_requires_force_for_stale_symlink() {
  local repo="$TEST_TMP_ROOT/update-client"
  local stale_target="$TEST_TMP_ROOT/stale-upkeeper"
  local rc

  init_client_repo "$repo"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$stale_target"
  chmod +x "$stale_target"
  ln -s "$stale_target" "$repo/Upkeeper.sh"

  set +e
  "$PROJECT_ROOT/tools/update_client_link.sh" --repo="$repo" >/dev/null 2>"$TEST_TMP_ROOT/update-refuse.err"
  rc="$?"
  set -e

  [[ "$rc" -ne 0 ]] || fail "update replaced stale symlink without --force"
  grep -Fq "refusing to overwrite" "$TEST_TMP_ROOT/update-refuse.err" ||
    fail "update refusal did not explain force requirement"

  "$PROJECT_ROOT/tools/update_client_link.sh" --repo="$repo" --force >/dev/null
  [[ "$(resolve_abs "$repo/Upkeeper.sh")" == "$(resolve_abs "$PROJECT_ROOT/Upkeeper")" ]] ||
    fail "update --force did not point symlink at central Upkeeper"
}

test_uninstall_removes_only_safe_symlink() {
  local repo="$TEST_TMP_ROOT/uninstall-client"
  local rc

  init_client_repo "$repo"
  "$PROJECT_ROOT/tools/install_client_link.sh" --repo="$repo" >/dev/null
  "$PROJECT_ROOT/tools/uninstall_client_link.sh" --repo="$repo" >/dev/null
  [[ ! -e "$repo/Upkeeper.sh" && ! -L "$repo/Upkeeper.sh" ]] ||
    fail "uninstall did not remove central symlink"

  printf 'not a symlink\n' >"$repo/Upkeeper.sh"
  set +e
  "$PROJECT_ROOT/tools/uninstall_client_link.sh" --repo="$repo" >/dev/null 2>"$TEST_TMP_ROOT/uninstall-refuse.err"
  rc="$?"
  set -e

  [[ "$rc" -ne 0 ]] || fail "uninstall deleted non-symlink path"
  grep -Fq "refusing to delete non-symlink" "$TEST_TMP_ROOT/uninstall-refuse.err" ||
    fail "uninstall refusal did not explain non-symlink guard"
  grep -Fq "not a symlink" "$repo/Upkeeper.sh" ||
    fail "uninstall modified non-symlink path"
}

test_install_and_doctor_client_link
test_install_refuses_overwrite_without_force
test_update_requires_force_for_stale_symlink
test_uninstall_removes_only_safe_symlink

printf 'client_link_tools_test: ok\n'
