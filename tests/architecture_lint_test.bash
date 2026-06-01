#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-architecture-lint-test.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'architecture_lint_test: %s\n' "$*" >&2
  exit 1
}

cat >"$TEST_TMP_ROOT/a.bash" <<'SH'
shared_func() {
  :
}
SH

cat >"$TEST_TMP_ROOT/b.bash" <<'SH'
shared_func() {
  :
}

shadow_wrapper() {
  eval "$(declare -f shared_func | sed '1s/shared_func/original_shared_func/')"
}
SH

set +e
tools/check_architecture.py --allowlist "$TEST_TMP_ROOT/missing.tsv" "$TEST_TMP_ROOT/a.bash" "$TEST_TMP_ROOT/b.bash" >"$TEST_TMP_ROOT/fail.out"
rc=$?
set -e
[[ "$rc" -eq 1 ]] || fail "unallowlisted duplicate function did not fail"
grep -Fq 'ERROR function-shadow' "$TEST_TMP_ROOT/fail.out" ||
  fail "duplicate function finding missing"
grep -Fq 'REPORT declare-f-sed-eval' "$TEST_TMP_ROOT/fail.out" ||
  fail "declare-f sed eval report missing"

cat >"$TEST_TMP_ROOT/allow.tsv" <<'EOF'
shared_func	#test	intentional duplicate for fixture
EOF

tools/check_architecture.py --allowlist "$TEST_TMP_ROOT/allow.tsv" "$TEST_TMP_ROOT/a.bash" "$TEST_TMP_ROOT/b.bash" >"$TEST_TMP_ROOT/pass.out"
! grep -Fq 'ERROR function-shadow' "$TEST_TMP_ROOT/pass.out" ||
  fail "allowlisted duplicate still emitted an error"
grep -Fq 'REPORT function-shadow' "$TEST_TMP_ROOT/pass.out" ||
  fail "allowlisted duplicate was not reported"
grep -Fq 'SUMMARY architecture_findings=' "$TEST_TMP_ROOT/pass.out" ||
  fail "architecture report summary missing"

printf 'architecture_lint_test: ok\n'
