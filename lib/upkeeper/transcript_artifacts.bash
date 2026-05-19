transcript_artifacts_marker_path() {
  local transcript_dir="$1"
  printf '%s/.upkeeper-transcript-artifacts.marker' "$transcript_dir"
}

transcript_artifacts_marker_expected() {
  local transcript_dir="$1"
  upkeeper_path_hmac "$transcript_dir"
}

transcript_artifacts_marker_readable() {
  local marker_path="$1"
  local marker_current

  [[ -f "$marker_path" && ! -L "$marker_path" ]] || return 1
  IFS= read -r marker_current < "$marker_path" || true
  [[ -n "$marker_current" ]] || return 1
  printf '%s' "$marker_current"
}

prune_transcript_artifacts() {
  local transcript_dir="$CODEX_TRANSCRIPT_DIR"
  local transcript_dir_abs marker_path marker_expected marker_current
  local default_transcript_dir keep_hours max_mb
  local owner mode

  [[ -n "$transcript_dir" ]] || return 0
  transcript_dir_abs="$(resolve_upkeeper_config_path "$transcript_dir")"
  default_transcript_dir="$ROOT_DIR/runtime/upkeeper-transcripts"

  if [[ -L "$transcript_dir_abs" ]]; then
    log_line "WARN" "transcript.prune_blocked reason=path_is_symlink path_redacted=1"
    return 0
  fi
  if [[ "$transcript_dir_abs" != "$default_transcript_dir" ]]; then
    marker_path="$(transcript_artifacts_marker_path "$transcript_dir_abs")"
    marker_expected="$(transcript_artifacts_marker_expected "$transcript_dir_abs")"
    marker_current="$(transcript_artifacts_marker_readable "$marker_path" || true)"
    if [[ "$marker_current" != "$marker_expected" ]]; then
      log_line "WARN" "transcript.prune_blocked reason=missing_ownership_marker path_redacted=1"
      return 0
    fi
    owner="$(stat -Lc '%u' -- "$marker_path" 2>/dev/null || printf '')"
    mode="$(stat -Lc '%a' -- "$marker_path" 2>/dev/null || printf '')"
    [[ "$owner" == "$(id -u)" ]] || {
      log_line "WARN" "transcript.prune_blocked reason=marker_wrong_owner path_redacted=1"
      return 0
    }
    [[ "$mode" == "600" ]] || {
      log_line "WARN" "transcript.prune_blocked reason=marker_wrong_mode path_redacted=1"
      return 0
    }
  fi

  keep_hours="$(sanitize_nonnegative_integer "$CODEX_TRANSCRIPT_KEEP_HOURS" "24")"
  max_mb="$(sanitize_nonnegative_integer "$CODEX_TRANSCRIPT_KEEP_MAX_MB" "200")"

  python3 - "$transcript_dir_abs" "$keep_hours" "$max_mb" <<'PY' || true
from pathlib import Path
import sys
import time

root = Path(sys.argv[1])
keep_hours = int(sys.argv[2])
max_mb = int(sys.argv[3])
try:
    root.mkdir(parents=True, exist_ok=True)
except OSError:
    raise SystemExit(0)
if keep_hours > 0:
    cutoff = time.time() - keep_hours * 3600
    for path in root.glob('*.log'):
        try:
            if path.is_file() and path.stat().st_mtime < cutoff:
                path.unlink()
        except OSError:
            pass
if max_mb <= 0:
    raise SystemExit(0)
max_bytes = max_mb * 1024 * 1024
entries = []
for path in root.glob('*.log'):
    try:
        st = path.stat()
    except OSError:
        continue
    if path.is_file():
        entries.append((st.st_mtime, st.st_size, path))
total = sum(size for _, size, _ in entries)
for _, size, path in sorted(entries):
    if total <= max_bytes:
        break
    try:
        path.unlink()
        total -= size
    except OSError:
        pass
PY
}

new_transcript_file() {
  local label="${1:-codex}"
  local transcript_dir="$CODEX_TRANSCRIPT_DIR"
  label="${label//[^A-Za-z0-9_.-]/_}"
  [[ -n "$transcript_dir" ]] || transcript_dir="$ROOT_DIR/runtime/upkeeper-transcripts"
  if ! mkdir -p -- "$transcript_dir"; then
    die "failed to create transcript directory $transcript_dir"
  fi
  chmod 700 "$transcript_dir" 2>/dev/null || true
  prune_transcript_artifacts
  mktemp "$transcript_dir/$CYCLE_ID.$CYCLE_RUN_HASH.$label.XXXXXX.log"
}

file_blob_hash() {
  local path="$1"
  local raw_hash

  raw_hash="$(git hash-object -- "$path" 2>/dev/null || true)"
  upkeeper_content_hmac "${raw_hash:-unknown}"
}

hash_text() {
  local value="$1"
  upkeeper_value_hmac text "$value"
}

file_size_bytes() {
  local path="$1"
  if command -v stat >/dev/null 2>&1; then
    stat -c '%s' -- "$path" 2>/dev/null && return 0
  fi
  python3 - "$path" <<'PY' 2>/dev/null || printf 'unknown'
import os
import sys
try:
    print(os.stat(sys.argv[1]).st_size)
except OSError:
    print("unknown")
PY
}

file_line_count() {
  local path="$1"
  local count

  if count="$(wc -l <"$path" 2>/dev/null)"; then
    printf '%s' "${count//[[:space:]]/}"
    return 0
  fi

  printf 'unknown'
}
