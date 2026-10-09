#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/upkeeper/change_scope.bash"
cd "$ROOT_DIR"

TEST_ROOT="$(mktemp -d /tmp/upkeeper-change-scope-test.XXXXXX)"
trap 'rm -r "$TEST_ROOT"' EXIT

fail() {
  printf 'change_scope_test: ERROR: %s\n' "$*" >&2
  exit 1
}

for path in README.md change_notes_2026.md docs/known-issues.md docs/prd.md docs/roadmap.md; do
  upkeeper_change_scope_path_is_docs_only "$path" || fail "editorial path was not docs-only: $path"
  upkeeper_change_scope_path_is_low_risk "$path" || fail "editorial path was not low-risk: $path"
done

for path in \
  AGENTS.md \
  prompts/default-review.md \
  Upkeeper.conf \
  configurations/default.conf \
  tools/run_tests.sh \
  tools/run_validation_phases.sh \
  .github/workflows/ci.yml \
  tests/client_link_tools_test.bash \
  docs/security.md; do
  if upkeeper_change_scope_path_is_docs_only "$path"; then
    fail "operational path was docs-only: $path"
  fi
  if upkeeper_change_scope_path_is_low_risk "$path"; then
    fail "operational path was low-risk: $path"
  fi
done

printf 'README.md\ndocs/roadmap.md\n' >"$TEST_ROOT/editorial.paths"
editorial_output="$(tools/docs_only_fast_path.sh --classify-only --paths-from "$TEST_ROOT/editorial.paths")"
grep -Fq 'scope=docs-only' <<<"$editorial_output" || fail "editorial paths did not report docs-only scope"
grep -Fq 'docs_only=1' <<<"$editorial_output" || fail "editorial paths did not report docs_only=1"
grep -Fq 'low_risk=1' <<<"$editorial_output" || fail "editorial paths did not report low_risk=1"
grep -Fq 'validation_gate=docs-only' <<<"$editorial_output" || fail "editorial paths did not select docs-only gate"

printf 'AGENTS.md\ntools/run_tests.sh\n' >"$TEST_ROOT/operational.paths"
operational_output="$(tools/docs_only_fast_path.sh --classify-only --paths-from "$TEST_ROOT/operational.paths")"
grep -Fq 'scope=full' <<<"$operational_output" || fail "operational paths did not report full scope"
grep -Fq 'docs_only=0' <<<"$operational_output" || fail "operational paths did not report docs_only=0"
grep -Fq 'low_risk=0' <<<"$operational_output" || fail "operational paths did not report low_risk=0"
grep -Fq 'validation_gate=full' <<<"$operational_output" || fail "operational paths did not select full gate"
grep -Fq 'non_low_risk_path=AGENTS.md' <<<"$operational_output" ||
  fail "operational diagnostics did not identify AGENTS.md"

editorial_authority="$(BACKLOG_SOURCE_ONLY=1 bash -c '
  set -euo pipefail
  cd "$1"
  source ./orchestration/backlog.sh
  backlog_changed_paths_for_head() { printf "%s\\n" README.md docs/roadmap.md; }
  backlog_validation_authority_for_head
' bash "$ROOT_DIR")"
[[ "$editorial_authority" == $'low-risk\tlocal-green-async-ci\texplicit-editorial-docs' ]] ||
  fail "editorial backlog authority was not the limited async policy: $editorial_authority"

operational_authority="$(BACKLOG_SOURCE_ONLY=1 bash -c '
  set -euo pipefail
  cd "$1"
  source ./orchestration/backlog.sh
  backlog_changed_paths_for_head() { printf "%s\\n" AGENTS.md tools/run_tests.sh; }
  backlog_validation_authority_for_head
' bash "$ROOT_DIR")"
[[ "$operational_authority" == $'normal\tblocking-ci\tsource-or-mixed-change' ]] ||
  fail "operational backlog authority was not blocking CI: $operational_authority"

fallback_root="$TEST_ROOT/backlog-fallback"
mkdir -p "$fallback_root/orchestration" "$fallback_root/lib/upkeeper"
cp "$ROOT_DIR/orchestration/backlog.sh" "$fallback_root/orchestration/backlog.sh"
cp "$ROOT_DIR/lib/upkeeper/runtime_format_json.bash" "$fallback_root/lib/upkeeper/runtime_format_json.bash"
fallback_authority="$(BACKLOG_SOURCE_ONLY=1 bash -c '
  set -euo pipefail
  source "$1/orchestration/backlog.sh"
  backlog_changed_paths_for_head() { printf "%s\\n" prompts/default-review.md Upkeeper.conf tests/client_link_tools_test.bash; }
  backlog_validation_authority_for_head
' bash "$fallback_root")"
[[ "$fallback_authority" == $'normal\tblocking-ci\tsource-or-mixed-change' ]] ||
  fail "backlog fallback classifier diverged from the blocking policy: $fallback_authority"

grep -Fq 'Report selected validation gate' "$ROOT_DIR/.github/workflows/ci.yml" ||
  fail "CI does not expose its selected validation gate"
grep -Fq "steps.scope.outputs.validation_gate == 'full'" "$ROOT_DIR/.github/workflows/ci.yml" ||
  fail "CI does not couple full validation to the classifier gate"

printf 'change_scope_test: ok\n'
