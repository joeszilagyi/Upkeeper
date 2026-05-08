prune_transcript_artifacts() {
  local transcript_dir="$CODEX_TRANSCRIPT_DIR"
  local keep_hours max_mb

  [[ -n "$transcript_dir" ]] || return 0
  keep_hours="$(sanitize_nonnegative_integer "$CODEX_TRANSCRIPT_KEEP_HOURS" "24")"
  max_mb="$(sanitize_nonnegative_integer "$CODEX_TRANSCRIPT_KEEP_MAX_MB" "200")"

  python3 - "$transcript_dir" "$keep_hours" "$max_mb" <<'PY' || true
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
  git hash-object -- "$path" 2>/dev/null || printf 'unknown'
}

hash_text() {
  local value="$1"
  python3 - "$value" <<'PY' 2>/dev/null || printf 'unknown'
import hashlib
import sys

print(hashlib.sha256(sys.argv[1].encode("utf-8", "surrogateescape")).hexdigest()[:24])
PY
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
