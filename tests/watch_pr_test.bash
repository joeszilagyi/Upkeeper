#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP="$(mktemp -d /tmp/upkeeper-watch-pr-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat >"$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-} ${2:-}" in
  "pr view")
    printf '777\n'
    exit 0
    ;;
  "pr checks")
    case "${WATCH_PR_GH_CASE:-pass}" in
      pass)
        cat <<'JSON'
[
  {"name":"Analyze (actions)","bucket":"pass","state":"SUCCESS","conclusion":"success","workflow":"CI","link":"https://example.invalid/actions"},
  {"name":"Local validation","bucket":"pass","state":"SUCCESS","conclusion":"success","workflow":"CI","link":"https://example.invalid/local"}
]
JSON
        exit 0
        ;;
      pending)
        cat <<'JSON'
[
  {"name":"Analyze (actions)","bucket":"pass","state":"SUCCESS","conclusion":"success","workflow":"CI","link":"https://example.invalid/actions"},
  {"name":"Local validation","bucket":"pending","state":"IN_PROGRESS","conclusion":"","workflow":"CI","link":"https://example.invalid/local"}
]
JSON
        exit 8
        ;;
      fail)
        cat <<'JSON'
[
  {"name":"Analyze (actions)","bucket":"pass","state":"SUCCESS","conclusion":"success","workflow":"CI","link":"https://example.invalid/actions"},
  {"name":"Local validation","bucket":"fail","state":"FAILURE","conclusion":"failure","workflow":"CI","link":"https://example.invalid/local"}
]
JSON
        exit 1
        ;;
      empty)
        printf '[]\n'
        exit 8
        ;;
      sequence)
        sequence_file="${WATCH_PR_SEQUENCE_FILE:?WATCH_PR_SEQUENCE_FILE is required}"
        count="$(sed -n '1p' "$sequence_file" 2>/dev/null || true)"
        count="${count:-0}"
        next_count=$((count + 1))
        printf '%s\n' "$next_count" >"$sequence_file"
        if [[ "$count" == "0" ]]; then
          WATCH_PR_GH_CASE=pending exec "$0" "$@"
        fi
        WATCH_PR_GH_CASE=pass exec "$0" "$@"
        ;;
      bad-json)
        printf 'not-json\n'
        printf 'github unavailable\n' >&2
        exit 1
        ;;
      *)
        printf 'unknown WATCH_PR_GH_CASE: %s\n' "${WATCH_PR_GH_CASE:-}" >&2
        exit 99
        ;;
    esac
    ;;
esac

printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 98
SH
chmod +x "$TMP/bin/gh"

PATH="$TMP/bin:$PATH"

run_watch_pr() {
  local output_var="$1"
  shift
  local captured status

  set +e
  captured="$("$@" 2>&1)"
  status="$?"
  set -e
  printf -v "$output_var" '%s' "$captured"
  return "$status"
}

output=""
run_watch_pr output env WATCH_PR_GH_CASE=pass ./orchestration/watch-pr.sh --once --pr 402
[[ "$?" == "0" ]]
grep -Fq 'PR #402 checks: status=pass' <<<"$output"
grep -Fq 'check='"'"'Local validation'"'"'' <<<"$output"

status=0
run_watch_pr output env WATCH_PR_GH_CASE=pending ./orchestration/watch-pr.sh --once --pr 402 || status="$?"
[[ "$status" == "2" ]]
grep -Fq 'PR #402 checks: status=pending' <<<"$output"
grep -Fq 'conclusion='"'"'pending'"'"'' <<<"$output"

status=0
run_watch_pr output env WATCH_PR_GH_CASE=empty ./orchestration/watch-pr.sh --once --pr 402 || status="$?"
[[ "$status" == "2" ]]
grep -Fq 'no check runs reported yet' <<<"$output"

status=0
run_watch_pr output env WATCH_PR_GH_CASE=fail ./orchestration/watch-pr.sh --once --pr 402 || status="$?"
[[ "$status" == "1" ]]
grep -Fq 'PR #402 checks: status=fail' <<<"$output"
grep -Fq 'check='"'"'Local validation'"'"'' <<<"$output"
grep -Fq 'conclusion='"'"'failure'"'"'' <<<"$output"
grep -Fq 'url=https://example.invalid/local' <<<"$output"

run_watch_pr output env WATCH_PR_GH_CASE=pass ./orchestration/watch-pr.sh --once
[[ "$?" == "0" ]]
grep -Fq 'PR #777 checks: status=pass' <<<"$output"

sequence_file="$TMP/sequence.count"
run_watch_pr output env WATCH_PR_GH_CASE=sequence WATCH_PR_SEQUENCE_FILE="$sequence_file" ./orchestration/watch-pr.sh --interval 0 --pr 402
[[ "$?" == "0" ]]
grep -Fq 'PR #402 checks: status=pending' <<<"$output"
grep -Fq 'PR #402 checks: still pending; checking again in 0s' <<<"$output"
grep -Fq 'PR #402 checks: status=pass' <<<"$output"
[[ "$(sed -n '1p' "$sequence_file")" == "2" ]]

status=0
run_watch_pr output env WATCH_PR_GH_CASE=bad-json ./orchestration/watch-pr.sh --once --pr 402 || status="$?"
[[ "$status" == "1" ]]
grep -Fq 'status=fail reason=github_check_read_failed' <<<"$output"

printf 'watch_pr_test: ok\n'
