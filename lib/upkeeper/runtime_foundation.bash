timestamp_now() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

terminal_timestamp_now() {
  date '+%Y-%m-%dT%H:%M:%S'
}

terminal_strip_column_timezone() {
  local line="${1:-}"

  if [[ "$line" =~ ^([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9])([+-][0-9][0-9][0-9][0-9])([[:space:]].*)?$ ]]; then
    printf '%s%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]:-}"
    return 0
  fi
  printf '%s\n' "$line"
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

log_kv_value() {
  printf '%q' "${1:-}"
}

log_kv() {
  local key="$1"
  local value="${2:-}"

  case "$key" in
    ''|*[!A-Za-z0-9_.-]*)
      key="invalid_key"
      ;;
  esac
  printf '%s=%s' "$key" "$(log_kv_value "$value")"
}

log_line_parts() {
  local level="$1"
  shift
  local message=""
  local part

  for part in "$@"; do
    message+="$part"
  done
  log_line "$level" "$message"
}

upkeeper_value_has_control_chars() {
  local value="${1:-}"

  case "$value" in
    *[[:cntrl:]]*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

upkeeper_path_contains_symlink_component() {
  local path="${1:-}"
  local candidate

  [[ -n "$path" ]] || return 1
  if [[ "$path" == "/" ]]; then
    [[ -L "/" ]]
    return
  fi

  path="${path%/}"
  candidate="$path"
  while [[ -n "$candidate" && "$candidate" != "." && "$candidate" != "/" ]]; do
    if [[ -L "$candidate" ]]; then
      return 0
    fi
    candidate="$(dirname -- "$candidate")"
  done

  return 1
}

upkeeper_private_directory_is_secure() {
  local path="${1:-}"
  local owner
  local mode

  [[ -n "$path" ]] || return 1
  if upkeeper_path_contains_symlink_component "$path"; then
    return 1
  fi
  if [[ -L "$path" ]]; then
    return 1
  fi
  if [[ -e "$path" ]] && ! [[ -d "$path" ]]; then
    return 1
  fi

  if [[ -e "$path" ]]; then
    if ! chmod 700 "$path" 2>/dev/null; then
      return 1
    fi
  else
    if ! mkdir -p -m 700 -- "$path" 2>/dev/null; then
      return 1
    fi
  fi

  owner="$(stat -Lc '%u' -- "$path" 2>/dev/null || printf '')"
  mode="$(stat -Lc '%a' -- "$path" 2>/dev/null || printf '')"
  [[ -n "$owner" && -n "$mode" ]] || return 1
  [[ "$owner" == "$(id -u)" ]] || return 1
  [[ "$mode" == "700" ]] || return 1

  return 0
}

upkeeper_redaction_key_material() {
  local key_file key_dir key_value token persist_key key_owner key_mode

  if [[ -n "${UPKEEPER_REDACTION_KEY:-}" ]]; then
    printf '%s' "$UPKEEPER_REDACTION_KEY"
    return 0
  fi
  if [[ -n "${UPKEEPER_LATTICE_REDACTION_KEY:-}" ]]; then
    printf '%s' "$UPKEEPER_LATTICE_REDACTION_KEY"
    return 0
  fi

  key_file="${UPKEEPER_REDACTION_KEY_FILE:-${ROOT_DIR:-$PWD}/runtime/upkeeper-redaction.key}"
  key_dir="$(dirname -- "$key_file")"
  persist_key=1
  if [[ -e "$key_file" ]]; then
    if [[ -L "$key_file" || ! -f "$key_file" ]]; then
      persist_key=0
    fi
    key_owner="$(stat -Lc '%u' -- "$key_file" 2>/dev/null || printf '')"
    key_mode="$(stat -Lc '%a' -- "$key_file" 2>/dev/null || printf '')"
    if [[ -r "$key_file" && "$key_owner" == "$(id -u)" && "$key_mode" == "600" ]]; then
      IFS= read -r key_value <"$key_file" || key_value=""
      if [[ -n "$key_value" ]]; then
        printf '%s' "$key_value"
        return 0
      fi
    fi
    if [[ -n "$key_owner" && "$key_owner" != "$(id -u)" ]]; then
      persist_key=0
    fi
  fi

  if upkeeper_path_contains_symlink_component "$key_dir"; then
    persist_key=0
  elif ! mkdir -p -m 700 -- "$key_dir" 2>/dev/null; then
    persist_key=0
  elif ! chmod 700 "$key_dir" 2>/dev/null; then
    persist_key=0
  elif [[ "$(stat -Lc '%u' -- "$key_dir" 2>/dev/null || printf '')" != "$(id -u)" ]]; then
    persist_key=0
  elif [[ "$(stat -Lc '%a' -- "$key_dir" 2>/dev/null || printf '')" != "700" ]]; then
    persist_key=0
  fi

  if [[ "$persist_key" == "1" && -r "$key_file" ]]; then
    IFS= read -r key_value <"$key_file" || key_value=""
    if [[ -n "$key_value" ]]; then
      printf '%s' "$key_value"
      return 0
    fi
  fi

  if [[ -r /dev/urandom ]]; then
    token="$(od -An -N 32 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
  else
    token=""
  fi
  if [[ -z "$token" ]]; then
    token="$(printf '%s' "${ROOT_DIR:-$PWD}|${CYCLE_ID:-unknown}|$$|$(date '+%s%N' 2>/dev/null || date '+%s')" | sha256sum 2>/dev/null | awk '{print $1}')"
  fi
  if [[ -n "$token" ]]; then
    if [[ "$persist_key" == "1" ]]; then
      if printf '%s\n' "$token" >"$key_file" 2>/dev/null && chmod 600 "$key_file" 2>/dev/null; then
        printf '%s' "$token"
        return 0
      fi
      rm -f -- "$key_file" 2>/dev/null || true
    fi
    printf '%s' "$token"
    return 0
  fi

  printf '%s' "${ROOT_DIR:-$PWD}|upkeeper-redaction-fallback"
}

upkeeper_hmac_sha256_text() {
  local namespace="$1"
  local value="${2:-}"
  local key

  key="$(upkeeper_redaction_key_material)"
  python3 - "$key" "$namespace" "$value" <<'PY' 2>/dev/null || printf 'unknown'
import hashlib
import hmac
import sys

key, namespace, value = sys.argv[1:4]
material = f"{namespace}\0{value}".encode("utf-8", "surrogateescape")
print(hmac.new(key.encode("utf-8", "surrogateescape"), material, hashlib.sha256).hexdigest())
PY
}

upkeeper_path_hmac() {
  local value="${1:-}"

  if [[ -z "$value" || "$value" == "none" || "$value" == "unknown" ]]; then
    printf '%s' "${value:-none}"
    return 0
  fi
  printf 'path-hmac-sha256:%s' "$(upkeeper_hmac_sha256_text path "$value")"
}

upkeeper_value_hmac() {
  local namespace="$1"
  local value="${2:-}"

  if [[ -z "$value" || "$value" == "none" || "$value" == "unknown" || "$value" == "missing" || "$value" == "unavailable" || "$value" == "clean" ]]; then
    printf '%s' "${value:-unknown}"
    return 0
  fi
  printf 'value-hmac-sha256:%s' "$(upkeeper_hmac_sha256_text "$namespace" "$value")"
}

upkeeper_content_hmac() {
  local value="${1:-}"

  if [[ -z "$value" || "$value" == "none" || "$value" == "unknown" || "$value" == "missing" || "$value" == "unavailable" || "$value" == "clean" || "$value" == "not_regular" ]]; then
    printf '%s' "${value:-unknown}"
    return 0
  fi
  printf 'content-hmac-sha256:%s' "$(upkeeper_hmac_sha256_text content "$value")"
}

upkeeper_redact_model_text() {
  local value="${1:-}"
  local max_len="${2:-700}"
  local key root

  key="$(upkeeper_redaction_key_material)"
  root="${ROOT_DIR:-$PWD}"
  python3 - "$key" "$root" "$max_len" "$value" <<'PY' 2>/dev/null || {
import hashlib
import hmac
import os
import re
import sys

key, root_raw, max_len_raw, value = sys.argv[1:5]
try:
    max_len = max(80, int(max_len_raw))
except ValueError:
    max_len = 700
root = os.path.realpath(root_raw)
key_bytes = key.encode("utf-8", "surrogateescape")


def digest(namespace: str, text: str) -> str:
    material = f"{namespace}\0{text}".encode("utf-8", "surrogateescape")
    return hmac.new(key_bytes, material, hashlib.sha256).hexdigest()


def path_repl(match: re.Match[str]) -> str:
    raw = match.group(0).rstrip(".,;:)]}'\"")
    suffix = match.group(0)[len(raw):]
    if raw == "/dev/null" or raw.startswith(("/bin/", "/usr/bin/", "/usr/local/bin/", "/opt/homebrew/bin/")):
        return raw + suffix
    try:
        resolved = os.path.realpath(raw)
    except OSError:
        resolved = raw
    try:
        rel = os.path.relpath(resolved, root)
    except ValueError:
        rel = ""
    if rel and not rel.startswith("..") and not os.path.isabs(rel):
        label = f"repo-path:{rel}"
    else:
        label = f"path-hmac-sha256:{digest('path', raw)}"
    return label + suffix


def email_repl(match: re.Match[str]) -> str:
    return f"email-hmac-sha256:{digest('email', match.group(0))}"


text = value.replace("\r", " ").replace("\n", " ")
text = re.sub(r"\s+", " ", text).strip()
text = re.sub(r"-----BEGIN [^-]{0,80}PRIVATE KEY-----.*?-----END [^-]{0,80}PRIVATE KEY-----", "[redacted-private-key]", text, flags=re.I)
text = re.sub(r"\bBearer\s+[A-Za-z0-9._~+/=-]{12,}", "Bearer [redacted-token]", text, flags=re.I)
text = re.sub(r"\b(?:sk-[A-Za-z0-9_-]{10,}|ghp_[A-Za-z0-9_]{10,}|github_pat_[A-Za-z0-9_]{10,}|AKIA[0-9A-Z]{12,}|xox[baprs]-[A-Za-z0-9-]{10,})\b", "[redacted-token]", text)
text = re.sub(r"\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b", "[redacted-jwt]", text)
text = re.sub(r"(?i)\b(api[_-]?key|access[_-]?token|auth[_-]?token|secret|password|passwd|credential|authorization)\b\s*[:=]\s*['\"]?[^'\"\s;,]{4,}", r"\1=[redacted-secret]", text)
text = re.sub(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b", email_repl, text)
text = re.sub(r"(?<![A-Za-z0-9:])/(?:[A-Za-z0-9._@%+=:,~-]+/)*[A-Za-z0-9._@%+=:,~-]+", path_repl, text)
if len(text) > max_len:
    text = text[: max_len - 15].rstrip() + "...<truncated>"
print(text)
PY
    printf '%s' "${value//$'\n'/ }"
  }
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
  message="$(upkeeper_redact_model_text "$message" 420)"
  printf '%s [INFO] Upkeeper: %s\n' "$(terminal_timestamp_now)" "$message" >&2
}

terminal_emit_log_line() {
  local level="$1"
  local line="$2"

  if terminal_wants_full_output; then
    terminal_strip_column_timezone "$line"
    return 0
  fi
  terminal_wants_silent_output && return 0
  if terminal_wants_quiet_output; then
    case "$level" in
      WARN|ERROR)
        terminal_strip_column_timezone "$line" >&2
        ;;
    esac
    return 0
  fi
  case "$level" in
    WARN|ERROR)
      terminal_strip_column_timezone "$line" >&2
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
  printf '%s [ERROR] cycle=%s run_hash=%s log.write_failed phase=%s path=%s reason=%s\n' "$(terminal_timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$phase" "$LOG_FILE" "$detail" >&2
  return "$rc"
}

