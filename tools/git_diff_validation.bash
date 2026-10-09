#!/usr/bin/env bash

# Shared committed and local whitespace validation.  Callers own shell
# strictness; this helper returns the underlying Git failure status.

upkeeper_git_diff_require_commit() {
  local ref="$1"
  local label="$2"

  git rev-parse --verify "$ref^{commit}" >/dev/null 2>&1 || {
    printf 'git_diff_validation: ERROR: %s ref is unavailable: %s\n' "$label" "$ref" >&2
    return 2
  }
}

upkeeper_git_diff_default_base_ref() {
  local merge_base

  git rev-parse --verify "origin/main^{commit}" >/dev/null 2>&1 || return 0
  merge_base="$(git merge-base HEAD origin/main 2>/dev/null || true)"
  [[ -n "$merge_base" ]] || {
    printf 'git_diff_validation: ERROR: cannot find a merge base for HEAD and origin/main\n' >&2
    return 2
  }
  printf '%s\n' "$merge_base"
}

upkeeper_git_diff_check_whitespace() {
  local base_ref="${1:-}"
  local head_ref="${2:-HEAD}"
  local check_local="${3:-1}"
  local rc

  if [[ -z "$base_ref" ]]; then
    base_ref="$(upkeeper_git_diff_default_base_ref)" || {
      rc=$?
      return "$rc"
    }
  fi

  if [[ -n "$base_ref" ]]; then
    upkeeper_git_diff_require_commit "$base_ref" base || return $?
    upkeeper_git_diff_require_commit "$head_ref" head || return $?
    git diff --check "$base_ref" "$head_ref" || return $?
  fi

  [[ "$check_local" == "1" ]] || return 0
  git diff --check --cached || return $?
  git diff --check
}
