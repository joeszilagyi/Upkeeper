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
  cp "$DB" "$TEST_TMP_ROOT/lattice-import-base.sqlite3"
  lattice doctor >$TEST_TMP_ROOT/lattice-doctor.json
  python3 - $TEST_TMP_ROOT/lattice-doctor.json <<'PY' || fail "doctor JSON did not pass"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "ok", data
assert data["checks"]["foreign_keys"] == 1, data
assert data["checks"]["quick_check"] == "ok", data
assert data["checks"]["required_tables_missing"] == [], data
assert data["checks"]["required_indexes_missing"] == [], data
raw_checks = data["checks"]["raw_storage_enforcement"]
for mode in ("minimal", "limited", "full"):
    assert raw_checks[mode]["replayed_upkeeper_log_raw"]["source_hashed"], raw_checks
    assert raw_checks[mode]["replayed_upkeeper_log_raw"]["limit_ids_hashed"], raw_checks
    assert raw_checks[mode]["replayed_upkeeper_log_raw"]["quota_fields_removed"], raw_checks
    assert raw_checks[mode]["imported_quota_source_record"]["source_path_hashed"], raw_checks
    assert raw_checks[mode]["imported_quota_source_record"]["source_uri_hashed"], raw_checks
assert raw_checks["full"]["imported_quota_source_record"]["raw_text_redacted"], raw_checks
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

  mapfile -t active_pass_codes < <(
    python3 - "$DB" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
for (pass_code,) in conn.execute("select pass_code from review_passes where active=1 order by pass_code"):
    print(pass_code)
PY
  )
  [[ "${#active_pass_codes[@]}" -gt 0 ]] || fail "could not read active Lattice pass registry"
  for pass_code in "${active_pass_codes[@]}"; do
    lattice record-pass-result \
      --pass "$pass_code" \
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

  mkdir -p "$REPO/runtime"
  local last_message_path="$REPO/runtime/last-message.txt"
  cat >"$last_message_path" <<'EOF'
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
    --from-file "$last_message_path" \
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
    --last-message-file "$last_message_path" >$TEST_TMP_ROOT/lattice-finish.json
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
  cat >"$TEST_TMP_ROOT/change_notes_2026_malicious.md" <<'EOF'
# 2026 Change Notes

2026-05-09: vtest changes:
	1. Added `https://example.com/space name.sh`.
	2. Added `../outside.py`.
	3. Added `/abs-path.sh`.
	4. Added `foo//bar.txt`.
	5. Added `./dot-prefix.sh`.
EOF
  lattice import-change-notes "$TEST_TMP_ROOT/change_notes_2026_malicious.md" >$TEST_TMP_ROOT/lattice-malicious-notes.json
  assert_sql_value "0" "select count(*) from change_log_file_refs where path='https://example.com/space name.sh'"
  assert_sql_value "0" "select count(*) from change_log_file_refs where path='../outside.py'"
  assert_sql_value "0" "select count(*) from change_log_file_refs where path='/abs-path.sh'"
  assert_sql_value "0" "select count(*) from change_log_file_refs where path='foo//bar.txt'"
  assert_sql_value "0" "select count(*) from change_log_file_refs where path='./dot-prefix.sh'"

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

  lattice export-jsonl --include-paths --output "$TEST_TMP_ROOT/export.jsonl" >$TEST_TMP_ROOT/lattice-export.json
  local lattice_import_rollup_db="$TEST_TMP_ROOT/lattice-import-rollup.sqlite3"
  local original_db="$DB"
  cp "$TEST_TMP_ROOT/lattice-import-base.sqlite3" "$lattice_import_rollup_db"
  DB="$lattice_import_rollup_db"
  UPKEEPER_LATTICE_ALLOW_UNSAFE_DB=1 \
    lattice import-jsonl "$TEST_TMP_ROOT/export.jsonl" >"$TEST_TMP_ROOT/lattice-import-rollup.json"
  python3 - "$original_db" "$lattice_import_rollup_db" <<'PY' || fail "import-jsonl did not rebuild file_pass_rollups"
import sqlite3
import sys

src_db, dst_db = sys.argv[1], sys.argv[2]
src = sqlite3.connect(src_db)
dst = sqlite3.connect(dst_db)
src.execute("PRAGMA foreign_keys=ON")
dst.execute("PRAGMA foreign_keys=ON")

src_rows = src.execute(
    """
    select count(*)
    from file_pass_runs r
    join files f on f.file_id = r.file_id
    join repositories repo on repo.repo_id = f.repo_id
    where (f.current_path = 'space name.sh' or f.canonical_path = 'space name.sh')
    """
).fetchone()[0]
if src_rows <= 0:
    raise AssertionError(f"source DB has no file_pass_runs for space name.sh, got {src_rows}")

dst_rows = dst.execute(
    """
    select count(*)
    from file_pass_runs r
    join files f on f.file_id = r.file_id
    join repositories repo on repo.repo_id = f.repo_id
    where (f.current_path = 'space name.sh' or f.canonical_path = 'space name.sh')
    """
).fetchone()[0]
if dst_rows != src_rows:
    raise AssertionError(f"imported file_pass_runs for space name.sh should match, source={src_rows} dst={dst_rows}")

rollup = dst.execute(
    """
    select rp.planned_count
    from files f
    join file_pass_rollups rp on rp.file_id = f.file_id
    where (f.current_path = 'space name.sh' or f.canonical_path = 'space name.sh')
    """
).fetchone()
if rollup is None:
    raise AssertionError("imported DB is missing file_pass_rollups for space name.sh")
if rollup[0] < 1:
    raise AssertionError(f"expected positive planned_count after import, got {rollup[0]}")
PY
  DB="$original_db"

  "$LATTICE_TOOL" --root "$REPO" --db "$original_db" export-jsonl --output "$TEST_TMP_ROOT/export-redacted.jsonl" >"$TEST_TMP_ROOT/lattice-export-redacted.json"
  local redacted_import_db="$TEST_TMP_ROOT/lattice-import-redacted.sqlite3"
  cp "$TEST_TMP_ROOT/lattice-import-base.sqlite3" "$redacted_import_db"
  DB="$redacted_import_db"
  set +e
  UPKEEPER_LATTICE_ALLOW_UNSAFE_DB=1 \
    lattice import-jsonl "$TEST_TMP_ROOT/export-redacted.jsonl" >"$TEST_TMP_ROOT/lattice-import-redacted.out" 2>"$TEST_TMP_ROOT/lattice-import-redacted.err"
  local redacted_export_rc=$?
  set -e
  [[ "$redacted_export_rc" -ne 0 ]] || fail "default redacted export should require --include-paths for structural replay"
  DB="$original_db"

  UPKEEPER_LATTICE_RAW_STORAGE=full \
    lattice export-jsonl --include-paths --include-raw --output "$TEST_TMP_ROOT/export-replay.jsonl" >"$TEST_TMP_ROOT/lattice-export-replay.json"

  UPKEEPER_LATTICE_RAW_STORAGE=full \
    lattice import-jsonl --preserve-raw "$TEST_TMP_ROOT/export-replay.jsonl" >$TEST_TMP_ROOT/lattice-import-repeat-1.json
  UPKEEPER_LATTICE_RAW_STORAGE=full \
    lattice import-jsonl --preserve-raw "$TEST_TMP_ROOT/export-replay.jsonl" >$TEST_TMP_ROOT/lattice-import-repeat-2.json
  python3 - $TEST_TMP_ROOT/lattice-import-repeat-2.json <<'PY' || fail "repeated JSONL import was not idempotent"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["conflicts"] == 0, data
PY

  python3 - "$TEST_TMP_ROOT/export-replay.jsonl" "$TEST_TMP_ROOT/conflict.jsonl" <<'PY'
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
  UPKEEPER_LATTICE_RAW_STORAGE=full \
    lattice import-jsonl --preserve-raw "$TEST_TMP_ROOT/conflict.jsonl" >"$TEST_TMP_ROOT/conflict.out" 2>"$TEST_TMP_ROOT/conflict.err"
  local conflict_rc=$?
  set -e
  [[ "$conflict_rc" -eq 8 ]] || fail "conflicting JSONL import exited $conflict_rc, expected 8"
  assert_sql_value "1" "select count(*) from lattice_import_conflicts"

  python3 - "$TEST_TMP_ROOT/export-replay.jsonl" "$TEST_TMP_ROOT/conflict-rehashed.jsonl" <<'PY'
import hashlib
import json
import sys


