#!/usr/bin/env bash
set -euo pipefail

# Exercise the real central wrapper through a disposable client fixture.  This
# is deliberately a dry run: it measures deterministic pre-model work and
# proves the backend was not started; it is not a live operational check.

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUDGET_MS="10000"
WARN_ONLY="0"
KEEP_FIXTURE="0"
FIXTURE_ROOT=""

usage() {
  cat <<'USAGE'
Usage: tools/measure_upkeeper_noop_path.sh [--budget-ms N] [--warn-only] [--keep-fixture]

Run an isolated UPKEEPER_DRY_RUN=1 wrapper cycle through a temporary symlinked
client fixture. The command prints aggregate pre-model timing and Python,
Lattice, and control-plane-audit subprocess counts. It exits 2 when the
observed fast path exceeds --budget-ms, unless --warn-only is selected.
USAGE
}

fail() {
  printf 'measure_upkeeper_noop_path: ERROR: %s\n' "$*" >&2
  exit 70
}

cleanup() {
  [[ "$KEEP_FIXTURE" == "1" ]] && return 0
  [[ "$FIXTURE_ROOT" == "${TMPDIR:-/tmp}"/upkeeper-noop-probe.* ]] || return 0
  rm -rf -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --budget-ms)
      BUDGET_MS="${2:-}"
      shift 2
      ;;
    --budget-ms=*)
      BUDGET_MS="${1#*=}"
      shift
      ;;
    --warn-only)
      WARN_ONLY=1
      shift
      ;;
    --keep-fixture)
      KEEP_FIXTURE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ "$BUDGET_MS" =~ ^[0-9]+$ ]] || fail "--budget-ms must be a non-negative integer"

FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-noop-probe.XXXXXX")"
fixture_repo="$FIXTURE_ROOT/client"
shim_dir="$FIXTURE_ROOT/bin"
log_file="$fixture_repo/Upkeeper.log"
python_log="$FIXTURE_ROOT/python-invocations.log"
real_python="$(command -v python3 || true)"
[[ -n "$real_python" ]] || fail "python3 is required by the wrapper fixture"

mkdir -p "$fixture_repo" "$shim_dir"
chmod 700 "$fixture_repo"
(
  cd "$fixture_repo"
  git init -q
  git checkout -q -B main
  git config user.name "Upkeeper no-op probe"
  git config user.email "noop-probe@example.invalid"
  printf '# isolated probe\n' >README.md
  printf 'runtime/\nUpkeeper.log\n' >.gitignore
  git add README.md .gitignore
  git commit -q -m fixture
)
ln -s "$ROOT_DIR/Upkeeper" "$fixture_repo/Upkeeper.sh"

# Dry runs still parse the local quota snapshot before reaching the backend
# boundary. Supply current, low-use evidence inside the fixture rather than
# inheriting a real operator session store.
quota_snapshot="$FIXTURE_ROOT/codex-home/sessions/probe/session.jsonl"
mkdir -p "$(dirname -- "$quota_snapshot")"
python3 - "$quota_snapshot" <<'PY'
import json
import sys
import time
from datetime import datetime, timezone

now = int(time.time())
rows = [
    {"type": "turn_context", "payload": {"model": "gpt-5.3-codex-spark"}},
    {
        "timestamp": datetime.fromtimestamp(now, timezone.utc).isoformat().replace("+00:00", "Z"),
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "rate_limits": {
                "limit_id": "noop-probe",
                "limit_name": "isolated no-op probe",
                "plan_type": "fixture",
                "rate_limit_reached_type": None,
                "primary": {"used_percent": 1.0, "window_minutes": 300, "resets_at": now + 3600},
                "secondary": {"used_percent": 1.0, "window_minutes": 10080, "resets_at": now + 86400},
            },
        },
    },
]
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    for row in rows:
        print(json.dumps(row, separators=(",", ":")), file=handle)
PY

cat >"$shim_dir/python3" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$UPKEEPER_NOOP_PROBE_PYTHON_LOG"
printf '\n' >>"$UPKEEPER_NOOP_PROBE_PYTHON_LOG"
exec "$UPKEEPER_NOOP_PROBE_REAL_PYTHON" "$@"
SHIM
chmod 700 "$shim_dir/python3"

