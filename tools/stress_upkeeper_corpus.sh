#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
TOOLS_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
ROOT_DIR="$(cd -- "$TOOLS_DIR/.." && pwd)"

MODE="local"
KEEP_WORKDIR=0
WORK_ROOT=""
FAILED=0
PASS_COUNT=0
SKIP_COUNT=0

usage() {
  cat <<'USAGE'
Usage: tools/stress_upkeeper_corpus.sh [--local] [--keep]

Build tiny local sample repositories and validate Upkeeper wrapper behavior
against them without spending Codex quota.

Modes:
  --local   Run dry-run, parser, terminal, symlink, dirty-worktree, and log
            scenarios only. This is the default and never launches real Codex.

Options:
  --keep    Keep the generated temp corpus after the run for inspection.
  --help    Show this help.

Backend stress runs are intentionally not implemented here yet. This harness is
the no-quota CI path promised by docs/stress-corpus.md.
USAGE
}

log() {
  printf 'stress_upkeeper_corpus: %s\n' "$*"
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'stress_upkeeper_corpus: ok: %s\n' "$*"
}

skip() {
  SKIP_COUNT=$((SKIP_COUNT + 1))
  printf 'stress_upkeeper_corpus: skip: %s\n' "$*"
}

fail() {
  FAILED=1
  printf 'stress_upkeeper_corpus: ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local rc=$?
  if [[ "$rc" -ne 0 ]]; then
    FAILED=1
  fi

  if [[ -n "$WORK_ROOT" && -d "$WORK_ROOT" ]]; then
    if [[ "$KEEP_WORKDIR" == "1" || "$FAILED" == "1" ]]; then
      log "evidence kept at $WORK_ROOT"
    else
      rm -rf -- "$WORK_ROOT"
    fi
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      MODE="local"
      ;;
    --backend)
      fail "--backend is not implemented; local corpus runs must not spend Codex quota"
      ;;
    --keep)
      KEEP_WORKDIR=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || fail "missing required command: $command_name"
}

require_commands() {
  local command_name
  for command_name in bash chmod date find git grep ln mkdir mktemp python3 rm sed sort touch tr; do
    require_command "$command_name"
  done
}

write_quota_snapshot() {
  local session_file="$1"
  local model="${2:-gpt-5.5}"

  python3 - "$session_file" "$model" <<'PY'
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
model = sys.argv[2]
path.parent.mkdir(parents=True, exist_ok=True)
now = int(time.time())
event_timestamp = datetime.fromtimestamp(now, timezone.utc).isoformat().replace("+00:00", "Z")
rows = [
    {"type": "turn_context", "payload": {"model": model}},
    {
        "timestamp": event_timestamp,
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "rate_limits": {
                "limit_id": f"stress-{model}",
                "limit_name": f"{model} stress fixture",
                "plan_type": "stress-local",
                "rate_limit_reached_type": None,
                "primary": {
                    "used_percent": 10.0,
                    "window_minutes": 300,
                    "resets_at": now + 3600,
                },
                "secondary": {
                    "used_percent": 10.0,
                    "window_minutes": 10080,
                    "resets_at": now + 86400,
                },
            },
        },
    },
]
with path.open("w", encoding="utf-8") as handle:
    for row in rows:
        print(json.dumps(row, separators=(",", ":")), file=handle)
PY
}

sample_path() {
  printf '%s/samples/%s' "$WORK_ROOT" "$1"
}

init_sample_repo() {
  local name="$1"
  local repo

  repo="$(sample_path "$name")"
  mkdir -p -- "$repo"
  chmod 700 "$repo" 2>/dev/null || true
  git -C "$repo" init -q
  git -C "$repo" config user.name "Upkeeper Stress Corpus"
  git -C "$repo" config user.email "upkeeper-stress@example.invalid"

  cat >"$repo/.gitignore" <<'EOF'
Upkeeper.sh
Upkeeper.log
runtime/
dist/
build/
generated/
node_modules/
coverage/
__pycache__/
*.pyc
EOF
  ln -s "$ROOT_DIR/Upkeeper" "$repo/Upkeeper.sh"
  printf '%s\n' "$repo"
}

