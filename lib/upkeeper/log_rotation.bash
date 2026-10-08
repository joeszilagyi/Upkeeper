oldest_wrapper_log_epoch() {
  local log_path="${1:-$LOG_FILE}"

  if [[ ! -s "$log_path" ]]; then
    return 1
  fi

  python3 - "$log_path" <<'PY'
from datetime import datetime
from pathlib import Path
import sys

path = Path(sys.argv[1])
try:
    first_line = path.open("r", encoding="utf-8", errors="ignore").readline()
except OSError:
    raise SystemExit(1)

timestamp = first_line.split(" ", 1)[0].strip()
if timestamp:
    try:
        print(int(datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%S%z").timestamp()))
        raise SystemExit(0)
    except ValueError:
        pass

try:
    print(int(path.stat().st_mtime))
except OSError:
    raise SystemExit(1)
PY
}

wrapper_log_archive_parent_is_private() {
  local owner mode

  [[ -d "$LOG_FILE_DIR" && ! -L "$LOG_FILE_DIR" ]] || return 1

  # Plaintext archives are retained only when the live-log directory is
  # already private to the current operator.
  owner="$(stat -Lc '%u' -- "$LOG_FILE_DIR" 2>/dev/null || printf '')"
  mode="$(stat -Lc '%a' -- "$LOG_FILE_DIR" 2>/dev/null || printf '')"
  [[ -n "$owner" && -n "$mode" ]] || return 1

  [[ "$owner" == "$(id -u)" && "$mode" == "700" ]]
}

log_rotation_marker_path() {
  printf '%s.upkeeper-log-rotation.marker' "$LOG_FILE"
}

log_rotation_marker_expected() {
  upkeeper_path_hmac "$LOG_FILE"
}

log_rotation_marker_secure_io() {
  local marker_path="$1"
  local operation="$2"
  local marker_expected="${3:-}"

  python3 - "$marker_path" "$operation" "$marker_expected" <<'PY'
import errno
import os
import stat
import sys

path_raw = sys.argv[1]
operation = sys.argv[2]
marker_expected = sys.argv[3]
parent = os.path.dirname(path_raw) or "."
name = os.path.basename(path_raw)
tmp_name = f"{name}.tmp.{os.getppid()}"

if not name or name in {".", ".."}:
    raise SystemExit(1)

dir_flags = os.O_RDONLY
for attr in ("O_DIRECTORY", "O_CLOEXEC", "O_NOFOLLOW"):
    dir_flags |= getattr(os, attr, 0)


def open_marker_parent(raw_parent: str) -> int:
    if raw_parent in ("", "."):
        return os.open(".", dir_flags)

    if os.path.isabs(raw_parent):
        fd = os.open(os.path.sep, dir_flags)
        parts = raw_parent.lstrip(os.path.sep).split(os.path.sep)
    else:
        fd = os.open(".", dir_flags)
        parts = raw_parent.split(os.path.sep)

    for part in parts:
        if not part or part == ".":
            continue
        try:
            next_fd = os.open(part, dir_flags, dir_fd=fd)
        except OSError:
            os.close(fd)
            raise
        os.close(fd)
        fd = next_fd

    return fd


try:
    parent_fd = open_marker_parent(parent)
except OSError:
    raise SystemExit(1)

tmp_created = False
try:
    if operation == "read":
        try:
            fd = os.open(name, os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0), dir_fd=parent_fd)
        except OSError:
            raise SystemExit(1)

        try:
            opened_stat = os.fstat(fd)
            if not stat.S_ISREG(opened_stat.st_mode):
                raise SystemExit(1)
            with os.fdopen(fd, "r", encoding="utf-8", errors="ignore", closefd=False) as handle:
                marker_current = handle.readline().rstrip("\n")
        finally:
            os.close(fd)

        if not marker_current:
            raise SystemExit(1)
        print(marker_current, end="")
    elif operation == "write":
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        for attr in ("O_CLOEXEC", "O_NOFOLLOW"):
            flags |= getattr(os, attr, 0)
        try:
            fd = os.open(tmp_name, flags, 0o600, dir_fd=parent_fd)
            tmp_created = True
        except OSError:
            raise SystemExit(1)

        try:
            data = f"{marker_expected}\n".encode("utf-8", errors="surrogateescape")
            while data:
                written = os.write(fd, data)
                if written <= 0:
                    raise OSError(errno.EIO, "marker write returned zero bytes")
                data = data[written:]
            os.fchmod(fd, 0o600)
            os.fsync(fd)
        except OSError:
            raise SystemExit(1)
        finally:
            os.close(fd)

        os.rename(tmp_name, name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
        tmp_created = False
    else:
        raise SystemExit(1)
except OSError:
    raise SystemExit(1)
finally:
    if tmp_created:
        try:
            os.unlink(tmp_name, dir_fd=parent_fd)
        except OSError:
            pass
    os.close(parent_fd)
PY
}

log_rotation_marker_readable() {
  local marker_path="$1"

  log_rotation_marker_secure_io "$marker_path" "read"
}

log_rotation_store_marker() {
  local marker_path="$1"
  local marker_expected="$2"

  log_rotation_marker_secure_io "$marker_path" "write" "$marker_expected"
}

log_rotation_target_is_safe() {
  local marker_path marker_expected marker_current
  local default_log_file="$ROOT_DIR/Upkeeper.log"
  local allow_unsafe=0
  local current_uid

  current_uid="$(id -u)"
  marker_path="$(log_rotation_marker_path)"
  marker_expected="$(log_rotation_marker_expected)"

  case "${CODEX_LOG_FILE_ALLOW_UNSAFE:-0}" in
    1|true|yes|on)
      allow_unsafe=1
      ;;
  esac

  if [[ -L "$LOG_FILE" ]]; then
    printf 'log_file_symlink'
    return 1
  fi
  if [[ -L "$LOG_FILE_DIR" || ! -d "$LOG_FILE_DIR" ]]; then
    printf 'log_dir_invalid'
    return 1
  fi

  if [[ -n "$LOG_FILE" && "$LOG_FILE" != "$default_log_file" && "$allow_unsafe" != "1" ]]; then
    printf 'custom_log_path_without_explicit_override'
    return 1
  fi

  marker_current="$(log_rotation_marker_readable "$marker_path" || true)"
  if [[ "$marker_current" != "$marker_expected" ]]; then
    if [[ "$LOG_FILE" == "$default_log_file" || "$allow_unsafe" == "1" ]]; then
      if ! log_rotation_store_marker "$marker_path" "$marker_expected"; then
        printf 'log_marker_write_failed'
        return 1
      fi
    else
      printf 'log_marker_missing'
      return 1
    fi
  fi

  marker_current="$(log_rotation_marker_readable "$marker_path" || true)"
  if [[ "$marker_current" != "$marker_expected" ]]; then
    printf 'log_marker_mismatch'
    return 1
  fi

  if [[ "$(stat -c '%u' -- "$marker_path" 2>/dev/null || printf '')" != "$current_uid" ]]; then
    printf 'log_marker_wrong_owner'
    return 1
  fi
  if [[ "$(stat -c '%a' -- "$marker_path" 2>/dev/null || printf '')" != "600" ]]; then
    printf 'log_marker_wrong_mode'
    return 1
  fi

  return 0
}

# Rotation cannot safely read or truncate the live log by pathname alone because
# the file can be swapped after startup; take a verified snapshot and truncate
# through no-follow file descriptors instead.
copy_wrapper_live_log_secure() {
  local destination_path="$1"

  python3 - "$LOG_FILE" "$destination_path" <<'PY'
import errno
import os
import shutil
import stat
import sys

path_raw = sys.argv[1]
destination_path = sys.argv[2]
uid = os.getuid()
parent = os.path.dirname(path_raw) or "."
name = os.path.basename(path_raw)


def fail(reason: str) -> None:
    print(reason)
    raise SystemExit(1)


def mode_text(mode: int) -> str:
    return oct(stat.S_IMODE(mode))


if not name or name in {".", ".."}:
    fail("invalid_log_filename")

dir_flags = os.O_RDONLY
for attr in ("O_DIRECTORY", "O_CLOEXEC", "O_NOFOLLOW"):
    dir_flags |= getattr(os, attr, 0)


def open_log_parent(raw_parent: str) -> int:
    if raw_parent in ("", "."):
        return os.open(".", dir_flags)

    if os.path.isabs(raw_parent):
        fd = os.open(os.path.sep, dir_flags)
        parts = raw_parent.lstrip(os.path.sep).split(os.path.sep)
    else:
        fd = os.open(".", dir_flags)
        parts = raw_parent.split(os.path.sep)

    for part in parts:
        if not part or part == ".":
            continue
        try:
            next_fd = os.open(part, dir_flags, dir_fd=fd)
        except OSError as exc:
            if exc.errno == errno.ELOOP:
                fail("log_parent_symlink")
            if exc.errno == errno.ENOENT:
                fail("log_parent_missing")
            if exc.errno == errno.ENOTDIR:
                fail("log_parent_not_directory")
            fail(f"log_parent_open_failed errno={exc.errno}")
        os.close(fd)
        fd = next_fd

    return fd


try:
    parent_fd = open_log_parent(parent)
except OSError as exc:
    fail(f"log_parent_open_failed errno={exc.errno}")

try:
    try:
        fd = os.open(name, os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0), dir_fd=parent_fd)
    except OSError as exc:
        if exc.errno == errno.ELOOP:
            fail("symlink_log_file")
        fail(f"log_file_open_failed errno={exc.errno}")

    try:
        opened_stat = os.fstat(fd)
        if not stat.S_ISREG(opened_stat.st_mode):
            fail(f"non_regular_log_file mode={mode_text(opened_stat.st_mode)}")
        if opened_stat.st_uid != uid:
            fail(f"wrong_log_owner uid={opened_stat.st_uid} expected_uid={uid}")
        if opened_stat.st_nlink != 1:
            fail(f"hardlinked_log_file links={opened_stat.st_nlink}")

        try:
            dest_fd = os.open(
                destination_path,
                os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_CLOEXEC", 0),
                0o600,
            )
        except OSError as exc:
            fail(f"log_snapshot_open_failed errno={exc.errno}")
        try:
            try:
                with os.fdopen(fd, "rb", closefd=False) as src, os.fdopen(dest_fd, "wb", closefd=False) as dest:
                    shutil.copyfileobj(src, dest)
            except OSError as exc:
                fail(f"log_snapshot_copy_failed errno={exc.errno}")
            try:
                os.fchmod(dest_fd, 0o600)
            except OSError as exc:
                fail(f"log_snapshot_chmod_failed errno={exc.errno}")
        finally:
            os.close(dest_fd)
    finally:
        os.close(fd)
finally:
    os.close(parent_fd)
PY
}

