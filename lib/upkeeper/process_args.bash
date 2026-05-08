compact_process_args() {
  sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

truncate_process_args() {
  local value="$1"
  local max_chars

  max_chars="$(sanitize_nonnegative_integer "$CODEX_PROCESS_ARGS_MAX_CHARS" "600")"
  if [[ "$max_chars" -eq 0 || "${#value}" -le "$max_chars" ]]; then
    printf '%s' "$value"
    return 0
  fi

  printf '%s...<truncated:%s chars>' "${value:0:max_chars}" "${#value}"
}
