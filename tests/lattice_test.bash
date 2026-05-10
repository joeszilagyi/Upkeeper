#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LATTICE_TOOL="$ROOT_DIR/tools/upkeeper_lattice.py"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-lattice-test.XXXXXX")"
trap 'rm -r "$TEST_TMP_ROOT" 2>/dev/null || true' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

write_quota_snapshot() {
  local path="$1"
  local model="${2:-gpt-5.5}"
  python3 - "$path" "$model" <<'PY'
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
model = sys.argv[2]
path.parent.mkdir(parents=True, exist_ok=True)
now = int(time.time())
ts = datetime.fromtimestamp(now, timezone.utc).isoformat().replace("+00:00", "Z")
rows = [
    {"type": "turn_context", "payload": {"model": model}},
    {
        "timestamp": ts,
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "rate_limits": {
                "limit_id": f"validation-{model}",
                "limit_name": f"{model} validation",
                "plan_type": "validation",
                "rate_limit_reached_type": None,
                "primary": {"used_percent": 10.0, "window_minutes": 300, "resets_at": now + 3600},
                "secondary": {"used_percent": 10.0, "window_minutes": 10080, "resets_at": now + 86400},
            },
        },
    },
]
with path.open("w", encoding="utf-8") as handle:
    for row in rows:
        print(json.dumps(row, separators=(",", ":")), file=handle)
PY
}

make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git config user.name "Lattice Test"
    git config user.email "lattice@example.invalid"
    printf 'runtime/\n' >.gitignore
    mkdir -p tests
    printf '# Lattice Test Fixture\n' >README.md
    printf 'tracked test fixture\n' >tests/example.txt
    touch -t 201901010000 README.md
    touch -t 201901020000 tests/example.txt
    printf '#!/usr/bin/env bash\nprintf "space\\n"\n' >"space name.sh"
    printf '#!/usr/bin/env bash\nprintf "single\\n"\n' >"quote'name.sh"
    printf '#!/usr/bin/env bash\nprintf "double\\n"\n' >'double"quote.sh'
    printf '#!/usr/bin/env bash\nprintf "unicode\\n"\n' >"unicode-λ.sh"
    printf '#!/usr/bin/env bash\nprintf "dash\\n"\n' >"leading-dash--file.sh"
    printf '#!/usr/bin/env bash\nprintf "brackets\\n"\n' >"brackets[1].sh"
    printf '#!/usr/bin/env bash\nprintf "semi\\n"\n' >"semi;colon.sh"
    printf '#!/usr/bin/env bash\nprintf "newline\\n"\n' >$'newline name\nfixture.sh'
    printf '#!/usr/bin/env bash\nprintf "old\\n"\n' >rename-old.sh
    printf '#!/usr/bin/env bash\nprintf "delete\\n"\n' >delete-me.sh
    git add -A
    git commit -q -m "initial torture fixtures"
    git mv rename-old.sh rename-new.sh
    git commit -q -m "rename fixture"
    printf '# renamed path changed\n' >>rename-new.sh
    git add rename-new.sh
    git commit -q -m "modify renamed fixture"
    git rm -q delete-me.sh
    git commit -q -m "delete fixture"
    printf '#!/usr/bin/env bash\nprintf "recreated\\n"\n' >delete-me.sh
    git add delete-me.sh
    git commit -q -m "recreate fixture"
    cp "space name.sh" copied-space.sh
    git add copied-space.sh
    git commit -q -m "copy fixture"
  )
}

lattice() {
  "$LATTICE_TOOL" --root "$REPO" --db "$DB" "$@"
}

assert_sql_value() {
  local expected="$1"
  local sql="$2"
  local got
  got="$(python3 - "$DB" "$sql" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute("PRAGMA foreign_keys=ON")
row = conn.execute(sys.argv[2]).fetchone()
print("" if row is None or row[0] is None else row[0])
PY
)"
  [[ "$got" == "$expected" ]] || fail "expected SQL [$sql] -> [$expected], got [$got]"
}

