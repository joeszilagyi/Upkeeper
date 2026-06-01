#!/usr/bin/env bash
# Sourceable focused validator contract for the Lattice CLI.

lattice_validator_contract_fail() {
  printf 'FAIL: %s\n' "$*" >&2
  return 1
}

lattice_validator_make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git config user.name "Lattice Validator"
    git config user.email "lattice-validator@example.invalid"
    printf 'runtime/\n' >.gitignore
    mkdir -p tests
    printf '# Lattice Validator Fixture\n' >README.md
    printf 'tracked test fixture\n' >tests/example.txt
    printf '#!/usr/bin/env bash\nprintf "space\\n"\n' >"space name.sh"
    git add -A
    git commit -q -m "initial validator fixture"
  )
}

test_lattice_validator_contract() {
  local project_root="${ROOT_DIR:-${PROJECT_ROOT:?PROJECT_ROOT or ROOT_DIR is required}}"
  local lattice_tool="$project_root/tools/upkeeper_lattice.py"
  local test_tmp_root="${TEST_TMP_ROOT:-}"
  local owned_tmp=0 repo db first_path

  if [[ -z "$test_tmp_root" ]]; then
    test_tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-lattice-validator.XXXXXX")"
    owned_tmp=1
  fi

  repo="$test_tmp_root/lattice-validator-repo"
  db="$repo/runtime/upkeeper-lattice/lattice.sqlite3"
  rm -rf -- "$repo"
  lattice_validator_make_repo "$repo"

  "$lattice_tool" --root "$repo" --db "$db" init >"$test_tmp_root/lattice-validator-init.json"
  "$lattice_tool" --root "$repo" --db "$db" doctor >"$test_tmp_root/lattice-validator-doctor.json"
  python3 - "$test_tmp_root/lattice-validator-doctor.json" <<'PY' ||
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "ok", data
assert data["checks"]["foreign_keys"] == 1, data
assert data["checks"]["quick_check"] == "ok", data
PY
    lattice_validator_contract_fail "doctor JSON did not pass"

  "$lattice_tool" --root "$repo" --db "$db" query selection-candidates --mode oldest-mtime --format jsonl \
    >"$test_tmp_root/lattice-validator-candidates.jsonl"
  grep -Fq '"path":"space name.sh"' "$test_tmp_root/lattice-validator-candidates.jsonl" ||
    lattice_validator_contract_fail "selection candidates missed space-bearing fixture"

  "$lattice_tool" --root "$repo" --db "$db" query selection-candidates --mode max-cover --format jsonl \
    >"$test_tmp_root/lattice-validator-max-cover.jsonl"
  first_path="$(python3 - "$test_tmp_root/lattice-validator-max-cover.jsonl" <<'PY'
import json
import sys

for line in open(sys.argv[1], encoding="utf-8"):
    row = json.loads(line)
    if row.get("candidate_state") == "eligible":
        print(row.get("path", ""))
        break
PY
)"
  [[ -n "$first_path" ]] ||
    lattice_validator_contract_fail "max-cover selection did not emit eligible candidates"
  grep -Fq 'coverage_mode' "$test_tmp_root/lattice-validator-max-cover.jsonl" ||
    lattice_validator_contract_fail "max-cover selection did not emit score_json"

  printf 'README.md\ntests/\n' >"$test_tmp_root/lattice-validator.upkeeperignore"
  CODEX_UPKEEPER_IGNORE_FILE="$test_tmp_root/lattice-validator.upkeeperignore" \
    "$lattice_tool" --root "$repo" --db "$db" query selection-candidates --mode max-cover --format jsonl \
    >"$test_tmp_root/lattice-validator-upkeeperignore.jsonl"
  python3 - "$test_tmp_root/lattice-validator-upkeeperignore.jsonl" <<'PY' ||
import json
import sys

states = {}
for line in open(sys.argv[1], encoding="utf-8"):
    row = json.loads(line)
    states[row.get("path", "")] = (row.get("candidate_state"), row.get("exclusion_reason"))
assert states.get("README.md") == ("excluded", "upkeeperignore"), states.get("README.md")
assert states.get("tests/example.txt") == ("excluded", "upkeeperignore"), states.get("tests/example.txt")
PY
    lattice_validator_contract_fail ".upkeeperignore did not exclude validator Lattice candidates"

  if [[ "$owned_tmp" == "1" ]]; then
    rm -rf -- "$test_tmp_root"
  fi
}
