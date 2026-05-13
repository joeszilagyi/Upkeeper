#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
TOOLS_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
UPKEEPER_IMPLEMENTATION_DIR="$(cd -- "$TOOLS_DIR/.." && pwd)"
UPKEEPER_MODULE_DIR="$UPKEEPER_IMPLEMENTATION_DIR/lib/upkeeper"

usage() {
  cat <<'USAGE'
Usage: tools/upkeeper_precontact_restore.sh --repo-root=PATH --backup-id=ID [--identity=PATH] [--restore-to=RELATIVE_PATH] [--vault-root=PATH]

Restore one Upkeeper pre-contact backup by opaque backup id.

Defaults restore to the original selected relative path. Age-encrypted backups
require --identity=PATH or UPKEEPER_PRECONTACT_BACKUP_AGE_IDENTITY. The restore
verifies the stored content fingerprint before replacing the destination.
USAGE
}

fail() {
  printf 'upkeeper_precontact_restore: ERROR: %s\n' "$*" >&2
  exit 2
}

REPO_ROOT=""
BACKUP_ID=""
IDENTITY_PATH="${UPKEEPER_PRECONTACT_BACKUP_AGE_IDENTITY:-}"
RESTORE_TO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root=*)
      REPO_ROOT="${1#*=}"
      ;;
    --repo-root)
      fail "use --repo-root=PATH"
      ;;
    --backup-id=*)
      BACKUP_ID="${1#*=}"
      ;;
    --backup-id)
      fail "use --backup-id=ID"
      ;;
    --identity=*)
      IDENTITY_PATH="${1#*=}"
      ;;
    --identity)
      fail "use --identity=PATH"
      ;;
    --restore-to=*)
      RESTORE_TO="${1#*=}"
      ;;
    --restore-to)
      fail "use --restore-to=RELATIVE_PATH"
      ;;
    --vault-root=*)
      UPKEEPER_PRECONTACT_BACKUP_ROOT="${1#*=}"
      ;;
    --vault-root)
      fail "use --vault-root=PATH"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

[[ -n "$REPO_ROOT" ]] || fail "--repo-root=PATH is required"
[[ -n "$BACKUP_ID" ]] || fail "--backup-id=ID is required"

ROOT_DIR="$(python3 - "$REPO_ROOT" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
)"
[[ -d "$ROOT_DIR" ]] || fail "repo root is not a directory"

LOG_FILE="${CODEX_LOG_FILE:-$ROOT_DIR/Upkeeper.log}"
LOG_FILE_DIR="$(dirname -- "$LOG_FILE")"
CYCLE_ID="restore-$(date '+%Y%m%dT%H%M%S%z')-$$"
CYCLE_RUN_HASH="$(printf '%s' "$ROOT_DIR|$CYCLE_ID|$$" | git hash-object --stdin 2>/dev/null | cut -c1-16 || true)"
[[ -n "$CYCLE_RUN_HASH" ]] || CYCLE_RUN_HASH="${CYCLE_ID//[^[:alnum:]]/}"
CODEX_TERMINAL_VERBOSITY="${CODEX_TERMINAL_VERBOSITY:-basic}"
RUN_TMP_DIR=""
UPKEEPER_PRECONTACT_BACKUP_ROOT="${UPKEEPER_PRECONTACT_BACKUP_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/upkeeper/precontact-vault}"

mkdir -p -- "$LOG_FILE_DIR"

die() {
  printf 'upkeeper_precontact_restore: ERROR: %s\n' "$*" >&2
  exit 3
}

# shellcheck source=/dev/null
source "$UPKEEPER_MODULE_DIR/fallback_artifacts.bash"
# shellcheck source=/dev/null
source "$UPKEEPER_MODULE_DIR/runtime_foundation.bash"
# shellcheck source=/dev/null
source "$UPKEEPER_MODULE_DIR/transcript_artifacts.bash"
# shellcheck source=/dev/null
source "$UPKEEPER_MODULE_DIR/precontact_backup.bash"

if ! precontact_backup_restore_by_id "$BACKUP_ID" "$ROOT_DIR" "$IDENTITY_PATH" "$RESTORE_TO"; then
  fail "${PRECONTACT_BACKUP_LAST_REASON:-restore_failed}"
fi