def dumps(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


src, dst = sys.argv[1:3]
changed_file = False
changed_schema = False
with open(src, encoding="utf-8") as handle, open(dst, "w", encoding="utf-8") as out:
    for line in handle:
        row = json.loads(line)
        if not changed_file and row.get("row_type") == "files":
            row["payload"]["current_state"] = "deleted"
            row["payload_sha256"] = hashlib.sha256(dumps(row["payload"]).encode("utf-8")).hexdigest()
            changed_file = True
        elif not changed_schema and row.get("row_type") == "schema_meta" and row["payload"].get("key") == "schema_version":
            row["payload"]["value"] = f"{row['payload'].get('value', '')}-conflict"
            row["payload_sha256"] = hashlib.sha256(dumps(row["payload"]).encode("utf-8")).hexdigest()
            changed_schema = True
        print(dumps(row), file=out)
assert changed_file
assert changed_schema
PY
  set +e
  UPKEEPER_LATTICE_RAW_STORAGE=full \
    lattice import-jsonl --preserve-raw "$TEST_TMP_ROOT/conflict-rehashed.jsonl" >"$TEST_TMP_ROOT/conflict-rehashed.out" 2>"$TEST_TMP_ROOT/conflict-rehashed.err"
  local rehashed_conflict_rc=$?
  set -e
  [[ "$rehashed_conflict_rc" -eq 8 ]] || fail "same-key rehashed JSONL import exited $rehashed_conflict_rc, expected 8"
  python3 - "$TEST_TMP_ROOT/conflict-rehashed.out" "$DB" <<'PY' || fail "rehashed JSONL import did not report same-key conflicts"
import json
import sqlite3
import sys

summary_path, db_path = sys.argv[1:3]
summary = json.load(open(summary_path, encoding="utf-8"))
if summary.get("duplicates", 0) <= 0:
    raise AssertionError(f"expected unchanged rows to remain duplicates: {summary}")
if summary.get("conflicts", 0) < 2:
    raise AssertionError(f"expected file and schema conflicts: {summary}")

conn = sqlite3.connect(db_path)
rows = conn.execute(
    """
    select row_type, logical_key, resolution, existing_hash, incoming_hash
    from lattice_import_conflicts
    where resolution='kept_existing'
    """
).fetchall()
row_types = {row[0] for row in rows}
if "files" not in row_types or "schema_meta" not in row_types:
    raise AssertionError(f"same-key conflicts were not recorded for files and schema_meta: {rows}")
for row_type, logical_key, resolution, existing_hash, incoming_hash in rows:
    if not existing_hash or not incoming_hash or existing_hash == incoming_hash:
        raise AssertionError(f"conflict hash evidence was incomplete for {row_type}:{logical_key}: {rows}")
PY

  set +e
  UPKEEPER_LATTICE_RAW_STORAGE=full \
    lattice import-jsonl --preserve-raw "$TEST_TMP_ROOT/export-replay.jsonl" --max-conflicts=0 >"$TEST_TMP_ROOT/malformed-jsonl.out" 2>"$TEST_TMP_ROOT/malformed-jsonl.err"
  local malformed_jsonl_rc=$?
  set -e
  [[ "$malformed_jsonl_rc" -eq 0 ]] || fail "valid export should still import successfully, got $malformed_jsonl_rc"

  printf 'not-jsonl\n' >"$TEST_TMP_ROOT/malformed.jsonl"
  set +e
  lattice import-jsonl "$TEST_TMP_ROOT/malformed.jsonl" >"$TEST_TMP_ROOT/malformed-import.out" 2>"$TEST_TMP_ROOT/malformed-import.err"
  local malformed_import_rc=$?
  set -e
  [[ "$malformed_import_rc" -eq 8 ]] || fail "malformed JSONL import exited $malformed_import_rc, expected 8"
  python3 - "$TEST_TMP_ROOT/malformed-import.out" <<'PY' || fail "malformed JSONL import should report conflicts"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "conflicts", data
assert data["conflicts"] > 0, data
PY

  python3 - "$DB" "$TEST_TMP_ROOT/injected.jsonl" <<'PY'
import json
import sqlite3
import sys
import time

db_path, out = sys.argv[1:3]
conn = sqlite3.connect(db_path)
repo_id = conn.execute("select repo_id from repositories order by repo_id asc limit 1").fetchone()[0]
base = int(time.time())
payload = {
  "repo_id": repo_id,
  "canonical_path": "security-danger.txt",
  "current_path": "security-danger.txt",
  "current_state": "active",
  "first_seen_epoch": base,
  "last_seen_epoch": base,
}
row = {
    "schema_version": 1,
    "row_type": "files",
    "row_version": 2,
    "logical_key": "files:security-danger.txt",
    "source_identity": {"db_path_hash": "integration"},
    "repo_identity": {"repo_id": repo_id, "root_path": "/tmp"},
    "payload": payload,
    "payload_sha256": "",
    "exported_epoch": base,
}
row["payload_sha256"] = __import__("hashlib").sha256(json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False, default=str).encode("utf-8")).hexdigest()
with open(out, "w", encoding="utf-8") as handle:
    handle.write(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n")
PY
  set +e
  lattice import-jsonl "$TEST_TMP_ROOT/injected.jsonl" >"$TEST_TMP_ROOT/injected-row-version.out" 2>"$TEST_TMP_ROOT/injected-row-version.err"
  local row_version_rc=$?
  set -e
  [[ "$row_version_rc" -eq 8 ]] || fail "row-version mismatch JSONL import exited $row_version_rc, expected 8"

  python3 - "$DB" "$TEST_TMP_ROOT/injected-redacted.jsonl" <<'PY'
import hashlib
import json
import sqlite3
import sys
import time

db_path, out = sys.argv[1:3]
conn = sqlite3.connect(db_path)
repo_id = conn.execute("select repo_id from repositories order by repo_id asc limit 1").fetchone()[0]
base = int(time.time())
payload = {
  "repo_id": repo_id,
  "canonical_path": "path-sha256:deadbeefdeadbeefdeadbeef",
  "current_path": "path-sha256:deadbeefdeadbeefdeadbeef",
  "current_state": "active",
  "first_seen_epoch": base,
}
row = {
  "schema_version": 1,
  "row_type": "files",
  "row_version": 1,
  "logical_key": "files:security-danger.txt",
  "source_identity": {"db_path_hash": "integration"},
  "repo_identity": {"repo_id": repo_id, "root_path": "/tmp"},
  "payload": payload,
  "payload_sha256": "",
  "exported_epoch": base,
}
row["payload_sha256"] = hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False, default=str).encode("utf-8")).hexdigest()
with open(out, "w", encoding="utf-8") as handle:
    handle.write(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n")
PY
  set +e
  lattice import-jsonl "$TEST_TMP_ROOT/injected-redacted.jsonl" >"$TEST_TMP_ROOT/injected-redacted.out" 2>"$TEST_TMP_ROOT/injected-redacted.err"
  local redacted_rc=$?
  set -e
  [[ "$redacted_rc" -eq 8 ]] || fail "redacted path JSONL import exited $redacted_rc, expected 8"

  python3 - "$DB" "$TEST_TMP_ROOT/cross-repo.sql" <<'PY'
import sqlite3
import sys
import time

conn = sqlite3.connect(sys.argv[1])
now = int(time.time())
cur = conn.execute(
    "insert into repositories(root_path, created_epoch, last_seen_epoch) values(?, ?, ?)",
    ("/tmp/lattice-cross", now, now),
)
other_repo_id = int(cur.lastrowid)
conn.execute(
    "insert into files(repo_id, canonical_path, current_path, current_state, first_seen_epoch, last_seen_epoch) values(?, ?, ?, ?, ?, ?)",
    (other_repo_id, "foreign_repo_file.txt", "foreign_repo_file.txt", "active", now, now),
)
foreign_file_id = conn.execute(
    "select file_id from files where repo_id=? and canonical_path=?",
    (other_repo_id, "foreign_repo_file.txt"),
).fetchone()[0]
conn.execute(
    "insert into file_paths(file_id, path, first_seen_epoch, last_seen_epoch) values (?, ?, ?, ?)",
    (foreign_file_id, "foreign_repo_file.txt", now, now),
)
cur = conn.execute(
    "insert into worktree_snapshots(repo_id, cycle_pk, snapshot_kind, observed_epoch, source_id) values (?, ?, ?, ?, ?)",
    (other_repo_id, None, "before_codex", now, None),
)
foreign_snapshot_id = int(cur.lastrowid)
conn.execute(
    "insert into worktree_snapshot_paths(worktree_snapshot_id, file_id, path, status, old_path, head_blob, worktree_hash, size_bytes, mtime_epoch) values (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    (foreign_snapshot_id, foreign_file_id, "foreign_repo_file.txt", "clean", None, None, None, 0, now),
)
foreign_selection_run_id = int(
    conn.execute(
        "insert into selection_runs(repo_id, selector_version, source_safe_boundary_version, mode_requested, mode_effective, priority_gate, generated_epoch, selected_file_id, selected_path) values (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            other_repo_id,
            "help_selection.bash/v1",
            "default-review/v1",
            "oldest-mtime",
            "oldest-mtime",
            "selected",
            now,
            foreign_file_id,
            "foreign_repo_file.txt",
        ),
    ).lastrowid
)
conn.execute(
    "insert into selection_candidates(selection_run_id, file_id, path, candidate_state, rank, git_status, content_state) values (?, ?, ?, ?, ?, ?, ?)",
    (foreign_selection_run_id, foreign_file_id, "foreign_repo_file.txt", "excluded", 1, "untracked", "missing"),
)
foreign_entry_id = int(
    conn.execute(
        "insert into change_log_entries(repo_id, version, entry_date, item_number, source_path, source_line, text) values (?, ?, ?, ?, ?, ?, ?)",
        (other_repo_id, "0.1.0", "2026-01-01", 1, "docs/README.md", 1, "foreign entry"),
    ).lastrowid
)
conn.execute(
    "insert into change_log_file_refs(change_log_entry_id, file_id, path, confidence) values (?, ?, ?, ?)",
    (foreign_entry_id, foreign_file_id, "foreign_repo_file.txt", "explicit_path"),
)
conn.commit()
PY
  lattice export-jsonl --output "$TEST_TMP_ROOT/restricted-export.jsonl" >$TEST_TMP_ROOT/export-repo-scoped.out
  python3 - "$TEST_TMP_ROOT/restricted-export.jsonl" <<'PY' || fail "cross-repo rows leaked during export"
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    row = json.loads(line)
    payload = row.get("payload", {})
    row_type = row.get("row_type")
    if row_type in {"file_paths", "worktree_snapshot_paths", "selection_candidates", "change_log_file_refs", "file_pass_rollups", "file_fragility_rollups", "file_git_churn_rollups", "file_selection_rollups", "file_failure_rollups"}:
        if payload.get("path") == "foreign_repo_file.txt" or payload.get("canonical_path") == "foreign_repo_file.txt":
            raise AssertionError(f"cross-repo row leaked into export: {row_type}")
    if row.get("row_type") == "files" and payload.get("canonical_path") == "foreign_repo_file.txt":
        raise AssertionError("cross-repo file row leaked into export")
PY

  set +e
  lattice export-jsonl --output "$DB" >"$TEST_TMP_ROOT/export-collision.out" 2>"$TEST_TMP_ROOT/export-collision.err"
  local collision_rc=$?
  set -e
  [[ "$collision_rc" -ne 0 ]] || fail "export to db path should fail"
}

