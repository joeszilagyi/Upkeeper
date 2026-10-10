#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-batch-validation-plan-test.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'batch_validation_plan_test: ERROR: %s\n' "$*" >&2
  exit 1
}

plan_for_paths() {
  local name="$1"
  shift
  local paths="$TEST_ROOT/$name.paths"

  printf '%s\n' "$@" >"$paths"
  "$ROOT_DIR/tools/plan_batch_validation.sh" --paths-from "$paths"
}

assert_plan() {
  local output="$1" expected_class="$2" expected_phase="$3" expected_skip="$4"

  jq -e --arg classification "$expected_class" --arg phase "$expected_phase" --arg skip "$expected_skip" '
    .schema == 1 and .record_type == "backlog_batch_validation_plan" and
    .classification == $classification and (.selected_phases | index($phase)) != null and
    (.skipped_phases | map(.phase) | index($skip)) != null
  ' <<<"$output" >/dev/null || fail "unexpected validation plan: $output"
}

docs_plan="$(plan_for_paths docs README.md docs/roadmap.md change_notes_2026.md)"
assert_plan "$docs_plan" editorial_docs public_docs unit_tests
jq -e '.selected_phases == ["public_docs", "diff_whitespace"] and .reason == "explicit_editorial_docs_allowlist"' <<<"$docs_plan" >/dev/null ||
  fail "editorial docs did not select the reduced deterministic lane"

for category_path in \
  'orchestration/backlog.sh' \
  'tools/upkeeper_lattice_core.py' \
  'prompts/default-review.md' \
  'Upkeeper.conf' \
  'tests/client_link_tools_test.bash' \
  'completions/upkeeper.bash' \
  'unknown/new-file.txt'; do
  output="$(plan_for_paths "$(tr '/.' '__' <<<"$category_path")" "$category_path")"
  jq -e '.classification == "full" and (.selected_phases | index("unit_tests")) != null and (.selected_phases | index("quick_validator")) != null and .skipped_phases == []' <<<"$output" >/dev/null ||
    fail "operational or unknown path did not fail closed: $category_path"
done

missing_plan="$(plan_for_paths missing __upkeeper_missing_merge_base__)"
jq -e '.classification == "full" and .reason == "missing_required_revision" and (.path_categories | index("missing_revision")) != null' <<<"$missing_plan" >/dev/null ||
  fail "missing revision did not select the full fail-closed lane"

empty_paths="$TEST_ROOT/empty.paths"
: >"$empty_paths"
empty_plan="$($ROOT_DIR/tools/plan_batch_validation.sh --paths-from "$empty_paths")"
jq -e '.classification == "full" and .reason == "no_changed_paths" and (.path_categories | index("no_changed_paths")) != null' <<<"$empty_plan" >/dev/null ||
  fail "empty path inventory did not select full validation"

printf 'batch_validation_plan_test: ok\n'
