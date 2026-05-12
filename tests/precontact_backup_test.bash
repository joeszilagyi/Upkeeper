#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-precontact-test.XXXXXX")"
trap 'rm -r "$TEST_TMP_ROOT" 2>/dev/null || true' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

shell_quote() {
  printf '%q' "$1"
}

timestamp_now() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

log_line() {
  local level="$1"
  shift
  printf '%s [%s] cycle=%s run_hash=%s %s\n' "$(timestamp_now)" "$level" "$CYCLE_ID" "$CYCLE_RUN_HASH" "$*" >>"$LOG_FILE"
}

terminal_emit_progress() {
  :
}

file_size_bytes() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).stat().st_size)
PY
}

run_mktemp() {
  local label="${1:-tmp}"
  mkdir -p -- "$RUN_TMP_DIR"
  mktemp "$RUN_TMP_DIR/${label}.XXXXXX"
}

finish_cycle() {
  local exit_code="$1"
  local reason="$2"
  local level="$3"
  shift 3
  printf 'exit_code=%s reason=%s level=%s detail=%s\n' "$exit_code" "$reason" "$level" "$*" >"$FINISH_CAPTURE"
  exit "$exit_code"
}

lattice_record_preselect() {
  :
}

# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/upkeeper/precontact_backup.bash"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/upkeeper/help_selection.bash"

make_repo() {
  local repo="$1"
  mkdir -p "$repo/dir" "$repo/runtime"
  (
    cd "$repo"
    git init -q
    git config user.name "Precontact Test"
    git config user.email "precontact@example.invalid"
    printf '#!/usr/bin/env bash\nprintf "hello space"\n' >"dir/space file.sh"
    printf '#!/usr/bin/env bash\nprintf "other"\n' >"dir/other.sh"
    printf 'runtime evidence\n' >"runtime/local.txt"
    git add "dir/space file.sh" "dir/other.sh"
    git commit -q -m "fixtures"
  )
}

reset_env() {
  local repo="$1"
  local name="$2"
  ROOT_DIR="$repo"
  LOG_FILE="$TEST_TMP_ROOT/$name.log"
  RUN_TMP_DIR="$TEST_TMP_ROOT/$name-run tmp"
  CYCLE_ID="cycle-$name"
  CYCLE_RUN_HASH="hash-$name"
  FINISH_CAPTURE="$TEST_TMP_ROOT/$name.finish"
  UPKEEPER_PRECONTACT_BACKUP_ENABLED=1
  UPKEEPER_PRECONTACT_BACKUP_REQUIRED=1
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
  UPKEEPER_PRECONTACT_BACKUP_ROOT="$TEST_TMP_ROOT/$name vault redacted"
  UPKEEPER_PRECONTACT_BACKUP_KEEP_PER_FILE=20
  UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT=""
  UPKEEPER_PRECONTACT_BACKUP_REDACT_PATHS=1
  CODEX_TARGET_FILE=""
  RUN_PRECONTACT_BACKUP_ID=""
  RUN_PRECONTACT_BACKUP_SHA256=""
  RUN_PRECONTACT_BACKUP_MODE=""
  RUN_PRECONTACT_BACKUP_ENCRYPTED=""
  RUN_PRECONTACT_BACKUP_PROTECTED_FROM_BACKEND=""
  mkdir -p "$RUN_TMP_DIR"
  chmod 700 "$RUN_TMP_DIR"
  : >"$LOG_FILE"
}

write_selection_file() {
  local path="$1"
  local output="$2"
  cat >"$output" <<EOF
path=$path
epoch=1
age=0h 0m
git_status=clean
content_state=matches_head
head_blob=head-fixture
worktree_hash=worktree-fixture
eligible_count=1
selection_mode=explicit_target
selection_source=enumerate
manifest_status=not_used
selection_order=oldest
selection_basis=test selected $path
failure_queue_selected=0
EOF
}

json_path_count() {
  find "$1" -type f -name '*.json' | wc -l | tr -d ' '
}