test_git_status_xy_preserves_index_worktree_columns() {
  local repo candidates_path

  repo="$TEST_TMP_ROOT/git-status-xy"
  REPO="$repo"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git config user.name "Lattice Test"
    git config user.email "lattice@example.invalid"
    printf 'runtime/\n' >.gitignore
    for path in clean.sh unstaged.sh staged.sh both.sh deleted.sh rename-old.sh; do
      printf '#!/usr/bin/env bash\nprintf "%s\\n"\n' "$path" >"$path"
    done
    git add -A
    git commit -q -m "initial xy fixtures"
    printf '# unstaged\n' >>unstaged.sh
    printf '# staged\n' >>staged.sh
    git add staged.sh
    printf '# staged first\n' >>both.sh
    git add both.sh
    printf '# unstaged second\n' >>both.sh
    rm deleted.sh
    git mv rename-old.sh rename-new.sh
  )

  lattice init >"$TEST_TMP_ROOT/git-status-xy-init.json"
  candidates_path="$TEST_TMP_ROOT/git-status-xy-candidates.jsonl"
  lattice query selection-candidates --mode oldest-mtime --format jsonl >"$candidates_path"
  python3 - "$candidates_path" <<'PY' || fail "selection candidates did not preserve Git XY status columns"
import json
import sys

rows = {}
with open(sys.argv[1], encoding="utf-8") as handle:
    for line in handle:
        row = json.loads(line)
        rows[row.get("path")] = row

expected = {
    "clean.sh": "clean",
    "unstaged.sh": "_M",
    "staged.sh": "M_",
    "both.sh": "MM",
    "deleted.sh": "_D",
}
missing = sorted(path for path in expected if path not in rows)
if missing:
    raise AssertionError(f"missing candidate rows: {missing}; saw {sorted(rows)}")
for path, git_status in expected.items():
    got = rows[path].get("git_status")
    if got != git_status:
        raise AssertionError(f"{path} git_status should be {git_status!r}, got {got!r}: {rows[path]}")
PY

  lattice record-worktree-snapshot --snapshot-kind xy >"$TEST_TMP_ROOT/git-status-xy-default-snapshot.json"
  python3 - "$DB" <<'PY' || fail "default worktree snapshot persisted path inventory"
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
snapshot_id = conn.execute(
    "select worktree_snapshot_id from worktree_snapshots where snapshot_kind='xy' order by worktree_snapshot_id desc limit 1"
).fetchone()[0]
path_count = conn.execute(
    "select count(*) from worktree_snapshot_paths where worktree_snapshot_id=?",
    (snapshot_id,),
).fetchone()[0]
dirty_count = conn.execute(
    "select dirty_path_count from worktree_snapshots where worktree_snapshot_id=?",
    (snapshot_id,),
).fetchone()[0]
if path_count != 0:
    raise AssertionError(f"default snapshot should store counts only, found {path_count} path rows")
if dirty_count <= 0:
    raise AssertionError(f"default snapshot should keep dirty path count, got {dirty_count}")
PY

  lattice record-worktree-snapshot --snapshot-kind xy-opt-in --worktree-untracked-files all >"$TEST_TMP_ROOT/git-status-xy-snapshot.json"
  python3 - "$DB" <<'PY' || fail "worktree snapshot did not preserve private Git XY evidence"
import sqlite3
import sys

raw_paths = {"unstaged.sh", "staged.sh", "both.sh", "deleted.sh", "rename-new.sh", "rename-old.sh"}
conn = sqlite3.connect(sys.argv[1])
conn.row_factory = sqlite3.Row
rows = list(
    conn.execute(
      """
      select p.path, p.path_hmac, p.path_class, p.status, p.old_path, p.old_path_hmac, p.old_path_class, p.file_id
        from worktree_snapshot_paths p
        join worktree_snapshots s on s.worktree_snapshot_id = p.worktree_snapshot_id
       where s.snapshot_kind = 'xy-opt-in'
      """
    )
)
if not rows:
    raise AssertionError("opt-in snapshot did not store path rows")
for row in rows:
    if row["path"] in raw_paths or row["old_path"] in raw_paths:
        raise AssertionError(f"snapshot persisted raw path: {dict(row)}")
    if not str(row["path"]).startswith("path-hmac-sha256:"):
        raise AssertionError(f"snapshot path should be HMAC, got {row['path']!r}")
    if row["path_hmac"] != row["path"]:
        raise AssertionError(f"path_hmac should mirror stored path HMAC: {dict(row)}")
    if row["old_path"] and not str(row["old_path"]).startswith("path-hmac-sha256:"):
        raise AssertionError(f"snapshot old_path should be HMAC, got {row['old_path']!r}")
    if row["file_id"] is not None:
        raise AssertionError(f"snapshot path rows should not link raw file ids: {dict(row)}")

statuses = {row["status"] for row in rows}
for status in {" M", "M ", "MM", " D"}:
    if status not in statuses:
        raise AssertionError(f"missing snapshot status {status!r}; saw {sorted(statuses)}")
rename_rows = [row for row in rows if str(row["status"]).startswith("R")]
if not rename_rows:
    raise AssertionError(f"missing rename snapshot row; saw statuses {sorted(statuses)}")
rename = rename_rows[0]
if not rename["old_path"] or not str(rename["old_path"]).startswith("path-hmac-sha256:"):
    raise AssertionError(f"rename old_path should be HMAC, got {rename['old_path']!r}")
if rename["path_class"] != "renamed_new" or rename["old_path_class"] != "renamed_old":
    raise AssertionError(f"rename classes wrong: {dict(rename)}")
for table, column in (("files", "canonical_path"), ("files", "current_path"), ("file_paths", "path")):
    placeholders = ",".join("?" for _ in raw_paths)
    count = conn.execute(
        f"select count(*) from {table} where {column} in ({placeholders})",
        tuple(raw_paths),
    ).fetchone()[0]
    if count:
        raise AssertionError(f"{table}.{column} leaked raw snapshot path count={count}")
PY
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
  local startup_count_before transcript_count_before quota_count_before
  read -r startup_count_before transcript_count_before quota_count_before < <(
python3 - "$DB" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
counts = []
for kind in ("startup_anomaly_state", "transcript", "quota_block_marker"):
    row = conn.execute("select count(*) from artifact_refs where artifact_kind=?", (kind,)).fetchone()
    counts.append(str(row[0] if row else 0))
print(" ".join(counts))
PY
)
  assert_sql_min "1" "select count(*) from artifact_refs where artifact_kind='startup_anomaly_state'"
  assert_sql_min "1" "select count(*) from artifact_refs where artifact_kind='transcript'"
  assert_sql_min "1" "select count(*) from artifact_refs where artifact_kind='quota_block_marker'"
  "$LATTICE_TOOL" --root "$recover_repo" --db "$recover_db" recover >"$TEST_TMP_ROOT/recover-repeat.out"
  assert_sql_value "$startup_count_before" "select count(*) from artifact_refs where artifact_kind='startup_anomaly_state'"
  assert_sql_value "$transcript_count_before" "select count(*) from artifact_refs where artifact_kind='transcript'"
  assert_sql_value "$quota_count_before" "select count(*) from artifact_refs where artifact_kind='quota_block_marker'"
}

test_import_git_prefers_checked_out_branch_state() {
  local repo DB state

  repo="$TEST_TMP_ROOT/lattice-import-git-head-branch"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git config user.name 'Lattice Test'
    git config user.email 'lattice@example.invalid'
    printf 'kept on master\n' >target.txt
    git add target.txt
    git commit -q -m "add target"
    git checkout -q -b dead-delete
    rm -f target.txt
    git add -A
    git commit -q -m "delete target on dead branch"
    git checkout -q master
  )
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/import-head-branch-init.out"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" import-git >"$TEST_TMP_ROOT/import-head-branch.out"

  state="$(python3 - "$DB" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
row = conn.execute("select current_state from files where canonical_path='target.txt'").fetchone()
print("" if row is None else row[0] or "")
conn.close()
PY
)"
  [[ "$state" == "active" ]] || fail "import-git set head-tracked file as $state"
}

test_import_git_privacy_defaults_and_opt_in() {
  local repo default_db optin_db export_path

  repo="$TEST_TMP_ROOT/lattice-import-git-privacy"
  default_db="$repo/runtime/upkeeper-lattice/default.sqlite3"
  optin_db="$repo/runtime/upkeeper-lattice/optin.sqlite3"
  export_path="$TEST_TMP_ROOT/lattice-privacy-export.jsonl"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git config user.name 'Lattice Privacy Fixture'
    git config user.email 'fixture@example.invalid'
    printf 'privacy fixture\n' >tracked.txt
    git add tracked.txt
    GIT_AUTHOR_NAME='Alice Example' \
      GIT_AUTHOR_EMAIL='alice@example.com' \
      GIT_COMMITTER_NAME='Bob Example' \
      GIT_COMMITTER_EMAIL='bob@example.com' \
      git commit -q -m 'Incident ACME-42 for Jane Doe'
  )

  "$LATTICE_TOOL" --root "$repo" --db "$default_db" init >"$TEST_TMP_ROOT/privacy-default-init.out"
  "$LATTICE_TOOL" --root "$repo" --db "$default_db" import-git >"$TEST_TMP_ROOT/privacy-default-import.out"
  python3 - "$default_db" <<'PY' || fail "default import-git retained contributor or subject PII"
import json
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.row_factory = sqlite3.Row
contributor = dict(conn.execute("select name, email, identity_hash, pii_included from contributors order by contributor_id limit 1").fetchone())
commit = dict(conn.execute("select subject, subject_hash, subject_length, subject_included from git_commits order by commit_id limit 1").fetchone())
parsed = json.loads(
    conn.execute(
        "select parsed_json from source_records where source_kind='local_git' and raw_ref!='git-import' order by source_id limit 1"
    ).fetchone()[0]
)
conn.close()

