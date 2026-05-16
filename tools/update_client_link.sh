#!/usr/bin/env bash
set -euo pipefail

UPKEEPER_CLIENT_LINK_TOOL_NAME="update_client_link"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/upkeeper_client_link_common.sh"

usage() {
  cat <<'EOF'
Usage: tools/update_client_link.sh [--repo=PATH] [--link-name=NAME] [--force] [--replace-tracked]

Refresh an existing client Upkeeper symlink so it points at this central
checkout. Use install_client_link.sh when the link is absent.

Options:
  --repo=PATH         Client Git worktree to update. Defaults to current directory.
  --link-name=NAME    Repo-root link filename. Defaults to Upkeeper.sh.
  --force             Replace an existing stale symlink or non-directory path.
  --replace-tracked   Permit --force to replace a tracked client path.
EOF
}

REPO_ARG="."
LINK_NAME="$UPKEEPER_CLIENT_LINK_DEFAULT_NAME"
FORCE=0
REPLACE_TRACKED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo=*)
      REPO_ARG="${1#*=}"
      shift
      ;;
    --repo)
      [[ $# -ge 2 ]] || upkeeper_client_link_fail "missing value for --repo"
      REPO_ARG="$2"
      shift 2
      ;;
    --link-name=*)
      LINK_NAME="${1#*=}"
      shift
      ;;
    --link-name)
      [[ $# -ge 2 ]] || upkeeper_client_link_fail "missing value for --link-name"
      LINK_NAME="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --replace-tracked)
      REPLACE_TRACKED=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      upkeeper_client_link_fail "unknown argument: $1"
      ;;
  esac
done

upkeeper_client_link_require_command git
upkeeper_client_link_require_command grep
upkeeper_client_link_require_command ln
upkeeper_client_link_require_command mkdir
upkeeper_client_link_require_command python3
upkeeper_client_link_require_command rm
upkeeper_client_link_require_command touch
upkeeper_client_link_validate_central
upkeeper_client_link_validate_link_name "$LINK_NAME"

REPO_ROOT="$(upkeeper_client_link_git_root "$REPO_ARG")"
LINK_PATH="$REPO_ROOT/$LINK_NAME"

if upkeeper_client_link_points_to_central "$LINK_PATH"; then
  upkeeper_client_link_append_local_excludes "$REPO_ROOT" "$LINK_NAME"
  printf 'update_client_link: already current: %s -> %s\n' "$LINK_PATH" "$UPKEEPER_CLIENT_LINK_ROOT/Upkeeper"
  exit 0
fi

[[ -e "$LINK_PATH" || -L "$LINK_PATH" ]] ||
  upkeeper_client_link_fail "client link is missing; run install_client_link.sh first: $LINK_PATH"

upkeeper_client_link_prepare_replace "$REPO_ROOT" "$LINK_NAME" "$FORCE" "$REPLACE_TRACKED"
upkeeper_client_link_install_symlink "$REPO_ROOT" "$LINK_NAME"
upkeeper_client_link_append_local_excludes "$REPO_ROOT" "$LINK_NAME"

printf 'update_client_link: updated: %s -> %s\n' "$LINK_PATH" "$UPKEEPER_CLIENT_LINK_ROOT/Upkeeper"
printf 'update_client_link: verified local ignores in %s\n' "$(upkeeper_client_link_exclude_file "$REPO_ROOT")"
