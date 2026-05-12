#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$TEST_TMP_ROOT/bin"

cat >"$TEST_TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  case "${GH_SCENARIO:-clean}" in
    clean)
      printf '[]\n'
      ;;
    security)
      cat <<'JSON'
[
  {"number":10,"title":"Critical data integrity older but lower class","url":"https://example.invalid/10","createdAt":"2026-05-01T00:00:00Z","updatedAt":"2026-05-01T00:00:00Z","comments":0,"labels":[{"name":"bug"},{"name":"data-integrity"}]},
  {"number":50,"title":"High security older untouched","url":"https://example.invalid/50","createdAt":"2026-05-02T00:00:00Z","updatedAt":"2026-05-02T00:00:00Z","comments":0,"labels":[{"name":"bug"},{"name":"security"}]},
  {"number":51,"title":"High security newer untouched","url":"https://example.invalid/51","createdAt":"2026-05-03T00:00:00Z","updatedAt":"2026-05-03T00:00:00Z","comments":0,"labels":[{"name":"bug"},{"name":"security"}]}
]
JSON
      ;;
    data)
      cat <<'JSON'
[
  {"number":20,"title":"Medium data integrity older untouched","url":"https://example.invalid/20","createdAt":"2026-05-01T00:00:00Z","updatedAt":"2026-05-01T00:00:00Z","comments":0,"labels":[{"name":"data-integrity"}]},
  {"number":21,"title":"High data integrity newer untouched","url":"https://example.invalid/21","createdAt":"2026-05-02T00:00:00Z","updatedAt":"2026-05-02T00:00:00Z","comments":0,"labels":[{"name":"data-integrity"}]}
]
JSON
      ;;
    general)
      cat <<'JSON'
[
  {"number":30,"title":"High ordinary bug","url":"https://example.invalid/30","createdAt":"2026-05-01T00:00:00Z","updatedAt":"2026-05-01T00:00:00Z","comments":0,"labels":[{"name":"bug"}]},
  {"number":31,"title":"Medium Lattice containment bug","url":"https://example.invalid/31","createdAt":"2026-05-02T00:00:00Z","updatedAt":"2026-05-02T00:00:00Z","comments":0,"labels":[{"name":"bug"}]}
]
JSON
      ;;
    skipped)
      cat <<'JSON'
[
  {"number":40,"title":"High security blocked","url":"https://example.invalid/40","createdAt":"2026-05-01T00:00:00Z","updatedAt":"2026-05-01T00:00:00Z","comments":0,"labels":[{"name":"bug"},{"name":"security"},{"name":"blocked"}]}
]
JSON
      ;;
    *)
      printf 'unknown GH_SCENARIO=%s\n' "${GH_SCENARIO:-}" >&2
      exit 2
      ;;
  esac
  exit 0
fi

printf 'unexpected fake gh invocation: %s\n' "$*" >&2
exit 2
EOF
chmod +x "$TEST_TMP_ROOT/bin/gh"

cat >"$TEST_TMP_ROOT/bin/upkeeper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'BEGIN\n'
  printf '%s\n' "$@"
} >>"${CHIMNEYSWEEP_CAPTURE:?}"
EOF
chmod +x "$TEST_TMP_ROOT/bin/upkeeper"

run_chimneysweep() {
  PATH="$TEST_TMP_ROOT/bin:$PATH" \
    UPKEEPER_CMD="$TEST_TMP_ROOT/bin/upkeeper" \
    UPKEEPER_OBLIGATION_DIR="${UPKEEPER_OBLIGATION_DIR:-$TEST_TMP_ROOT/empty-obligations}" \
    CHIMNEYSWEEP_CAPTURE="$TEST_TMP_ROOT/capture.txt" \
    GH_SCENARIO="${GH_SCENARIO:-clean}" \
    "$ROOT_DIR/ChimneySweep" "$@"
}

write_open_obligation() {
  local obligation_dir="$1"
  mkdir -p "$obligation_dir/open"
  cat >"$obligation_dir/open/obligation-fixture.json" <<'JSON'
{
  "schema": 1,
  "record_type": "automation_obligation",
  "status": "open",
  "id": "obligation-fixture",
  "created_at": "2026-05-10T00:00:00-0700",
  "kind": "issue_workflow_comment_unavailable",
  "severity": "high",
  "summary": "Fixture obligation takes priority over GitHub issue ranking",
  "target_file": "lib/upkeeper/codex_io.bash",
  "source_cycle_id": "fixture-cycle",
  "source_run_hash": "fixture-run",
  "required_resolution": ["repair the fixture"]
}
JSON
}

