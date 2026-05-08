codex_session_store_write_check() {
  local marker_dir="$CODEX_HOME_DIR/sessions"
  local marker_path
  local err_file

  if ! err_file="$(mktemp)"; then
    printf 'mktemp_failed'
    return 1
  fi

  if ! mkdir -p "$marker_dir" 2>"$err_file"; then
    printf 'mkdir_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f "$err_file"
    return 1
  fi

  marker_path="$marker_dir/.upkeeper-write-test.$$"
  if ! ( : >"$marker_path" ) 2>"$err_file"; then
    printf 'write_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f "$err_file"
    return 1
  fi

  if ! rm -f "$marker_path" 2>"$err_file"; then
    printf 'cleanup_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f "$err_file"
    return 1
  fi

  rm -f "$err_file"
  printf 'ok'
  return 0
}

ensure_codex_session_store_writable_or_exit() {
  local phase="$1"
  local codex_exec_started="$2"
  local detail detail_q code_home_q session_store_q

  detail="$(codex_session_store_write_check | compact_process_args || true)"
  if [[ "$detail" == "ok" ]]; then
    return 0
  fi

  detail_q="$(shell_quote "$detail")"
  code_home_q="$(shell_quote "$CODEX_HOME_DIR")"
  session_store_q="$(shell_quote "$CODEX_HOME_DIR/sessions")"
  log_line "ERROR" "codex.session_store_unwritable phase=$phase code_home=$code_home_q session_store=$session_store_q detail=$detail_q"
  finish_cycle 3 CODEX_SESSION_STORE_UNWRITABLE ERROR "phase=$phase codex_exec_started=$codex_exec_started code_home=$code_home_q session_store=$session_store_q detail=$detail_q"
}