assert contributor["name"] is None, contributor
assert contributor["email"] is None, contributor
assert contributor["identity_hash"].startswith("contributor-sha256:"), contributor
assert int(contributor["pii_included"]) == 0, contributor
assert commit["subject"] is None, commit
assert commit["subject_hash"].startswith("subject-sha256:"), commit
assert int(commit["subject_length"]) == len("Incident ACME-42 for Jane Doe"), commit
assert int(commit["subject_included"]) == 0, commit
assert "subject" not in parsed or parsed["subject"] is None, parsed
assert parsed["subject_hash"].startswith("subject-sha256:"), parsed
PY
  "$LATTICE_TOOL" --root "$repo" --db "$default_db" query file-history --path tracked.txt --format json >"$TEST_TMP_ROOT/privacy-default-history.json"
  python3 - "$TEST_TMP_ROOT/privacy-default-history.json" <<'PY' || fail "file-history exposed a raw commit subject by default"
import json
import sys

rows = json.load(open(sys.argv[1], encoding="utf-8"))
git_rows = [row for row in rows if row.get("kind") == "git_change"]
assert git_rows, rows
assert git_rows[0]["subject"] is None, git_rows
assert git_rows[0]["subject_hash"].startswith("subject-sha256:"), git_rows
PY
  "$LATTICE_TOOL" --root "$repo" --db "$default_db" export-jsonl --output "$export_path" >"$TEST_TMP_ROOT/privacy-default-export.out"
  if grep -Eq 'alice@example.com|Incident ACME-42 for Jane Doe' "$export_path"; then
    fail "default export-jsonl leaked contributor or commit subject PII"
  fi

  "$LATTICE_TOOL" --root "$repo" --db "$optin_db" init >"$TEST_TMP_ROOT/privacy-optin-init.out"
  "$LATTICE_TOOL" --root "$repo" --db "$optin_db" import-git --include-contributor-pii --include-commit-subjects >"$TEST_TMP_ROOT/privacy-optin-import.out"
  python3 - "$optin_db" <<'PY' || fail "opt-in import-git did not preserve raw contributor or subject data"
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.row_factory = sqlite3.Row
contributor = dict(conn.execute("select name, email, identity_hash, pii_included from contributors where email is not null order by contributor_id limit 1").fetchone())
commit = dict(conn.execute("select subject, subject_hash, subject_length, subject_included from git_commits order by commit_id limit 1").fetchone())
conn.close()

assert contributor["name"] == "Alice Example", contributor
assert contributor["email"] == "alice@example.com", contributor
assert contributor["identity_hash"].startswith("contributor-sha256:"), contributor
assert int(contributor["pii_included"]) == 1, contributor
assert commit["subject"] == "Incident ACME-42 for Jane Doe", commit
assert commit["subject_hash"].startswith("subject-sha256:"), commit
assert int(commit["subject_included"]) == 1, commit
PY
}

test_backup_is_read_only() {
  local repo DB counts_before counts_after before_source_count before_artifact_count after_source_count after_artifact_count

  repo="$TEST_TMP_ROOT/lattice-backup-read-only"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git config user.name 'Lattice Test'
    git config user.email 'lattice@example.invalid'
    printf 'noop\n' >README.md
    git add README.md
    git commit -q -m "init"
  )
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/backup-read-only-init.out"

  counts_before="$(python3 - "$DB" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
print(
    f"{conn.execute('select count(*) from source_records').fetchone()[0]} "
    f"{conn.execute('select count(*) from artifact_refs').fetchone()[0]}"
)
conn.close()
PY
)"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" backup >"$TEST_TMP_ROOT/backup-read-only.out"
  counts_after="$(python3 - "$DB" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
print(
    f"{conn.execute('select count(*) from source_records').fetchone()[0]} "
    f"{conn.execute('select count(*) from artifact_refs').fetchone()[0]}"
)
conn.close()
PY
)"

  before_source_count="${counts_before%% *}"
  before_artifact_count="${counts_before##* }"
  after_source_count="${counts_after%% *}"
  after_artifact_count="${counts_after##* }"
  if [[ "$before_source_count" != "$after_source_count" ]]; then
    fail "backup mutated source_records count: before=$before_source_count after=$after_source_count"
  fi
  if [[ "$before_artifact_count" != "$after_artifact_count" ]]; then
    fail "backup mutated artifact_refs count: before=$before_artifact_count after=$after_artifact_count"
  fi
}

test_missing_selection_path_stays_missing() {
  local repo DB

  repo="$TEST_TMP_ROOT/lattice-missing-selection"
  REPO="$repo"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  make_repo "$repo"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/missing-selection-init.out"

  cat >"$TEST_TMP_ROOT/missing-selection.env" <<'EOF'
path=missing-target.txt
selection_mode=oldest-mtime
selection_basis=missing fixture
EOF
  lattice record-preselect \
    --cycle-id cycle-missing \
    --run-hash hash-missing \
    --selection-file "$TEST_TMP_ROOT/missing-selection.env" >"$TEST_TMP_ROOT/missing-selection-preselect.out"

  assert_sql_value "missing" "select current_state from files where canonical_path='missing-target.txt'"
}

test_missing_selected_candidate_target_stays_missing() {
  local repo DB selection_run_id

  repo="$TEST_TMP_ROOT/lattice-missing-selection-candidates"
  REPO="$repo"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  make_repo "$repo"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/missing-selection-candidates-init.out"

  cat >"$TEST_TMP_ROOT/missing-selection-candidates.env" <<'EOF'
path=missing-target.txt
selection_mode=oldest-mtime
selection_basis=missing candidate fixture
EOF
  cat >"$TEST_TMP_ROOT/missing-selection-candidates.jsonl" <<'EOF'
{"path":"missing-target.txt","candidate_state":"eligible","rank":1,"git_status":"M","content_state":"untracked","head_blob":"none","worktree_hash":"none","mtime_epoch":111}
EOF
  lattice record-preselect \
    --cycle-id cycle-missing-candidate \
    --run-hash hash-missing-candidate \
    --selection-file "$TEST_TMP_ROOT/missing-selection-candidates.env" \
    --candidate-file "$TEST_TMP_ROOT/missing-selection-candidates.jsonl" \
    >"$TEST_TMP_ROOT/missing-selection-candidates-preselect.out"

  selection_run_id="$(python3 - "$TEST_TMP_ROOT/missing-selection-candidates-preselect.out" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding='utf-8'))
print(data['selection_run_id'])
PY
)"

  assert_sql_value "missing" "select current_state from files where canonical_path='missing-target.txt'"
  assert_sql_value "missing" "select content_state from selection_candidates where selection_run_id=${selection_run_id} and path='missing-target.txt'"
  assert_sql_value "selected" "select candidate_state from selection_candidates where selection_run_id=${selection_run_id} and path='missing-target.txt'"
}

test_wrapper_required_policy() {
  local repo rc

  repo="$TEST_TMP_ROOT/client"
  make_repo "$repo"
  chmod 700 "$repo"
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
      UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0 \
      UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1 \
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
  grep -Fq "detail_summary=" "$repo/Upkeeper.log" ||
    fail "REQUIRED=0 lattice warning did not use bounded detail_summary"
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
      UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0 \
      UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1 \
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
  grep -Fq "detail_summary=" "$repo/Upkeeper.log" ||
    fail "REQUIRED=1 lattice failure did not use bounded detail_summary"
}

test_lattice_unavailable_summary_redacts_raw_detail() {
  local detail summary

  detail='{"status":"integrity_failure","checks":{"cycle_finish_report_only_outcome":{"ok":false,"selected_path":"/tmp/private/path.py"}}}'
  # shellcheck source=/dev/null
  source "$ROOT_DIR/lib/upkeeper/lattice.bash"
  summary="$(lattice_unavailable_detail_summary "$detail")"
  [[ "$summary" == *"detail_sha256="* ]] || fail "lattice unavailable summary missing detail hash"
  [[ "$summary" == *"detail_bytes="* ]] || fail "lattice unavailable summary missing byte count"
  [[ "$summary" == *"json_status=integrity_failure"* ]] || fail "lattice unavailable summary missing JSON status"
  [[ "$summary" == *"first_failed_check=cycle_finish_report_only_outcome"* ]] ||
    fail "lattice unavailable summary missing failed check name"
  [[ "$summary" != *"/tmp/private"* ]] || fail "lattice unavailable summary leaked raw path"
  [[ "$summary" != *"selected_path"* ]] || fail "lattice unavailable summary leaked raw detail key"
}

test_unsafe_lattice_db_path_is_rejected_by_default() {
  local repo outside_db rc

  repo="$TEST_TMP_ROOT/lattice-unsafe-db"
  outside_db="$TEST_TMP_ROOT/lattice-outside.sqlite3"
  make_repo "$repo"

  set +e
  "$LATTICE_TOOL" --root "$repo" --db "$outside_db" init >"$TEST_TMP_ROOT/lattice-outside-db.out" 2>"$TEST_TMP_ROOT/lattice-outside-db.err"
  rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || fail "lattice init with outside DB path exited $rc, expected 4"
  [[ -f "$outside_db" ]] && fail "lattice init created an unsafe outside root db"
  grep -Fq '"status": "unsafe_db_path"' "$TEST_TMP_ROOT/lattice-outside-db.out" "$TEST_TMP_ROOT/lattice-outside-db.err" ||
    fail "lattice did not emit unsafe_db_path status"
}