write_runtime_fixture_obligation() {
  local obligation_dir="$1"
  mkdir -p "$obligation_dir/open"
  cat >"$obligation_dir/open/runtime-fixture-obligation.json" <<'JSON'
{
  "schema": 1,
  "record_type": "automation_obligation",
  "status": "open",
  "id": "runtime-fixture-obligation",
  "created_at": "2026-05-10T00:00:00-0700",
  "kind": "target_file_not_eligible",
  "severity": "medium",
  "summary": "Runtime fixture target must not be replayed as the next explicit repair target",
  "target_file": "runtime/upkeeper-explicit-target-fixture.txt",
  "source_cycle_id": "fixture-cycle",
  "source_run_hash": "fixture-run",
  "launcher": "ChimneySweep",
  "variant": "issue-repair",
  "policy": "own-bug-queue",
  "workflow": "obligation-repair",
  "required_resolution": ["remap the poisoned target before the next repair cycle"]
}
JSON
}

test_chimneysweep_help_documents_fix_contract() {
  local help

  help="$("$ROOT_DIR/ChimneySweep" --help)"
  grep -Fq "Usage: ChimneySweep" <<<"$help" || fail "help missing usage"
  grep -Fq "security-class issues, then data-integrity-class issues" <<<"$help" || fail "help missing class priority"
  grep -Fq "exit 25" <<<"$help" || fail "help missing clean exit code"
  grep -Fq -- "--dry-run" <<<"$help" || fail "help missing dry-run flag"
  grep -Fq -- "--workflow=" <<<"$help" || fail "help missing workflow flag"
  grep -Fq -- "--model-override=SPEC" <<<"$help" || fail "help missing model override flag"
  grep -Fq -- "--model MODEL" <<<"$help" || fail "help missing model shortcut flag"
  grep -Fq "comment -> review -> apply" <<<"$help" || fail "help missing staged workflow"
  grep -Fq "full pass/module coverage" <<<"$help" || fail "help missing full burn contract"
  grep -Fq "Lattice required" <<<"$help" || fail "help missing required Lattice contract"
}

test_chimneysweep_clean_queue_exits_25() {
  local output rc

  set +e
  output="$(GH_SCENARIO=clean run_chimneysweep --dry-run 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 25 ]] || fail "clean queue exited $rc, expected 25"
  grep -Fq "high five yay" <<<"$output" || fail "clean queue did not print high-five text"
}

test_chimneysweep_skipped_queue_counts_clean() {
  local output rc

  set +e
  output="$(GH_SCENARIO=skipped run_chimneysweep --dry-run 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 25 ]] || fail "skipped-only queue exited $rc, expected 25"
  grep -Fq "high five yay" <<<"$output" || fail "skipped-only queue did not print high-five text"
}

test_chimneysweep_security_class_wins() {
  local output

  output="$(GH_SCENARIO=security run_chimneysweep --dry-run 2>&1)"
  grep -Fq -- "--fix-issue=50" <<<"$output" || fail "security scenario did not lock oldest security issue"
  grep -Fq "class=security" <<<"$output" || fail "security scenario did not report class"
  grep -Fq -- "--prompt-pass=all" <<<"$output" || fail "security scenario did not request all prompt passes"
  grep -Fq -- "--review-modules=p24\\,p25\\,p26\\,p27\\,p28\\,p29" <<<"$output" || fail "security scenario did not request all review modules"
  grep -Fq -- "--issue-workflow-stage=comment" <<<"$output" || fail "security scenario did not request comment stage"
  grep -Fq -- "--issue-workflow-stage=review" <<<"$output" || fail "security scenario did not request review stage"
  grep -Fq -- "--issue-workflow-stage=apply" <<<"$output" || fail "security scenario did not request apply stage"
  grep -Fq "UPKEEPER_LATTICE_REQUIRED=1" <<<"$output" || fail "security scenario missing required Lattice burn default"
  grep -Fq "UPKEEPER_PRECONTACT_BACKUP_MODE=age" <<<"$output" || fail "security scenario missing age backup burn default"
  grep -Fq "UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=1" <<<"$output" || fail "security scenario missing encrypted backup requirement"
  grep -Fq "CODEX_5H_STOP_PERCENT=0" <<<"$output" || fail "security scenario missing five-hour spend-to-zero quota default"
  grep -Fq "CODEX_WEEK_STOP_PERCENT=0" <<<"$output" || fail "security scenario missing weekly spend-to-zero quota default"
  grep -Fq "CODEX_QUOTA_GUARDRAIL_BYPASS=1" <<<"$output" || fail "security scenario missing quota guardrail bypass for launcher burn"
  grep -Fq "CODEX_QUOTA_COOLDOWN_BYPASS=1" <<<"$output" || fail "security scenario missing cooldown bypass for launcher burn"
  grep -Fq "UPKEEPER_AUTOMATION_LAUNCHER=ChimneySweep" <<<"$output" || fail "security scenario missing ChimneySweep automation identity"
  grep -Fq "UPKEEPER_AUTOMATION_VARIANT=issue-repair" <<<"$output" || fail "security scenario missing ChimneySweep automation variant"
  grep -Fq "UPKEEPER_AUTOMATION_POLICY=own-bug-queue" <<<"$output" || fail "security scenario missing ChimneySweep automation policy"
  grep -Fq "UPKEEPER_AUTOMATION_WORKFLOW=comment-review-apply" <<<"$output" || fail "security scenario missing ChimneySweep automation workflow"
}

