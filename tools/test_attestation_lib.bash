#!/usr/bin/env bash
# Partial test reuse from live-checkout v1 records is removed. Identical whole
# test/phase/validator requests use the shared pinned execution owner instead.
declare -A UPKEEPER_ATTESTED_TESTS=()
UPKEEPER_TEST_ATTESTATION_STATUS="rejected"
UPKEEPER_TEST_ATTESTATION_REASON="legacy_or_unpinned_evidence"

upkeeper_test_attestation_load() {
  UPKEEPER_ATTESTED_TESTS=()
  UPKEEPER_TEST_ATTESTATION_STATUS="rejected"
  UPKEEPER_TEST_ATTESTATION_REASON="legacy_or_unpinned_evidence"
  return 1
}

upkeeper_test_attestation_has() { return 1; }

upkeeper_test_attestation_write() {
  [[ -z "${2:-}" ]] && return 0
  printf 'validation_evidence: blocked direct publication requires pinned execution\n' >&2
  return 3
}
