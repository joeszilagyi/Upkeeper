#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'upkeeper_client_link_common: source this helper from a client-link tool\n' >&2
  exit 2
fi

UPKEEPER_CLIENT_LINK_TOOLS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UPKEEPER_CLIENT_LINK_ROOT="$(cd -- "$UPKEEPER_CLIENT_LINK_TOOLS_DIR/.." && pwd)"
UPKEEPER_CLIENT_LINK_DEFAULT_NAME="Upkeeper.sh"

upkeeper_client_link_fail() {
  printf '%s: ERROR: %s\n' "${UPKEEPER_CLIENT_LINK_TOOL_NAME:-upkeeper_client_link}" "$*" >&2
  exit 2
}

upkeeper_client_link_require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 ||
    upkeeper_client_link_fail "required command missing: $command_name; see docs/dependencies.md"
}

upkeeper_client_link_resolve_abs() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
}

upkeeper_client_link_validate_central() {
  [[ -f "$UPKEEPER_CLIENT_LINK_ROOT/Upkeeper" ]] ||
    upkeeper_client_link_fail "central Upkeeper entrypoint missing: $UPKEEPER_CLIENT_LINK_ROOT/Upkeeper"
  [[ -r "$UPKEEPER_CLIENT_LINK_ROOT/Upkeeper" ]] ||
    upkeeper_client_link_fail "central Upkeeper entrypoint is not readable: $UPKEEPER_CLIENT_LINK_ROOT/Upkeeper"
  [[ -d "$UPKEEPER_CLIENT_LINK_ROOT/lib/upkeeper" ]] ||
    upkeeper_client_link_fail "central module directory missing: $UPKEEPER_CLIENT_LINK_ROOT/lib/upkeeper"
  [[ -s "$UPKEEPER_CLIENT_LINK_ROOT/prompts/default-review.md" ]] ||
    upkeeper_client_link_fail "central default prompt missing: $UPKEEPER_CLIENT_LINK_ROOT/prompts/default-review.md"
  [[ -x "$UPKEEPER_CLIENT_LINK_ROOT/tools/validate_upkeeper.sh" ]] ||
    upkeeper_client_link_fail "central validator is not executable: $UPKEEPER_CLIENT_LINK_ROOT/tools/validate_upkeeper.sh"
}

upkeeper_client_link_git_root() {
  local repo_arg="$1"
  local repo_abs

  repo_abs="$(upkeeper_client_link_resolve_abs "$repo_arg")"
  git -C "$repo_abs" rev-parse --show-toplevel 2>/dev/null ||
    upkeeper_client_link_fail "client path is not inside a Git worktree: $repo_arg"
}

upkeeper_client_link_validate_link_name() {
  local link_name="$1"

  [[ -n "$link_name" ]] || upkeeper_client_link_fail "link name must not be empty"
  [[ "$link_name" != /* ]] || upkeeper_client_link_fail "link name must be repo-relative: $link_name"
  [[ "$link_name" != */* ]] || upkeeper_client_link_fail "link name must be a root filename, not a path: $link_name"
  [[ "$link_name" != "." && "$link_name" != ".." ]] ||
    upkeeper_client_link_fail "link name must not be . or .."
  [[ "$link_name" != ".git" && "$link_name" != .git/* ]] ||
    upkeeper_client_link_fail "link name must not target Git control files"
  [[ "$link_name" != -* ]] || upkeeper_client_link_fail "link name must not start with '-': $link_name"
}

upkeeper_client_link_points_to_central() {
  local link_path="$1"
  local central_path="$UPKEEPER_CLIENT_LINK_ROOT/Upkeeper"
  local link_resolved central_resolved

  [[ -L "$link_path" ]] || return 1
  link_resolved="$(upkeeper_client_link_resolve_abs "$link_path")"
  central_resolved="$(upkeeper_client_link_resolve_abs "$central_path")"
  [[ "$link_resolved" == "$central_resolved" ]]
}

upkeeper_client_link_is_tracked() {
  local repo_root="$1"
  local link_name="$2"

  git -C "$repo_root" ls-files --error-unmatch -- "$link_name" >/dev/null 2>&1
}

upkeeper_client_link_exclude_file() {
  local repo_root="$1"
  local exclude_file

  exclude_file="$(git -C "$repo_root" rev-parse --git-path info/exclude)" ||
    upkeeper_client_link_fail "failed to resolve Git exclude path for $repo_root"
  if [[ "$exclude_file" != /* ]]; then
    exclude_file="$repo_root/$exclude_file"
  fi
  printf '%s\n' "$exclude_file"
}

upkeeper_client_link_append_local_excludes() {
  local repo_root="$1"
  local link_name="$2"
  local exclude_file entry

  exclude_file="$(upkeeper_client_link_exclude_file "$repo_root")"
  mkdir -p -- "$(dirname -- "$exclude_file")"
  touch "$exclude_file"

  for entry in "$link_name" Upkeeper.log runtime/ docs/scripts/upkeeper.md; do
    grep -Fxq "$entry" "$exclude_file" 2>/dev/null || printf '%s\n' "$entry" >>"$exclude_file"
  done
}

upkeeper_client_link_require_local_excludes() {
  local repo_root="$1"
  local link_name="$2"
  local entry check_path

  for entry in "$link_name" Upkeeper.log runtime/ docs/scripts/upkeeper.md; do
    check_path="$entry"
    if [[ "$entry" == "runtime/" ]]; then
      check_path="runtime/upkeeper-client-link-probe"
    fi
    (
      cd "$repo_root"
      git check-ignore --no-index -q -- "$check_path"
    ) || upkeeper_client_link_fail "client local artifact is not ignored: $entry"
  done
}

upkeeper_client_link_prepare_replace() {
  local repo_root="$1"
  local link_name="$2"
  local force="$3"
  local replace_tracked="$4"
  local link_path="$repo_root/$link_name"

  if [[ ! -e "$link_path" && ! -L "$link_path" ]]; then
    return 0
  fi

  [[ "$force" == "1" ]] ||
    upkeeper_client_link_fail "refusing to overwrite existing client path without --force: $link_path"
  if upkeeper_client_link_is_tracked "$repo_root" "$link_name" && [[ "$replace_tracked" != "1" ]]; then
    upkeeper_client_link_fail "refusing to replace tracked client path without --replace-tracked: $link_name"
  fi
  [[ ! -d "$link_path" || -L "$link_path" ]] ||
    upkeeper_client_link_fail "refusing to replace directory: $link_path"

  rm -f -- "$link_path"
}

upkeeper_client_link_install_symlink() {
  local repo_root="$1"
  local link_name="$2"
  local link_path="$repo_root/$link_name"

  ln -s "$UPKEEPER_CLIENT_LINK_ROOT/Upkeeper" "$link_path"
}