truncate_wrapper_live_log_secure() {
  python3 - "$LOG_FILE" <<'PY'
import errno
import os
import stat
import sys

path_raw = sys.argv[1]
uid = os.getuid()
parent = os.path.dirname(path_raw) or "."
name = os.path.basename(path_raw)


def fail(reason: str) -> None:
    print(reason)
    raise SystemExit(1)


def mode_text(mode: int) -> str:
    return oct(stat.S_IMODE(mode))


if not name or name in {".", ".."}:
    fail("invalid_log_filename")

dir_flags = os.O_RDONLY
for attr in ("O_DIRECTORY", "O_CLOEXEC", "O_NOFOLLOW"):
    dir_flags |= getattr(os, attr, 0)


def open_log_parent(raw_parent: str) -> int:
    if raw_parent in ("", "."):
        return os.open(".", dir_flags)

    if os.path.isabs(raw_parent):
        fd = os.open(os.path.sep, dir_flags)
        parts = raw_parent.lstrip(os.path.sep).split(os.path.sep)
    else:
        fd = os.open(".", dir_flags)
        parts = raw_parent.split(os.path.sep)

    for part in parts:
        if not part or part == ".":
            continue
        try:
            next_fd = os.open(part, dir_flags, dir_fd=fd)
        except OSError as exc:
            if exc.errno == errno.ELOOP:
                fail("log_parent_symlink")
            if exc.errno == errno.ENOENT:
                fail("log_parent_missing")
            if exc.errno == errno.ENOTDIR:
                fail("log_parent_not_directory")
            fail(f"log_parent_open_failed errno={exc.errno}")
        os.close(fd)
        fd = next_fd

    return fd


try:
    parent_fd = open_log_parent(parent)
except OSError as exc:
    fail(f"log_parent_open_failed errno={exc.errno}")

try:
    flags = os.O_WRONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(name, flags, dir_fd=parent_fd)
    except OSError as exc:
        if exc.errno == errno.ELOOP:
            fail("symlink_log_file")
        fail(f"log_file_open_failed errno={exc.errno}")

    try:
        opened_stat = os.fstat(fd)
        if not stat.S_ISREG(opened_stat.st_mode):
            fail(f"non_regular_log_file mode={mode_text(opened_stat.st_mode)}")
        if opened_stat.st_uid != uid:
            fail(f"wrong_log_owner uid={opened_stat.st_uid} expected_uid={uid}")
        if opened_stat.st_nlink != 1:
            fail(f"hardlinked_log_file links={opened_stat.st_nlink}")
        try:
            os.fchmod(fd, 0o600)
        except OSError as exc:
            fail(f"log_file_chmod_failed errno={exc.errno}")
        try:
            os.ftruncate(fd, 0)
        except OSError as exc:
            fail(f"log_file_truncate_failed errno={exc.errno}")
    finally:
        os.close(fd)
finally:
    os.close(parent_fd)
PY
}