test_default_runtime_symlink_db_path_is_rejected() {
  local repo rc

  repo="$TEST_TMP_ROOT/lattice-unsafe-runtime-symlink"
  make_repo "$repo"
  mkdir -p "$TEST_TMP_ROOT/external-lattice-root"
  mkdir -p "$repo/runtime"
  rm -rf "$repo/runtime/upkeeper-lattice"
  ln -s "$TEST_TMP_ROOT/external-lattice-root" "$repo/runtime/upkeeper-lattice"

  set +e
  "$LATTICE_TOOL" --root "$repo" init >"$TEST_TMP_ROOT/lattice-runtime-symlink.out" 2>"$TEST_TMP_ROOT/lattice-runtime-symlink.err"
  rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || fail "lattice init with symlinked runtime DB path exited $rc, expected 4"
  [[ ! -f "$TEST_TMP_ROOT/external-lattice-root/lattice.sqlite3" ]] || fail "lattice created DB through symlinked runtime path"
  grep -Fq '"status": "unsafe_db_path"' "$TEST_TMP_ROOT/lattice-runtime-symlink.out" "$TEST_TMP_ROOT/lattice-runtime-symlink.err" ||
    fail "lattice did not emit unsafe_db_path status for symlinked runtime db path"

  set +e
  "$LATTICE_TOOL" --root "$repo" record-pass-result --pass P1 --file README.md --outcome clean \
    >"$TEST_TMP_ROOT/lattice-runtime-symlink-pass.out" 2>"$TEST_TMP_ROOT/lattice-runtime-symlink-pass.err"
  rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || fail "ordinary command with symlinked default DB path exited $rc, expected 4"
  [[ ! -f "$TEST_TMP_ROOT/external-lattice-root/lattice.sqlite3" ]] || fail "ordinary command created db through symlinked runtime path"
}

test_ordinary_command_does_not_create_missing_db() {
  local repo rc

  repo="$TEST_TMP_ROOT/lattice-missing-ordinary-db"
  make_repo "$repo"

  set +e
  "$LATTICE_TOOL" --root "$repo" --db "$repo/source-tree.sqlite3" record-pass-result --pass P1 --file README.md --outcome clean \
    >"$TEST_TMP_ROOT/missing-ordinary-db.out" 2>"$TEST_TMP_ROOT/missing-ordinary-db.err"
  rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || fail "ordinary command with non-approved db path exited $rc, expected 4"
  [[ ! -f "$repo/source-tree.sqlite3" ]] || fail "ordinary command created missing unsafe db file"
}

test_lattice_jsonl_input_guardrails() {
  local repo rc

  repo="$TEST_TMP_ROOT/lattice-import-jsonl-guard"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  mkdir -p "$repo"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/import-guard-init.out"

  set +e
  "$LATTICE_TOOL" --root "$repo" --db "$DB" import-jsonl "$TEST_TMP_ROOT/missing-input.jsonl" \
    >"$TEST_TMP_ROOT/import-missing-input.out" 2>"$TEST_TMP_ROOT/import-missing-input.err"
  rc=$?
  set -e
  [[ "$rc" -eq 2 ]] || fail "import-jsonl with missing input exited $rc, expected 2"
  python3 - "$TEST_TMP_ROOT/import-missing-input.out" <<'PY' || fail "missing input import-jsonl did not emit missing_input"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data.get("status") == "unavailable", data
assert data.get("reason") == "missing_input", data
PY

  mkdir -p "$TEST_TMP_ROOT/import-jsonl-file"
  set +e
  "$LATTICE_TOOL" --root "$repo" --db "$DB" import-jsonl "$TEST_TMP_ROOT/import-jsonl-file" \
    >"$TEST_TMP_ROOT/import-unreadable-input.out" 2>"$TEST_TMP_ROOT/import-unreadable-input.err"
  rc=$?
  set -e
  [[ "$rc" -eq 2 ]] || fail "import-jsonl with unreadable input exited $rc, expected 2"
  python3 - "$TEST_TMP_ROOT/import-unreadable-input.out" <<'PY' || fail "unreadable input did not emit input_unreadable"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data.get("status") == "unavailable", data
assert data.get("reason") == "input_unreadable", data
PY
}

test_export_backup_output_collision() {
  local repo rc

  repo="$TEST_TMP_ROOT/lattice-output-collision"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  mkdir -p "$repo"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/output-collision-init.out"

  set +e
  "$LATTICE_TOOL" --root "$repo" --db "$DB" export-jsonl --output "$DB" \
    >"$TEST_TMP_ROOT/export-collision-live.out" 2>"$TEST_TMP_ROOT/export-collision-live.err"
  rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || fail "export to live DB should fail"
  grep -Fq "unsafe output path collides" "$TEST_TMP_ROOT/export-collision-live.err" ||
    fail "export to live DB did not report collision"

  set +e
  "$LATTICE_TOOL" --root "$repo" --db "$DB" backup --output "$DB" \
    >"$TEST_TMP_ROOT/backup-collision-live.out" 2>"$TEST_TMP_ROOT/backup-collision-live.err"
  rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || fail "backup to live DB should fail"
  grep -Fq "unsafe output path collides" "$TEST_TMP_ROOT/backup-collision-live.err" ||
    fail "backup to live DB did not report collision"
}

test_prune_respects_transient_artifact_older_than_days() {
  local repo old_epoch now rc

  repo="$TEST_TMP_ROOT/lattice-prune-artifact-cutoff"
  REPO="$repo"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  make_repo "$repo"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/prune-cutoff-init.out"

  now=$(date +%s)
  old_epoch=$((now - 172800))
  fresh_epoch=$((now - 3600))

  run_sql "
    insert into artifact_refs(repo_id, cycle_pk, source_id, artifact_kind, path, exists_at_record_time, observed_epoch, retained)
      select repo_id, null, null, 'transcript', 'runtime/transcripts/artifact-old.log', 1, $old_epoch, 1 from repositories;
    insert into artifact_refs(repo_id, cycle_pk, source_id, artifact_kind, path, exists_at_record_time, observed_epoch, retained)
      select repo_id, null, null, 'transcript', 'runtime/transcripts/artifact-fresh.log', 1, $fresh_epoch, 1 from repositories;
  "

  lattice prune --transient-artifacts --older-than-days 1 >"$TEST_TMP_ROOT/prune-artifacts-cutoff.out" 2>"$TEST_TMP_ROOT/prune-artifacts-cutoff.err"

  python3 - "$DB" <<'PY' || fail "transient artifact prune cutoff did not keep fresh artifact only"
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
rows = conn.execute(
    "select path, retained from artifact_refs where path like 'runtime/transcripts/artifact-%.log' order by path"
).fetchall()
expected = {
    "runtime/transcripts/artifact-fresh.log": 1,
    "runtime/transcripts/artifact-old.log": 0,
}
if len(rows) != len(expected):
    raise AssertionError(f"expected {len(expected)} fixture artifacts, got {len(rows)}: {rows}")
for path, retained in rows:
    if expected.get(path) != retained:
        raise AssertionError(f"unexpected retained value for {path}: got {retained}, expected {expected[path]}")
PY
}

test_prune_scopes_actions_to_current_repo() {
  local repo_a repo_b old_epoch now

  repo_a="$TEST_TMP_ROOT/lattice-prune-shared-db-a"
  repo_b="$TEST_TMP_ROOT/lattice-prune-shared-db-b"
  DB="$repo_a/runtime/upkeeper-lattice/lattice.sqlite3"
  make_repo "$repo_a"
  make_repo "$repo_b"

  "$LATTICE_TOOL" --root "$repo_a" --db "$DB" init >"$TEST_TMP_ROOT/prune-shared-init-a.out"
  "$LATTICE_TOOL" --root "$repo_b" --db "$DB" --allow-unsafe-db init >"$TEST_TMP_ROOT/prune-shared-init-b.out"

  now=$(date +%s)
  old_epoch=$((now - 172800))
  fresh_epoch=$((now - 3600))

  python3 - "$DB" "$old_epoch" "$fresh_epoch" <<'PY' || fail "failed to seed shared-db prune fixtures"
import sqlite3
import sys

db, old_epoch, fresh_epoch = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])

with sqlite3.connect(db) as conn:
    conn.execute("PRAGMA foreign_keys=ON")
    repo_ids = [row[0] for row in conn.execute("select repo_id from repositories order by repo_id asc").fetchall()]
    if len(repo_ids) != 2:
        raise AssertionError(f"expected both repos in shared db, got {repo_ids}")

    repo_a_id, repo_b_id = repo_ids

    conn.executemany(
        """
        insert into source_records (repo_id, source_kind, source_epoch, imported_epoch, raw_ref, raw_text)
        values (?, 'operator', ?, ?, 'prune-regression', ?)
        """,
        [
            (repo_a_id, old_epoch, old_epoch, "repo-a-old"),
            (repo_b_id, old_epoch, old_epoch, "repo-b-old"),
        ],
    )

    conn.execute(
        """
        insert into selection_runs (
          repo_id, selector_version, source_safe_boundary_version, mode_requested, mode_effective, priority_gate, generated_epoch
        )
        values (?, 'help-selection', 'help-selection', 'oldest-mtime', 'oldest-mtime', 'default', ?)
        """,
        (repo_a_id, old_epoch),
    )
    run_a = int(conn.execute("select last_insert_rowid()").fetchone()[0])
    conn.execute(
        """
        insert into selection_runs (
          repo_id, selector_version, source_safe_boundary_version, mode_requested, mode_effective, priority_gate, generated_epoch
        )
        values (?, 'help-selection', 'help-selection', 'oldest-mtime', 'oldest-mtime', 'default', ?)
        """,
        (repo_b_id, old_epoch),
    )
    run_b = int(conn.execute("select last_insert_rowid()").fetchone()[0])

    conn.executemany(
        """
        insert into selection_candidates (selection_run_id, path, candidate_state, rank, mtime_epoch)
        values (?, ?, ?, 100, ?)
        """,
        [
            (run_a, "shared-old-a", "excluded", old_epoch),
            (run_b, "shared-old-b", "excluded", old_epoch),
        ],
    )

    conn.executemany(
        """
        insert into artifact_refs (
          repo_id, cycle_pk, source_id, artifact_kind, path, exists_at_record_time, observed_epoch, retained
        )
        values (?, null, null, 'transcript', ?, 1, ?, 1)
        """,
        [
            (repo_a_id, "runtime/transcripts/shared-old-a.log", old_epoch),
            (repo_a_id, "runtime/transcripts/shared-fresh-a.log", fresh_epoch),
            (repo_b_id, "runtime/transcripts/shared-old-b.log", old_epoch),
            (repo_b_id, "runtime/transcripts/shared-fresh-b.log", fresh_epoch),
        ],
    )