commit_sample_repo() {
  local repo="$1"
  local message="$2"

  git -C "$repo" add .
  git -C "$repo" commit -qm "$message"
}

set_oldest() {
  local repo="$1"
  local path="$2"

  touch -t 202001010101 -- "$repo/$path"
}

run_upkeeper_dry() {
  local name="$1"
  local repo="$2"
  local verbosity="$3"
  local expected_rc="$4"
  local log_file="$5"
  shift 5

  local run_id safe_run_id evidence_dir codex_home rc
  run_id="$name-$verbosity-$PASS_COUNT"
  safe_run_id="$(printf '%s' "$run_id" | tr -c 'A-Za-z0-9_.-' '_')"
  evidence_dir="$WORK_ROOT/evidence/$safe_run_id"
  codex_home="$WORK_ROOT/codex-home/$safe_run_id"
  mkdir -p -- "$evidence_dir" "$codex_home"
  chmod 700 "$evidence_dir" "$codex_home" 2>/dev/null || true
  write_quota_snapshot "$codex_home/sessions/2026/05/08/stress-session.jsonl" "gpt-5.5"

  set +e
  (
    cd "$repo"
    CODEX_HOME="$codex_home" \
      CODEX_LOG_FILE="$log_file" \
      CODEX_TRANSCRIPT_DIR="$evidence_dir/transcripts" \
      CODEX_ACTIVE_LOCK_DIR="$evidence_dir/active.lock" \
      CODEX_WRAPPER_HEALTH_STATE_DIR="$evidence_dir/health" \
      CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$evidence_dir/startup-gates" \
      CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
      CODEX_TERMINAL_VERBOSITY="$verbosity" \
      CODEX_MODEL=gpt-5.5 \
      CODEX_REASONING_EFFORT=xhigh \
      CODEX_FALLBACK_ENABLED=0 \
      CODEX_FALLBACK_SCREEN_ENABLED=0 \
      CODEX_POSTMORTEM_ENABLED=0 \
      CODEX_TOOL_FAILURE_QUEUE_ENABLED=0 \
      CODEX_UPKEEPER_SELF_REVIEW_AFTER_DAYS=99999 \
      CODEX_MARK_INTERVAL_SECONDS=3600 \
      UPKEEPER_DRY_RUN=1 \
      ./Upkeeper.sh "$@" >"$evidence_dir/stdout.txt" 2>"$evidence_dir/stderr.txt"
  )
  rc=$?
  set -e

  printf '%s\n' "$rc" >"$evidence_dir/rc.txt"
  if [[ "$rc" -ne "$expected_rc" ]]; then
    sed -n '1,160p' "$evidence_dir/stderr.txt" >&2 || true
    fail "$name exited $rc, expected $expected_rc; evidence=$evidence_dir"
  fi

  printf '%s\n' "$evidence_dir"
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  grep -Fq -- "$needle" "$file" || fail "$message"
}

assert_file_not_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if grep -Fq -- "$needle" "$file"; then
    fail "$message"
  fi
}

assert_redacted_preselect() {
  local log_file="$1"
  local message="$2"

  assert_file_contains "$log_file" "review.preselect path_hmac=path-hmac-sha256:" "$message"
  assert_file_contains "$log_file" "path_redacted=1" "$message"
}

create_bash_tool_sample() {
  local repo name
  name="${1:-bash-tool}"
  repo="$(init_sample_repo "$name")"
  mkdir -p "$repo/bin" "$repo/tests" "$repo/generated"
  cat >"$repo/bin/old-tool.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: old-tool.sh NAME
USAGE
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

name="${1:-}"
[[ -n "$name" ]] || {
  printf 'old-tool: missing NAME\n' >&2
  exit 64
}
printf 'hello %s\n' "$name"
SH
  chmod +x "$repo/bin/old-tool.sh"
  cat >"$repo/tests/test_old_tool.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
../bin/old-tool.sh world
SH
  chmod +x "$repo/tests/test_old_tool.sh"
  cat >"$repo/generated/generated-tool.sh" <<'SH'
#!/usr/bin/env bash
echo generated
SH
  chmod +x "$repo/generated/generated-tool.sh"
  commit_sample_repo "$repo" "add bash sample"
  set_oldest "$repo" "bin/old-tool.sh"
  printf '%s\n' "$repo"
}