assert_sql_min() {
  local expected_min="$1"
  local sql="$2"
  local got
  got="$(python3 - "$DB" "$sql" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute("PRAGMA foreign_keys=ON")
row = conn.execute(sys.argv[2]).fetchone()
print(0 if row is None or row[0] is None else row[0])
PY
)"
  [[ "$got" =~ ^[0-9]+$ ]] || fail "expected numeric SQL [$sql], got [$got]"
  (( got >= expected_min )) || fail "expected SQL [$sql] >= [$expected_min], got [$got]"
}

run_sql() {
  local sql="$1"
  python3 - "$DB" "$sql" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute("PRAGMA foreign_keys=ON")
with conn:
    conn.executescript(sys.argv[2])
PY
}

test_lattice_cli_contracts() {
  REPO="$TEST_TMP_ROOT/repo"
  DB="$REPO/runtime/upkeeper-lattice/lattice.sqlite3"
  make_repo "$REPO"

  lattice init >$TEST_TMP_ROOT/lattice-init-1.json
  lattice init >$TEST_TMP_ROOT/lattice-init-2.json
  lattice doctor >$TEST_TMP_ROOT/lattice-doctor.json
  python3 - $TEST_TMP_ROOT/lattice-doctor.json <<'PY' || fail "doctor JSON did not pass"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "ok", data
assert data["checks"]["foreign_keys"] == 1, data
assert data["checks"]["quick_check"] == "ok", data
assert data["checks"]["required_tables_missing"] == [], data
assert data["checks"]["required_indexes_missing"] == [], data
PY

  lattice record-cycle-start \
    --cycle-id cycle-1 \
    --run-hash hash-1 \
    --execution-origin primary \
    --model gpt-5.5 \
    --effort xhigh \
    --mode '--sandbox workspace-write' \
    --config-file Upkeeper.conf \
    --dirty-path-count 0 \
    --dry-run 1 >$TEST_TMP_ROOT/lattice-cycle-start.json
  assert_sql_value "1" "select count(*) from worktree_snapshots where snapshot_kind='before_codex'"

  cat >"$TEST_TMP_ROOT/selection.env" <<'EOF'
path=space name.sh
epoch=100
age=1h 0m
git_status=clean
content_state=matches_head
head_blob=head
worktree_hash=worktree
eligible_count=1
selection_mode=explicit_target
selection_source=enumerate
manifest_status=enumerated
selection_order=oldest
selection_basis=test explicit target
EOF
  lattice query selection-candidates --mode oldest-mtime --format jsonl >"$TEST_TMP_ROOT/candidates.jsonl"
  grep -Fq '"path":"space name.sh"' "$TEST_TMP_ROOT/candidates.jsonl" ||
    fail "selection candidates missed space-bearing fixture"
  grep -Fq 'newline name' "$TEST_TMP_ROOT/candidates.jsonl" ||
    fail "selection candidates missed newline-name fixture evidence"

  lattice query selection-candidates --mode max-cover --format jsonl >"$TEST_TMP_ROOT/max-cover-candidates.jsonl"
  first_max_cover_path="$(python3 - "$TEST_TMP_ROOT/max-cover-candidates.jsonl" <<'PY'
import json
import sys

for line in open(sys.argv[1], encoding="utf-8"):
    row = json.loads(line)
    if row.get("candidate_state") == "eligible":
        print(row.get("path", ""))
        break
PY
)"
  [[ "$first_max_cover_path" == "README.md" ]] ||
    fail "max-cover did not prefer the oldest tracked text file with unrun passes; got $first_max_cover_path"
  grep -Fq '"path":"tests/example.txt"' "$TEST_TMP_ROOT/max-cover-candidates.jsonl" ||
    fail "max-cover selection missed tracked test text fixture"
  grep -Fq 'coverage_mode' "$TEST_TMP_ROOT/max-cover-candidates.jsonl" ||
    fail "max-cover selection did not emit score_json"

  printf 'README.md\ntests/\n' >"$TEST_TMP_ROOT/upkeeperignore"
  CODEX_UPKEEPER_IGNORE_FILE="$TEST_TMP_ROOT/upkeeperignore" lattice query selection-candidates --mode max-cover --format jsonl >"$TEST_TMP_ROOT/max-cover-upkeeperignore.jsonl"
  python3 - "$TEST_TMP_ROOT/max-cover-upkeeperignore.jsonl" <<'PY' ||
