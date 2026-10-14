#!/usr/bin/env bash
# Reusable proof belongs to the pinned execution owner, never an end-of-run
# snapshot or caller-supplied PASS table. Legacy helpers reject that authority.
UPKEEPER_VALIDATION_ATTESTATION_REASON="execution_owner_required"

upkeeper_validation_attestation_load() {
  UPKEEPER_VALIDATION_ATTESTATION_REASON="legacy_or_unpinned_evidence"
  return 1
}

upkeeper_validation_attestation_write() {
  [[ -z "${2:-}" ]] && return 0
  printf 'validation_evidence: blocked direct publication requires pinned execution\n' >&2
  return 3
}

upkeeper_validation_evidence_dispatch() {
  local root="$1" kind="$2" artifact="$3" head program
  local -a pinned_git=(/usr/bin/env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE
    -u GIT_CONFIG_COUNT -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    /usr/bin/git --no-replace-objects -c core.fsmonitor=false)
  shift 3
  [[ -n "$artifact" ]] || return 0
  # Resolve once. The producer also comes from that immutable object, not a
  # second read of a file another process can edit during startup.
  head="$("${pinned_git[@]}" -C "$root" rev-parse --verify 'HEAD^{commit}')" || return $?
  program="$("${pinned_git[@]}" -C "$root" show "$head:tools/validation_evidence.py")" || {
    printf 'validation_evidence: blocked pinned producer is unavailable\n' >&2
    return 3
  }
  exec /usr/bin/python3 -I -c "$program" "$root" "$head" "$kind" "$artifact" "$@"
}