test_plain_required_backup_succeeds() {
  local repo="$TEST_TMP_ROOT/plain repo"
  local selection_file json_file bak_file expected_sha derivation_prefix backup_id expected_path_hash
  make_repo "$repo"
  reset_env "$repo" plain
  selection_file="$TEST_TMP_ROOT/plain-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"

  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"

  [[ -n "$RUN_PRECONTACT_BACKUP_ID" ]] || fail "plain backup did not set backup id"
  json_file="$(find "$UPKEEPER_PRECONTACT_BACKUP_ROOT" -type f -name "${RUN_PRECONTACT_BACKUP_ID}.json" -print)"
  bak_file="$(find "$UPKEEPER_PRECONTACT_BACKUP_ROOT" -type f -name "${RUN_PRECONTACT_BACKUP_ID}.bak" -print)"
  [[ -s "$json_file" ]] || fail "plain sidecar missing"
  [[ -s "$bak_file" ]] || fail "plain backup artifact missing"

  expected_sha="$(precontact_backup_sha256_file "$repo/dir/space file.sh")"
  expected_path_hash="$(precontact_backup_sha256_text "dir/space file.sh")"
  [[ "$(precontact_backup_sha256_file "$bak_file")" == "$expected_sha" ]] || fail "plain backup sha mismatch"
  backup_id="$(basename -- "$json_file" .json)"
  derivation_prefix="$(jq -r '.backup_id_derivation_sha256[0:32]' "$json_file")"
  [[ "$backup_id" == *"$derivation_prefix"* ]] || fail "backup id does not derive from recorded derivation sha"
  grep -Fq "precontact_backup.created target_hash=$expected_path_hash" "$LOG_FILE" || fail "created log did not record target hash"
  ! grep -Fq "target=dir/space file.sh" "$LOG_FILE" || fail "created log leaked selected relative path"
  jq -e \
    --arg rel "dir/space file.sh" \
    --arg sha "$expected_sha" \
    '.schema_version == 1
      and .selected_relative_path == $rel
      and .content_sha256 == $sha
      and (.relative_path_sha256 | length) == 64
      and .cycle_id == "cycle-plain"
      and .cycle_run_hash == "hash-plain"
      and .selected_git_status == "clean"
      and .selected_worktree_hash == "worktree-fixture"
      and .selection_basis == "test selected dir/space file.sh"
      and .backup_mode == "plain"
      and .encrypted == false
      and .protected_from_backend == false' "$json_file" >/dev/null ||
    fail "plain sidecar JSON missing required fields"
}

test_age_mode_uses_public_recipient_only() {
  local repo="$TEST_TMP_ROOT/age repo"
  local fake_bin="$TEST_TMP_ROOT/fake-age-bin"
  local record="$TEST_TMP_ROOT/fake-age-record.txt"
  local selection_file json_file age_file old_path
  make_repo "$repo"
  reset_env "$repo" age
  selection_file="$TEST_TMP_ROOT/age-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/age" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --recipient|-r)
      printf 'recipient=%s\n' "$2" >>"$FAKE_AGE_RECORD"
      shift 2
      ;;
    --identity|-i)
      printf 'identity=%s\n' "$2" >>"$FAKE_AGE_RECORD"
      shift 2
      ;;
    --output|-o)
      out="$2"
      printf 'output_seen=1\n' >>"$FAKE_AGE_RECORD"
      shift 2
      ;;
    --encrypt)
      printf 'encrypt_seen=1\n' >>"$FAKE_AGE_RECORD"
      shift
      ;;
    *)
      printf 'arg=%s\n' "$1" >>"$FAKE_AGE_RECORD"
      shift
      ;;
  esac
done
[[ -n "$out" ]] || exit 9
printf 'FAKEAGE\n' >"$out"
cat >>"$out"
SH
  chmod +x "$fake_bin/age"
  old_path="$PATH"
  PATH="$fake_bin:$PATH"
  export FAKE_AGE_RECORD="$record"
  UPKEEPER_PRECONTACT_BACKUP_MODE=age
  UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT="age1testrecipient"

  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  PATH="$old_path"

  json_file="$(find "$UPKEEPER_PRECONTACT_BACKUP_ROOT" -type f -name "${RUN_PRECONTACT_BACKUP_ID}.json" -print)"
  age_file="$(find "$UPKEEPER_PRECONTACT_BACKUP_ROOT" -type f -name "${RUN_PRECONTACT_BACKUP_ID}.age" -print)"
  [[ -s "$age_file" ]] || fail "age artifact missing"
  grep -Fq "recipient=age1testrecipient" "$record" || fail "fake age did not receive public recipient"
  ! grep -Fq "identity=" "$record" || fail "age backup requested an identity"
  jq -e '.backup_mode == "age" and .encrypted == true and .protected_from_backend == "unknown"' "$json_file" >/dev/null ||
    fail "age sidecar did not record encrypted unknown-protection state"
}

