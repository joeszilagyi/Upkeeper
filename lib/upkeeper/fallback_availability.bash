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

fallback_would_rediscover_dirty_block() {
  local trigger="$1"

  # A default-prompt pre-run quota fallback would rediscover the same dirty
  # worktree and likely stop as "no backend task"; explicit prompts keep their
  # task context and are allowed to fall back.
  [[ "$trigger" == "primary_quota_before_run" && "$DIRTY_PATH_COUNT" -gt 0 && -z "$PROMPT_FILE" && -z "$INLINE_PROMPT" ]]
}