create_python_sample() {
  local repo
  repo="$(init_sample_repo python-package)"
  mkdir -p "$repo/tools" "$repo/src/samplepkg" "$repo/tests" "$repo/fixtures"
  cat >"$repo/tools/parse_config.py" <<'PY'
#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: parse_config.py CONFIG_JSON", file=sys.stderr)
        return 64
    path = Path(sys.argv[1])
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"malformed json: {path}: {exc.msg}", file=sys.stderr)
        return 65
    if not isinstance(payload, dict) or "name" not in payload:
        print(f"invalid config: {path}: expected object with name", file=sys.stderr)
        return 66
    print(payload["name"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
  chmod +x "$repo/tools/parse_config.py"
  printf '{"name":"stress"}\n' >"$repo/fixtures/good.json"
  printf '{"name":\n' >"$repo/fixtures/bad.json"
  printf 'def identity(value):\n    return value\n' >"$repo/src/samplepkg/__init__.py"
  printf 'from samplepkg import identity\n\n\ndef test_identity():\n    assert identity(1) == 1\n' >"$repo/tests/test_parser.py"
  commit_sample_repo "$repo" "add python sample"
  set_oldest "$repo" "tools/parse_config.py"
  printf '%s\n' "$repo"
}

create_node_sample() {
  local repo
  repo="$(init_sample_repo node-typescript)"
  mkdir -p "$repo/scripts" "$repo/src" "$repo/docs" "$repo/dist"
  cat >"$repo/scripts/build.mjs" <<'JS'
#!/usr/bin/env node
import { readFileSync } from "node:fs";

const pkg = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8"));
console.log(`${pkg.name}: build placeholder`);
JS
  chmod +x "$repo/scripts/build.mjs"
  cat >"$repo/package.json" <<'JSON'
{"name":"upkeeper-stress-node","type":"module","scripts":{"build":"node scripts/build.mjs"}}
JSON
  printf 'export const answer: number = 42;\n' >"$repo/src/index.ts"
  printf '# API\n\nThis doc is intentionally stale for corpus selection.\n' >"$repo/docs/api.md"
  printf 'ignored generated bundle\n' >"$repo/dist/bundle.js"
  commit_sample_repo "$repo" "add node sample"
  set_oldest "$repo" "scripts/build.mjs"
  printf '%s\n' "$repo"
}

create_docs_only_sample() {
  local repo
  repo="$(init_sample_repo docs-only)"
  mkdir -p "$repo/docs/scripts"
  printf '# Docs Only\n\nNo source tools live here.\n' >"$repo/README.md"
  printf '# Operator Notes\n\nDocs-only fixture.\n' >"$repo/docs/scripts/upkeeper.md"
  commit_sample_repo "$repo" "add docs sample"
  printf '%s\n' "$repo"
}

create_generated_heavy_sample() {
  local repo
  repo="$(init_sample_repo generated-heavy)"
  mkdir -p "$repo/tools" "$repo/generated" "$repo/dist" "$repo/runtime"
  cat >"$repo/tools/clean.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
rm -rf generated dist
SH
  chmod +x "$repo/tools/clean.sh"
  printf '#!/usr/bin/env bash\necho ignored\n' >"$repo/generated/ignored.sh"
  chmod +x "$repo/generated/ignored.sh"
  printf '#!/usr/bin/env bash\necho ignored\n' >"$repo/dist/ignored.sh"
  chmod +x "$repo/dist/ignored.sh"
  printf 'runtime evidence\n' >"$repo/runtime/evidence.log"
  commit_sample_repo "$repo" "add generated-heavy sample"
  set_oldest "$repo" "tools/clean.sh"
  printf '%s\n' "$repo"
}

create_symlinked_client_sample() {
  local repo
  repo="$(init_sample_repo symlinked-client)"
  mkdir -p "$repo/scripts"
  cat >"$repo/scripts/client-maintenance.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'client maintenance\n'
SH
  chmod +x "$repo/scripts/client-maintenance.sh"
  commit_sample_repo "$repo" "add symlinked client sample"
  set_oldest "$repo" "scripts/client-maintenance.sh"
  printf '%s\n' "$repo"
}

create_dirty_worktree_sample() {
  local repo
  repo="$(init_sample_repo dirty-worktree)"
  mkdir -p "$repo/tools"
  cat >"$repo/tools/dirty.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'clean baseline\n'
SH
  chmod +x "$repo/tools/dirty.sh"
  commit_sample_repo "$repo" "add dirty sample"
  cat >"$repo/tools/dirty.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'dirty baseline\n'
SH
  chmod +x "$repo/tools/dirty.sh"
  set_oldest "$repo" "tools/dirty.sh"
  printf '%s\n' "$repo"
}

create_historical_log_sample() {
  local repo stamp boot_id
  repo="$(init_sample_repo historical-log)"
  mkdir -p "$repo/scripts"
  cat >"$repo/Upkeeper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'repo-local Upkeeper gate fixture\n'
SH
  chmod +x "$repo/Upkeeper"
  cat >"$repo/scripts/repair.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'repair\n'
SH
  chmod +x "$repo/scripts/repair.sh"
  commit_sample_repo "$repo" "add historical log sample"
  stamp="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf 'unknown')"
  printf '%s [INFO] cycle=stress-prior run_hash=stresshash cycle.start boot_id=%s\n' "$stamp" "$boot_id" >"$repo/Upkeeper.log"
  printf '%s\n' "$repo"
}

check_bash_tool_sample() {
  local repo evidence log_file
  repo="$(create_bash_tool_sample bash-tool)"
  log_file="$repo/Upkeeper.log"
  : >"$log_file"
  evidence="$(run_upkeeper_dry bash-tool "$repo" basic 0 "$log_file")"
  assert_redacted_preselect "$log_file" "bash sample did not log a redacted preselection"
  assert_file_contains "$evidence/stderr.txt" "selected file bin/old-tool.sh" "basic terminal did not show selected bash file"
  assert_file_not_contains "$evidence/stderr.txt" "selected file tests/test_old_tool.sh" "bash sample selected a test"
  assert_file_not_contains "$evidence/stderr.txt" "selected file generated/ignored.sh" "bash sample selected ignored generated output"
  pass "bash-tool selected source tool and ignored tests/generated output"
}

check_python_sample() {
  local repo evidence log_file rc
  repo="$(create_python_sample)"
  log_file="$repo/Upkeeper.log"
  : >"$log_file"
  set +e
  python3 "$repo/tools/parse_config.py" "$repo/fixtures/bad.json" >"$WORK_ROOT/evidence/python-bad.out" 2>"$WORK_ROOT/evidence/python-bad.err"
  rc=$?
  set -e
  [[ "$rc" -eq 65 ]] || fail "python malformed config fixture exited $rc, expected 65"
  assert_file_contains "$WORK_ROOT/evidence/python-bad.err" "malformed json:" "python malformed config diagnostic was not focused"
  evidence="$(run_upkeeper_dry python-package "$repo" basic 0 "$log_file")"
  assert_redacted_preselect "$log_file" "python sample did not log a redacted preselection"
  assert_file_contains "$evidence/stderr.txt" "selected file tools/parse_config.py" "basic terminal did not show selected python file"
  pass "python-package selected parser tool and proved malformed-data diagnostic"
}

check_node_sample() {
  local repo evidence log_file
  repo="$(create_node_sample)"
  log_file="$repo/Upkeeper.log"
  : >"$log_file"
  evidence="$(run_upkeeper_dry node-typescript "$repo" basic 0 "$log_file")"
  assert_redacted_preselect "$log_file" "node sample did not log a redacted preselection"
  assert_file_contains "$evidence/stderr.txt" "selected file scripts/build.mjs" "node sample did not select package script"
  assert_file_not_contains "$evidence/stderr.txt" "selected file docs/api.md" "node sample selected docs in automatic rotation"
  assert_file_not_contains "$evidence/stderr.txt" "selected file dist/bundle.js" "node sample selected generated bundle"
  pass "node-typescript selected package script and ignored docs/generated output"
}

check_docs_only_sample() {
  local repo log_file
  repo="$(create_docs_only_sample)"
  log_file="$repo/Upkeeper.log"
  : >"$log_file"
  run_upkeeper_dry docs-only "$repo" basic 0 "$log_file" >/dev/null
  assert_file_contains "$log_file" "review.preselect.none reason=no_eligible_script_tool" "docs-only sample did not report no eligible script/tool"
  assert_file_not_contains "$log_file" "review.preselect path=docs/scripts/upkeeper.md" "docs-only sample selected docs automatically"
  pass "docs-only repo stayed docs-only without inventing a source target"
}

check_generated_heavy_sample() {
  local repo evidence log_file
  repo="$(create_generated_heavy_sample)"
  log_file="$repo/Upkeeper.log"
  : >"$log_file"
  evidence="$(run_upkeeper_dry generated-heavy "$repo" basic 0 "$log_file")"
  assert_redacted_preselect "$log_file" "generated-heavy sample did not log a redacted preselection"
  assert_file_contains "$evidence/stderr.txt" "selected file tools/clean.sh" "generated-heavy sample did not select source tool"
  assert_file_not_contains "$evidence/stderr.txt" "selected file generated/ignored.sh" "generated-heavy sample selected ignored generated path"
  assert_file_not_contains "$evidence/stderr.txt" "selected file dist/ignored.sh" "generated-heavy sample selected ignored dist path"
  assert_file_not_contains "$evidence/stderr.txt" "selected file runtime/evidence.log" "generated-heavy sample selected runtime evidence"
  pass "generated-heavy repo kept ignored/generated/runtime paths out of selection"
}

check_symlinked_client_sample() {
  local repo evidence log_file
  repo="$(create_symlinked_client_sample)"
  log_file="$repo/Upkeeper.log"
  : >"$log_file"
  evidence="$(run_upkeeper_dry symlinked-client "$repo" basic 0 "$log_file")"
  assert_file_contains "$log_file" "implementation_hash=value-hmac-sha256:" "symlinked client did not log central implementation hash"
  assert_redacted_preselect "$log_file" "symlinked client did not log a redacted preselection"
  assert_file_contains "$evidence/stderr.txt" "selected file scripts/client-maintenance.sh" "symlinked client did not select local script"
  pass "symlinked client used central modules against client repo"
}

check_dirty_worktree_sample() {
  local repo evidence log_file
  repo="$(create_dirty_worktree_sample)"
  log_file="$repo/Upkeeper.log"
  : >"$log_file"
  evidence="$(run_upkeeper_dry dirty-worktree "$repo" basic 0 "$log_file")"
  assert_redacted_preselect "$log_file" "dirty sample did not log a redacted preselection"
  assert_file_contains "$evidence/stderr.txt" "selected file tools/dirty.sh" "dirty sample did not select dirty tool"
  assert_file_contains "$log_file" "content_state=differs_from_head" "dirty sample did not preserve dirty baseline metadata"
  pass "dirty worktree target was treated as baseline state"
}

check_historical_log_sample() {
  local repo log_file
  repo="$(create_historical_log_sample)"
  log_file="$repo/Upkeeper.log"
  run_upkeeper_dry historical-log "$repo" basic 0 "$log_file" >/dev/null
  assert_file_contains "$log_file" "previous_run.anomaly" "historical log sample did not detect prior incomplete cycle"
  assert_file_contains "$log_file" "previous_cycle=stress-prior" "historical log sample did not name the prior cycle"
  assert_file_contains "$log_file" "startup_anomaly.gate_target status=eligible path=Upkeeper" "historical log sample did not use repo-local regular Upkeeper gate target"
  assert_file_contains "$log_file" "selection_mode=startup_anomaly_gate" "historical log sample did not force startup anomaly selection mode"
  pass "historical log anomaly forced regular local Upkeeper gate target"
}

check_active_lock_sample() {
  local repo log_file evidence_dir codex_home rc
  repo="$(init_sample_repo active-lock)"
  mkdir -p "$repo/scripts"
  cat >"$repo/scripts/locked.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'locked\n'
SH
  chmod +x "$repo/scripts/locked.sh"
  commit_sample_repo "$repo" "add active-lock sample"
  log_file="$repo/Upkeeper.log"
  evidence_dir="$WORK_ROOT/evidence/active-lock"
  codex_home="$WORK_ROOT/codex-home/active-lock"
  mkdir -p "$evidence_dir" "$repo/runtime/upkeeper-active.lock"
  write_quota_snapshot "$codex_home/sessions/2026/05/08/stress-session.jsonl" "gpt-5.5"

  set +e
  (
    cd "$repo"
    CODEX_HOME="$codex_home" \
      CODEX_LOG_FILE="$log_file" \
      CODEX_TRANSCRIPT_DIR="$evidence_dir/transcripts" \
      CODEX_ACTIVE_LOCK_DIR="$repo/runtime/upkeeper-active.lock" \
      CODEX_WRAPPER_HEALTH_STATE_DIR="$evidence_dir/health" \
      CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$evidence_dir/startup-gates" \
      CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
      CODEX_TERMINAL_VERBOSITY=quiet \
      CODEX_MODEL=gpt-5.5 \
      CODEX_REASONING_EFFORT=xhigh \
      CODEX_FALLBACK_ENABLED=0 \
      CODEX_FALLBACK_SCREEN_ENABLED=0 \
      CODEX_POSTMORTEM_ENABLED=0 \
      UPKEEPER_DRY_RUN=1 \
      ./Upkeeper.sh >"$evidence_dir/stdout.txt" 2>"$evidence_dir/stderr.txt"
  )
  rc=$?
  set -e

  [[ "$rc" -eq 7 ]] || fail "active-lock sample exited $rc, expected 7"
  assert_file_contains "$log_file" "active_lock.incomplete" "active-lock sample did not log incomplete lock"
  assert_file_contains "$log_file" "reason=UPKEEPER_ACTIVE_LOCK_HELD" "active-lock sample did not classify held active lock"
  pass "active lock failure was classified without backend work"
}

check_terminal_modes() {
  local repo log_file basic_evidence quiet_evidence silent_evidence
  repo="$(create_bash_tool_sample terminal-modes)"
  log_file="$repo/Upkeeper.log"

  : >"$log_file"
  basic_evidence="$(run_upkeeper_dry terminal-basic "$repo" basic 0 "$log_file")"
  assert_file_contains "$basic_evidence/stderr.txt" "selected file bin/old-tool.sh" "basic terminal mode did not show selected file"

  : >"$log_file"
  quiet_evidence="$(run_upkeeper_dry terminal-quiet "$repo" quiet 0 "$log_file")"
  assert_file_contains "$quiet_evidence/stderr.txt" "selected file bin/old-tool.sh" "quiet terminal mode did not show major progress"

  : >"$log_file"
  silent_evidence="$(run_upkeeper_dry terminal-silent "$repo" silent 0 "$log_file")"
  [[ ! -s "$silent_evidence/stderr.txt" ]] || fail "silent terminal mode wrote stderr"
  [[ ! -s "$silent_evidence/stdout.txt" ]] || fail "silent terminal mode wrote stdout"
  pass "terminal modes basic, quiet, and silent obeyed local dry-run contract"
}

check_review_summary_fixture() {
  local temp_dir summary selected_file outcome
  temp_dir="$WORK_ROOT/evidence/review-summary"
  mkdir -p "$temp_dir"
  cat >"$temp_dir/last-message.txt" <<'EOF'
REVIEWED_AND_FIXED

Selected `tools/parse_config.py` from the stress corpus.

Findings:
- malformed JSON was reported as absence

Changes:
- added strict malformed-input diagnostics

Verification:
- python3 tools/parse_config.py fixtures/bad.json

UPKEEPER_STATUS: WORK_DONE
EOF
  summary="$(bash -lc 'cd "$1"; source ./Upkeeper; review_report_summary_json "$2"' bash "$ROOT_DIR" "$temp_dir/last-message.txt")"
  selected_file="$(printf '%s' "$summary" | python3 -c 'import json,sys; print(json.load(sys.stdin)["selected_file"])')"
  outcome="$(printf '%s' "$summary" | python3 -c 'import json,sys; print(json.load(sys.stdin)["outcome"])')"
  [[ "$selected_file" == "tools/parse_config.py" ]] || fail "review summary fixture selected $selected_file"
  [[ "$outcome" == "REVIEWED_AND_FIXED" ]] || fail "review summary fixture outcome $outcome"
  pass "review-summary parser surfaced selected file and outcome"
}

check_transcript_filter_fixture() {
  local temp_dir
  temp_dir="$WORK_ROOT/evidence/transcript-filter"
  mkdir -p "$temp_dir"
  cat >"$temp_dir/transcript.log" <<'EOF'
Reading prompt from stdin...
user
Prompt text says ERROR failed Exception but is not runtime evidence.
codex
I am checking the selected file before validation.
exec
/bin/bash -lc 'rg ERROR docs'
exited 1 in 0ms:
exec
python -m pytest
exited 1 in 0.1s
UPKEEPER_STATUS: WORK_DONE
EOF
  CODEX_LOG_FILE="$temp_dir/Upkeeper.log" CYCLE_ID=stress-transcript CYCLE_RUN_HASH=stresshash \
    CODEX_TERMINAL_VERBOSITY=silent \
    bash -lc 'cd "$1"; source ./Upkeeper; emit_codex_transcript_summary stress "$2" 1' bash "$ROOT_DIR" "$temp_dir/transcript.log" \
      >"$temp_dir/stdout.txt" 2>"$temp_dir/stderr.txt"
  assert_file_contains "$temp_dir/Upkeeper.log" "codex.transcript.signal label=stress text=exited\\ 1\\ in\\ 0.1s" "transcript filter did not surface runtime test failure"
  assert_file_contains "$temp_dir/Upkeeper.log" "codex.transcript.signal label=stress text=UPKEEPER_STATUS:\\ WORK_DONE" "transcript filter did not surface status marker"
  assert_file_not_contains "$temp_dir/Upkeeper.log" "Prompt\\ text\\ says\\ ERROR" "transcript filter surfaced prompt echo as runtime evidence"
  pass "transcript filter kept prompt/search noise out of runtime evidence"
}

run_local_corpus() {
  check_bash_tool_sample
  check_python_sample
  check_node_sample
  check_docs_only_sample
  check_generated_heavy_sample
  check_symlinked_client_sample
  check_dirty_worktree_sample
  check_historical_log_sample
  check_active_lock_sample
  check_terminal_modes
  check_review_summary_fixture
  check_transcript_filter_fixture
}

require_commands
[[ "$MODE" == "local" ]] || fail "unsupported mode: $MODE"

WORK_ROOT="$(mktemp -d /tmp/upkeeper-stress-corpus.XXXXXX)"
mkdir -p "$WORK_ROOT/samples" "$WORK_ROOT/evidence" "$WORK_ROOT/codex-home"
chmod 700 "$WORK_ROOT" "$WORK_ROOT/samples" "$WORK_ROOT/evidence" "$WORK_ROOT/codex-home" 2>/dev/null || true
log "work root: $WORK_ROOT"
log "mode: local; backend Codex disabled"

run_local_corpus

log "local corpus passed: checks=$PASS_COUNT skips=$SKIP_COUNT"
