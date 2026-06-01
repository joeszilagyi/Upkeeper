#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-contract-manifest.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$TEST_TMP_ROOT/root/docs"
printf 'hello contract\n' >"$TEST_TMP_ROOT/root/docs/ok.md"

cat >"$TEST_TMP_ROOT/pass.tsv" <<'EOF'
id	file	contains	error
docs.ok	docs/ok.md	hello contract	ok text missing
EOF

"$ROOT_DIR/tools/check_contract_manifest.py" --root "$TEST_TMP_ROOT/root" "$TEST_TMP_ROOT/pass.tsv" \
  >"$TEST_TMP_ROOT/pass.out" ||
  fail "valid manifest did not pass"
grep -Fq 'contract_manifest: ok' "$TEST_TMP_ROOT/pass.out" ||
  fail "valid manifest did not emit ok summary"

cat >"$TEST_TMP_ROOT/missing-file.tsv" <<'EOF'
id	file	contains	error
docs.missing	docs/missing.md	hello	missing file contract
EOF
if "$ROOT_DIR/tools/check_contract_manifest.py" --root "$TEST_TMP_ROOT/root" "$TEST_TMP_ROOT/missing-file.tsv" \
  >"$TEST_TMP_ROOT/missing-file.out" 2>"$TEST_TMP_ROOT/missing-file.err"; then
  fail "missing file manifest unexpectedly passed"
fi
grep -Fq 'missing file contract' "$TEST_TMP_ROOT/missing-file.err" ||
  fail "missing file error did not include row error"

cat >"$TEST_TMP_ROOT/missing-text.tsv" <<'EOF'
id	file	contains	error
docs.missing_text	docs/ok.md	absent text	missing text contract
EOF
if "$ROOT_DIR/tools/check_contract_manifest.py" --root "$TEST_TMP_ROOT/root" "$TEST_TMP_ROOT/missing-text.tsv" \
  >"$TEST_TMP_ROOT/missing-text.out" 2>"$TEST_TMP_ROOT/missing-text.err"; then
  fail "missing text manifest unexpectedly passed"
fi
grep -Fq 'missing text contract' "$TEST_TMP_ROOT/missing-text.err" ||
  fail "missing text error did not include row error"

cat >"$TEST_TMP_ROOT/duplicate.tsv" <<'EOF'
id	file	contains	error
docs.dupe	docs/ok.md	hello	first duplicate
docs.dupe	docs/ok.md	hello	second duplicate
EOF
if "$ROOT_DIR/tools/check_contract_manifest.py" --root "$TEST_TMP_ROOT/root" "$TEST_TMP_ROOT/duplicate.tsv" \
  >"$TEST_TMP_ROOT/duplicate.out" 2>"$TEST_TMP_ROOT/duplicate.err"; then
  fail "duplicate-id manifest unexpectedly passed"
fi
grep -Fq "duplicate id 'docs.dupe'" "$TEST_TMP_ROOT/duplicate.err" ||
  fail "duplicate-id error did not identify the duplicate id"

"$ROOT_DIR/tools/check_contract_manifest.py" --root "$ROOT_DIR" "$ROOT_DIR/contracts/public_docs.tsv" \
  >"$TEST_TMP_ROOT/public.out" ||
  fail "public docs manifest does not pass on repository"

printf 'ok - contract manifest\n'