PY

  REPO="$repo_a"
  lattice prune \
    --older-than-days 1 \
    --raw-only \
    --candidate-details \
    --transient-artifacts >"$TEST_TMP_ROOT/prune-shared.out"

  python3 - "$DB" <<'PY' || fail "prune scoped-by-repo test assertions failed"
import sqlite3
import sys

db = sys.argv[1]

with sqlite3.connect(db) as conn:
    repo_ids = [row[0] for row in conn.execute("select repo_id from repositories order by repo_id asc").fetchall()]
    if len(repo_ids) != 2:
        raise AssertionError(f"expected both repos in shared db, got {repo_ids}")

    repo_a_id, repo_b_id = repo_ids

    repo_a_rows = conn.execute(
        "select raw_text from source_records where repo_id = ? and raw_ref = 'prune-regression'",
        (repo_a_id,),
    ).fetchall()
    repo_b_rows = conn.execute(
        "select raw_text from source_records where repo_id = ? and raw_ref = 'prune-regression'",
        (repo_b_id,),
    ).fetchall()
    if repo_a_rows.count((None,)) != 1:
        raise AssertionError(f"repo_a raw_text rows not nulled as expected: {repo_a_rows}")
    if repo_b_rows != [("repo-b-old",)]:
        raise AssertionError(f"repo_b raw_text rows were modified unexpectedly: {repo_b_rows}")

    repo_a_candidates = conn.execute(
        """
        select count(*) from selection_candidates
        where selection_run_id in (select selection_run_id from selection_runs where repo_id=?)
          and candidate_state != 'selected'
        """,
        (repo_a_id,),
    ).fetchone()[0]
    repo_b_candidates = conn.execute(
        """
        select count(*) from selection_candidates
        where selection_run_id in (select selection_run_id from selection_runs where repo_id=?)
          and candidate_state != 'selected'
        """,
        (repo_b_id,),
    ).fetchone()[0]
    if repo_a_candidates != 0:
        raise AssertionError(f"repo_a candidate details were not fully cleaned: {repo_a_candidates}")
    if repo_b_candidates != 1:
        raise AssertionError(f"repo_b candidate details were modified unexpectedly: {repo_b_candidates}")

    repo_a_old_artifact_retained = conn.execute(
        "select retained from artifact_refs where repo_id = ? and path = 'runtime/transcripts/shared-old-a.log'",
        (repo_a_id,),
    ).fetchone()[0]
    repo_b_old_artifact_retained = conn.execute(
        "select retained from artifact_refs where repo_id = ? and path = 'runtime/transcripts/shared-old-b.log'",
        (repo_b_id,),
    ).fetchone()[0]
    repo_a_fresh_artifact_retained = conn.execute(
        "select retained from artifact_refs where repo_id = ? and path = 'runtime/transcripts/shared-fresh-a.log'",
        (repo_a_id,),
    ).fetchone()[0]
    repo_b_fresh_artifact_retained = conn.execute(
        "select retained from artifact_refs where repo_id = ? and path = 'runtime/transcripts/shared-fresh-b.log'",
        (repo_b_id,),
    ).fetchone()[0]

    if repo_a_old_artifact_retained not in (0, None):
        raise AssertionError(f"repo_a old artifact not unretained as expected: {repo_a_old_artifact_retained}")
    if repo_b_old_artifact_retained != 1:
        raise AssertionError(f"repo_b old artifact was modified unexpectedly: {repo_b_old_artifact_retained}")
    if repo_a_fresh_artifact_retained != 1:
        raise AssertionError(f"repo_a fresh artifact was modified unexpectedly: {repo_a_fresh_artifact_retained}")
    if repo_b_fresh_artifact_retained != 1:
        raise AssertionError(f"repo_b fresh artifact was modified unexpectedly: {repo_b_fresh_artifact_retained}")
PY
}

test_recover_no_backup_first_toggle() {
  local repo rc

  repo="$TEST_TMP_ROOT/lattice-recover-backup-toggle"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  make_repo "$repo"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/recover-backup-toggle-init.out"

  set +e
  "$LATTICE_TOOL" --root "$repo" --db "$DB" recover --backup-first 0 >"$TEST_TMP_ROOT/recover-no-backup.out" 2>"$TEST_TMP_ROOT/recover-no-backup.err"
  rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || fail "recover --no-backup-first exited $rc, expected 0"
  [[ ! -d "$repo/runtime/upkeeper-lattice/backups" ]] || fail "recover --no-backup-first unexpectedly created backup directory"
}

test_recover_backup_first_preserves_pre_recovery_provenance() {
  local repo backup_path

  repo="$TEST_TMP_ROOT/lattice-recover-backup-provenance"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  make_repo "$repo"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/recover-backup-provenance-init.out"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" recover --backup-first 1 >"$TEST_TMP_ROOT/recover-backup-provenance.out"

  backup_path="$(find "$repo/runtime/upkeeper-lattice/backups" -maxdepth 1 -type f -name 'lattice-backup-*.sqlite3' | sort | tail -1)"
  [[ -n "$backup_path" && -f "$backup_path" ]] || fail "recover --backup-first did not create a backup DB"

  python3 - "$backup_path" <<'PY' || fail "recover backup did not preserve pre-recovery provenance boundary"
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
backup_refs = conn.execute(
    "select count(*) from artifact_refs where artifact_kind='backup' and details_json like '%pre_recovery%'"
).fetchone()[0]
if backup_refs != 1:
    raise AssertionError(f"expected one pre-recovery backup artifact ref in backup DB, got {backup_refs}")
recovery_sources = conn.execute(
    "select count(*) from source_records where source_kind='recovery' and raw_ref='recover'"
).fetchone()[0]
if recovery_sources != 1:
    raise AssertionError(f"expected one recover source in backup DB, got {recovery_sources}")
local_git_sources = conn.execute(
    "select count(*) from source_records where source_kind='local_git'"
).fetchone()[0]
if local_git_sources != 0:
    raise AssertionError(f"backup DB should be captured before post-recovery local_git import, got {local_git_sources}")
conn.close()
PY
}

