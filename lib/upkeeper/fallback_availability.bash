# Fallback availability predicates.
#
# These helpers read wrapper-global fallback configuration and runtime state.
# Keep the reason strings stable because logs and postmortem context use them
# to explain why a stronger fallback child was not launched.
fallback_unavailable_reason() {
  if [[ "$CODEX_FALLBACK_ENABLED" != "1" ]]; then
    printf 'fallback_disabled'
    return 0
  fi
  if [[ "$CODEX_FALLBACK_CHAIN_ACTIVE" == "1" ]]; then
    printf 'already_in_fallback_chain'
    return 0
  fi
  if [[ "$CODEX_FALLBACK_MODEL" == "$CODEX_MODEL" && "$CODEX_FALLBACK_REASONING_EFFORT" == "$CODEX_REASONING_EFFORT" && "$CODEX_FALLBACK_MODE" == "$CODEX_MODE_STRING" ]]; then
    printf 'same_model_config'
    return 0
  fi
  return 0
}

fallback_available() {
  [[ -z "$(fallback_unavailable_reason)" ]]
}

# Missing a final status after a primary model response is recoverable through
# a bounded second attempt by default.  A nonempty terminal status instead
# represents an explicit backend result, so generic-failure recovery remains
# opt-in.  Keeping this decision here gives the entrypoint and focused tests
# one policy owner rather than making an empty marker an accidental exception
# to the broad failure switch.
fallback_failure_trigger_enabled() {
  local status_marker="$1"

  if [[ -z "$status_marker" ]]; then
    [[ "${CODEX_FALLBACK_ON_NO_OUTPUT:-0}" == "1" ]]
    return
  fi
  [[ "${CODEX_FALLBACK_ON_FAILURE:-0}" == "1" ]]
}

# Keep trigger-to-setting authority in one place.  The caller supplies the
# status marker only for the broad failure path, which lets a missing final
# marker retain its separately configured recovery path without enabling an
# automatic retry for every explicit error result.
fallback_trigger_enabled() {
  local trigger="$1"
  local status_marker="${2:-}"

  case "$trigger" in
    primary_quota_before_run|primary_quota_after_run|primary_backend_usage_limit)
      [[ "${CODEX_FALLBACK_ON_PRIMARY_QUOTA:-0}" == "1" ]]
      ;;
    dirty_no_backend_task)
      [[ "${CODEX_FALLBACK_ON_DIRTY_NO_BACKEND_TASK:-0}" == "1" ]]
      ;;
    blocked)
      [[ "${CODEX_FALLBACK_ON_BLOCKED:-0}" == "1" ]]
      ;;
    failure)
      fallback_failure_trigger_enabled "$status_marker"
      ;;
    *)
      return 1
      ;;
  esac
}

fallback_would_rediscover_dirty_block() {
  local trigger="$1"

  # A default-prompt pre-run quota fallback would rediscover the same dirty
  # worktree and likely stop as "no backend task"; explicit prompts keep their
  # task context and are allowed to fall back.
  [[ "$trigger" == "primary_quota_before_run" && "$DIRTY_PATH_COUNT" -gt 0 && -z "$PROMPT_FILE" && -z "$INLINE_PROMPT" ]]
}
