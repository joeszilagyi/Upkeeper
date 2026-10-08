#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
TOOLS_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
ROOT_DIR="$(cd -- "$TOOLS_DIR/.." && pwd)"

MODE="validate"
BASE_REF=""
HEAD_REF="HEAD"
PATHS_FROM=""
ALLOW_EMPTY=0

usage() {
  cat <<'USAGE'
Usage: tools/docs_only_fast_path.sh [--validate|--classify-only] [--base REF] [--head REF] [--paths-from FILE] [--allow-empty]

Classify and validate the narrow docs-only edit path without backend Codex,
GitHub CLI, GitHub polling, or network fetches. The classifier also reports
broader low-risk path sets so CI can skip the full validator for mechanical
config, shell, test, and tool edits.

Modes:
  --validate       Require a docs-only change and run the local docs fast path.
  --classify-only  Print docs_only/low_risk/scope metadata and exit without
                   validation.

Inputs:
  --base REF       Compare REF to --head for committed branch changes.
  --head REF       Compare --base to REF. Default: HEAD.
  --paths-from FILE
                   Read changed paths from FILE instead of asking git.
  --allow-empty    Permit an empty path set.

The validation path runs:
  tools/check_public_docs.sh --quick
  tools/validate_upkeeper.sh --smoke
  git diff --check
USAGE
}

fail() {
  printf 'docs_only_fast_path: ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf 'docs_only_fast_path: %s\n' "$*" >&2
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --validate)
      MODE="validate"
      ;;
    --classify-only)
      MODE="classify"
      ;;
    --base)
      [[ "$#" -ge 2 ]] || fail "--base needs a value"
      BASE_REF="$2"
      shift
      ;;
    --head)
      [[ "$#" -ge 2 ]] || fail "--head needs a value"
      HEAD_REF="$2"
      shift
      ;;
    --paths-from)
      [[ "$#" -ge 2 ]] || fail "--paths-from needs a value"
      PATHS_FROM="$2"
      shift
      ;;
    --allow-empty)
      ALLOW_EMPTY=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

cd "$ROOT_DIR"
source "$ROOT_DIR/lib/upkeeper/change_scope.bash"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  fail "not a Git worktree: $ROOT_DIR"

append_changed_paths_from_git() {
  local path_file="$1"
  local base_ref="$2"
  local head_ref="$3"
  local merge_base

  if [[ -n "$base_ref" ]]; then
    git rev-parse --verify "$base_ref^{commit}" >/dev/null 2>&1 ||
      fail "base ref is not available locally: $base_ref"
    git rev-parse --verify "$head_ref^{commit}" >/dev/null 2>&1 ||
      fail "head ref is not available locally: $head_ref"
    git diff --name-only "$base_ref" "$head_ref" >>"$path_file"
    return 0
  fi

  if git rev-parse --verify "origin/main^{commit}" >/dev/null 2>&1; then
    merge_base="$(git merge-base HEAD origin/main 2>/dev/null || true)"
    if [[ -n "$merge_base" ]]; then
      git diff --name-only "$merge_base" HEAD >>"$path_file"
    fi
  fi

  git diff --name-only --cached >>"$path_file"
  git diff --name-only >>"$path_file"
  git ls-files --others --exclude-standard >>"$path_file"
}

check_diff_whitespace() {
  local base_ref="$1"
  local head_ref="$2"
  local merge_base

  if [[ -n "$base_ref" ]]; then
    git diff --check "$base_ref" "$head_ref"
    return 0
  fi

  if git rev-parse --verify "origin/main^{commit}" >/dev/null 2>&1; then
    merge_base="$(git merge-base HEAD origin/main 2>/dev/null || true)"
    if [[ -n "$merge_base" ]]; then
      git diff --check "$merge_base" HEAD
    fi
  fi

  git diff --check --cached
  git diff --check
}

tmp_dir="$(mktemp -d /tmp/upkeeper-docs-only.XXXXXX)"
trap 'rm -r "$tmp_dir" 2>/dev/null || true' EXIT
all_paths_file="$tmp_dir/paths.all"
changed_paths_file="$tmp_dir/paths.changed"
non_docs_file="$tmp_dir/paths.non-docs"
non_low_risk_file="$tmp_dir/paths.non-low-risk"
: >"$all_paths_file"
: >"$changed_paths_file"
: >"$non_docs_file"
: >"$non_low_risk_file"

if [[ -n "$PATHS_FROM" ]]; then
  [[ -r "$PATHS_FROM" ]] || fail "cannot read paths file: $PATHS_FROM"
  sed '/^[[:space:]]*$/d' "$PATHS_FROM" >>"$all_paths_file"
else
  append_changed_paths_from_git "$all_paths_file" "$BASE_REF" "$HEAD_REF"
fi

sort -u "$all_paths_file" >"$changed_paths_file"

while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  if ! upkeeper_change_scope_path_is_docs_only "$path"; then
    printf '%s\n' "$path" >>"$non_docs_file"
  fi
  if ! upkeeper_change_scope_path_is_low_risk "$path"; then
    printf '%s\n' "$path" >>"$non_low_risk_file"
  fi
done <"$changed_paths_file"

changed_count="$(wc -l <"$changed_paths_file" | tr -d ' ')"
non_docs_count="$(wc -l <"$non_docs_file" | tr -d ' ')"
non_low_risk_count="$(wc -l <"$non_low_risk_file" | tr -d ' ')"
docs_only=0
low_risk=0
scope="full"
if [[ "$changed_count" -gt 0 && "$non_low_risk_count" == "0" ]]; then
  low_risk=1
  scope="low-risk"
fi
if [[ "$changed_count" -gt 0 && "$non_docs_count" == "0" ]]; then
  docs_only=1
  low_risk=1
  scope="docs-only"
fi
if [[ "$changed_count" == "0" && "$ALLOW_EMPTY" == "1" ]]; then
  docs_only=1
  low_risk=1
  scope="docs-only"
fi

printf 'scope_known=1\n'
printf 'scope=%s\n' "$scope"
printf 'docs_only=%s\n' "$docs_only"
printf 'low_risk=%s\n' "$low_risk"
printf 'changed_count=%s\n' "$changed_count"
printf 'non_docs_count=%s\n' "$non_docs_count"
printf 'non_low_risk_count=%s\n' "$non_low_risk_count"
if [[ "$non_docs_count" != "0" ]]; then
  sed 's/^/non_doc_path=/' "$non_docs_file"
fi
if [[ "$non_low_risk_count" != "0" ]]; then
  sed 's/^/non_low_risk_path=/' "$non_low_risk_file"
fi

if [[ "$MODE" == "classify" ]]; then
  exit 0
fi

if [[ "$docs_only" != "1" ]]; then
  if [[ "$changed_count" == "0" ]]; then
    fail "no changed docs paths found; pass --allow-empty only for an intentional docs fast-path smoke"
  fi
  fail "change is not docs-only; use the broader validation path"
fi

log "running public documentation check"
tools/check_public_docs.sh --quick
log "running smoke validation"
tools/validate_upkeeper.sh --smoke
log "checking diff whitespace"
check_diff_whitespace "$BASE_REF" "$HEAD_REF"
log "docs-only fast path passed"