import json
import sys

states = {}
for line in open(sys.argv[1], encoding="utf-8"):
    row = json.loads(line)
    states[row.get("path", "")] = (row.get("candidate_state"), row.get("exclusion_reason"))
assert states.get("README.md") == ("excluded", "upkeeperignore"), states.get("README.md")
assert states.get("tests/example.txt") == ("excluded", "upkeeperignore"), states.get("tests/example.txt")
PY
    fail ".upkeeperignore did not exclude max-cover Lattice candidates"

  set +e
  lattice query selection-candidates --mode max-cover --format jsonl \
    2>"$TEST_TMP_ROOT/max-cover-head.err" |
    head -n 1 >"$TEST_TMP_ROOT/max-cover-head.jsonl"
  pipe_status=("${PIPESTATUS[@]}")
  set -e
  [[ "${pipe_status[0]}" -eq 0 ]] || fail "max-cover query did not tolerate a closed stdout pipe"
  [[ "${pipe_status[1]}" -eq 0 ]] || fail "head unexpectedly failed for max-cover pipe"
  [[ -s "$TEST_TMP_ROOT/max-cover-head.jsonl" ]] || fail "max-cover pipe did not emit one row"
  [[ ! -s "$TEST_TMP_ROOT/max-cover-head.err" ]] || fail "max-cover pipe wrote stderr on closed pipe"

  for pass_num in $(seq 1 29); do
    lattice record-pass-result \
      --pass "P$pass_num" \
      --file "README.md" \
      --applicable 1 \
      --outcome clean \
      --changed 0 \
      --regression 0 >/dev/null
  done
  lattice query selection-candidates --mode max-cover --format jsonl >"$TEST_TMP_ROOT/max-cover-after-readme.jsonl"
  first_after_readme="$(python3 - "$TEST_TMP_ROOT/max-cover-after-readme.jsonl" <<'PY'
import json
import sys

for line in open(sys.argv[1], encoding="utf-8"):
    row = json.loads(line)
    if row.get("candidate_state") == "eligible":
        print(row.get("path", ""))
        break
PY
)"
  [[ "$first_after_readme" != "README.md" ]] ||
    fail "max-cover still preferred fully covered README.md over unrun tracked text"
  python3 - "$TEST_TMP_ROOT/max-cover-after-readme.jsonl" <<'PY' ||
import json
import sys

for line in open(sys.argv[1], encoding="utf-8"):
    row = json.loads(line)
    if row.get("path") == "README.md":
        score = json.loads(row.get("score_json") or "{}")
        assert score.get("unrun_pass_count") == 0, score
        assert score.get("least_covered_count") == 1, score
        break
else:
    raise AssertionError("README.md max-cover score missing")
PY
    fail "fully covered README.md did not get the expected max-cover score"
  lattice record-preselect \
    --cycle-id cycle-1 \
    --run-hash hash-1 \
    --selection-file "$TEST_TMP_ROOT/selection.env" \
    --candidate-file "$TEST_TMP_ROOT/candidates.jsonl" >$TEST_TMP_ROOT/lattice-preselect.json

  lattice record-pass-result \
    --cycle-id cycle-1 \
    --run-hash hash-1 \
    --pass P999 \
    --file "space name.sh" \
    --applicable 1 \
    --outcome fixed \
    --changed 1 \
    --regression 0 \
    --attribute custom:key=42 >$TEST_TMP_ROOT/lattice-p999.json
  assert_sql_value "1" "select count(*) from review_passes where pass_code='P999'"
  assert_sql_value "42" "select value_integer from pass_run_attributes where namespace='custom' and key='key'"

  cat >"$TEST_TMP_ROOT/last-message.txt" <<'EOF'
