oldest_wrapper_log_epoch() {
  if [[ ! -s "$LOG_FILE" ]]; then
    return 1
  fi

  python3 - "$LOG_FILE" <<'PY'
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
  local archive_path archive_timestamp

  prune_wrapper_log_archives

  if [[ ! -s "$LOG_FILE" ]]; then
    return 0
  fi

  rotate_after_hours="$(sanitize_nonnegative_integer "$CODEX_LOG_ROTATE_AFTER_HOURS" "72")"
  keep_hours="$(sanitize_nonnegative_integer "$CODEX_LOG_ROTATE_KEEP_HOURS" "144")"

  if [[ "$rotate_after_hours" -eq 0 ]]; then
    return 0
  fi

  oldest_epoch="$(oldest_wrapper_log_epoch || true)"
  if [[ -z "$oldest_epoch" || ! "$oldest_epoch" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  rotate_after_seconds=$((rotate_after_hours * 3600))
  now_epoch="$(date '+%s')"
  if (( now_epoch - oldest_epoch < rotate_after_seconds )); then
    return 0
  fi

  archive_timestamp="$(date '+%Y%m%dT%H%M%S%z')"
  archive_path="$LOG_FILE.$archive_timestamp.zip"
  if zip -qjm "$archive_path" "$LOG_FILE" >/dev/null 2>&1; then
    : >"$LOG_FILE"
    printf '%s [INFO] cycle=%s run_hash=%s log.rotate live=%s archive=%s rotate_after_hours=%s keep_hours=%s oldest_entry_epoch=%s\n' \
      "$(timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$LOG_FILE" "$archive_path" "$rotate_after_hours" "$keep_hours" "$oldest_epoch" | tee -a "$LOG_FILE"
  else
    rm -f "$archive_path"
    printf '%s [WARN] cycle=%s run_hash=%s log.rotate_failed live=%s attempted_archive=%s reason=zip_failed\n' \
      "$(timestamp_now)" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$LOG_FILE" "$archive_path" | tee -a "$LOG_FILE"
  fi

  prune_wrapper_log_archives
}