test_review_parser_and_redaction() {
  local repo redaction_export_path review_summary_path

  repo="$TEST_TMP_ROOT/lattice-review-parser-redaction"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  redaction_export_path="$TEST_TMP_ROOT/redaction-export.jsonl"
  make_repo "$repo"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/review-init.out"
  REPO="$repo"
  review_summary_path="$repo/runtime/review-summary.txt"

  cat >"$review_summary_path" <<'EOF'
Some preamble text.
Review target:
selected file: reviewed/with:colon/path.sh
REVIEWED_AND_REPORTED
EOF

  lattice record-cycle-start \
    --cycle-id cycle-review \
    --run-hash run-review \
    --execution-origin primary \
    --model gpt-5.5 \
    --effort xhigh \
    --mode '--sandbox workspace-write' \
    --config-file Upkeeper.conf \
    --dirty-path-count 0 \
    --dry-run 1 >"$TEST_TMP_ROOT/review-start.json"
  lattice record-cycle-finish \
    --cycle-id cycle-review \
    --run-hash run-review \
    --wrapper-exit 0 \
    --finish-reason REVIEW_FINISH \
    --finish-level INFO \
    --codex-exec-started 0 \
    --dry-run 1 \
    --selected-path "README.md" \
    --last-message-file "$review_summary_path" >"$TEST_TMP_ROOT/review-finish.json"

  python3 - "$DB" <<'PY' || fail "review summary parser did not preserve colon-bearing target in rejection evidence"
import json
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
row = conn.execute(
    "select cycle_pk, review_outcome from cycles where cycle_id=? and run_hash=?",
    ("cycle-review", "run-review"),
).fetchone()
if row is None:
    raise AssertionError("review cycle not recorded")
cycle_pk, review_outcome = row
if review_outcome != "STOPPED_ON_BLOCKER":
    raise AssertionError(f"review_outcome={review_outcome}")
row = conn.execute(
    "select path, details_json from file_events where cycle_pk=? and event_kind='target_substitution_rejected'",
    (cycle_pk,),
).fetchone()
if row is None:
    raise AssertionError("target substitution rejection event missing for review parser mismatch")
if row[0] != "README.md":
    raise AssertionError(f"target_substitution_rejected path mismatch: {row[0]}")
details = json.loads(row[1])
if details.get("preselected_path") != "README.md":
    raise AssertionError(f"preselected_path mismatch: {details}")
if details.get("reported_selected_path") != "reviewed/with:colon/path.sh":
    raise AssertionError(f"reported_selected_path mismatch: {details}")

row = conn.execute(
    "select selected_path from cycles where cycle_pk=?",
    (cycle_pk,),
).fetchone()
if row is None or row[0] != "README.md":
    raise AssertionError(f"cycle selected_path did not preserve preselected target: {None if row is None else row[0]}")

row = conn.execute(
    "select f.canonical_path from cycles c join files f on f.file_id=c.selected_file_id where c.cycle_pk=?",
    (cycle_pk,),
).fetchone()
if row is None or row[0] != "README.md":
    raise AssertionError(f"cycle selected_file_id mismatch: {None if row is None else row[0]}")
PY

  python3 - "$DB" <<'PY'
import json
import sqlite3
import sys
import time

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
repo_id = conn.execute("select repo_id from repositories order by repo_id asc limit 1").fetchone()[0]
conn.execute("update repositories set remote_url=? where repo_id=?", ("https://example.internal/git/example.git", repo_id))
now = int(time.time())
parsed = {
    "path": "record/source/path/with:colon.txt",
    "details": {
        "remote_url": "https://example.internal/secret-remote",
        "output_path": "record/source/output:artifact.txt",
    },
}
cur = conn.execute(
    """
    insert into source_records(
      repo_id, source_kind, source_path, source_uri, source_epoch, imported_epoch, raw_ref, raw_text, parsed_json, parse_status, fact_confidence
    ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """,
    (
        repo_id,
        "operator",
        "/tmp/lattice-review-source.txt",
        "file:///tmp/lattice-review-source.txt",
        now,
        now,
        "redact-paths",
        "raw/source/path/with:colon.txt",
        json.dumps(parsed),
        "parsed",
        "observed",
    ),
)
source_id = int(cur.lastrowid)
conn.execute(
    """
    insert into file_events(
      repo_id, cycle_pk, source_id, event_kind, event_epoch, path, confidence, details_json
    ) values (?, ?, ?, ?, ?, ?, ?, ?)
    """,
    (
        repo_id,
        None,
        source_id,
        "redacted_probe",
        now,
        "event/original/path/with:colon.txt",
        "observed",
        json.dumps({
            "path": "details/original/path/with:colon.txt",
            "remote_url": "https://example.internal/secret-event",
            "output_path": "details/original/output:artifact.txt",
        }),
    ),
)
conn.commit()
conn.close()
PY

  lattice export-jsonl --redact-paths --redact-raw --output "$redaction_export_path" >"$TEST_TMP_ROOT/redaction-export.out"
  python3 - "$redaction_export_path" <<'PY' || fail "redaction export did not mask path/token fields"
import json

export_path = __import__("sys").argv[1]
forbidden = [
    "https://example.internal/git/example.git",
    "record/source/path/with:colon.txt",
    "record/source/output:artifact.txt",
    "record/source/secret-remote",
    "raw/source/path/with:colon.txt",
    "event/original/path/with:colon.txt",
    "details/original/path/with:colon.txt",
    "details/original/output:artifact.txt",
    "https://example.internal/secret-event",
]
raw = open(export_path, encoding="utf-8").read()
for needle in forbidden:
    if needle in raw:
        raise AssertionError(f"forbidden token leaked to redacted export: {needle}")

found_repo_remote = False
found_review_cycle = False
found_source_raw = False
found_event_paths = False
for line in raw.splitlines():
    row = json.loads(line)
    payload = row.get("payload", {})
    if row.get("row_type") == "repositories":
        remote = payload.get("remote_url") or ""
        if remote == "https://example.internal/git/example.git":
            raise AssertionError("repositories.remote_url was not redacted")
        if remote.startswith("path-sha256:"):
            found_repo_remote = True
    if row.get("row_type") == "cycles" and payload.get("cycle_id") == "cycle-review":
        selected_path = payload.get("selected_path")
        if selected_path and not selected_path.startswith("path-sha256:"):
            raise AssertionError(f"cycles.selected_path was not redacted: {selected_path}")
        found_review_cycle = True
    if row.get("row_type") == "source_records" and payload.get("raw_ref") == "redact-paths":
        if payload.get("raw_text") != "<redacted>":
            raise AssertionError(f"source_records.raw_text was not redacted: {payload.get('raw_text')}")
        parsed = json.loads(payload.get("parsed_json") or "{}")
        if not parsed.get("path", "").startswith("path-sha256:"):
            raise AssertionError("parsed_json.path was not redacted")
        details = parsed.get("details") or {}
        if not details.get("output_path", "").startswith("path-sha256:"):
            raise AssertionError("parsed_json.details.output_path was not redacted")
        if not details.get("remote_url", "").startswith("path-sha256:"):
            raise AssertionError("parsed_json.details.remote_url was not redacted")
        found_source_raw = True
    if row.get("row_type") == "file_events" and payload.get("event_kind") == "redacted_probe":
        if not payload.get("path", "").startswith("path-sha256:"):
            raise AssertionError("file_events.path was not redacted")
        details = json.loads(payload.get("details_json") or "{}")
        if not details.get("path", "").startswith("path-sha256:"):
            raise AssertionError("file_events.details_json.path was not redacted")
        if not details.get("remote_url", "").startswith("path-sha256:"):
            raise AssertionError("file_events.details_json.remote_url was not redacted")
        if not details.get("output_path", "").startswith("path-sha256:"):
            raise AssertionError("file_events.details_json.output_path was not redacted")
        found_event_paths = True

if not found_repo_remote:
    raise AssertionError("expected repositories row with redacted remote_url")
if not found_review_cycle:
    raise AssertionError("expected cycle-review row with redacted selected_path")
if not found_source_raw:
    raise AssertionError("expected source_records row with redacted raw/parsed fields")
if not found_event_paths:
    raise AssertionError("expected file_events row with redacted nested path fields")
PY
}

test_clean_touch_uses_mtime_ns() {
  local repo rc

  repo="$TEST_TMP_ROOT/lattice-clean-touch-ns"
  REPO="$repo"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  make_repo "$repo"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/clean-touch-init.out"

  lattice record-cycle-start \
    --cycle-id cycle-touch-ns \
    --run-hash run-touch-ns \
    --execution-origin primary \
    --model gpt-5.5 \
    --effort xhigh \
    --mode '--sandbox workspace-write' \
    --config-file Upkeeper.conf \
    --dirty-path-count 0 \
    --dry-run 1 >"$TEST_TMP_ROOT/clean-touch-start.out"
  cat >"$TEST_TMP_ROOT/clean-touch-selection.env" <<'EOF'
path=README.md
selection_mode=oldest-mtime
selection_basis=clean touch fixture
EOF
  lattice record-preselect \
    --cycle-id cycle-touch-ns \
    --run-hash run-touch-ns \
    --selection-file "$TEST_TMP_ROOT/clean-touch-selection.env" >"$TEST_TMP_ROOT/clean-touch-preselect.out"

  python3 - "$repo/README.md" <<'PY'
import os
import sys

path = sys.argv[1]
stat = os.stat(path)
os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns + 250_000_000))
PY

  lattice record-cycle-finish \
    --cycle-id cycle-touch-ns \
    --run-hash run-touch-ns \
    --wrapper-exit 0 \
    --finish-reason CLEAN_FINISH \
    --finish-level INFO \
    --codex-exec-started 0 \
    --selected-path "README.md" \
    --review-outcome REVIEWED_CLEAN >"$TEST_TMP_ROOT/clean-touch-finish.out"

  python3 - "$DB" <<'PY' || fail "clean touch was not detected when only mtime_ns changed"
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    "select count(*) from file_events where event_kind='touched_clean' and path='README.md'"
).fetchone()
if not row or int(row[0]) < 1:
    raise AssertionError("expected touched_clean event for same-second mtime_ns change")
PY
}

test_sparse_lifecycle_replay_preserves_metadata() {
  local repo rc

  repo="$TEST_TMP_ROOT/lattice-sparse-lifecycle"
  REPO="$repo"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  make_repo "$repo"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/sparse-lifecycle-init.out"

  lattice record-cycle-start \
    --cycle-id cycle-sparse \
    --run-hash hash-sparse \
    --execution-origin primary \
    --model gpt-5.5 \
    --effort xhigh \
    --mode '--sandbox workspace-write' \
    --config-file Upkeeper.conf \
    --dirty-path-count 0 \
    --dry-run 1 >"$TEST_TMP_ROOT/sparse-lifecycle-start.out"
  lattice record-cycle-finish \
    --cycle-id cycle-sparse \
    --run-hash hash-sparse \
    --wrapper-exit 9 \
    --codex-exit 9 \
    --status-marker PREVIOUS_STATUS \
    --finish-reason PREVIOUS_FINISH \
    --finish-level INFO \
    --codex-exec-started 1 \
    --review-outcome REVIEWED_AND_REPORTED \
    --dry-run 1 \
    --selected-path README.md >"$TEST_TMP_ROOT/sparse-lifecycle-finish.out"

  lattice record-cycle-start \
    --cycle-id cycle-sparse \
    --run-hash hash-sparse >"$TEST_TMP_ROOT/sparse-lifecycle-restart.out"
  lattice record-cycle-finish \
    --cycle-id cycle-sparse \
    --run-hash hash-sparse >"$TEST_TMP_ROOT/sparse-lifecycle-replay.out"

  cat >"$TEST_TMP_ROOT/sparse-lifecycle.log" <<'EOF'
2026-05-08T00:00:00-0700 [INFO] cycle=cycle-sparse run_hash=hash-sparse cycle.start
2026-05-08T00:00:01-0700 [INFO] cycle=cycle-sparse run_hash=hash-sparse cycle.summary
2026-05-08T00:00:02-0700 [INFO] cycle=cycle-sparse run_hash=hash-sparse cycle.exit
EOF
  lattice import-upkeeper-log --path "$TEST_TMP_ROOT/sparse-lifecycle.log" >"$TEST_TMP_ROOT/sparse-lifecycle-import.out" || fail "sparse log import failed"

  python3 - "$DB" <<'PY' || fail "sparse cycle replay cleared terminal metadata"
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
row = conn.execute(
    "select status_marker, review_outcome, codex_exit, wrapper_exit, finish_reason, finish_level, codex_exec_started, dry_run, selected_path "
    "from cycles where cycle_id='cycle-sparse' and run_hash='hash-sparse'"
).fetchone()
if row is None:
    raise AssertionError("cycle-sparse row missing after replay")
expected = (
    "PREVIOUS_STATUS",
    "REVIEWED_AND_REPORTED",
    9,
    9,
    "PREVIOUS_FINISH",
    "INFO",
    1,
    1,
    "README.md",
)
if tuple(row) != expected:
    raise AssertionError(f"terminal metadata changed by sparse replay: {row}")
PY
}

