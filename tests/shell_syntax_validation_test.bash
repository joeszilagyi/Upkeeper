#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
umask 077
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-shell-syntax.XXXXXX")"
finish() {
  local rc=$?
  if [[ "$rc" == 0 ]]; then
    rm -r -- "$TEST_ROOT"
  else
    printf 'shell_syntax_validation_test: retained failure evidence: %s\n' "$TEST_ROOT" >&2
  fi
}
trap finish EXIT
fail() { printf 'shell_syntax_validation_test: ERROR: %s\n' "$*" >&2; exit 1; }

# Copy source only, never .git/config, ignored runtime evidence or credentials.
repo="$TEST_ROOT/repo"
mkdir -p "$repo"
git -C "$ROOT_DIR" ls-files -z --cached --others --exclude-standard >"$TEST_ROOT/paths"
while IFS= read -r -d '' path; do
  [[ -e "$ROOT_DIR/$path" || -L "$ROOT_DIR/$path" ]] || continue
  mkdir -p -- "$repo/$(dirname -- "$path")"
  cp -P -- "$ROOT_DIR/$path" "$repo/$path"
done <"$TEST_ROOT/paths"

mkdir -p "$TEST_ROOT"/{home,state,cache,config,codex,gh,obligations,ledger,backups,logs,locks,tmp,bin}
for command_name in codex gh; do
  printf '#!/bin/bash\nprintf "unexpected transport\\n" >>"$FIXTURE_TRANSPORT_LOG"\nexit 97\n' >"$TEST_ROOT/bin/$command_name"
  chmod 700 "$TEST_ROOT/bin/$command_name"
done

run() {
  env -i PATH="$TEST_ROOT/bin:/usr/bin:/bin" HOME="$TEST_ROOT/home" \
    XDG_STATE_HOME="$TEST_ROOT/state" XDG_CACHE_HOME="$TEST_ROOT/cache" XDG_CONFIG_HOME="$TEST_ROOT/config" \
    CODEX_HOME="$TEST_ROOT/codex" GH_CONFIG_DIR="$TEST_ROOT/gh" TMPDIR="$TEST_ROOT/tmp" \
    UPKEEPER_OBLIGATION_DIR="$TEST_ROOT/obligations" UPKEEPER_AUTOMATION_LEDGER_DIR="$TEST_ROOT/ledger" \
    UPKEEPER_PRECONTACT_BACKUP_ROOT="$TEST_ROOT/backups" CODEX_LOG_FILE="$TEST_ROOT/logs/upkeeper.log" \
    UPKEEPER_ACTIVE_LOCK_DIR="$TEST_ROOT/locks/active" FIXTURE_TRANSPORT_LOG="$TEST_ROOT/transport.log" \
    UPKEEPER_VALIDATION_TIMING_FILE="$TEST_ROOT/timing.jsonl" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null LANG=C.UTF-8 \
    "$@"
}
cd "$repo"
run git init -q
run git add .
run git -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture

expect_bad() {
  local expected_path="$1"; shift
  local rc=0
  run "$@" >"$TEST_ROOT/output" 2>&1 || rc=$?
  [[ "$rc" == 2 ]] || fail "expected parser exit 2, got $rc: $*"
  grep -Fq -- "$expected_path" "$TEST_ROOT/output" || fail "diagnostic omitted $expected_path: $*"
}

# Each mutation is independent. Use real runners, not a copied check_syntax or
# a mock of the syntax gate. The baseline phase exits 0 at the first case.
for path in testruns/manifest_refresh_dry_run.sh lib/upkeeper/codex_io.bash \
  tests/validation_attestation_test.bash configurations/default.conf; do
  cp -- "$path" "$TEST_ROOT/original"
  printf '\nif then\n' >>"$path"
  expect_bad "$path" bash -n "$path"
  expect_bad "$path" bash tools/run_validation_phases.sh --phases shell_syntax --serial
  expect_bad "$path" bash tools/run_validation_phases.sh --phases shell_syntax --jobs 2
  for mode in --smoke --quick --full; do
    expect_bad "$path" bash tools/validate_upkeeper.sh "$mode" --profile
    grep -Fq 'check=syntax status=fail' "$TEST_ROOT/output" || fail "validator failed later instead of syntax: $path $mode"
  done
  cp -- "$TEST_ROOT/original" "$path"
done

run bash tools/run_validation_phases.sh --phases shell_syntax --serial
run bash tools/run_validation_phases.sh --phases shell_syntax --jobs 2
run bash tools/check_public_docs.sh --quick

