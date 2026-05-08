# Detached fallback supervision.
#
# Screen fallback exists so a stronger model can clean up after the primary path
# without tying recovery to the visible terminal. The parent therefore writes and
# polls explicit state files; `screen -dmS` returning zero is not enough evidence
# that a recovery child actually started or finished.
#
# Runtime artifact and marker reads happen in cleanup/logging paths; transient
# files should degrade to sentinel values instead of aborting under `set -e`.
shell_quote() {
  printf '%q' "$1"
}

read_artifact_or_unknown() {
  local path="$1"
  if [[ -s "$path" && -r "$path" ]]; then
    if tr -d '\r\n' 2>/dev/null <"$path"; then
      return 0
    fi
  fi
  printf 'unknown'
}

marker_field() {
  local path="$1"
  local key="$2"
  [[ -r "$path" ]] || return 0
  awk -v key="$key" '
    index($0, key ":") == 1 {
      sub("^[^:]*:[[:space:]]*", "")
      print
      exit
    }
  ' "$path" 2>/dev/null || return 0
}
