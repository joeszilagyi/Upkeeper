timestamp_now() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

epoch_now_fraction() {
  local now
  now="$(date '+%s.%N' 2>/dev/null || true)"
  if [[ "$now" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf '%.5f\n' "$now"
  else
    date '+%s'
  fi
}

system_boot_id() {
  if [[ -r /proc/sys/kernel/random/boot_id ]]; then
    tr -d '[:space:]' </proc/sys/kernel/random/boot_id
  else
    printf 'unknown'
  fi
}

system_uptime_seconds() {
  if [[ -r /proc/uptime ]]; then
    awk '{ printf "%.2f", $1 }' /proc/uptime
  else
    printf 'unknown'
  fi
}

process_start_fingerprint() {
  local pid="$1"
  local stat_text after_comm
  if [[ -r "/proc/$pid/stat" ]]; then
    IFS= read -r stat_text <"/proc/$pid/stat" || true
    after_comm="${stat_text##*) }"
    set -- $after_comm
    if [[ $# -ge 20 && -n "${20:-}" ]]; then
      printf 'proc_start_ticks=%s' "${20}"
      return 0
    fi
  fi
  printf 'proc_start_ticks=unknown'
}

generate_fallback_chain_token() {
  local token
  if [[ -r /dev/urandom ]]; then
    token="$(od -An -N 24 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
    if [[ "${#token}" -eq 48 ]]; then
      printf '%s' "$token"
      return 0
    fi
  fi
  printf '%s' "fallback-${CYCLE_ID:-unknown}-$$-$(date '+%s%N' 2>/dev/null || date '+%s')"
}

terminal_mode() {
  local raw="${CODEX_TERMINAL_VERBOSITY:-basic}"
  raw="${raw,,}"
  case "$raw" in
    ''|basic|summary|normal|default)
      printf 'basic'
      ;;
    verbose|1|yes|true)
      printf 'verbose'
      ;;
    debug|debug1)
      printf 'debug1'
      ;;
    quiet)
      printf 'quiet'
      ;;
    silent|none|0|no|false)
      printf 'silent'
      ;;
    full|raw)
      printf 'full'
      ;;
    *)
      printf '%s' "$raw"
      ;;
  esac
}

terminal_wants_full_output() {
  case "$(terminal_mode)" in
    full)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_wants_quiet_output() {
  case "$(terminal_mode)" in
    quiet)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_wants_silent_output() {
  case "$(terminal_mode)" in
    silent)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_wants_verbose_output() {
  case "$(terminal_mode)" in
    verbose|debug1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_suppresses_progress() {
  case "$(terminal_mode)" in
    silent)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_suppresses_heartbeat() {
  case "$(terminal_mode)" in
    quiet|silent|full)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terminal_emit_progress() {
  local message="$*"
  local mode

  terminal_wants_full_output && return 0
  terminal_suppresses_progress && return 0
  mode="$(terminal_mode)"
  if [[ "$mode" == "quiet" ]]; then
    case "$message" in
      selected\ file*|starting\ Codex*|Codex\ review\ finished*|review\ completed*)
        ;;
      *)
        return 0
        ;;
    esac
  fi
  printf '%s [INFO] Upkeeper: %s\n' "$(timestamp_now)" "$message" >&2
}

terminal_emit_log_line() {
  local level="$1"
  local line="$2"

  if terminal_wants_full_output; then
    printf '%s\n' "$line"
    return 0
  fi
  terminal_wants_silent_output && return 0
  if terminal_wants_quiet_output; then
    case "$level" in
      WARN|ERROR)
        printf '%s\n' "$line" >&2
        ;;
    esac
    return 0
  fi
  case "$level" in
    WARN|ERROR)
      printf '%s\n' "$line" >&2
      ;;
  esac
}

append_log_line_secure() {
  local line="$1"
  local phase="${2:-append}"
  local detail rc

  if detail="$(
    python3 - "$LOG_FILE" 3<<<"$line" <<'PY' 2>&1
import errno
import os
import stat
import sys

path_raw = sys.argv[1]

try:
    line = os.fdopen(3, "r", encoding="utf-8", errors="surrogateescape").read()
except OSError as exc:
    print(f"line_read_failed errno={exc.errno}")
    raise SystemExit(1)
if not line.endswith("\n"):
    line += "\n"

parent = os.path.dirname(path_raw) or "."
name = os.path.basename(path_raw)
uid = os.getuid()


def fail(reason: str) -> None:
    print(reason)
    raise SystemExit(1)


def mode_text(mode: int) -> str:
    return oct(stat.S_IMODE(mode))


if not name or name in {".", ".."}:
    fail("invalid_log_filename")

try:
    path_stat = os.lstat(path_raw)
except FileNotFoundError:
    path_stat = None
except OSError as exc:
    fail(f"log_file_stat_failed errno={exc.errno}")

if path_stat is not None:
    if stat.S_ISLNK(path_stat.st_mode):
        fail("symlink_log_file")
    if not stat.S_ISREG(path_stat.st_mode):
        fail(f"non_regular_log_file mode={mode_text(path_stat.st_mode)}")
    if path_stat.st_uid != uid:
        fail(f"wrong_log_owner uid={path_stat.st_uid} expected_uid={uid}")
    if path_stat.st_nlink != 1:
        fail(f"hardlinked_log_file links={path_stat.st_nlink}")

dir_flags = os.O_RDONLY
for attr in ("O_DIRECTORY", "O_CLOEXEC", "O_NOFOLLOW"):
    dir_flags |= getattr(os, attr, 0)


def open_log_parent(raw_parent):
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

file_flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND
for attr in ("O_CLOEXEC", "O_NONBLOCK", "O_NOFOLLOW"):
    file_flags |= getattr(os, attr, 0)

try:
    try:
        fd = os.open(name, file_flags, 0o600, dir_fd=parent_fd)
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

        data = line.encode("utf-8", errors="surrogateescape")
        while data:
            try:
                written = os.write(fd, data)
            except OSError as exc:
                fail(f"log_file_write_failed errno={exc.errno}")
            if written <= 0:
                fail("log_file_write_failed bytes=0")
            data = data[written:]
    finally:
        os.close(fd)
finally:
    os.close(parent_fd)
PY
  )"; then
    return 0
  else
    rc=$?
  fi
  detail="${detail//$'\n'/; }"
  [[ -n "$detail" ]] || detail="unknown"
  printf '%s [ERROR] cycle=%s run_hash=%s log.write_failed phase=%s path=%s reason=%s\n' "$(timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$phase" "$LOG_FILE" "$detail" >&2
  return "$rc"
}