test_age_restore_uses_payload_metadata() {
  local repo="$TEST_TMP_ROOT/age-restore repo"
  local fake_bin="$TEST_TMP_ROOT/fake-age-bin"
  local selection_file json_file age_file restored_sha original_sha sidecar
  local identity_file="$TEST_TMP_ROOT/age-identity.key"
  local old_path expected_path_hash
  local record
  make_repo "$repo"
  reset_env "$repo" age_restore
  selection_file="$TEST_TMP_ROOT/age-restore-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/age" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
mode="encrypt"
out=""
input=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --encrypt)
      mode="encrypt"
      shift
      ;;
    --decrypt)
      mode="decrypt"
      shift
      ;;
    --recipient|-r)
      shift 2
      ;;
    --identity|-i)
      shift 2
      ;;
    --output|-o)
      out="$2"
      shift 2
      ;;
    *)
      input="$1"
      shift
      ;;
  esac
done
if [[ "$mode" == "encrypt" ]]; then
  [[ -n "$out" ]] || exit 9
  cat >"$out"
else
  [[ -n "$out" ]] || exit 9
  [[ -n "$input" ]] || exit 9
  cat "$input" >"$out"
fi
SH
  printf 'restore-id\n' >"$identity_file"
  chmod +x "$fake_bin/age"
  old_path="$PATH"
  PATH="$fake_bin:$PATH"
  record="${record:-$TEST_TMP_ROOT/age-restore-record.txt}"
  export FAKE_AGE_RECORD="$record"
  UPKEEPER_PRECONTACT_BACKUP_MODE=age
  UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT="age1testrecipient"
  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"

  json_file="$(find "$UPKEEPER_PRECONTACT_BACKUP_ROOT" -type f -name "${RUN_PRECONTACT_BACKUP_ID}.json" -print)"
  age_file="$(find "$UPKEEPER_PRECONTACT_BACKUP_ROOT" -type f -name "${RUN_PRECONTACT_BACKUP_ID}.age" -print)"
  sidecar="$json_file"
  [[ -s "$age_file" ]] || fail "age restore test missing age artifact"
  [[ -s "$sidecar" ]] || fail "age restore test missing age sidecar"

  original_sha="$(precontact_backup_sha256_file "$repo/dir/space file.sh")"
  expected_path_hash="$(precontact_backup_sha256_text "dir/space file.sh")"
  printf 'mutated\n' >"$repo/dir/space file.sh"
  precontact_backup_restore_by_id "$RUN_PRECONTACT_BACKUP_ID" "$repo" "$identity_file" ""
  restored_sha="$(precontact_backup_sha256_file "$repo/dir/space file.sh")"
  PATH="$old_path"
  [[ "$restored_sha" == "$original_sha" ]] || fail "age restore did not restore original bytes"
  grep -Fq "precontact_backup.restore target_hash=$expected_path_hash" "$LOG_FILE" || fail "restore log did not record target hash"
  ! grep -Fq "precontact_backup.restore target=dir/space file.sh" "$LOG_FILE" || fail "restore log leaked selected relative path"

  jq -e 'has("selected_relative_path") | not' "$sidecar" >/dev/null ||
    fail "age sidecar leaked detailed restore metadata"
}