UPKEEPER_PASS_RESULT: pass=P23 file="space name.sh" applicable=1 outcome=clean changed=0 regression=0
UPKEEPER_PASS_RESULT: pass=P24 file="space name.sh" applicable=1 outcome=clean changed=0 changed=0 regression=0
```
UPKEEPER_PASS_RESULT: pass=P25 file="space name.sh" applicable=1 outcome=clean changed=0 regression=0
```
UPKEEPER_STATUS: WORK_DONE
EOF
  lattice record-pass-result \
    --cycle-id cycle-1 \
    --run-hash hash-1 \
    --from-file "$TEST_TMP_ROOT/last-message.txt" \
    --selected-path "space name.sh" \
    --planned-passes P23,P24,P25 >$TEST_TMP_ROOT/lattice-pass-lines.json
  assert_sql_value "1" "select count(*) from source_records where parse_status='rejected'"
  assert_sql_value "1" "select count(*) from file_pass_runs where pass_code='P24' and outcome='unknown'"

  printf '#!/usr/bin/env bash\nprintf "space changed\\n"\n' >"$REPO/space name.sh"
  lattice record-cycle-finish \
    --cycle-id cycle-1 \
    --run-hash hash-1 \
    --wrapper-exit 0 \
    --finish-reason TEST_FINISH \
    --finish-level INFO \
    --codex-exec-started 1 \
    --dry-run 0 \
    --selected-path "space name.sh" \
    --last-message-file "$TEST_TMP_ROOT/last-message.txt" >$TEST_TMP_ROOT/lattice-finish.json
  assert_sql_value "1" "select count(*) from worktree_snapshots where snapshot_kind='after_codex'"
  assert_sql_value "1" "select count(*) from file_events where event_kind='snapshot_before' and path='space name.sh'"
  assert_sql_value "1" "select count(*) from file_events where event_kind='snapshot_after' and path='space name.sh'"
  assert_sql_min "1" "select count(*) from file_events where event_kind='changed' and path='space name.sh'"

  lattice record-cycle-start \
    --cycle-id cycle-clean \
    --run-hash hash-clean \
    --execution-origin primary \
    --model gpt-5.5 \
    --effort xhigh \
    --mode '--sandbox workspace-write' \
    --config-file Upkeeper.conf \
    --dirty-path-count 0 \
    --dry-run 1 >$TEST_TMP_ROOT/lattice-clean-start.json
  cat >"$TEST_TMP_ROOT/selection-clean.env" <<'EOF'
path=unicode-λ.sh
epoch=101
git_status=clean
content_state=matches_head
eligible_count=1
selection_mode=oldest-mtime
selection_basis=clean touch fixture
EOF
  lattice record-preselect \
    --cycle-id cycle-clean \
    --run-hash hash-clean \
    --selection-file "$TEST_TMP_ROOT/selection-clean.env" >$TEST_TMP_ROOT/lattice-clean-preselect.json
  lattice record-pass-result \
    --cycle-id cycle-clean \
    --run-hash hash-clean \
    --pass P23 \
    --file "unicode-λ.sh" \
    --applicable 1 \
    --outcome clean \
    --changed 0 \
    --regression 0 >$TEST_TMP_ROOT/lattice-clean-pass.json
  touch -d @2000000000 "$REPO/unicode-λ.sh"
  lattice record-cycle-finish \
    --cycle-id cycle-clean \
    --run-hash hash-clean \
    --wrapper-exit 0 \
    --finish-reason CLEAN_FINISH \
    --finish-level INFO \
    --codex-exec-started 1 \
    --dry-run 0 \
    --selected-path "unicode-λ.sh" >$TEST_TMP_ROOT/lattice-clean-finish.json
  assert_sql_value "1" "select count(*) from file_events where event_kind='touched_clean' and path='unicode-λ.sh'"

  printf '# dirty before codex\n' >>"$REPO/brackets[1].sh"
  lattice record-cycle-start \
    --cycle-id cycle-dirty \
    --run-hash hash-dirty \
    --execution-origin primary \
    --model gpt-5.5 \
    --effort xhigh \
    --mode '--sandbox workspace-write' \
    --config-file Upkeeper.conf \
    --dirty-path-count 1 \
    --dry-run 1 >$TEST_TMP_ROOT/lattice-dirty-start.json
  cat >"$TEST_TMP_ROOT/selection-dirty.env" <<'EOF'
