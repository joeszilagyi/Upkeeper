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
printf '%s\n' "$@" >"${CHIMNEYSWEEP_CAPTURE:?}"
EOF
chmod +x "$TEST_TMP_ROOT/bin/upkeeper"

run_chimneysweep() {
  PATH="$TEST_TMP_ROOT/bin:$PATH" \
    UPKEEPER_CMD="$TEST_TMP_ROOT/bin/upkeeper" \
    CHIMNEYSWEEP_CAPTURE="$TEST_TMP_ROOT/capture.txt" \
    GH_SCENARIO="${GH_SCENARIO:-clean}" \
    "$ROOT_DIR/ChimneySweep" "$@"
}

test_chimneysweep_help_documents_fix_contract() {
  local help

  help="$("$ROOT_DIR/ChimneySweep" --help)"
  grep -Fq "Usage: ChimneySweep" <<<"$help" || fail "help missing usage"
  grep -Fq "security-class issues, then data-integrity-class issues" <<<"$help" || fail "help missing class priority"
  grep -Fq "exit 25" <<<"$help" || fail "help missing clean exit code"
  grep -Fq -- "--dry-run" <<<"$help" || fail "help missing dry-run flag"
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
  grep -Fxq -- "--model-override=5.5_xhigh" "$TEST_TMP_ROOT/capture.txt" || fail "exec did not pass model override"
  grep -Fxq -- "--fix-issue=50" "$TEST_TMP_ROOT/capture.txt" || fail "exec did not pass locked issue"
}

test_chimneysweep_completion_loads() {
  local output

  output="$(
    source "$ROOT_DIR/completions/upkeeper.bash"
    complete -p ./ChimneySweep >/dev/null
    COMP_WORDS=(./ChimneySweep --d)
    COMP_CWORD=1
    _chimneysweep_complete
    printf '%s\n' "${COMPREPLY[@]}"
  )"
  grep -Fxq -- "--dry-run" <<<"$output" || fail "ChimneySweep completion did not suggest --dry-run"
  grep -Fxq -- "--debug1" <<<"$output" || fail "ChimneySweep completion did not suggest --debug1"
}

test_chimneysweep_help_documents_fix_contract
test_chimneysweep_clean_queue_exits_25
test_chimneysweep_skipped_queue_counts_clean
test_chimneysweep_security_class_wins
test_chimneysweep_data_integrity_after_security_clear
test_chimneysweep_general_queue_prefers_containment_signal
test_chimneysweep_exec_hands_locked_issue_to_upkeeper
test_chimneysweep_completion_loads
printf 'ok - chimneysweep\n'