test_required_encrypted_mode_fails_closed() {
  local repo="$TEST_TMP_ROOT/fail repo"
  local selection_file rc
  make_repo "$repo"
  reset_env "$repo" fail
  selection_file="$TEST_TMP_ROOT/fail-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  UPKEEPER_PRECONTACT_BACKUP_MODE=age
  UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT=""

  set +e
  ( precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file" )
  rc=$?
  set -e
  [[ "$rc" -eq 7 ]] || fail "required unavailable backup exited $rc, expected 7"
  grep -Fq "PRECONTACT_BACKUP_UNAVAILABLE" "$FINISH_CAPTURE" || fail "finish_cycle reason not captured"
  grep -Fq "codex_exec_started=0" "$FINISH_CAPTURE" || fail "finish detail did not preserve codex_exec_started=0"
  grep -Fq "recipient_missing" "$FINISH_CAPTURE" || fail "finish detail did not include recipient_missing"
}

assert_target_rejected() {
  local rel_path="$1"
  local expected_reason="$2"
  if precontact_backup_validate_target "$rel_path"; then
    fail "unsafe target was accepted: $rel_path"
  fi
  [[ "$PRECONTACT_BACKUP_LAST_REASON" == "$expected_reason" ]] ||
    fail "expected $rel_path to fail as $expected_reason, got $PRECONTACT_BACKUP_LAST_REASON"
}

test_unsafe_target_rejection() {
  local repo="$TEST_TMP_ROOT/unsafe repo"
  make_repo "$repo"
  reset_env "$repo" unsafe
  mkdir -p "$repo/.aws" "$repo/.kube" "$repo/certs" "$repo/keys"
  ln -s "space file.sh" "$repo/dir/link.sh"
  mkdir -p "$repo/dir/subdir"
  printf 'TOKEN=secret\n' >"$repo/.env"
  printf '//registry.npmjs.org/:_authToken=secret\n' >"$repo/.npmrc"
  printf '[pypi]\nusername=user\npassword=secret\n' >"$repo/.pypirc"
  printf 'machine example.invalid login user password secret\n' >"$repo/.netrc"
  printf '[default]\naws_access_key_id=key\naws_secret_access_key=secret\n' >"$repo/.aws/credentials"
  printf 'clusters: []\nusers: []\n' >"$repo/.kube/config"
  printf 'PRIVATE KEY\n' >"$repo/id_rsa"
  printf -- '-----BEGIN PRIVATE KEY-----\n' >"$repo/certs/deploy.pem"
  printf -- '-----BEGIN PRIVATE KEY-----\n' >"$repo/keys/service.key"

  assert_target_rejected "$repo/dir/space file.sh" "absolute_path"
  assert_target_rejected "../outside.sh" "unsafe_relative_path"
  assert_target_rejected "dir/link.sh" "symlink_target_rejected"
  assert_target_rejected "dir/subdir" "directory_target_rejected"
  assert_target_rejected "dir/missing.sh" "missing_file"
  assert_target_rejected "runtime/local.txt" "runtime_path_rejected"
  assert_target_rejected ".git/config" "git_path_rejected"
  assert_target_rejected ".env" "sensitive_target_rejected"
  assert_target_rejected ".npmrc" "sensitive_target_rejected"
  assert_target_rejected ".pypirc" "sensitive_target_rejected"
  assert_target_rejected ".netrc" "sensitive_target_rejected"
  assert_target_rejected ".aws/credentials" "sensitive_target_rejected"
  assert_target_rejected ".kube/config" "sensitive_target_rejected"
  assert_target_rejected "id_rsa" "sensitive_target_rejected"
  assert_target_rejected "certs/deploy.pem" "sensitive_target_rejected"
  assert_target_rejected "keys/service.key" "sensitive_target_rejected"
}

test_precontact_backup_validate_root_secure_private_dir() {
  local repo="$TEST_TMP_ROOT/root-secure repo"
  local symlink_root

  make_repo "$repo"
  reset_env "$repo" root-secure
  UPKEEPER_PRECONTACT_BACKUP_ROOT="$TEST_TMP_ROOT/secure root"
  if ! precontact_backup_validate_root "$repo"; then
    fail "secure backup root failed validation"
  fi
  [[ "$(stat -Lc '%a' -- "$UPKEEPER_PRECONTACT_BACKUP_ROOT" 2>/dev/null || printf '')" == "700" ]] ||
    fail "secure backup root did not enforce 0700 mode"

  symlink_root="$TEST_TMP_ROOT/bad-root"
  ln -s "$TEST_TMP_ROOT/does-not-exist" "$symlink_root"
  UPKEEPER_PRECONTACT_BACKUP_ROOT="$symlink_root"
  if precontact_backup_validate_root "$repo"; then
    fail "symlinked backup root was accepted"
  fi
  [[ "$PRECONTACT_BACKUP_LAST_REASON" == "backup_root_contains_symlink" ]] ||
    fail "symlinked root failed as $PRECONTACT_BACKUP_LAST_REASON"
}

test_prompt_redaction_and_replacement_rule() {
  local repo="$TEST_TMP_ROOT/prompt repo"
  local compiled="$TEST_TMP_ROOT/compiled.prompt"
  local selected="dir/space file.sh"
  make_repo "$repo"
  reset_env "$repo" prompt

  preselect_review_target() {
    cat <<EOF
path=$selected
epoch=100
age=0h 1m
git_status=clean
content_state=matches_head
head_blob=head-fixture
worktree_hash=worktree-fixture
eligible_count=1
selection_mode=explicit_target
selection_source=enumerate
manifest_status=not_used
selection_order=oldest
target_root=none
target_max_depth=none
include_globs=none
exclude_globs=none
selection_review_modules=none
failure_queue_selected=0
selection_basis=test prompt selection
EOF
  }

  append_preselected_review_target "$compiled"

  [[ -n "$RUN_PRECONTACT_BACKUP_ID" ]] || fail "prompt path did not create backup"
  ! grep -Fq "$UPKEEPER_PRECONTACT_BACKUP_ROOT" "$compiled" || fail "compiled prompt leaked vault root"
  ! grep -Fq "$UPKEEPER_PRECONTACT_BACKUP_ROOT" "$LOG_FILE" || fail "log leaked vault root"
  grep -Fq "report BLOCKED" "$compiled" || fail "compiled prompt missing BLOCKED rule"
  grep -Fq "Replacement target selection is wrapper-only" "$compiled" || fail "compiled prompt missing wrapper-only replacement rule"
  grep -Fq "Pre-contact backup was created by the wrapper before this prompt was compiled" "$compiled" || fail "compiled prompt missing backup notice"
  grep -Fq "you may modify only the selected file shown above" "$compiled" || fail "compiled prompt missing selected-target-only write rule"
  grep -Fq "ADDITIONAL_FILES_NEEDED:" "$compiled" || fail "compiled prompt missing additional-files-needed reporting rule"
  grep -Fq "paired multi-file edits is subordinate to this selected-target-only write boundary" "$compiled" ||
    fail "compiled prompt missing paired-edit override rule"
  ! grep -Fq "backup_id=$RUN_PRECONTACT_BACKUP_ID" "$compiled" || fail "compiled prompt leaked backup id"
  ! grep -Fq "backup_id=$RUN_PRECONTACT_BACKUP_ID" "$LOG_FILE" || fail "runtime log leaked backup id"

  ! grep -Fq "sha256=$RUN_PRECONTACT_BACKUP_SHA256" "$compiled" || fail "compiled prompt leaked backup content hash"
  ! grep -Fq "use the same source-safe selection boundary for the replacement" "$compiled" ||
    fail "compiled prompt still grants model replacement authority"
}

test_retention_prunes_only_same_path() {
  local repo="$TEST_TMP_ROOT/retention repo"
  local selection_file path_sha repo_sha path_dir other_sha other_dir count other_count i
  make_repo "$repo"
  reset_env "$repo" retention
  UPKEEPER_PRECONTACT_BACKUP_KEEP_PER_FILE=2
  selection_file="$TEST_TMP_ROOT/retention-selection.env"

  write_selection_file "dir/other.sh" "$selection_file"
  precontact_backup_selected_target_or_exit "dir/other.sh" "$selection_file"

  for i in 1 2 3 4; do
    CYCLE_ID="cycle-retention-$i"
    CYCLE_RUN_HASH="hash-retention-$i"
    write_selection_file "dir/space file.sh" "$selection_file"
    precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  done

  repo_sha="$(precontact_backup_sha256_text "$(precontact_backup_realpath "$repo")")"
  path_sha="$(precontact_backup_sha256_text "dir/space file.sh")"
  other_sha="$(precontact_backup_sha256_text "dir/other.sh")"
  path_dir="$UPKEEPER_PRECONTACT_BACKUP_ROOT/repo-$repo_sha/path-$path_sha"
  other_dir="$UPKEEPER_PRECONTACT_BACKUP_ROOT/repo-$repo_sha/path-$other_sha"
  count="$(json_path_count "$path_dir")"
  other_count="$(json_path_count "$other_dir")"
  [[ "$count" == "2" ]] || fail "retention kept $count backups for selected path, expected 2"
  [[ "$other_count" == "1" ]] || fail "retention pruned unrelated path key"
}

test_plain_restore_and_unsafe_id() {
  local repo="$TEST_TMP_ROOT/restore repo"
  local selection_file backup_id original_sha restored_sha
  make_repo "$repo"
  reset_env "$repo" restore
  selection_file="$TEST_TMP_ROOT/restore-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  original_sha="$(precontact_backup_sha256_file "$repo/dir/space file.sh")"
  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  backup_id="$RUN_PRECONTACT_BACKUP_ID"

  printf 'mutated\n' >"$repo/dir/space file.sh"
  precontact_backup_restore_by_id "$backup_id" "$repo" "" ""
  restored_sha="$(precontact_backup_sha256_file "$repo/dir/space file.sh")"
  [[ "$restored_sha" == "$original_sha" ]] || fail "plain restore did not restore original bytes"

  if precontact_backup_restore_by_id "../bad" "$repo" "" ""; then
    fail "unsafe backup id was accepted"
  fi
  [[ "$PRECONTACT_BACKUP_LAST_REASON" == "unsafe_backup_id" ]] ||
    fail "unsafe backup id failed as $PRECONTACT_BACKUP_LAST_REASON"

  if precontact_backup_restore_by_id "$backup_id" "$repo" "" "/absolute/path"; then
    fail "absolute restore destination was accepted"
  fi
  [[ "$PRECONTACT_BACKUP_LAST_REASON" == "unsafe_restore_destination" ]] ||
    fail "absolute restore destination failed as $PRECONTACT_BACKUP_LAST_REASON"
}

test_restore_temp_stays_private_until_rename() {
  local repo="$TEST_TMP_ROOT/restore-mode repo"
  local selection_file backup_id tmp_mode final_mode
  make_repo "$repo"
  reset_env "$repo" restore-mode
  selection_file="$TEST_TMP_ROOT/restore-mode-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  chmod 644 "$repo/dir/space file.sh"
  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  backup_id="$RUN_PRECONTACT_BACKUP_ID"

  printf 'mutated\n' >"$repo/dir/space file.sh"
  mv() {
    local source_path="$1"
    if [[ "$source_path" == "--" ]]; then
      source_path="${2:-}"
    fi
    tmp_mode="$(stat -Lc '%a' -- "$source_path" 2>/dev/null || printf 'missing')"
    command mv "$@"
  }
  precontact_backup_restore_by_id "$backup_id" "$repo" "" ""
  unset -f mv

  final_mode="$(stat -Lc '%a' -- "$repo/dir/space file.sh" 2>/dev/null || printf 'missing')"
  [[ "$tmp_mode" == "600" ]] || fail "restore temp mode was $tmp_mode, expected 600 before rename"
  [[ "$final_mode" == "644" ]] || fail "restored target mode was $final_mode, expected 644 after rename"
}

test_plain_restore_temporary_directory_cleaned_on_failure() {
  local repo="$TEST_TMP_ROOT/restore-cleanup repo"
  local selection_file backup_id old_tmpdir old_run_tmp rc tmp_count tmp_root

  make_repo "$repo"
  reset_env "$repo" restore-cleanup
  selection_file="$TEST_TMP_ROOT/restore-cleanup-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  backup_id="$RUN_PRECONTACT_BACKUP_ID"

  rm -f -- "$UPKEEPER_PRECONTACT_BACKUP_ROOT"/*/*/"${backup_id}.bak"
  old_run_tmp="$RUN_TMP_DIR"
  old_tmpdir="${TMPDIR-}"
  RUN_TMP_DIR=""
  tmp_root="$TEST_TMP_ROOT/restore-cleanup-tmp"
  mkdir -p "$tmp_root"
  TMPDIR="$tmp_root"

  set +e
  precontact_backup_restore_by_id "$backup_id" "$repo" "" ""
  rc=$?
  set -e

  RUN_TMP_DIR="$old_run_tmp"
  if [[ -n "$old_tmpdir" ]]; then
    TMPDIR="$old_tmpdir"
  else
    unset TMPDIR
  fi

  [[ "$rc" -eq 1 ]] || fail "restore failure was expected"
  [[ "$PRECONTACT_BACKUP_LAST_REASON" == "plain_artifact_missing" ]] ||
    fail "restore failure did not preserve expected reason"

  tmp_count="$(find "$tmp_root" -maxdepth 1 -type d -name 'upkeeper-restore-*' | wc -l | tr -d ' ')"
  [[ "$tmp_count" == "0" ]] || fail "temporary restore directory not cleaned (found ${tmp_count})"
}

test_plain_required_backup_succeeds
test_age_mode_uses_public_recipient_only
test_required_encrypted_mode_fails_closed
test_unsafe_target_rejection
test_precontact_backup_validate_root_secure_private_dir
test_prompt_redaction_and_replacement_rule
test_retention_prunes_only_same_path
test_plain_restore_and_unsafe_id
test_restore_temp_stays_private_until_rename
test_plain_restore_temporary_directory_cleaned_on_failure
test_age_restore_uses_payload_metadata

printf 'precontact_backup_test: ok\n'
