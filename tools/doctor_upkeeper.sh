#!/usr/bin/env bash
set -euo pipefail

UPKEEPER_CLIENT_LINK_TOOL_NAME="doctor_upkeeper"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/upkeeper_client_link_common.sh"

usage() {
  cat <<'EOF'
Usage: tools/doctor_upkeeper.sh [--repo=PATH] [--link-name=NAME] [--skip-deps] [--skip-dry-run]

Validate a client repo's central Upkeeper symlink without launching real Codex
backend work.

Checks:
  - central Upkeeper entrypoint, module directory, prompt, and validator exist
  - client repo is a Git worktree
  - repo-root link is a symlink to this central Upkeeper entrypoint
  - local Upkeeper artifacts are ignored by the client
  - central dependency report passes unless --skip-deps is used
  - UPKEEPER_DRY_RUN=1 client startup succeeds unless --skip-dry-run is used
EOF
}

REPO_ARG="."
LINK_NAME="$UPKEEPER_CLIENT_LINK_DEFAULT_NAME"
SKIP_DEPS=0
SKIP_DRY_RUN=0

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
    --skip-deps)
      SKIP_DEPS=1
      shift
      ;;
    --skip-dry-run)
      SKIP_DRY_RUN=1
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
upkeeper_client_link_require_command mktemp
upkeeper_client_link_require_command python3
upkeeper_client_link_require_command sed
upkeeper_client_link_validate_central
upkeeper_client_link_validate_link_name "$LINK_NAME"

REPO_ROOT="$(upkeeper_client_link_git_root "$REPO_ARG")"
LINK_PATH="$REPO_ROOT/$LINK_NAME"

upkeeper_client_link_points_to_central "$LINK_PATH" ||
  upkeeper_client_link_fail "client link does not point at this central Upkeeper: $LINK_PATH"
upkeeper_client_link_require_local_excludes "$REPO_ROOT" "$LINK_NAME"

printf 'doctor_upkeeper: central checkout: %s\n' "$UPKEEPER_CLIENT_LINK_ROOT"
printf 'doctor_upkeeper: client repo: %s\n' "$REPO_ROOT"
printf 'doctor_upkeeper: symlink ok: %s -> %s\n' "$LINK_PATH" "$UPKEEPER_CLIENT_LINK_ROOT/Upkeeper"
printf 'doctor_upkeeper: local ignores ok\n'

if [[ "$SKIP_DEPS" != "1" ]]; then
  "$UPKEEPER_CLIENT_LINK_ROOT/tools/validate_upkeeper.sh" --deps >/dev/null
  printf 'doctor_upkeeper: dependency report ok\n'
fi

if [[ "$SKIP_DRY_RUN" != "1" ]]; then
  DOCTOR_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-client-doctor.XXXXXX")"
  trap 'rm -r "$DOCTOR_TMP_DIR" 2>/dev/null || true' EXIT
  DOCTOR_STDOUT="$DOCTOR_TMP_DIR/stdout.txt"
  DOCTOR_STDERR="$DOCTOR_TMP_DIR/stderr.txt"
  (
    cd "$REPO_ROOT"
    UPKEEPER_DRY_RUN=1 \
      CODEX_QUOTA_GUARDRAIL_BYPASS=1 \
      CODEX_QUOTA_COOLDOWN_BYPASS=1 \
      UPKEEPER_PRECONTACT_BACKUP_MODE=off \
      UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0 \
      UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1 \
      "./$LINK_NAME" >"$DOCTOR_STDOUT" 2>"$DOCTOR_STDERR"
  ) || {
    rc="$?"
    printf 'doctor_upkeeper: dry-run stdout follows\n' >&2
    sed -n '1,120p' "$DOCTOR_STDOUT" >&2 2>/dev/null || true
    printf 'doctor_upkeeper: dry-run stderr follows\n' >&2
    sed -n '1,120p' "$DOCTOR_STDERR" >&2 2>/dev/null || true
    upkeeper_client_link_fail "client dry-run failed with exit $rc"
  }
  printf 'doctor_upkeeper: dry-run startup ok\n'
fi

printf 'doctor_upkeeper: ok\n'