test_import_upkeeper_log_omits_sensitive_parsed_fields() {
  local repo

  repo="$TEST_TMP_ROOT/lattice-log-import-redaction"
  REPO="$repo"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  make_repo "$repo"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/log-import-redaction-init.out"

  cat >"$TEST_TMP_ROOT/log-import-redaction.log" <<'EOF'
2026-05-12T00:00:00-0700 [INFO] cycle=cycle-private run_hash=hash-private cycle.start execution_origin=primary model=gpt-5.5 effort=xhigh mode="--sandbox workspace-write" config_file=configurations/default.conf dirty_paths=2 dry_run=1 target=lib/upkeeper/process_args.bash review_globs="lib/upkeeper/*.bash" review_labels=security
2026-05-12T00:00:01-0700 [INFO] cycle=cycle-private run_hash=hash-private review.preselect path=lib/upkeeper/process_args.bash basis=automatic_rotation source=manifest
2026-05-12T00:00:02-0700 [INFO] cycle=cycle-private run_hash=hash-private cycle.summary status_marker=WORK_DONE codex_exit=0 detail="selected file stored elsewhere"
2026-05-12T00:00:03-0700 [INFO] cycle=cycle-private run_hash=hash-private cycle.exit exit_code=0 reason="contains target path details" codex_exec_started=1
EOF

  lattice import-upkeeper-log --path "$TEST_TMP_ROOT/log-import-redaction.log" >"$TEST_TMP_ROOT/log-import-redaction-import.out" ||
    fail "sensitive log import failed"

  python3 - "$DB" <<'PY' || fail "sensitive log import retained restricted fields"
import json
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.row_factory = sqlite3.Row

rows = conn.execute(
    "select raw_ref, raw_text, parsed_json from source_records where source_kind='upkeeper_log' order by source_id"
).fetchall()
expected = {
    "cycle.start": {"timestamp", "level", "event", "cycle", "run_hash", "execution_origin", "dirty_paths", "dry_run"},
    "review.preselect": {"timestamp", "level", "event", "cycle", "run_hash"},
    "cycle.summary": {"timestamp", "level", "event", "cycle", "run_hash", "status_marker", "codex_exit"},
    "cycle.exit": {"timestamp", "level", "event", "cycle", "run_hash", "exit_code", "codex_exec_started"},
}
for row in rows:
    raw_ref = row["raw_ref"]
    parsed = json.loads(row["parsed_json"] or "{}")
    if row["raw_text"] is not None:
        raise AssertionError(f"raw_text should be empty when --raw is not used for {raw_ref}")
    if raw_ref not in expected:
        continue
    if set(parsed) != expected[raw_ref]:
        raise AssertionError(f"unexpected parsed_json keys for {raw_ref}: {sorted(parsed)}")
    for forbidden_key in (
        "model",
        "effort",
        "mode",
        "config_file",
        "path",
        "target",
        "source",
        "reason",
        "detail",
        "review_globs",
        "review_labels",
    ):
        if forbidden_key in parsed:
            raise AssertionError(f"forbidden parsed_json key survived for {raw_ref}: {forbidden_key}")

cycle = conn.execute(
    "select execution_origin, model, effort, mode, config_file, selected_path, selection_basis, "
    "status_marker, codex_exit, wrapper_exit, finish_reason, codex_exec_started, dry_run, worktree_dirty "
    "from cycles where cycle_id='cycle-private' and run_hash='hash-private'"
).fetchone()
if cycle is None:
    raise AssertionError("cycle-private row missing after log import")
expected_cycle = (
    "primary",
    None,
    None,
    None,
    None,
    None,
    "automatic_rotation",
    "WORK_DONE",
    0,
    0,
    None,
    1,
    1,
    1,
)
if tuple(cycle) != expected_cycle:
    raise AssertionError(f"normalized cycle fields were not safely filtered: {tuple(cycle)}")
PY
}

test_source_record_identity_reuses_imported_lines_only() {
  local repo log_path

  repo="$TEST_TMP_ROOT/lattice-source-record-identity"
  REPO="$repo"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  make_repo "$repo"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/source-record-identity-init.out"

  log_path="$TEST_TMP_ROOT/source-record-identity.log"
  cat >"$log_path" <<'EOF'
2026-05-12T00:00:00-0700 [INFO] cycle=cycle-source run_hash=hash-source cycle.start dry_run=1
2026-05-12T00:00:01-0700 [INFO] cycle=cycle-source run_hash=hash-source review.preselect path=README.md
2026-05-12T00:00:02-0700 [INFO] cycle=cycle-source run_hash=hash-source cycle.exit exit_code=0
EOF

  lattice import-upkeeper-log --path "$log_path" >"$TEST_TMP_ROOT/source-record-identity-import-1.out"
  lattice import-upkeeper-log --path "$log_path" >"$TEST_TMP_ROOT/source-record-identity-import-2.out"
  lattice record-cycle-start --cycle-id cycle-source-a --run-hash hash-source-a >"$TEST_TMP_ROOT/source-record-identity-start-a.out"
  lattice record-cycle-start --cycle-id cycle-source-b --run-hash hash-source-b >"$TEST_TMP_ROOT/source-record-identity-start-b.out"

  python3 - "$DB" <<'PY' || fail "source_records identity replay boundary regressed"
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
rows = conn.execute(
    "select source_line, raw_sha256 from source_records where source_kind='upkeeper_log' order by source_line"
).fetchall()
if len(rows) != 3:
    raise AssertionError(f"expected repeated imported log lines to reuse three source_records, got {len(rows)}: {rows}")
for expected_line, (source_line, raw_sha256) in enumerate(rows, start=1):
    if int(source_line or 0) != expected_line:
        raise AssertionError(f"source_line mismatch: expected {expected_line}, got {source_line}")
    if not raw_sha256:
        raise AssertionError(f"raw_sha256 missing for imported log line {expected_line}")

wrapper_count = conn.execute(
    "select count(*) from source_records where source_kind='wrapper_observed' and raw_ref='cycle_start'"
).fetchone()[0]
if int(wrapper_count) != 2:
    raise AssertionError(f"wrapper observations without an anchored source identity collapsed: {wrapper_count}")
PY
}

test_planned_pass_semantics_do_not_mark_all_runs_as_planned() {
  local repo

  repo="$TEST_TMP_ROOT/lattice-planned-semantics"
  REPO="$repo"
  DB="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  make_repo "$repo"
  "$LATTICE_TOOL" --root "$repo" --db "$DB" init >"$TEST_TMP_ROOT/planned-semantics-init.out"

  lattice record-cycle-start \
    --cycle-id cycle-planning \
    --run-hash hash-planning \
    --execution-origin primary \
    --model gpt-5.5 \
    --effort xhigh \
    --mode '--sandbox workspace-write' \
    --config-file Upkeeper.conf \
    --dirty-path-count 0 \
    --dry-run 1 >"$TEST_TMP_ROOT/planned-semantics-start.out"
  lattice record-pass-result \
    --cycle-id cycle-planning \
    --run-hash hash-planning \
    --pass P23 \
    --file README.md \
    --applicable 1 \
    --outcome clean \
    --changed 0 \
    --regression 0 >"$TEST_TMP_ROOT/planned-actual-pass.out"
  lattice record-pass-result \
    --cycle-id cycle-planning \
    --run-hash hash-planning \
    --path README.md \
    --planned-passes P24 >"$TEST_TMP_ROOT/planned-missing-marker.out"

  python3 - "$DB" <<'PY' || fail "planned pass semantics did not preserve completed-attempt intent"
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    "select planned, attempted, outcome, changed from file_pass_runs where pass_code='P24' and outcome='planned' and file_id=(select file_id from files where canonical_path='README.md' limit 1)"
).fetchone()
if row is None:
    raise AssertionError("missing planned P24 run")
planned, attempted, _, _ = row
if int(planned or 0) != 1:
    raise AssertionError(f"planned marker run missing planned=1: {(planned, attempted)}")
if int(attempted or 0) != 0:
    raise AssertionError(f"planned marker run unexpectedly attempted: {(planned, attempted)}")

row = conn.execute(
    "select planned, attempted from file_pass_runs where pass_code='P23' and outcome='clean' and file_id=(select file_id from files where canonical_path='README.md' limit 1)"
).fetchone()
if row is None:
    raise AssertionError("missing explicit P23 clean run")
planned, attempted = row
if int(planned or 0) != 0:
    raise AssertionError(f"explicit clean run incorrectly marked planned: {(planned, attempted)}")
if int(attempted or 0) != 1:
    raise AssertionError(f"explicit clean run attempted flag incorrect: {(planned, attempted)}")

row = conn.execute(
    "select unknown_count from file_pass_rollups where file_id=(select file_id from files where canonical_path='README.md' limit 1)"
).fetchone()
if row is None:
    raise AssertionError("missing file_pass_rollups row for README.md")
if int(row[0]) != 0:
    raise AssertionError(f"planned marker inflated unknown_count: {row[0]}")
PY
}

test_lattice_cli_contracts
test_git_status_xy_preserves_index_worktree_columns
test_no_git_import_and_recovery
test_import_git_prefers_checked_out_branch_state
test_import_git_privacy_defaults_and_opt_in
test_backup_is_read_only
test_missing_selection_path_stays_missing
test_missing_selected_candidate_target_stays_missing
test_wrapper_required_policy
test_lattice_unavailable_summary_redacts_raw_detail
test_unsafe_lattice_db_path_is_rejected_by_default
test_default_runtime_symlink_db_path_is_rejected
test_ordinary_command_does_not_create_missing_db
test_lattice_jsonl_input_guardrails
test_export_backup_output_collision
test_prune_respects_transient_artifact_older_than_days
test_prune_scopes_actions_to_current_repo
test_recover_no_backup_first_toggle
test_recover_backup_first_preserves_pre_recovery_provenance
test_review_parser_and_redaction
test_clean_touch_uses_mtime_ns
test_sparse_lifecycle_replay_preserves_metadata
test_import_upkeeper_log_omits_sensitive_parsed_fields
test_source_record_identity_reuses_imported_lines_only
test_planned_pass_semantics_do_not_mark_all_runs_as_planned
printf 'ok - lattice\n'
