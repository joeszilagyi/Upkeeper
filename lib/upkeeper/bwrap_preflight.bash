## Codex bubblewrap temp registry preflight.
##
## Codex can fail before producing useful session evidence when its bubblewrap
## synthetic-mount registry is not writable. Upkeeper probes the registry root,
## lock file, and a disposable child path before launching backend work so the
## failure becomes an explicit wrapper exit with parseable log detail.

codex_bwrap_tmp_write_check() {
  local registry_root="$CODEX_BWRAP_TMP_ROOT"
  local lock_path="$registry_root/lock"
  local probe_dir=""
  local probe_file
  local err_file

  if [[ "$CODEX_BWRAP_TMP_PREFLIGHT" != "1" ]]; then
    printf 'ok'
    return 0
  fi

  if ! err_file="$(mktemp)"; then
    printf 'mktemp_failed'
    return 1
  fi

  if [[ -e "$registry_root" && ! -d "$registry_root" ]]; then
    printf 'not_directory:%s' "$registry_root"
    rm -f -- "$err_file"
    return 1
  fi

  if ! mkdir -p -- "$registry_root" 2>"$err_file"; then
    printf 'mkdir_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f -- "$err_file"
    return 1
  fi

  if ! ( : >>"$lock_path" ) 2>"$err_file"; then
    printf 'lock_write_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f -- "$err_file"
    return 1
  fi

  if ! probe_dir="$(mktemp -d -- "$registry_root/.upkeeper-write-test.XXXXXX" 2>"$err_file")"; then
    printf 'probe_dir_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f -- "$err_file"
    return 1
  fi

  probe_file="$probe_dir/probe"
  if ! ( : >"$probe_file" ) 2>"$err_file"; then
    printf 'probe_write_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rmdir -- "$probe_dir" >/dev/null 2>&1 || true
    rm -f -- "$err_file"
    return 1
  fi

  if ! rm -f -- "$probe_file" 2>"$err_file"; then
    printf 'probe_file_cleanup_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rmdir -- "$probe_dir" >/dev/null 2>&1 || true
    rm -f -- "$err_file"
    return 1
  fi

  if ! rmdir -- "$probe_dir" 2>"$err_file"; then
    printf 'probe_dir_cleanup_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f -- "$err_file"
    return 1
  fi

  rm -f -- "$err_file"
  printf 'ok'
  return 0
}

ensure_codex_bwrap_tmp_writable_or_exit() {
  local phase="$1"
  local codex_exec_started="$2"
  local detail detail_q registry_root_q

  detail="$(codex_bwrap_tmp_write_check | compact_process_args || true)"
  if [[ "$detail" == "ok" ]]; then
    return 0
  fi

  detail_q="$(shell_quote "$detail")"
  registry_root_q="$(shell_quote "$CODEX_BWRAP_TMP_ROOT")"
  log_line "ERROR" "codex.bwrap_tmp_unwritable phase=$phase registry_root=$registry_root_q detail=$detail_q"
  finish_cycle 3 CODEX_BWRAP_TMP_UNWRITABLE ERROR "phase=$phase codex_exec_started=$codex_exec_started registry_root=$registry_root_q detail=$detail_q"
}