log_line() {
  local level="$1"
  shift
  local ts line
  ts="$(timestamp_now)"
  line="$(printf '%s [%s] cycle=%s run_hash=%s %s' "$ts" "$level" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$*")"
  append_log_line_secure "$line" "log_line"
  terminal_emit_log_line "$level" "$line"
}

ensure_log_parent() {
  if [[ -n "$LOG_FILE_DIR" && "$LOG_FILE_DIR" != "." ]]; then
    if ! mkdir -p -- "$LOG_FILE_DIR"; then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s\n' "$(timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" >&2
      exit 3
    fi

    if [[ -L "$LOG_FILE_DIR" ]]; then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s reason=symlink_parent\n' "$(timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" >&2
      exit 3
    fi
    if [[ ! -d "$LOG_FILE_DIR" ]]; then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s reason=not_directory\n' "$(timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" >&2
      exit 3
    fi

    log_parent_uid="$(stat -Lc '%u' -- "$LOG_FILE_DIR" 2>/dev/null || printf '')"
    log_parent_mode="$(stat -Lc '%a' -- "$LOG_FILE_DIR" 2>/dev/null || printf '')"
    if [[ -z "$log_parent_uid" || -z "$log_parent_mode" ]]; then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s reason=stat_failed\n' "$(timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" >&2
      exit 3
    fi

    if [[ "$log_parent_uid" != "$(id -u)" ]]; then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s reason=wrong_owner expected=%s actual=%s\n' \
        "$(timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" "$(id -u)" "$log_parent_uid" >&2
      exit 3
    fi
    if (( (8#$log_parent_mode & 8#022) != 0 )); then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s reason=unsafe_permissions mode=%s\n' \
        "$(timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" "$log_parent_mode" >&2
      exit 3
    fi
  fi
}

ensure_run_tmp_dir() {
  if [[ -n "$RUN_TMP_DIR" ]]; then
    if [[ -L "$RUN_TMP_DIR" ]]; then
      die "run temp directory is a symlink $RUN_TMP_DIR"
    fi
    if [[ ! -d "$RUN_TMP_DIR" ]]; then
      die "run temp directory is not a directory $RUN_TMP_DIR"
    fi
    if ! chmod 700 "$RUN_TMP_DIR"; then
      die "run temp directory is not writable $RUN_TMP_DIR"
    fi
    owner="$(stat -Lc '%u' -- "$RUN_TMP_DIR" 2>/dev/null || printf '')"
    if [[ -z "$owner" || "$owner" != "$(id -u)" ]]; then
      die "run temp directory has unexpected owner $RUN_TMP_DIR"
    fi
    mode="$(stat -Lc '%a' -- "$RUN_TMP_DIR" 2>/dev/null || printf '')"
    if [[ -z "$mode" || "$mode" != 700 ]]; then
      die "run temp directory permissions are insecure $RUN_TMP_DIR"
    fi
    log_line "INFO" "run.tmp_dir path=$(shell_quote "$RUN_TMP_DIR")" >/dev/null
    return 0
  fi

  local tmp_base="${TMPDIR:-/tmp}"
  local mode owner
  if ! RUN_TMP_DIR="$(mktemp -d "$tmp_base/upkeeper-XXXXXX")"; then
    die "failed to create run temp directory under $tmp_base"
  fi

  if ! chmod 700 "$RUN_TMP_DIR"; then
    die "run temp directory is not writable $RUN_TMP_DIR"
  fi
  owner="$(stat -Lc '%u' -- "$RUN_TMP_DIR" 2>/dev/null || printf '')"
  if [[ -z "$owner" || "$owner" != "$(id -u)" ]]; then
    die "run temp directory has unexpected owner $RUN_TMP_DIR"
  fi
  mode="$(stat -Lc '%a' -- "$RUN_TMP_DIR" 2>/dev/null || printf '')"
  if [[ -z "$mode" || "$mode" != 700 ]]; then
    die "run temp directory permissions are insecure $RUN_TMP_DIR"
  fi
  if [[ -L "$RUN_TMP_DIR" ]]; then
    rm -rf -- "$RUN_TMP_DIR"
    die "run temp directory is a symlink $RUN_TMP_DIR"
  fi
  log_line "INFO" "run.tmp_dir path=$(shell_quote "$RUN_TMP_DIR")" >/dev/null
}

run_mktemp() {
  local label="${1:-tmp}"
  ensure_run_tmp_dir
  mktemp "$RUN_TMP_DIR/${label}.XXXXXX"
}