write_wrapper_log_archive_from_snapshot() {
  local snapshot_path="$1"
  local archive_temp_path="$2"

  python3 - "$snapshot_path" "$archive_temp_path" "$LOG_FILE_NAME" <<'PY'
import os
import sys
import zipfile

snapshot_path = sys.argv[1]
archive_path = sys.argv[2]
archive_name = sys.argv[3]

with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    archive.write(snapshot_path, arcname=archive_name)

os.chmod(archive_path, 0o600)
PY
}

prune_wrapper_log_archives() {
  local keep_hours keep_minutes

  keep_hours="$(sanitize_nonnegative_integer "$CODEX_LOG_ROTATE_KEEP_HOURS" "144")"
  keep_minutes=$((keep_hours * 60))

  python3 - "$LOG_FILE_DIR" "$LOG_ARCHIVE_GLOB" "$keep_minutes" <<'PY' || true
from pathlib import Path
import fnmatch
import sys
import time

root = Path(sys.argv[1])
pattern = sys.argv[2]
keep_minutes = int(sys.argv[3])
cutoff = time.time() - (keep_minutes * 60)

try:
    entries = list(root.iterdir())
except OSError:
    raise SystemExit(0)

for path in entries:
    try:
        if path.is_file() and fnmatch.fnmatch(path.name, pattern) and path.stat().st_mtime < cutoff:
            path.unlink()
    except OSError:
        pass
PY
}

