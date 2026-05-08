format_epoch_local() {
  local epoch="$1"
  if [[ -z "$epoch" || "$epoch" == "null" ]]; then
    printf 'unknown'
    return 0
  fi
  if [[ "$epoch" =~ ^[0-9]+([.][0-9]+)?$ ]] && date -d "@$epoch" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null; then
    return 0
  fi
  python3 - "$epoch" <<'PY' 2>/dev/null || printf '%s' "$epoch"
from datetime import datetime
import sys

try:
    epoch = int(float(sys.argv[1]))
except ValueError:
    raise SystemExit(1)

print(datetime.fromtimestamp(epoch).astimezone().strftime("%Y-%m-%dT%H:%M:%S%z"))
PY
}

json_field() {
  local json="$1"
  local path="$2"

  jq -r "$path // empty" <<<"$json" 2>/dev/null
}