path=brackets[1].sh
epoch=102
git_status=M
content_state=differs_from_head
eligible_count=1
selection_mode=oldest-mtime
selection_basis=dirty baseline fixture
EOF
  lattice record-preselect \
    --cycle-id cycle-dirty \
    --run-hash hash-dirty \
    --selection-file "$TEST_TMP_ROOT/selection-dirty.env" >$TEST_TMP_ROOT/lattice-dirty-preselect.json
  lattice record-pass-result \
    --cycle-id cycle-dirty \
    --run-hash hash-dirty \
    --pass P23 \
    --file "brackets[1].sh" \
    --applicable 1 \
    --outcome clean \
    --changed 0 \
    --regression 0 >$TEST_TMP_ROOT/lattice-dirty-pass.json
  lattice record-cycle-finish \
    --cycle-id cycle-dirty \
    --run-hash hash-dirty \
    --wrapper-exit 0 \
    --finish-reason DIRTY_BASELINE_FINISH \
    --finish-level INFO \
    --codex-exec-started 1 \
    --dry-run 0 \
    --selected-path "brackets[1].sh" >$TEST_TMP_ROOT/lattice-dirty-finish.json
  assert_sql_value "1" "select count(*) from file_events where event_kind='dirty_baseline' and path='brackets[1].sh'"
  assert_sql_value "0" "select count(*) from file_events where event_kind='changed' and path='brackets[1].sh'"

  lattice query never-pass --pass P23 --format json --scope known-active >$TEST_TMP_ROOT/lattice-never-pass.json
  lattice query pass-counts --path "space name.sh" --format json >$TEST_TMP_ROOT/lattice-pass-counts.json
  python3 - $TEST_TMP_ROOT/lattice-pass-counts.json <<'PY' || fail "pass-counts did not expose expected counters"
import json, sys
rows = json.load(open(sys.argv[1], encoding="utf-8"))
codes = {row["pass_code"]: row for row in rows}
assert codes["P23"]["completed_count"] == 1, rows
assert codes["P24"]["unknown_count"] == 1, rows
assert codes["P999"]["changed_count"] == 1, rows
PY

  lattice import-change-notes "$TEST_TMP_ROOT/change_notes_2026.md" >$TEST_TMP_ROOT/lattice-empty-notes.json
  cat >"$TEST_TMP_ROOT/change_notes_2026.md" <<'EOF'
# 2026 Change Notes

2026-05-08: vtest changes:
	1. Updated `space name.sh` to exercise changelog imports.
EOF
  lattice import-change-notes "$TEST_TMP_ROOT/change_notes_2026.md" >$TEST_TMP_ROOT/lattice-notes.json
  assert_sql_value "1" "select count(*) from change_log_entries where version='vtest'"

  cat >"$TEST_TMP_ROOT/Upkeeper.log" <<'EOF'
2026-05-08T00:00:00-0700 [INFO] cycle=log-cycle run_hash=loghash cycle.start mode=--sandbox\ workspace-write model=gpt-5.5 dry_run=1
2026-05-08T00:00:01-0700 [INFO] cycle=log-cycle run_hash=loghash review.preselect path=space\ name.sh basis=quoted\ basis
2026-05-08T00:00:02-0700 [INFO] cycle=log-cycle run_hash=loghash cycle.exit exit_code=0 reason=DRY_RUN codex_exec_started=0
EOF
  lattice import-upkeeper-log --path "$TEST_TMP_ROOT/Upkeeper.log" --raw >$TEST_TMP_ROOT/lattice-log.json
  assert_sql_value "1" "select count(*) from cycles where cycle_id='log-cycle'"

  lattice import-git >$TEST_TMP_ROOT/lattice-git.json
  assert_sql_value "1" "select count(*) from git_file_changes where status like 'R%' and old_path='rename-old.sh' and path='rename-new.sh'"
  assert_sql_value "1" "select count(distinct file_id) from git_file_changes where path in ('rename-old.sh','rename-new.sh')"
  assert_sql_value "0" "select count(*) from (select commit_id, status, path, old_path, count(*) as c from git_file_changes group by commit_id, status, path, old_path having c > 1)"
  lattice import-git >$TEST_TMP_ROOT/lattice-git-repeat.json
  python3 - "$TEST_TMP_ROOT/lattice-git-repeat.json" <<'PY' || fail "repeated Git import was not idempotent"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "ok", data