test_chimneysweep_model_override_supports_spark() {
  local output

  output="$(GH_SCENARIO=security CHIMNEYSWEEP_MODEL_OVERRIDE=5.3-codex-spark_xhigh run_chimneysweep --dry-run 2>&1)"
  grep -Fq -- "--model-override=5.3-codex-spark_xhigh" <<<"$output" || fail "ChimneySweep env Spark override was not passed through"

  output="$(GH_SCENARIO=security run_chimneysweep --dry-run --model gpt-5.3-codex-spark --reasoning-effort xhigh 2>&1)"
  grep -Fq -- "--model-override=5.3-codex-spark_xhigh" <<<"$output" || fail "ChimneySweep model shortcut did not resolve Spark override"
}

test_chimneysweep_reconciles_obligations_before_github_queue() {
  local output obligation_dir

  obligation_dir="$TEST_TMP_ROOT/chimneysweep-obligations"
  write_open_obligation "$obligation_dir"
  output="$(UPKEEPER_OBLIGATION_DIR="$obligation_dir" GH_SCENARIO=security run_chimneysweep --dry-run 2>&1)"
  grep -Fq "selected automation obligation obligation-fixture" <<<"$output" || fail "ChimneySweep did not select open automation obligation first"
  grep -Fq "UPKEEPER_AUTOMATION_WORKFLOW=obligation-repair" <<<"$output" || fail "ChimneySweep obligation run missing obligation workflow"
  grep -Fq "UPKEEPER_AUTOMATION_OBLIGATION_ID=obligation-fixture" <<<"$output" || fail "ChimneySweep obligation run missing obligation id"
  grep -Fq -- "--target-file=lib/upkeeper/codex_io.bash" <<<"$output" || fail "ChimneySweep obligation run did not lock obligation target"
  grep -Fq -- "--prompt-file" <<<"$output" || fail "ChimneySweep obligation run did not pass wrapper-generated prompt file"
  if grep -Fq -- "--fix-issue=50" <<<"$output"; then
    fail "ChimneySweep ranked GitHub issues before reconciling open obligations"
  fi
}

test_chimneysweep_remaps_runtime_fixture_obligation_targets() {
  local output obligation_dir

  obligation_dir="$TEST_TMP_ROOT/chimneysweep-runtime-target-obligations"
  write_runtime_fixture_obligation "$obligation_dir"
  output="$(UPKEEPER_OBLIGATION_DIR="$obligation_dir" GH_SCENARIO=security run_chimneysweep --dry-run 2>&1)"
  grep -Fq "selected automation obligation runtime-fixture-obligation" <<<"$output" || fail "runtime fixture obligation was not selected"
  grep -Fq -- "--target-file=ChimneySweep" <<<"$output" || fail "runtime fixture obligation was not remapped to ChimneySweep"
  grep -Fq "obligation target remapped from runtime/upkeeper-explicit-target-fixture.txt to ChimneySweep" <<<"$output" || fail "runtime fixture obligation remap was not reported"
  if grep -Fq -- "--target-file=runtime/upkeeper-explicit-target-fixture.txt" <<<"$output"; then
    fail "runtime fixture obligation replayed the poisoned runtime target"
  fi
}

test_chimneysweep_data_integrity_after_security_clear() {
  local output

  output="$(GH_SCENARIO=data run_chimneysweep --dry-run 2>&1)"
  grep -Fq -- "--fix-issue=20" <<<"$output" || fail "data scenario did not lock oldest data-integrity issue"
  grep -Fq "class=data-integrity" <<<"$output" || fail "data scenario did not report class"
}

