#!/usr/bin/env bash
# Parse shell inputs; never source or execute them. Requires Bash and Git.
set -euo pipefail

fail() {
  printf 'check_shell_syntax: ERROR: %s\n' "$*" >&2
  exit 2
}

parse_file() {
  local path="$1" parent="$1" rc
  # Neither file nor directory symlinks may redirect the syntax inventory.
  while [[ "$parent" != . && "$parent" != / ]]; do
    [[ ! -L "$parent" ]] || fail "symlink input is not supported: $(printf %q "$path")"
    [[ "$parent" == */* ]] || break
    parent="${parent%/*}"
    [[ -n "$parent" ]] || parent=/
  done
  [[ -f "$path" && -r "$path" ]] || fail "missing/nonregular/unreadable input: $(printf %q "$path")"
  if env -u BASH_ENV -u ENV bash --noprofile --norc -n -- "$path"; then
    return 0
  else
    rc=$?
    printf 'check_shell_syntax: FAIL file=%q rc=%s\n' "$path" "$rc" >&2
    return "$rc"
  fi
}

if [[ "${1:-}" == --files ]]; then
  shift
  [[ $# -gt 0 ]] || fail '--files requires at least one file (empty groups are errors)'
  for path in "$@"; do
    parse_file "$path" || exit $?
  done
  exit 0
fi
[[ $# -eq 0 ]] || fail 'usage: tools/check_shell_syntax.sh [--files FILE ...]'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
git rev-parse --is-inside-work-tree >/dev/null || fail 'a Git checkout is required'

# Anchors remain required even if removed from the index. Other intentional
# staged deletions leave the inventory; unstaged deletions remain and fail.
for path in Upkeeper ChimneySweep FlameOn Upkeeper.conf configurations/default.conf; do
  parse_file "$path" || exit $?
done

# Git supplies NUL-separated tracked and nonignored new paths, including nested
# helpers. Missing tracked files fail instead of disappearing from a glob.
# pipefail preserves inventory errors, not just the parser's status.
git ls-files -z --cached --others --exclude-standard -- '*.sh' '*.bash' '*.conf' |
{
  declare -A groups=()
  count=3
  while IFS= read -r -d '' path; do
    parse_file "$path" || exit $?
    groups["${path%%/*}"]=1
    count=$((count + 1))
  done
  for group in completions configurations lib tools tests testruns orchestration launcher_examples; do
    [[ "${groups[$group]:-0}" == 1 ]] || fail "required shell group is empty: $group"
  done
  printf 'check_shell_syntax: parsed=%s\n' "$count"
}