assert data["commits_written"] == 0, data
assert data["file_changes_written"] == 0, data
assert data["file_changes_duplicate"] > 0, data
PY
  assert_sql_value "0" "select count(*) from (select commit_id, status, path, old_path, count(*) as c from git_file_changes group by commit_id, status, path, old_path having c > 1)"
  run_sql "drop index idx_git_file_changes_unique_event;
insert into git_file_changes(repo_id, commit_id, file_id, status, path, old_path, additions, deletions, change_epoch, source_id)
select repo_id, commit_id, file_id, status, path, old_path, additions, deletions, change_epoch, source_id
from git_file_changes
limit 3;"
  assert_sql_value "3" "select count(*) from (select commit_id, status, path, old_path, count(*) as c from git_file_changes group by commit_id, status, path, old_path having c > 1)"
  lattice init >$TEST_TMP_ROOT/lattice-init-dedupe.json
  assert_sql_value "0" "select count(*) from (select commit_id, status, path, old_path, count(*) as c from git_file_changes group by commit_id, status, path, old_path having c > 1)"
  assert_sql_value "1" "select count(*) from sqlite_master where type='index' and name='idx_git_file_changes_unique_event'"
  lattice query file-history --path "space name.sh" --format json >$TEST_TMP_ROOT/lattice-history.json
  lattice query file-history --path "rename-new.sh" --format json >$TEST_TMP_ROOT/lattice-rename-history.json
  lattice query file-history --path "rename-old.sh" --format json >$TEST_TMP_ROOT/lattice-rename-old-history.json
  python3 - "$TEST_TMP_ROOT/lattice-rename-history.json" <<'PY' || fail "renamed file history did not stay on one lineage"
import json, sys
rows = json.load(open(sys.argv[1], encoding="utf-8"))
statuses = [row.get("status", "") for row in rows if row.get("kind") == "git_change"]
assert "A" in statuses, rows
assert any(status.startswith("R") for status in statuses), rows
assert "M" in statuses, rows
PY
  python3 - "$TEST_TMP_ROOT/lattice-rename-old-history.json" <<'PY' || fail "old rename path did not resolve through file path aliases"
import json, sys
rows = json.load(open(sys.argv[1], encoding="utf-8"))
assert any(row.get("path") == "rename-new.sh" and row.get("status", "").startswith("R") for row in rows), rows
PY

  lattice backup >$TEST_TMP_ROOT/lattice-backup.json
  python3 - $TEST_TMP_ROOT/lattice-backup.json <<'PY' || fail "backup command did not create a backup"
import json, pathlib, sys
path = pathlib.Path(json.load(open(sys.argv[1], encoding="utf-8"))["backup_path"])
assert path.exists() and path.stat().st_size > 0, path
PY

  lattice export-jsonl --output "$TEST_TMP_ROOT/export.jsonl" >$TEST_TMP_ROOT/lattice-export.json
  lattice import-jsonl "$TEST_TMP_ROOT/export.jsonl" >$TEST_TMP_ROOT/lattice-import-repeat-1.json
  lattice import-jsonl "$TEST_TMP_ROOT/export.jsonl" >$TEST_TMP_ROOT/lattice-import-repeat-2.json
  python3 - $TEST_TMP_ROOT/lattice-import-repeat-2.json <<'PY' || fail "repeated JSONL import was not idempotent"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["conflicts"] == 0, data
PY

  python3 - "$TEST_TMP_ROOT/export.jsonl" "$TEST_TMP_ROOT/conflict.jsonl" <<'PY'
import json
import sys