rotate_wrapper_log_if_needed() {
  local rotate_after_hours keep_hours rotate_after_seconds now_epoch oldest_epoch
  local archive_path archive_temp_path archive_timestamp rotation_line
  local archive_owner archive_mode archive_retained archive_reason
  local live_log_hash archive_path_hash
  local rotation_safety_error live_log_snapshot
  local previous_signal_traps

  _log_rotate_wrapper_cleanup() {
    if [[ -n "${live_log_snapshot:-}" && -f "$live_log_snapshot" ]]; then
      rm -f -- "$live_log_snapshot"
    fi
    if [[ -n "${archive_temp_path:-}" && -f "$archive_temp_path" ]]; then
      rm -f -- "$archive_temp_path"
    fi
  }

  _log_rotate_wrapper_signal() {
    local signal_name="$1"

    _log_rotate_wrapper_cleanup
    if declare -F handle_wrapper_signal >/dev/null 2>&1; then
      handle_wrapper_signal "$signal_name"
    fi
    return 130
  }

  previous_signal_traps="$(trap -p INT TERM HUP)"

  # RETURN handles the normal fast-path exits, while the signal traps clean up
  # before handing control back to the wrapper's existing interrupt handler.
  trap 'trap - RETURN; _log_rotate_wrapper_cleanup; if [[ -n "${previous_signal_traps:-}" ]]; then eval "$previous_signal_traps"; else trap - INT TERM HUP; fi' RETURN
  trap '_log_rotate_wrapper_signal INT' INT
  trap '_log_rotate_wrapper_signal TERM' TERM
  trap '_log_rotate_wrapper_signal HUP' HUP

  rotation_safety_error="$(log_rotation_target_is_safe || true)"
  if [[ -n "$rotation_safety_error" ]]; then
    rotation_line="$(printf '%s [WARN] cycle=%s run_hash=%s log.rotate_blocked reason=%s path_redacted=1' \
      "$(timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$rotation_safety_error")"
    append_log_line_secure "$rotation_line" "log_rotate_blocked"
    printf '%s\n' "$rotation_line"
    return 0
  fi

  prune_wrapper_log_archives

  if [[ ! -s "$LOG_FILE" ]]; then
    return 0
  fi

  live_log_snapshot="$(mktemp "${LOG_FILE}.rotation.XXXXXX")" || {
    rotation_line="$(printf '%s [WARN] cycle=%s run_hash=%s log.rotate_blocked reason=snapshot_create_failed path_redacted=1' \
      "$(timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH")"
    append_log_line_secure "$rotation_line" "log_rotate_blocked"
    printf '%s\n' "$rotation_line"
    return 0
  }
  chmod 600 "$live_log_snapshot" 2>/dev/null || true

  rotation_safety_error="$(copy_wrapper_live_log_secure "$live_log_snapshot" 2>/dev/null || true)"
  if [[ -n "$rotation_safety_error" ]]; then
    rm -f -- "$live_log_snapshot"
    rotation_line="$(printf '%s [WARN] cycle=%s run_hash=%s log.rotate_blocked reason=%s path_redacted=1' \
      "$(timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$rotation_safety_error")"
    append_log_line_secure "$rotation_line" "log_rotate_blocked"
    printf '%s\n' "$rotation_line"
    return 0
  fi

  rotate_after_hours="$(sanitize_nonnegative_integer "$CODEX_LOG_ROTATE_AFTER_HOURS" "72")"
  keep_hours="$(sanitize_nonnegative_integer "$CODEX_LOG_ROTATE_KEEP_HOURS" "144")"

  if [[ "$rotate_after_hours" -eq 0 ]]; then
    rm -f -- "$live_log_snapshot"
    return 0
  fi

  oldest_epoch="$(oldest_wrapper_log_epoch "$live_log_snapshot" || true)"
  if [[ -z "$oldest_epoch" || ! "$oldest_epoch" =~ ^[0-9]+$ ]]; then
    rm -f -- "$live_log_snapshot"
    return 0
  fi

  rotate_after_seconds=$((rotate_after_hours * 3600))
  now_epoch="$(date '+%s')"
  if (( now_epoch - oldest_epoch < rotate_after_seconds )); then
    rm -f -- "$live_log_snapshot"
    return 0
  fi

  archive_timestamp="$(date '+%Y%m%dT%H%M%S%z')"
  archive_path="$LOG_FILE.$archive_timestamp.zip"
  archive_temp_path="$archive_path.tmp.$$"
  archive_retained=0
  archive_reason="archive_parent_not_private"
  live_log_hash="$(upkeeper_path_hmac "$LOG_FILE")"
  archive_path_hash="$(upkeeper_path_hmac "$archive_path")"

  if wrapper_log_archive_parent_is_private; then
    archive_reason="zip_failed"
    if write_wrapper_log_archive_from_snapshot "$live_log_snapshot" "$archive_temp_path" >/dev/null 2>&1; then
      archive_owner="$(stat -Lc '%u' -- "$archive_temp_path" 2>/dev/null || printf '')"
      archive_mode="$(stat -Lc '%a' -- "$archive_temp_path" 2>/dev/null || printf '')"
      if [[ "$archive_owner" == "$(id -u)" && "$archive_mode" == "600" ]] \
        && mv -f -- "$archive_temp_path" "$archive_path"; then
        archive_retained=1
      else
        archive_reason="archive_mode_verification_failed"
        rm -f -- "$archive_temp_path"
      fi
    else
      rm -f -- "$archive_temp_path"
    fi
  fi

  rotation_safety_error="$(truncate_wrapper_live_log_secure 2>/dev/null || true)"
  rm -f -- "$live_log_snapshot"
  if [[ -z "$rotation_safety_error" ]]; then
    if [[ "$archive_retained" -eq 1 ]]; then
      rotation_line="$(printf '%s [INFO] cycle=%s run_hash=%s log.rotate live_hash=%s archive_hash=%s path_redacted=1 rotate_after_hours=%s keep_hours=%s oldest_entry_epoch=%s' \
        "$(timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$live_log_hash" "$archive_path_hash" "$rotate_after_hours" "$keep_hours" "$oldest_epoch")"
      append_log_line_secure "$rotation_line" "log_rotate"
      printf '%s\n' "$rotation_line"
    else
      rm -f -- "$archive_path"
      rotation_line="$(printf '%s [WARN] cycle=%s run_hash=%s log.rotate_unarchived live_hash=%s attempted_archive_hash=%s path_redacted=1 rotate_after_hours=%s keep_hours=%s oldest_entry_epoch=%s reason=%s' \
        "$(timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$live_log_hash" "$archive_path_hash" "$rotate_after_hours" "$keep_hours" "$oldest_epoch" "$archive_reason")"
      append_log_line_secure "$rotation_line" "log_rotate_unarchived"
      printf '%s\n' "$rotation_line"
    fi
  else
    rm -f -- "$archive_temp_path" "$archive_path"
    rotation_line="$(printf '%s [WARN] cycle=%s run_hash=%s log.rotate_failed live_hash=%s attempted_archive_hash=%s path_redacted=1 reason=truncate_failed archive_reason=%s safety_reason=%s' \
      "$(timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$live_log_hash" "$archive_path_hash" "$archive_reason" "$rotation_safety_error")"
    append_log_line_secure "$rotation_line" "log_rotate_failed"
    printf '%s\n' "$rotation_line"
  fi

  prune_wrapper_log_archives
  return 0
}
