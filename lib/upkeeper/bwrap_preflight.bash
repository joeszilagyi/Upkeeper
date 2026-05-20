## Codex bubblewrap temp registry preflight.
##
## Codex can fail before producing useful session evidence when its bubblewrap
## synthetic-mount registry is not writable. Upkeeper probes the registry root,
## lock file, and a disposable child path before launching backend work so the
## failure becomes an explicit wrapper exit with parseable log detail.

codex_bwrap_tmp_existing_path_check() {
  local registry_root="$1"

  python3 - "$registry_root" <<'PY'
import errno
import os
import stat
import sys
from pathlib import Path

path = Path(sys.argv[1])

if path.is_absolute():
    cursor = Path(path.root)
    parts = path.parts[1:]
else:
    cursor = Path(".")
    parts = path.parts

for part in parts:
    cursor = cursor / part
    try:
        lst = os.lstat(cursor)
    except FileNotFoundError:
        break
    except OSError as exc:
        if exc.errno == errno.ENOTDIR:
            print(f"not_directory:{cursor}")
        else:
            print(f"stat_failed:{exc.strerror or exc}")
        sys.exit(1)
    if stat.S_ISLNK(lst.st_mode):
        print(f"unsafe_symlink:{cursor}")
        sys.exit(1)
    if not stat.S_ISDIR(lst.st_mode):
        print(f"not_directory:{cursor}")
        sys.exit(1)

print("ok")
PY
}

codex_bwrap_tmp_dir_safety_check() {
  local registry_root="$1"

  python3 - "$registry_root" <<'PY'
import errno
import os
import stat
import sys
from pathlib import Path

path_raw = sys.argv[1]
path = Path(path_raw)

if path.is_absolute():
    cursor = Path(path.root)
    parts = path.parts[1:]
else:
    cursor = Path(".")
    parts = path.parts

for part in parts:
    cursor = cursor / part
    try:
        lst = os.lstat(cursor)
    except FileNotFoundError:
        break
    except OSError as exc:
        print(f"stat_failed:{exc.strerror or exc}")
        sys.exit(1)
    if stat.S_ISLNK(lst.st_mode):
        print(f"unsafe_symlink:{cursor}")
        sys.exit(1)

try:
    lst = os.lstat(path_raw)
except FileNotFoundError:
    print(f"missing:{path_raw}")
    sys.exit(1)
except OSError as exc:
    print(f"stat_failed:{exc.strerror or exc}")
    sys.exit(1)

if stat.S_ISLNK(lst.st_mode):
    print(f"unsafe_symlink:{path_raw}")
    sys.exit(1)

flags = os.O_RDONLY
if hasattr(os, "O_DIRECTORY"):
    flags |= os.O_DIRECTORY
if hasattr(os, "O_NOFOLLOW"):
    flags |= os.O_NOFOLLOW
if hasattr(os, "O_CLOEXEC"):
    flags |= os.O_CLOEXEC

try:
    fd = os.open(path_raw, flags)
except OSError as exc:
    if exc.errno == errno.ELOOP:
        print(f"unsafe_symlink:{path_raw}")
    elif exc.errno == errno.ENOTDIR:
        print(f"not_directory:{path_raw}")
    else:
        print(f"open_failed:{exc.strerror or exc}")
    sys.exit(1)

try:
    st = os.fstat(fd)
    if not stat.S_ISDIR(st.st_mode):
        print(f"not_directory:{path_raw}")
        sys.exit(1)

    expected_uid = os.geteuid()
    if st.st_uid != expected_uid:
        print(f"unsafe_owner:expected={expected_uid} actual={st.st_uid} path={path_raw}")
        sys.exit(1)

    mode = stat.S_IMODE(st.st_mode)
    if mode & 0o022:
        try:
            os.fchmod(fd, 0o700)
        except OSError as exc:
            print(f"unsafe_permissions:mode={mode:04o} path={path_raw} chmod_failed={exc.strerror or exc}")
            sys.exit(1)

        st = os.fstat(fd)
        mode = stat.S_IMODE(st.st_mode)
        if not stat.S_ISDIR(st.st_mode):
            print(f"not_directory:{path_raw}")
            sys.exit(1)
        if st.st_uid != expected_uid:
            print(f"unsafe_owner:expected={expected_uid} actual={st.st_uid} path={path_raw}")
            sys.exit(1)
        if mode & 0o022:
            print(f"unsafe_permissions:mode={mode:04o} path={path_raw}")
            sys.exit(1)

    print("ok")
finally:
    os.close(fd)
PY
}