src, dst = sys.argv[1:3]
changed = False
with open(src, encoding="utf-8") as handle, open(dst, "w", encoding="utf-8") as out:
    for line in handle:
        row = json.loads(line)
        if not changed and row.get("row_type") == "files":
            row["payload"]["current_state"] = "deleted"
            row["payload_sha256"] = "different"
            changed = True
        print(json.dumps(row, sort_keys=True, separators=(",", ":")), file=out)
assert changed
PY
  set +e
  lattice import-jsonl "$TEST_TMP_ROOT/conflict.jsonl" >"$TEST_TMP_ROOT/conflict.out" 2>"$TEST_TMP_ROOT/conflict.err"
  local conflict_rc=$?
  set -e
  [[ "$conflict_rc" -eq 8 ]] || fail "conflicting JSONL import exited $conflict_rc, expected 8"
  assert_sql_value "1" "select count(*) from lattice_import_conflicts"
}

test_no_git_import_and_recovery() {
  local no_git_dir no_git_db rc recover_repo recover_db

  no_git_dir="$TEST_TMP_ROOT/no-git"
  no_git_db="$no_git_dir/runtime/upkeeper-lattice/lattice.sqlite3"
  mkdir -p "$no_git_dir"
  "$LATTICE_TOOL" --root "$no_git_dir" --db "$no_git_db" init >$TEST_TMP_ROOT/lattice-no-git-init.json
  set +e
  "$LATTICE_TOOL" --root "$no_git_dir" --db "$no_git_db" import-git >"$TEST_TMP_ROOT/no-git.out" 2>"$TEST_TMP_ROOT/no-git.err"
  rc=$?
  set -e
  [[ "$rc" -eq 7 ]] || fail "import-git without git exited $rc, expected 7"
  grep -Fq '"reason": "no_git_repository"' "$TEST_TMP_ROOT/no-git.out" ||
    fail "import-git without git did not report no_git_repository"

  recover_repo="$TEST_TMP_ROOT/recover-repo"
  recover_db="$recover_repo/runtime/upkeeper-lattice/lattice.sqlite3"
  make_repo "$recover_repo"
  cat >"$recover_repo/Upkeeper.log" <<'EOF'
2026-05-08T00:00:00-0700 [INFO] cycle=recover-cycle run_hash=recoverhash cycle.start model=gpt-5.5
EOF
  mkdir -p "$recover_repo/runtime/startup-anomaly-gates" \
    "$recover_repo/runtime/upkeeper-transcripts" \
    "$recover_repo/runtime/journals/upkeeper-postmortems/recover-cycle"
  printf '{"status":"active"}\n' >"$recover_repo/runtime/startup-anomaly-gates/recover-cycle.json"
  printf '{"type":"metadata"}\n' >"$recover_repo/runtime/upkeeper-transcripts/recover-cycle.jsonl"
  printf 'blocked_until_epoch=2000000000\n' >"$recover_repo/runtime/journals/upkeeper-postmortems/recover-cycle/primary-quota-blocked-until.txt"
  "$LATTICE_TOOL" --root "$recover_repo" --db "$recover_db" recover >"$TEST_TMP_ROOT/recover.out"
  grep -Fq '"status": "ok"' "$TEST_TMP_ROOT/recover.out" ||
    fail "recover did not report ok from local fixtures"
  DB="$recover_db"
  assert_sql_min "1" "select count(*) from artifact_refs where artifact_kind='startup_anomaly_state'"
  assert_sql_min "1" "select count(*) from artifact_refs where artifact_kind='transcript'"
  assert_sql_min "1" "select count(*) from artifact_refs where artifact_kind='quota_block_marker'"
}

