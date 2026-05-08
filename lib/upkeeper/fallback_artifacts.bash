# Detached fallback supervision.
#
# Screen fallback exists so a stronger model can clean up after the primary path
# without tying recovery to the visible terminal. The parent therefore writes and
# polls explicit state files; `screen -dmS` returning zero is not enough evidence
# that a recovery child actually started or finished.
shell_quote() {
  printf '%q' "$1"
}

read_artifact_or_unknown() {
  local path="$1"
  if [[ -s "$path" ]]; then
    tr -d '\r\n' <"$path"
  else
    printf 'unknown'
  fi
}

marker_field() {
  local path="$1"
  local key="$2"
  awk -v key="$key" '
    index($0, key ":") == 1 {
      sub("^[^:]*:[[:space:]]*", "")
      print
      exit
    }
  ' "$path"
}
