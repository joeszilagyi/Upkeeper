#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck source=/dev/null
source "$ROOT_DIR/lib/upkeeper/change_scope.bash"

PATHS_FROM=""
OUTPUT=""

usage() {
  cat <<'USAGE'
Usage: tools/plan_batch_validation.sh [--paths-from FILE] [--output FILE]

Produce a deterministic JSON plan for local backlog batch validation.  Only the
explicit editorial-docs allowlist takes the reduced lane; every other path or
an uncertain path inventory selects the full fail-closed lane.
USAGE
}

fail() {
  printf 'plan_batch_validation: ERROR: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --paths-from)
      [[ -n "${2:-}" ]] || fail "--paths-from requires a value"
      PATHS_FROM="$2"
      shift 2
      ;;
    --output)
      [[ -n "${2:-}" ]] || fail "--output requires a value"
      OUTPUT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-batch-validation-plan.XXXXXX")"
trap 'rm -rf -- "$tmp_dir"' EXIT
paths_file="$tmp_dir/paths"
: >"$paths_file"

append_git_paths() {
  local merge_base

  if git rev-parse --verify 'origin/main^{commit}' >/dev/null 2>&1; then
    merge_base="$(git merge-base HEAD origin/main 2>/dev/null || true)"
    if [[ -n "$merge_base" ]]; then
      git diff --name-only "$merge_base" HEAD >>"$paths_file"
    else
      printf '%s\n' '__upkeeper_missing_merge_base__' >>"$paths_file"
    fi
  else
    printf '%s\n' '__upkeeper_missing_origin_main__' >>"$paths_file"
  fi
  git diff --name-only --cached >>"$paths_file"
  git diff --name-only >>"$paths_file"
  git ls-files --others --exclude-standard >>"$paths_file"
}

if [[ -n "$PATHS_FROM" ]]; then
  [[ -r "$PATHS_FROM" ]] || fail "cannot read paths file: $PATHS_FROM"
  sed '/^[[:space:]]*$/d' "$PATHS_FROM" >>"$paths_file"
else
  append_git_paths
fi

sort -u "$paths_file" -o "$paths_file"
head_ref="$(git rev-parse --verify HEAD 2>/dev/null || printf unknown)"
base_ref="$(git merge-base HEAD origin/main 2>/dev/null || printf unknown)"
classification="full"
reason="uncertain_or_operational_path"
phases='["shell_syntax","unit_tests","public_docs","diff_whitespace","quick_validator"]'
skipped='[]'
categories=()
all_docs=1
path_count=0

while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  path_count=$((path_count + 1))
  case "$path" in
    __upkeeper_missing_*)
      categories+=("missing_revision")
      all_docs=0
      reason="missing_required_revision"
      ;;
    tools/upkeeper_lattice.py|tools/upkeeper_lattice_core.py|tools/upkeeper_lib/*|lib/upkeeper/*lattice*|tests/lattice_*)
      categories+=("lattice")
      all_docs=0
      ;;
    orchestration/*|Upkeeper|ChimneySweep|FlameOn|lib/upkeeper/*|tools/run_validation_phases.sh|tools/validate_upkeeper.sh|.github/workflows/*|AGENTS.md)
      categories+=("control_plane")
      all_docs=0
      ;;
    prompts/*)
      categories+=("prompt")
      all_docs=0
      ;;
    Upkeeper.conf|configurations/*)
      categories+=("config")
      all_docs=0
      ;;
    tests/*)
      categories+=("test")
      all_docs=0
      ;;
    *.bash|*.sh)
      categories+=("shell")
      all_docs=0
      ;;
    *)
      if upkeeper_change_scope_path_is_docs_only "$path"; then
        categories+=("editorial_docs")
      else
        categories+=("other_runtime")
        all_docs=0
      fi
      ;;
  esac
done <"$paths_file"

if [[ "$path_count" -eq 0 ]]; then
  categories+=("no_changed_paths")
  all_docs=0
  reason="no_changed_paths"
elif [[ "$all_docs" == "1" ]]; then
  classification="editorial_docs"
  reason="explicit_editorial_docs_allowlist"
  phases='["public_docs","diff_whitespace"]'
  skipped='[{"phase":"shell_syntax","reason":"editorial_docs_allowlist"},{"phase":"unit_tests","reason":"editorial_docs_allowlist"},{"phase":"quick_validator","reason":"editorial_docs_allowlist"}]'
fi

python3 - "$paths_file" "$head_ref" "$base_ref" "$classification" "$reason" "$phases" "$skipped" "${BACKLOG_PER_BUG_VALIDATION_MODE:-light}" "${BACKLOG_SKIP_LOCAL_VALIDATION:-0}" "${categories[*]:-}" <<'PY' >"$tmp_dir/plan.json"
import json
import sys

(
    paths_file, head, base, classification, reason, phases_json, skipped_json,
    per_bug_mode, skip_local, categories_text,
) = sys.argv[1:]
paths = [line.rstrip("\n") for line in open(paths_file, encoding="utf-8") if line.strip()]
categories = sorted(set(filter(None, categories_text.split())))
print(json.dumps({
    "schema": 1,
    "record_type": "backlog_batch_validation_plan",
    "head": head,
    "base": base,
    "classification": classification,
    "reason": reason,
    "paths": paths,
    "path_categories": categories,
    "selected_phases": json.loads(phases_json),
    "skipped_phases": json.loads(skipped_json),
    "environment": {
        "BACKLOG_PER_BUG_VALIDATION_MODE": per_bug_mode,
        "BACKLOG_SKIP_LOCAL_VALIDATION": skip_local,
    },
}, sort_keys=True))
PY

if [[ -n "$OUTPUT" ]]; then
  parent="$(dirname -- "$OUTPUT")"
  mkdir -p -- "$parent"
  chmod 700 "$parent" 2>/dev/null || true
  install -m 600 "$tmp_dir/plan.json" "$OUTPUT"
fi
cat "$tmp_dir/plan.json"