test_chimneysweep_general_queue_prefers_containment_signal() {
  local output

  output="$(GH_SCENARIO=general run_chimneysweep --dry-run 2>&1)"
  grep -Fq -- "--fix-issue=31" <<<"$output" || fail "general scenario did not prefer containment signal"
  grep -Fq "basis=general queue ranked by containment signal" <<<"$output" || fail "general scenario did not report ranking basis"
}

test_chimneysweep_exec_hands_locked_issue_to_upkeeper() {
  rm -f "$TEST_TMP_ROOT/capture.txt"
  GH_SCENARIO=security run_chimneysweep >/dev/null 2>&1
  [[ "$(grep -c '^BEGIN$' "$TEST_TMP_ROOT/capture.txt")" -eq 3 ]] || fail "exec did not run three workflow stages"
  grep -Fxq -- "--model-override=5.5_xhigh" "$TEST_TMP_ROOT/capture.txt" || fail "exec did not pass model override"
  grep -Fxq -- "--prompt-pass=all" "$TEST_TMP_ROOT/capture.txt" || fail "exec did not pass all prompt pass"
  grep -Fxq -- "--review-modules=p24,p25,p26,p27,p28,p29" "$TEST_TMP_ROOT/capture.txt" || fail "exec did not pass all review modules"
  grep -Fxq -- "--fix-issue=50" "$TEST_TMP_ROOT/capture.txt" || fail "exec did not pass locked issue"
  grep -Fxq -- "--issue-workflow-stage=comment" "$TEST_TMP_ROOT/capture.txt" || fail "exec did not run comment stage"
  grep -Fxq -- "--issue-workflow-stage=review" "$TEST_TMP_ROOT/capture.txt" || fail "exec did not run review stage"
  grep -Fxq -- "--issue-workflow-stage=apply" "$TEST_TMP_ROOT/capture.txt" || fail "exec did not run apply stage"
}

test_chimneysweep_apply_workflow_runs_one_stage() {
  rm -f "$TEST_TMP_ROOT/capture.txt"
  GH_SCENARIO=security run_chimneysweep --workflow=apply >/dev/null 2>&1
  [[ "$(grep -c '^BEGIN$' "$TEST_TMP_ROOT/capture.txt")" -eq 1 ]] || fail "apply workflow did not run one stage"
  grep -Fxq -- "--issue-workflow-stage=apply" "$TEST_TMP_ROOT/capture.txt" || fail "apply workflow did not pass apply stage"
}

test_chimneysweep_completion_loads() {
  local debug_output workflow_output

  debug_output="$(
    source "$ROOT_DIR/completions/upkeeper.bash"
    complete -p ./ChimneySweep >/dev/null
    COMP_WORDS=(./ChimneySweep --d)
    COMP_CWORD=1
    _chimneysweep_complete
    printf '%s\n' "${COMPREPLY[@]}"
  )"
  grep -Fxq -- "--dry-run" <<<"$debug_output" || fail "ChimneySweep completion did not suggest --dry-run"
  grep -Fxq -- "--debug1" <<<"$debug_output" || fail "ChimneySweep completion did not suggest --debug1"

  workflow_output="$(
    source "$ROOT_DIR/completions/upkeeper.bash"
    complete -p ./ChimneySweep >/dev/null
    COMP_WORDS=(./ChimneySweep --w)
    COMP_CWORD=1
    _chimneysweep_complete
    printf '%s\n' "${COMPREPLY[@]}"
  )"
  grep -Fxq -- "--workflow=" <<<"$workflow_output" || fail "ChimneySweep completion did not suggest --workflow"

  workflow_output="$(
    source "$ROOT_DIR/completions/upkeeper.bash"
    complete -p ./ChimneySweep >/dev/null
    COMP_WORDS=(./ChimneySweep --model-override=)
    COMP_CWORD=1
    _chimneysweep_complete
    printf '%s\n' "${COMPREPLY[@]}"
  )"
  grep -Fxq -- "--model-override=5.3-codex-spark_xhigh" <<<"$workflow_output" || fail "ChimneySweep completion did not suggest Spark model override"
}

test_chimneysweep_help_documents_fix_contract
test_chimneysweep_clean_queue_exits_25
test_chimneysweep_skipped_queue_counts_clean
test_chimneysweep_security_class_wins
test_chimneysweep_model_override_supports_spark
test_chimneysweep_reconciles_obligations_before_github_queue
test_chimneysweep_remaps_runtime_fixture_obligation_targets
test_chimneysweep_data_integrity_after_security_clear
test_chimneysweep_general_queue_prefers_containment_signal
test_chimneysweep_exec_hands_locked_issue_to_upkeeper
test_chimneysweep_apply_workflow_runs_one_stage
test_chimneysweep_completion_loads
printf 'ok - chimneysweep\n'
