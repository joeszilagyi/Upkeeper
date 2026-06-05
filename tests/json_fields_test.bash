#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/lib/upkeeper/runtime_format_json.bash"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_json_fields_nul_preserves_scalar_and_structured_values() {
  local json
  local -a fields=()

  json="$(python3 - <<'PY'
import json
print(json.dumps({
    "missing_fallback": None,
    "null_value": None,
    "flag_false": False,
    "flag_true": True,
    "count": 17,
    "text": "line one\twith tab\nline two",
    "nested": {"k": "v"},
    "list": ["a", "b"],
}, separators=(",", ":")))
PY
)"

  mapfile -d '' -t fields < <(
    json_fields_nul \
      "$json" \
      '.missing_path // ""' \
      '.null_value' \
      '.flag_false' \
      '.flag_true' \
      '.count' \
      '.text' \
      '.nested' \
      '.list' \
      '(.missing_path // "fallback")'
  )

  [[ "${#fields[@]}" -eq 9 ]] || fail "json_fields_nul returned ${#fields[@]} fields, expected 9"
  [[ "${fields[0]}" == "" ]] || fail "missing path did not map to empty string"
  [[ "${fields[1]}" == "" ]] || fail "null value did not map to empty string"
  [[ "${fields[2]}" == "false" ]] || fail "false boolean was ${fields[2]}"
  [[ "${fields[3]}" == "true" ]] || fail "true boolean was ${fields[3]}"
  [[ "${fields[4]}" == "17" ]] || fail "number was ${fields[4]}"
  [[ "${fields[5]}" == $'line one\twith tab\nline two' ]] || fail "string with tab/newline was not preserved"
  [[ "${fields[6]}" == '{"k":"v"}' ]] || fail "object was ${fields[6]}"
  [[ "${fields[7]}" == '["a","b"]' ]] || fail "array was ${fields[7]}"
  [[ "${fields[8]}" == "fallback" ]] || fail "fallback expression was ${fields[8]}"
}

test_json_fields_nul_rejects_malformed_json() {
  local stderr_file rc

  stderr_file="$(mktemp "${TMPDIR:-/tmp}/upkeeper-json-fields-stderr.XXXXXX")"
  trap 'rm -f "$stderr_file"' RETURN

  set +e
  json_fields_nul '{bad json' '.field' >/dev/null 2>"$stderr_file"
  rc=$?
  set -e

  [[ "$rc" -ne 0 ]] || fail "json_fields_nul accepted malformed JSON"
  grep -Fq 'json_fields_nul failed' "$stderr_file" ||
    fail "json_fields_nul did not emit a clear malformed-JSON error"
  rm -f "$stderr_file"
  trap - RETURN
}

test_json_fields_nul_preserves_scalar_and_structured_values
test_json_fields_nul_rejects_malformed_json

printf 'json_fields_test: ok\n'
