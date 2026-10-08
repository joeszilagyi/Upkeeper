#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tools/test_attestation_lib.bash"

TEST_ROOT="$(mktemp -d /tmp/upkeeper-test-attestation.XXXXXX)"
trap 'find "$TEST_ROOT" -depth -delete 2>/dev/null || true' EXIT

fail_test() {
  printf 'test_attestation_test: ERROR: %s\n' "$*" >&2
  exit 1
}

git -C "$TEST_ROOT" init -q -b main
git -C "$TEST_ROOT" config user.name "Upkeeper Validation"
git -C "$TEST_ROOT" config user.email "validation@example.invalid"
mkdir -p "$TEST_ROOT/tests"
printf '#!/usr/bin/env bash\nexit 0\n' >"$TEST_ROOT/tests/example_test.bash"
git -C "$TEST_ROOT" add tests/example_test.bash
git -C "$TEST_ROOT" commit -q -m baseline

artifact="$TEST_ROOT/attestation.json"
upkeeper_test_attestation_write "$TEST_ROOT" "$artifact" tests/example_test.bash >/dev/null
upkeeper_test_attestation_load "$TEST_ROOT" "$artifact" || fail_test "valid attestation rejected"
upkeeper_test_attestation_has tests/example_test.bash || fail_test "valid test missing from attestation"

printf '# changed\n' >>"$TEST_ROOT/tests/example_test.bash"
if upkeeper_test_attestation_load "$TEST_ROOT" "$artifact"; then
  fail_test "changed tracked tree accepted"
fi
[[ "$UPKEEPER_TEST_ATTESTATION_REASON" == "tracked_tree_dirty" ]] ||
  fail_test "changed tree rejection reason was $UPKEEPER_TEST_ATTESTATION_REASON"
git -C "$TEST_ROOT" restore tests/example_test.bash

python3 - "$artifact" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["environment"] = "wrong-environment"
json.dump(data, open(path, "w", encoding="utf-8"))
PY
if upkeeper_test_attestation_load "$TEST_ROOT" "$artifact"; then
  fail_test "wrong environment accepted"
fi
[[ "$UPKEEPER_TEST_ATTESTATION_REASON" == "metadata_mismatch" ]] ||
  fail_test "environment rejection reason was $UPKEEPER_TEST_ATTESTATION_REASON"

printf 'test_attestation_test: ok\n'
