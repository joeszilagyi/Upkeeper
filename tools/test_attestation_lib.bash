#!/usr/bin/env bash

# Same-checkout unit-test attestations for later validation phases. Reuse is
# fail-closed: the producer must have passed every test against an unchanged
# tracked tree, and the consumer rehashes every recorded test before trusting it.

declare -A UPKEEPER_ATTESTED_TESTS=()
UPKEEPER_TEST_ATTESTATION_STATUS="missing"
UPKEEPER_TEST_ATTESTATION_REASON="not_requested"

upkeeper_test_environment_class() {
  if [[ -n "${CI:-}" ]]; then
    printf 'ci\n'
  else
    printf 'local\n'
  fi
}

upkeeper_test_attestation_write() {
  local root_dir="$1"
  local output_file="$2"
  shift 2
  local head tree environment tracked_dirty="false" output_dir temp_file

  [[ -n "$output_file" ]] || return 0
  head="$(git -C "$root_dir" rev-parse HEAD)"
  tree="$(git -C "$root_dir" rev-parse 'HEAD^{tree}')"
  environment="$(upkeeper_test_environment_class)"
  if ! git -C "$root_dir" diff --quiet --ignore-submodules -- ||
      ! git -C "$root_dir" diff --cached --quiet --ignore-submodules --; then
    tracked_dirty="true"
  fi
  output_dir="$(dirname -- "$output_file")"
  mkdir -p "$output_dir"
  temp_file="$output_file.tmp.${BASHPID:-$$}"
  python3 - "$root_dir" "$temp_file" "$head" "$tree" "$environment" "$tracked_dirty" "$@" <<'PY'
import json
import os
import subprocess
import sys

root, output, head, tree, environment, tracked_dirty, *tests = sys.argv[1:]
rows = []
for path in tests:
    blob = subprocess.check_output(
        ["git", "-C", root, "hash-object", "--", path], text=True
    ).strip()
    rows.append({"path": path, "git_blob": blob, "status": "pass"})
payload = {
    "schema": "upkeeper.test-attestation.v1",
    "command": "tools/run_tests.sh",
    "git_head": head,
    "git_tree": tree,
    "environment": environment,
    "tracked_dirty": tracked_dirty == "true",
    "tests": rows,
}
old_umask = os.umask(0o077)
try:
    with open(output, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, sort_keys=True, separators=(",", ":"))
        handle.write("\n")
finally:
    os.umask(old_umask)
PY
  mv -f -- "$temp_file" "$output_file"
  printf 'run_tests: attestation=%s tests=%s\n' "$output_file" "$#"
}

upkeeper_test_attestation_load() {
  local root_dir="$1"
  local input_file="${2:-}"
  local expected_head expected_tree expected_environment path expected_blob actual_blob

  UPKEEPER_ATTESTED_TESTS=()
  UPKEEPER_TEST_ATTESTATION_STATUS="rejected"
  UPKEEPER_TEST_ATTESTATION_REASON="missing"
  [[ -n "$input_file" && -f "$input_file" && ! -L "$input_file" ]] || return 1

  expected_head="$(git -C "$root_dir" rev-parse HEAD 2>/dev/null || true)"
  expected_tree="$(git -C "$root_dir" rev-parse 'HEAD^{tree}' 2>/dev/null || true)"
  expected_environment="$(upkeeper_test_environment_class)"
  if ! jq -e \
      --arg head "$expected_head" \
      --arg tree "$expected_tree" \
      --arg environment "$expected_environment" \
      '.schema == "upkeeper.test-attestation.v1" and
       .command == "tools/run_tests.sh" and
       .git_head == $head and .git_tree == $tree and
       .environment == $environment and .tracked_dirty == false and
       (.tests | type == "array" and length > 0) and
       all(.tests[]; .status == "pass" and (.path | type == "string") and
           (.git_blob | type == "string"))' \
      "$input_file" >/dev/null 2>&1; then
    UPKEEPER_TEST_ATTESTATION_REASON="metadata_mismatch"
    return 1
  fi
  if ! git -C "$root_dir" diff --quiet --ignore-submodules -- ||
      ! git -C "$root_dir" diff --cached --quiet --ignore-submodules --; then
    UPKEEPER_TEST_ATTESTATION_REASON="tracked_tree_dirty"
    return 1
  fi

  while IFS=$'\t' read -r path expected_blob; do
    [[ "$path" == tests/*.bash && -f "$root_dir/$path" && ! -L "$root_dir/$path" ]] || {
      UPKEEPER_TEST_ATTESTATION_REASON="unsafe_test_path"
      UPKEEPER_ATTESTED_TESTS=()
      return 1
    }
    actual_blob="$(git -C "$root_dir" hash-object -- "$path" 2>/dev/null || true)"
    if [[ -z "$actual_blob" || "$actual_blob" != "$expected_blob" ]]; then
      UPKEEPER_TEST_ATTESTATION_REASON="test_hash_mismatch"
      UPKEEPER_ATTESTED_TESTS=()
      return 1
    fi
    UPKEEPER_ATTESTED_TESTS["$path"]="1"
  done < <(jq -r '.tests[] | [.path, .git_blob] | @tsv' "$input_file")

  UPKEEPER_TEST_ATTESTATION_STATUS="valid"
  UPKEEPER_TEST_ATTESTATION_REASON="same_tree_environment_and_test_hashes"
  return 0
}

upkeeper_test_attestation_has() {
  [[ "${UPKEEPER_ATTESTED_TESTS[${1:-}]:-0}" == "1" ]]
}