# Exercise the real backlog per-bug function without starting its launcher.
# Only unrelated heartbeat/compile/focused gates are test doubles; the actual
# syntax caller and its status propagation remain unchanged.
cp testruns/manifest_refresh_dry_run.sh "$TEST_ROOT/original"
printf '\nif then\n' >>testruns/manifest_refresh_dry_run.sh
expect_bad testruns/manifest_refresh_dry_run.sh bash -c '
  BACKLOG_SOURCE_ONLY=1 source orchestration/backlog.sh
  backlog_validation_attestation_file() { printf "%s/proof.json\n" "$TMPDIR"; }
  backlog_update_active_owner_heartbeat() { :; }
  run_changed_python_compile_validation() { :; }
  run_focused_issue_validation() { :; }
  run_changed_source_contract_validation() { :; }
  run_per_bug_validation 909 testruns/manifest_refresh_dry_run.sh
'
cp "$TEST_ROOT/original" testruns/manifest_refresh_dry_run.sh

# The wrapper's explicit launcher-example caller parses every supplied file.
# Other issue-96 checks are not run: this is caller integration, not a live run.
printf 'if then\n' >launcher_examples/zz-syntax.sh
rc=0
run bash -c '
  source ./Upkeeper
  CODEX_ISSUE_FIX_NUMBER=96
  issue_96_docs_contract_check_command() {
    if [[ "$1" == launcher_examples_bash_syntax ]]; then shift; "$@"; else return 0; fi
  }
  run_issue_96_docs_contract_checks
' >"$TEST_ROOT/output" 2>&1 || rc=$?
[[ "$rc" != 0 ]] || fail 'wrapper launcher-example caller accepted malformed second file'
grep -Fq launcher_examples/zz-syntax.sh "$TEST_ROOT/output" || fail 'wrapper did not reach example parser'
rm launcher_examples/zz-syntax.sh

# A new non-first tool, nested helper, completion and named config are inputs.
for path in tools/zz-syntax.sh tests/lib/zz-syntax.bash completions/zz-syntax.bash configurations/zz-syntax.conf; do
  printf 'if then\n' >"$path"
  expect_bad "$path" bash tools/run_validation_phases.sh --phases shell_syntax --serial
  rm -- "$path"
done

# Unusual names and parse-without-execution, including a leading dash.
for path in 'tests/space name.bash' $'tests/line\nbreak.bash' '-leading.sh'; do
  printf 'touch "$HOME/SHOULD_NOT_EXECUTE"\n' >"$path"
  run bash tools/check_shell_syntax.sh
  [[ ! -e "$TEST_ROOT/home/SHOULD_NOT_EXECUTE" ]] || fail 'syntax check executed source'
  printf 'if then\n' >>"$path"
  rc=0
  run bash tools/run_validation_phases.sh --phases shell_syntax --serial >"$TEST_ROOT/output" 2>&1 || rc=$?
  [[ "$rc" == 2 ]] || fail 'unusual-name syntax error was missed'
  rm -- "$path"
done

mv configurations/default.conf "$TEST_ROOT/default.conf"
expect_bad configurations/default.conf bash tools/run_validation_phases.sh --phases shell_syntax --serial
mv "$TEST_ROOT/default.conf" configurations/default.conf
mv lib/upkeeper/codex_io.bash "$TEST_ROOT/codex_io.bash"
expect_bad lib/upkeeper/codex_io.bash bash tools/check_shell_syntax.sh
mv "$TEST_ROOT/codex_io.bash" lib/upkeeper/codex_io.bash

ln -s ../Upkeeper tests/linked.bash
expect_bad symlink bash tools/check_shell_syntax.sh
rm tests/linked.bash
mkdir "$TEST_ROOT/linked-dir"
printf ':\n' >"$TEST_ROOT/linked-dir/item.bash"
ln -s "$TEST_ROOT/linked-dir" tests/linked-dir
expect_bad symlink bash tools/check_shell_syntax.sh --files tests/linked-dir/item.bash
rm tests/linked-dir
expect_bad 'requires at least one' bash tools/check_shell_syntax.sh --files
expect_bad missing bash tools/check_shell_syntax.sh --files 'missing/*.sh'
mkfifo tests/pipe.bash
expect_bad nonregular bash tools/check_shell_syntax.sh --files tests/pipe.bash
rm tests/pipe.bash

# Enumeration failure must survive the pipeline even if parsing consumed no
# paths; do not turn failed inventory collection into an empty successful set.
printf '#!/bin/bash\nif [[ "$1" == ls-files ]]; then exit 23; fi\nexec /usr/bin/git "$@"\n' >"$TEST_ROOT/bin/git"
chmod 700 "$TEST_ROOT/bin/git"
rc=0
run bash tools/check_shell_syntax.sh >"$TEST_ROOT/output" 2>&1 || rc=$?
[[ "$rc" != 0 ]] || fail 'failed inventory was accepted'
rm "$TEST_ROOT/bin/git"
run git rm -q completions/upkeeper.bash
expect_bad 'empty: completions' bash tools/check_shell_syntax.sh

[[ ! -e "$TEST_ROOT/transport.log" ]] || fail 'unexpected Codex/GitHub transport'
printf 'shell_syntax_validation_test: ok\n'
