#!/usr/bin/env bash
set -euo pipefail

UPKEEPER_CLIENT_LINK_TOOL_NAME="uninstall_client_link"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/upkeeper_client_link_common.sh"

usage() {
  cat <<'EOF'
Usage: tools/uninstall_client_link.sh [--repo=PATH] [--link-name=NAME] [--force]

Remove a repo-local Upkeeper symlink that points at this central checkout.

The helper intentionally leaves .git/info/exclude entries in place because they
are harmless local safeguards and may protect future reinstalls.

Options:
  --repo=PATH         Client Git worktree to update. Defaults to current directory.
  --link-name=NAME    Repo-root link filename. Defaults to Upkeeper.sh.
  --force             Remove a symlink even when it points somewhere else.
EOF
}

REPO_ARG="."
LINK_NAME="$UPKEEPER_CLIENT_LINK_DEFAULT_NAME"
FORCE=0

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
upkeeper_client_link_require_command python3
upkeeper_client_link_require_command rm
upkeeper_client_link_validate_central
upkeeper_client_link_validate_link_name "$LINK_NAME"

REPO_ROOT="$(upkeeper_client_link_git_root "$REPO_ARG")"
LINK_PATH="$REPO_ROOT/$LINK_NAME"

if [[ ! -e "$LINK_PATH" && ! -L "$LINK_PATH" ]]; then
  printf 'uninstall_client_link: already absent: %s\n' "$LINK_PATH"
  exit 0
fi

if upkeeper_client_link_points_to_central "$LINK_PATH"; then
  rm -f -- "$LINK_PATH"
  printf 'uninstall_client_link: removed: %s\n' "$LINK_PATH"
  exit 0
fi

if [[ -L "$LINK_PATH" && "$FORCE" == "1" ]]; then
  rm -f -- "$LINK_PATH"
  printf 'uninstall_client_link: removed stale symlink: %s\n' "$LINK_PATH"
  exit 0
fi

[[ -L "$LINK_PATH" ]] ||
  upkeeper_client_link_fail "refusing to delete non-symlink client path: $LINK_PATH"
upkeeper_client_link_fail "refusing to remove symlink that does not point at central Upkeeper without --force: $LINK_PATH"
