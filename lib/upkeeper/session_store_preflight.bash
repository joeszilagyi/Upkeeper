## Codex session store preflight.
##
## Codex writes session JSONL under $CODEX_HOME/sessions. Upkeeper probes that
## store before launching backend work so local filesystem failures stop before
## quota is spent or recursive recovery tries to launch more Codex processes.

codex_session_store_dir_safety_check() {
  local marker_dir="$1"

  python3 - "$marker_dir" <<'PY'
import errno
import os
import stat
import sys

path = sys.argv[1]
try:
    lst = os.lstat(path)
except FileNotFoundError:
    print(f"missing:{path}")
    sys.exit(1)
except OSError as exc:
    print(f"stat_failed:{exc.strerror or exc}")
    sys.exit(1)

if stat.S_ISLNK(lst.st_mode):
    print(f"unsafe_symlink:{path}")
    sys.exit(1)

flags = os.O_RDONLY
if hasattr(os, "O_DIRECTORY"):
    flags |= os.O_DIRECTORY
if hasattr(os, "O_NOFOLLOW"):
    flags |= os.O_NOFOLLOW
if hasattr(os, "O_CLOEXEC"):
    flags |= os.O_CLOEXEC

try:
    fd = os.open(path, flags)
except OSError as exc:
    if exc.errno == errno.ELOOP:
        print(f"unsafe_symlink:{path}")
    elif exc.errno == errno.ENOTDIR:
        print(f"not_directory:{path}")
    else:
        print(f"open_failed:{exc.strerror or exc}")
    sys.exit(1)

try:
    st = os.fstat(fd)
    if not stat.S_ISDIR(st.st_mode):
        print(f"not_directory:{path}")
        sys.exit(1)

    expected_uid = os.geteuid()
    if st.st_uid != expected_uid:
        print(f"unsafe_owner:expected={expected_uid} actual={st.st_uid} path={path}")
        sys.exit(1)

    mode = stat.S_IMODE(st.st_mode)
    if mode & 0o022:
        try:
            os.fchmod(fd, 0o700)
        except OSError as exc:
            print(f"unsafe_permissions:mode={mode:04o} path={path} chmod_failed={exc.strerror or exc}")
            sys.exit(1)

        st = os.fstat(fd)
        mode = stat.S_IMODE(st.st_mode)
        if not stat.S_ISDIR(st.st_mode):
            print(f"not_directory:{path}")
            sys.exit(1)
        if st.st_uid != expected_uid:
            print(f"unsafe_owner:expected={expected_uid} actual={st.st_uid} path={path}")
            sys.exit(1)
        if mode & 0o022:
            print(f"unsafe_permissions:mode={mode:04o} path={path}")
            sys.exit(1)

    print("ok")
finally:
    os.close(fd)
PY
}

codex_session_store_write_check() {
  local marker_dir="$CODEX_HOME_DIR/sessions"
  local probe_file
  local safety_detail
  local err_file

  if ! err_file="$(mktemp)"; then
    printf 'mktemp_failed'
    return 1
  fi

  if [[ -L "$marker_dir" ]]; then
    printf 'unsafe_symlink:%s' "$marker_dir"
    rm -f -- "$err_file"
    return 1
  fi

  if [[ -e "$marker_dir" && ! -d "$marker_dir" ]]; then
    printf 'not_directory:%s' "$marker_dir"
    rm -f -- "$err_file"
    return 1
  fi

  if ! mkdir -p -- "$marker_dir" 2>"$err_file"; then
    printf 'mkdir_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f -- "$err_file"
    return 1
  fi

  if ! safety_detail="$(codex_session_store_dir_safety_check "$marker_dir")"; then
    printf '%s' "$safety_detail"
    rm -f -- "$err_file"
    return 1
  fi

  if ! probe_file="$(mktemp -- "$marker_dir/.upkeeper-write-test.XXXXXX" 2>"$err_file")"; then
    printf 'probe_file_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f -- "$err_file"
    return 1
  fi

  if ! python3 - "$probe_file" 2>"$err_file" <<'PY'
import os
import sys

path = sys.argv[1]
flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
for attr in ("O_NOFOLLOW", "O_CLOEXEC"):
    flags |= getattr(os, attr, 0)

try:
    fd = os.open(path, flags, 0o600)
except OSError as exc:
    print(f"probe_open_failed:{exc.errno}:{exc.strerror or exc}")
    raise SystemExit(1)

try:
    os.write(fd, b"probe")
finally:
    os.close(fd)

PY
    printf 'probe_write_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f -- "$probe_file"
    rm -f -- "$err_file"
    return 1
  fi

  if ! rm -f -- "$probe_file" 2>"$err_file"; then
    printf 'probe_file_cleanup_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f -- "$probe_file"
    rm -f -- "$err_file"
    return 1
  fi

  rm -f -- "$err_file"
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