test_wrapper_required_policy() {
  local repo rc

  repo="$TEST_TMP_ROOT/client"
  make_repo "$repo"
  ln -s "$ROOT_DIR/Upkeeper" "$repo/Upkeeper.sh"
  touch "$repo/tracked.sqlite3"
  (
    cd "$repo"
    git add tracked.sqlite3
    git commit -q -m "tracked unsafe db"
  )
  write_quota_snapshot "$TEST_TMP_ROOT/codex-home/sessions/2026/05/08/fake.jsonl"

  set +e
  (
    cd "$repo"
    CODEX_HOME="$TEST_TMP_ROOT/codex-home" \
      CODEX_LOG_FILE="$repo/Upkeeper.log" \
      CODEX_TRANSCRIPT_DIR="$repo/runtime/transcripts" \
      CODEX_ACTIVE_LOCK_DIR="$repo/runtime/active.lock" \
      CODEX_WRAPPER_HEALTH_STATE_DIR="$repo/runtime/health" \
      CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$repo/runtime/startup-gates" \
      CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
      CODEX_TERMINAL_VERBOSITY=quiet \
      CODEX_MODEL=gpt-5.5 \
      CODEX_REASONING_EFFORT=xhigh \
      CODEX_FALLBACK_ENABLED=0 \
      CODEX_FALLBACK_SCREEN_ENABLED=0 \
      CODEX_POSTMORTEM_ENABLED=0 \
      UPKEEPER_PRECONTACT_BACKUP_ROOT="$TEST_TMP_ROOT/precontact-vault" \
      UPKEEPER_LATTICE_DB="$repo/tracked.sqlite3" \
      UPKEEPER_LATTICE_REQUIRED=0 \
      UPKEEPER_DRY_RUN=1 \
      ./Upkeeper.sh --target-file="space name.sh" >"$TEST_TMP_ROOT/required0.out" 2>"$TEST_TMP_ROOT/required0.err"
  )
  rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || fail "REQUIRED=0 unsafe DB dry-run exited $rc, expected 0"
  grep -Fq "lattice.unavailable required=0" "$repo/Upkeeper.log" ||
    fail "REQUIRED=0 did not warn about unavailable lattice"
  [[ -s "$repo/runtime/upkeeper-lattice/recovery/lattice-unavailable.jsonl" ]] ||
    fail "REQUIRED=0 did not spool recovery evidence"

  set +e
  (
    cd "$repo"
    : >Upkeeper.log
    CODEX_HOME="$TEST_TMP_ROOT/codex-home" \
      CODEX_LOG_FILE="$repo/Upkeeper.log" \
      CODEX_TRANSCRIPT_DIR="$repo/runtime/transcripts2" \
      CODEX_ACTIVE_LOCK_DIR="$repo/runtime/active2.lock" \
      CODEX_WRAPPER_HEALTH_STATE_DIR="$repo/runtime/health2" \
      CODEX_STARTUP_ANOMALY_GATE_STATE_DIR="$repo/runtime/startup-gates2" \
      CODEX_OPERATOR_GUIDE_BOOTSTRAP=0 \
      CODEX_TERMINAL_VERBOSITY=quiet \
      CODEX_MODEL=gpt-5.5 \
      CODEX_REASONING_EFFORT=xhigh \
      CODEX_FALLBACK_ENABLED=0 \
      CODEX_FALLBACK_SCREEN_ENABLED=0 \
      CODEX_POSTMORTEM_ENABLED=0 \
      UPKEEPER_PRECONTACT_BACKUP_ROOT="$TEST_TMP_ROOT/precontact-vault" \
      UPKEEPER_LATTICE_DB="$repo/tracked.sqlite3" \
      UPKEEPER_LATTICE_REQUIRED=1 \
      UPKEEPER_DRY_RUN=1 \
      ./Upkeeper.sh --target-file="space name.sh" >"$TEST_TMP_ROOT/required1.out" 2>"$TEST_TMP_ROOT/required1.err"
  )
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || fail "REQUIRED=1 unsafe DB dry-run exited $rc, expected 3"
  grep -Fq "reason=LATTICE_UNAVAILABLE" "$repo/Upkeeper.log" ||
    fail "REQUIRED=1 did not fail before Codex launch with LATTICE_UNAVAILABLE"
  grep -Fq "codex_exec_started=0" "$repo/Upkeeper.log" ||
    fail "REQUIRED=1 failure did not record codex_exec_started=0"
}

test_lattice_cli_contracts
test_no_git_import_and_recovery
test_wrapper_required_policy
printf 'ok - lattice\n'