set +e
run_output="$(
  cd "$fixture_repo" && \
    HOME="$FIXTURE_ROOT/home" \
    XDG_STATE_HOME="$FIXTURE_ROOT/state" \
    XDG_CACHE_HOME="$FIXTURE_ROOT/cache" \
    GH_CONFIG_DIR="$FIXTURE_ROOT/gh" \
    CODEX_HOME="$FIXTURE_ROOT/codex-home" \
    CODEX_LOG_FILE="$log_file" \
    CODEX_TRANSCRIPT_DIR="$fixture_repo/runtime/transcripts" \
    CODEX_ACTIVE_LOCK_DIR="$fixture_repo/runtime/upkeeper-active.lock" \
    CODEX_WRAPPER_HEALTH_STATE_DIR="$FIXTURE_ROOT/wrapper-health" \
    CODEX_WRAPPER_HEALTH_ARCHIVE_DIR="$FIXTURE_ROOT/wrapper-health-archive" \
    CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$fixture_repo/runtime/startup-gates" \
    CODEX_TOOL_FAILURE_QUEUE_DIR="$fixture_repo/runtime/tool-failures" \
    UPKEEPER_AUTOMATION_LEDGER_DIR="$fixture_repo/runtime/automation-ledger" \
    UPKEEPER_OBLIGATION_DIR="$fixture_repo/runtime/obligations" \
    UPKEEPER_PRECONTACT_BACKUP_ROOT="$FIXTURE_ROOT/precontact-vault" \
    UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0 \
    UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1 \
    UPKEEPER_LATTICE_DB="$fixture_repo/runtime/upkeeper-lattice/lattice.sqlite3" \
    UPKEEPER_LATTICE_REQUIRED=1 \
    UPKEEPER_CONFIG_DISABLE=1 \
    UPKEEPER_LOCAL_ENV_DISABLE=1 \
    CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
    CODEX_TERMINAL_VERBOSITY=quiet \
    CODEX_MODEL=gpt-5.3-codex-spark \
    CODEX_REASONING_EFFORT=low \
    CODEX_MODE='--sandbox workspace-write' \
    CODEX_FALLBACK_ENABLED=0 \
    CODEX_FALLBACK_SCREEN_ENABLED=0 \
    CODEX_POSTMORTEM_ENABLED=0 \
    UPKEEPER_DRY_RUN=1 \
    UPKEEPER_FAST_PATH_TIMING_BUDGET_MS="$BUDGET_MS" \
    UPKEEPER_NOOP_PROBE_PYTHON_LOG="$python_log" \
    UPKEEPER_NOOP_PROBE_REAL_PYTHON="$real_python" \
    PATH="$shim_dir:$PATH" \
    timeout --kill-after=5s 60s ./Upkeeper.sh --target-file=README.md 2>&1
)"
run_rc=$?
set -e

if [[ "$run_rc" -ne 0 ]]; then
  printf '%s\n' "$run_output" >&2
  fail "isolated dry-run wrapper exited $run_rc"
fi
[[ -s "$log_file" ]] || fail "isolated wrapper did not create its private log"
summary="$(grep 'fast_path_timing.summary ' "$log_file" | tail -n 1 || true)"
[[ -n "$summary" ]] || fail "wrapper did not emit pre-model timing summary"
grep -Fq 'reason=DRY_RUN' "$log_file" || fail "wrapper did not finish as a dry run"
if grep -Fq 'codex_exec_started=1' "$log_file"; then
  fail "isolated probe observed a backend launch"
fi

summary_field() {
  local key="$1"
  sed -n "s/.*[[:space:]]$key=\\([^[:space:]]*\\).*/\\1/p" <<<"$summary" | tail -n 1
}

total_ms="$(summary_field total_ms)"
outcome="$(summary_field outcome)"
[[ "$total_ms" =~ ^[0-9]+$ ]] || fail "timing summary had invalid total_ms: $summary"
[[ "$outcome" == "pass" || "$outcome" == "budget_exceeded" ]] || fail "timing summary had invalid outcome: $summary"
python_count="$(wc -l <"$python_log" | tr -d ' ')"
lattice_count="$(awk -v path="$ROOT_DIR/tools/upkeeper_lattice.py" 'index($0, path) { count += 1 } END { print count + 0 }' "$python_log")"
audit_count="$(awk -v path="$ROOT_DIR/tools/upkeeper_control_plane_audit.py" 'index($0, path) { count += 1 } END { print count + 0 }' "$python_log")"

printf 'upkeeper_noop_probe total_ms=%s budget_ms=%s outcome=%s backend_exec_started=0 python_subprocesses=%s lattice_python_subprocesses=%s control_plane_audit_python_subprocesses=%s fixture_state=private\n' \
  "$total_ms" "$BUDGET_MS" "$outcome" "$python_count" "$lattice_count" "$audit_count"

if [[ "$outcome" == "budget_exceeded" && "$WARN_ONLY" != "1" ]]; then
  printf 'measure_upkeeper_noop_path: budget exceeded; inspect the preceding fast_path_timing.summary and phase evidence\n' >&2
  exit 2
fi

if [[ "$KEEP_FIXTURE" == "1" ]]; then
  printf 'measure_upkeeper_noop_path: retained private fixture at %s\n' "$FIXTURE_ROOT" >&2
fi