codex_bwrap_tmp_file_probe() {
  local path="$1"

  python3 - "$path" <<'PY'
import errno
import os
import stat
import sys

path = sys.argv[1]
flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
for attr in ("O_NOFOLLOW", "O_CLOEXEC"):
    flags |= getattr(os, attr, 0)

try:
    fd = os.open(path, flags, 0o600)
except OSError as exc:
    if exc.errno == errno.ELOOP:
        print(f"unsafe_symlink:{path}")
    elif exc.errno == errno.EEXIST:
        print(f"probe_exists:{path}")
    else:
        print(f"probe_open_failed:{exc.errno}:{exc.strerror or exc}")
    sys.exit(1)

try:
    os.write(fd, b"probe")
finally:
    os.close(fd)
PY
}

codex_bwrap_tmp_lock_touch() {
  local lock_path="$1"

  python3 - "$lock_path" <<'PY'
import errno
import os
import stat
import sys

path = sys.argv[1]
flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND
for attr in ("O_NOFOLLOW", "O_CLOEXEC"):
    flags |= getattr(os, attr, 0)

try:
    fd = os.open(path, flags, 0o600)
except OSError as exc:
    if exc.errno == errno.ELOOP:
        print(f"unsafe_symlink:{path}")
    else:
        print(f"lock_open_failed:{exc.errno}:{exc.strerror or exc}")
    sys.exit(1)

try:
    st = os.fstat(fd)
    if stat.S_IMODE(st.st_mode) != 0o600:
        try:
            os.fchmod(fd, 0o600)
        except OSError as exc:
            print(f"unsafe_permissions:mode={oct(stat.S_IMODE(st.st_mode))} path={path} chmod_failed={exc.strerror or exc}")
            sys.exit(1)
        st = os.fstat(fd)
        if stat.S_IMODE(st.st_mode) != 0o600:
            print(f"unsafe_permissions:mode={oct(stat.S_IMODE(st.st_mode))} path={path}")
            sys.exit(1)
    if not stat.S_ISREG(st.st_mode):
        print(f"lock_not_regular:{path}")
        sys.exit(1)
    if st.st_uid != os.geteuid():
        print(f"unsafe_owner:expected={os.geteuid()} actual={st.st_uid} path={path}")
        sys.exit(1)
finally:
    os.close(fd)

print("ok")
PY
}

codex_bwrap_tmp_write_check() {
  local registry_root="$CODEX_BWRAP_TMP_ROOT"
  local lock_path="$registry_root/lock"
  local safety_detail
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

  if ! safety_detail="$(codex_bwrap_tmp_existing_path_check "$registry_root")"; then
    printf '%s' "$safety_detail"
    rm -f -- "$err_file"
    return 1
  fi

  if ! mkdir -p -- "$registry_root" 2>"$err_file"; then
    printf 'mkdir_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f -- "$err_file"
    return 1
  fi

  if ! safety_detail="$(codex_bwrap_tmp_dir_safety_check "$registry_root")"; then
    printf '%s' "$safety_detail"
    rm -f -- "$err_file"
    return 1
  fi

  if ! probe_dir="$(mktemp -d -- "$registry_root/.upkeeper-write-test.XXXXXX" 2>"$err_file")"; then
    printf 'probe_dir_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    rm -f -- "$err_file"
    return 1
  fi

  probe_file="$probe_dir/probe"
  if ! safety_detail="$(codex_bwrap_tmp_file_probe "$probe_file" 2>"$err_file")"; then
    if [[ -n "$safety_detail" ]]; then
      printf '%s' "$safety_detail"
    else
      printf 'probe_write_failed:%s' "$(tr '\n' ' ' <"$err_file")"
    fi
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

  if ! safety_detail="$(codex_bwrap_tmp_lock_touch "$lock_path")"; then
    printf '%s' "$safety_detail"
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