log_line() {
  local level="$1"
  shift
  local ts line

  if declare -F tool_failure_queue_open_custody_log >/dev/null 2>&1 &&
    tool_failure_queue_open_custody_log "$level" "$*"; then
    # An open tool-failure marker is the durable custody record for a failed
    # local check. Keep it visible without making the custody row a new WARN.
    level="INFO"
    set -- "tool_failure_queue.open_custody custody=tool_failure_queue $*"
  fi

  ts="$(timestamp_now)"
  line="$(printf '%s [%s] cycle=%s run_hash=%s %s' "$ts" "$level" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$*")"
  append_log_line_secure "$line" "log_line"
  terminal_emit_log_line "$level" "$line"
}

ensure_log_parent() {
  if [[ -n "$LOG_FILE_DIR" && "$LOG_FILE_DIR" != "." ]]; then
    if upkeeper_path_contains_symlink_component "$LOG_FILE_DIR"; then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s reason=symlink_parent\n' "$(terminal_timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" >&2
      exit 3
    fi
    if ! mkdir -p -- "$LOG_FILE_DIR"; then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s\n' "$(terminal_timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" >&2
      exit 3
    fi

    if [[ -L "$LOG_FILE_DIR" ]]; then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s reason=symlink_parent\n' "$(terminal_timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" >&2
      exit 3
    fi
    if [[ ! -d "$LOG_FILE_DIR" ]]; then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s reason=not_directory\n' "$(terminal_timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" >&2
      exit 3
    fi

    log_parent_uid="$(stat -Lc '%u' -- "$LOG_FILE_DIR" 2>/dev/null || printf '')"
    log_parent_mode="$(stat -Lc '%a' -- "$LOG_FILE_DIR" 2>/dev/null || printf '')"
    if [[ -z "$log_parent_uid" || -z "$log_parent_mode" ]]; then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s reason=stat_failed\n' "$(terminal_timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" >&2
      exit 3
    fi

    if [[ "$log_parent_uid" != "$(id -u)" ]]; then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s reason=wrong_owner expected=%s actual=%s\n' \
        "$(terminal_timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" "$(id -u)" "$log_parent_uid" >&2
      exit 3
    fi
    if (( (8#$log_parent_mode & 8#022) != 0 )); then
      printf '%s [ERROR] cycle=%s log.parent_failed path=%s reason=unsafe_permissions mode=%s\n' \
        "$(terminal_timestamp_now)" "$CYCLE_ID" "$LOG_FILE_DIR" "$log_parent_mode" >&2
      exit 3
    fi
  fi
}

run_tmp_dir_ownership_marker_path() {
  local run_tmp_dir="$1"

  printf '%s/.upkeeper-run-tmp-owner\n' "$run_tmp_dir"
}

run_tmp_dir_is_wrapper_managed() {
  local run_tmp_dir="${1:-}"
  local tmp_base="${TMPDIR:-/tmp}"

  [[ -n "$run_tmp_dir" && "$run_tmp_dir" == "$tmp_base"/upkeeper-* ]]
}

run_tmp_dir_ownership_marker_is_trusted() {
  local run_tmp_dir="$1"
  local marker_path marker_owner marker_mode marker_header

  marker_path="$(run_tmp_dir_ownership_marker_path "$run_tmp_dir")"
  [[ -f "$marker_path" && ! -L "$marker_path" ]] || return 1

  marker_owner="$(stat -Lc '%u' -- "$marker_path" 2>/dev/null || printf '')"
  marker_mode="$(stat -Lc '%a' -- "$marker_path" 2>/dev/null || printf '')"
  [[ "$marker_owner" == "$(id -u)" && "$marker_mode" == "600" ]] || return 1

  IFS= read -r marker_header <"$marker_path" || return 1
  [[ "$marker_header" == "upkeeper-run-tmp-owner-v1" ]]
}

write_run_tmp_dir_ownership_marker() {
  local run_tmp_dir="$1"
  local marker_path

  marker_path="$(run_tmp_dir_ownership_marker_path "$run_tmp_dir")"
  {
    printf 'upkeeper-run-tmp-owner-v1\n'
    printf 'uid=%s\n' "$(id -u)"
    printf 'cycle=%s\n' "${CYCLE_ID:-unknown}"
  } >"$marker_path" 2>/dev/null || return 1
  chmod 600 "$marker_path" 2>/dev/null || return 1
}

ensure_run_tmp_dir() {
  local tmp_base="${TMPDIR:-/tmp}"
  local run_tmp_dir_preexisted=0

  if [[ -n "$RUN_TMP_DIR" ]]; then
    if [[ -e "$RUN_TMP_DIR" ]]; then
      run_tmp_dir_preexisted=1
    fi
    if ! upkeeper_private_directory_is_secure "$RUN_TMP_DIR"; then
      die "run temp directory is not secure $RUN_TMP_DIR"
    fi
    # Cleanup later only deletes wrapper-managed tmp roots, so reusing an
    # existing matching directory is safe only when a trusted earlier run
    # stamped it as wrapper-owned.
    if (( run_tmp_dir_preexisted )) &&
      run_tmp_dir_is_wrapper_managed "$RUN_TMP_DIR" &&
      ! run_tmp_dir_ownership_marker_is_trusted "$RUN_TMP_DIR"; then
      die "run temp directory is missing a trusted ownership marker $RUN_TMP_DIR"
    fi
    if run_tmp_dir_is_wrapper_managed "$RUN_TMP_DIR" &&
      ! write_run_tmp_dir_ownership_marker "$RUN_TMP_DIR"; then
      die "failed to stamp run temp directory ownership marker $RUN_TMP_DIR"
    fi
    log_line "INFO" "run.tmp_dir path=$(shell_quote "$RUN_TMP_DIR")" >/dev/null
    return 0
  fi

  if upkeeper_path_contains_symlink_component "$tmp_base"; then
    die "run temp base is a symlink $tmp_base"
  fi
  if ! RUN_TMP_DIR="$(mktemp -d "$tmp_base/upkeeper-XXXXXX")"; then
    die "failed to create run temp directory under $tmp_base"
  fi

  if ! upkeeper_private_directory_is_secure "$RUN_TMP_DIR"; then
    rm -rf -- "$RUN_TMP_DIR"
    die "run temp directory is not secure $RUN_TMP_DIR"
  fi
  if ! write_run_tmp_dir_ownership_marker "$RUN_TMP_DIR"; then
    die "failed to stamp run temp directory ownership marker $RUN_TMP_DIR"
  fi
  log_line "INFO" "run.tmp_dir path=$(shell_quote "$RUN_TMP_DIR")" >/dev/null
}

run_mktemp() {
  local label="${1:-tmp}"
  ensure_run_tmp_dir
  mktemp "$RUN_TMP_DIR/${label}.XXXXXX"
}
