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

  # Callers pass wrapper-owned JSON. Malformed input is a wrapper defect, so
  # keep the non-zero exit and make the failed extraction visible to operators.
  # jq's // operator treats false as absent; preserve real booleans while still
  # mapping missing or null fields to the empty string for marker callers.
  if ! jq -r "($path) as \$value | if \$value == null then empty else \$value end" <<<"$json"; then
    printf 'Upkeeper: ERROR: json_field failed for jq path %s\n' "$path" >&2
    return 1
  fi
}

json_fields_nul() {
  local json="$1"
  shift
  local path filter="" separator=""

  [[ $# -gt 0 ]] || return 0

  for path in "$@"; do
    filter+="${separator}((${path}) as \$value | if \$value == null then \"\" elif ((\$value | type) == \"array\" or (\$value | type) == \"object\") then (\$value | tojson) else (\$value | tostring) end)"
    separator=', "\u0000", '
  done
  filter+=', "\u0000"'

  if ! jq -j "$filter" <<<"$json"; then
    printf 'Upkeeper: ERROR: json_fields_nul failed for %s jq path(s)\n' "$#" >&2
    return 1
  fi
}
