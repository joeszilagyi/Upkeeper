#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-precontact-test.XXXXXX")"

cleanup() {
  # This exact root is created by mktemp above. Backup fixtures can contain
  # read-only files, so terminal cleanup must never wait for confirmation.
  rm -rf -- "$TEST_TMP_ROOT" 2>/dev/null || true
}
trap cleanup EXIT

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

log_line_parts() {
  local level="$1"
  shift
  local message="" part
  for part in "$@"; do
    message+="$part"
  done
  log_line "$level" "$message"
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
  UPKEEPER_PRECONTACT_BACKUP_MODE=auto
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=1
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=0
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_RESTORE=0
  UPKEEPER_PRECONTACT_BACKUP_ROOT="$TEST_TMP_ROOT/$name vault redacted"
  UPKEEPER_PRECONTACT_BACKUP_KEEP_PER_FILE=20
  UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT=""
  UPKEEPER_PRECONTACT_BACKUP_REDACT_PATHS=1
  UPKEEPER_LOCAL_ENV_FILE="$TEST_TMP_ROOT/$name.local.env"
  UPKEEPER_REDACTION_KEY="precontact-test-key-$name"
  UPKEEPER_DRY_RUN=0
  CODEX_TARGET_FILE=""
  CODEX_BUG_REPORT_ONLY=0
  CODEX_ISSUE_WORKFLOW_STAGE=""
  RUN_PRECONTACT_BACKUP_ID=""
  RUN_PRECONTACT_BACKUP_SHA256=""
  RUN_PRECONTACT_BACKUP_MODE=""
  RUN_PRECONTACT_BACKUP_ENCRYPTED=""
  RUN_PRECONTACT_BACKUP_PROTECTED_FROM_BACKEND=""
  mkdir -p "$RUN_TMP_DIR"
  chmod 700 "$RUN_TMP_DIR"
  : >"$LOG_FILE"
}

test_machine_preflight_blocks_before_issue_selection() {
  local repo="$TEST_TMP_ROOT/machine-preflight repo"
  local rc

  make_repo "$repo"
  reset_env "$repo" machine-preflight

  set +e
  ( precontact_backup_machine_preflight_or_exit )
  rc=$?
  set -e

  [[ "$rc" -eq 7 ]] || fail "machine preflight exited $rc, expected 7"
  grep -Fq "reason=PRECONTACT_BACKUP_PREREQ_MISSING" "$FINISH_CAPTURE" || fail "machine preflight did not preserve prereq-missing reason"
  grep -Fq "preflight_reason=recipient_missing" "$FINISH_CAPTURE" || fail "machine preflight did not preserve recipient-missing detail"
  grep -Fq "local_env_file=$UPKEEPER_LOCAL_ENV_FILE" "$FINISH_CAPTURE" || fail "machine preflight did not name the local env file"
  grep -Fq "precontact_backup.preflight_blocked" "$LOG_FILE" || fail "machine preflight block was not logged"
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
  local selection_file json_file bak_file expected_sha derivation_prefix backup_id expected_path_hmac
  local expected_size expected_mode expected_mtime
  make_repo "$repo"
  reset_env "$repo" plain
  selection_file="$TEST_TMP_ROOT/plain-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1
  chmod 640 "$repo/dir/space file.sh"
  python3 - "$repo/dir/space file.sh" <<'PY'
import os
import sys

known_mtime_ns = 946_684_800_123_456_789
os.utime(sys.argv[1], ns=(known_mtime_ns, known_mtime_ns))
PY
  expected_size="$(file_size_bytes "$repo/dir/space file.sh")"
  expected_mode="640"
  expected_mtime="$(python3 - "$repo/dir/space file.sh" <<'PY'
from datetime import datetime, timezone
from pathlib import Path
import sys

print(datetime.fromtimestamp(Path(sys.argv[1]).stat().st_mtime, timezone.utc).isoformat().replace("+00:00", "Z"))
PY
)"

  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"

  [[ -n "$RUN_PRECONTACT_BACKUP_ID" ]] || fail "plain backup did not set backup id"
  json_file="$(find "$UPKEEPER_PRECONTACT_BACKUP_ROOT" -type f -name "${RUN_PRECONTACT_BACKUP_ID}.json" -print)"
  bak_file="$(find "$UPKEEPER_PRECONTACT_BACKUP_ROOT" -type f -name "${RUN_PRECONTACT_BACKUP_ID}.bak" -print)"
  [[ -s "$json_file" ]] || fail "plain sidecar missing"
  [[ -s "$bak_file" ]] || fail "plain backup artifact missing"
  [[ "$(dirname -- "$json_file")" == "$(dirname -- "$bak_file")" ]] || fail "plain backup pair was split across directories"
  [[ "$(basename -- "$(dirname -- "$json_file")")" == "$RUN_PRECONTACT_BACKUP_ID" ]] || fail "plain backup pair was not atomically published by backup id"

  expected_sha="$(precontact_backup_sha256_file "$repo/dir/space file.sh")"
  expected_path_hmac="$(precontact_backup_path_hmac "dir/space file.sh")"
  [[ "$(precontact_backup_sha256_file "$bak_file")" == "$expected_sha" ]] || fail "plain backup sha mismatch"
  backup_id="$(basename -- "$json_file" .json)"
  derivation_prefix="$(jq -r '.backup_id_derivation_sha256[0:32]' "$json_file")"
  [[ "$backup_id" == *"$derivation_prefix"* ]] || fail "backup id does not derive from recorded derivation sha"
  grep -Fq "precontact_backup.created target_hmac=$expected_path_hmac" "$LOG_FILE" || fail "created log did not record target HMAC"
  ! grep -Fq "target=dir/space file.sh" "$LOG_FILE" || fail "created log leaked selected relative path"
  jq -e \
    --arg content_hmac "$(precontact_backup_content_hmac "$expected_sha")" \
    --arg path_hmac "$expected_path_hmac" \
    --argjson expected_size "$expected_size" \
    --arg expected_mode "$expected_mode" \
    --arg expected_mtime "$expected_mtime" \
    '.schema_version == 3
      and .selected_relative_path_redacted == true
      and (has("selected_relative_path") | not)
      and .content_hmac == $content_hmac
      and .relative_path_hmac == $path_hmac
      and (.content_sha256 | not)
      and (.relative_path_sha256 | not)
      and .cycle_id == "cycle-plain"
      and .cycle_run_hash == "hash-plain"
      and .selected_git_status == "clean"
      and .selected_worktree_hash == "worktree-fixture"
      and .size_bytes == $expected_size
      and .mode == $expected_mode
      and .mtime == $expected_mtime
      and .selection_basis == "redacted"
      and .backup_mode == "plain"
      and .encrypted == false
      and .protected_from_backend == false' "$json_file" >/dev/null ||
    fail "plain sidecar JSON missing required fields"
  ! grep -Fq 'dir/space file.sh' "$json_file" || fail "redacted plain sidecar leaked the selected path"
}

test_age_mode_uses_public_recipient_only() {
  local repo="$TEST_TMP_ROOT/age repo"
  local fake_bin="$TEST_TMP_ROOT/fake-age-bin"
  local record="$TEST_TMP_ROOT/fake-age-record.txt"
  local selection_file json_file age_file old_path expected_path_hmac
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
  [[ "$(dirname -- "$json_file")" == "$(dirname -- "$age_file")" ]] || fail "age backup pair was split across directories"
  [[ "$(basename -- "$(dirname -- "$json_file")")" == "$RUN_PRECONTACT_BACKUP_ID" ]] || fail "age backup pair was not atomically published by backup id"
  grep -Fq "recipient=age1testrecipient" "$record" || fail "fake age did not receive public recipient"
  ! grep -Fq "identity=" "$record" || fail "age backup requested an identity"
  jq -e '.backup_mode == "age" and .encrypted == true and .protected_from_backend == "unknown"' "$json_file" >/dev/null ||
    fail "age sidecar did not record encrypted unknown-protection state"
}

test_age_restore_uses_payload_metadata() {
  local repo="$TEST_TMP_ROOT/age-restore repo"
  local destination_repo="$TEST_TMP_ROOT/age-restore destination repo"
  local fake_bin="$TEST_TMP_ROOT/fake-age-bin"
  local selection_file json_file age_file restored_sha original_sha sidecar destination_sha
  local identity_file="$TEST_TMP_ROOT/age-identity.key"
  local old_path expected_path_hmac expected_mtime_ns restored_mtime_ns
  local extracted_file extracted_metadata
  local record
  make_repo "$repo"
  make_repo "$destination_repo"
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
  python3 - "$repo/dir/space file.sh" <<'PY'
import os
import sys

known_mtime_ns = 946_684_800_123_456_789
os.utime(sys.argv[1], ns=(known_mtime_ns, known_mtime_ns))
PY
  expected_mtime_ns="$(python3 - "$repo/dir/space file.sh" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).stat().st_mtime_ns)
PY
)"
  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"

  json_file="$(find "$UPKEEPER_PRECONTACT_BACKUP_ROOT" -type f -name "${RUN_PRECONTACT_BACKUP_ID}.json" -print)"
  age_file="$(find "$UPKEEPER_PRECONTACT_BACKUP_ROOT" -type f -name "${RUN_PRECONTACT_BACKUP_ID}.age" -print)"
  sidecar="$json_file"
  [[ -s "$age_file" ]] || fail "age restore test missing age artifact"
  [[ -s "$sidecar" ]] || fail "age restore test missing age sidecar"
  extracted_file="$RUN_TMP_DIR/age-restore-extracted"
  extracted_metadata="$RUN_TMP_DIR/age-restore-metadata.json"
  precontact_backup_extract_payload "$age_file" "$extracted_file" "$extracted_metadata"
  jq -e --argjson expected "$expected_mtime_ns" '.mtime_ns == $expected' "$extracted_metadata" >/dev/null ||
    fail "age private metadata did not record integer mtime_ns"

  printf 'encrypted restore destination content\n' >"$destination_repo/dir/space file.sh"
  destination_sha="$(precontact_backup_sha256_file "$destination_repo/dir/space file.sh")"
  if precontact_backup_restore_by_id "$RUN_PRECONTACT_BACKUP_ID" "$destination_repo" "$identity_file" ""; then
    fail "encrypted restore accepted private metadata from another repository"
  fi
  [[ "$PRECONTACT_BACKUP_LAST_REASON" == "restore_repo_identity_mismatch" ]] ||
    fail "encrypted cross-repository restore failed as $PRECONTACT_BACKUP_LAST_REASON"
  [[ "$(precontact_backup_sha256_file "$destination_repo/dir/space file.sh")" == "$destination_sha" ]] ||
    fail "rejected encrypted cross-repository restore changed the destination"

  original_sha="$(precontact_backup_sha256_file "$repo/dir/space file.sh")"
  expected_path_hmac="$(precontact_backup_path_hmac "dir/space file.sh")"
  printf 'mutated\n' >"$repo/dir/space file.sh"
  env \
    PATH="$PATH" \
    UPKEEPER_REDACTION_KEY="$UPKEEPER_REDACTION_KEY" \
    CODEX_LOG_FILE="$LOG_FILE" \
    "$PROJECT_ROOT/tools/upkeeper_precontact_restore.sh" \
      --repo-root="$repo" \
      --backup-id="$RUN_PRECONTACT_BACKUP_ID" \
      --identity="$identity_file" \
      --vault-root="$UPKEEPER_PRECONTACT_BACKUP_ROOT"
  restored_sha="$(precontact_backup_sha256_file "$repo/dir/space file.sh")"
  [[ "$restored_sha" == "$original_sha" ]] || fail "age restore did not restore original bytes"
  restored_mtime_ns="$(python3 - "$repo/dir/space file.sh" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).stat().st_mtime_ns)
PY
)"
  [[ "$restored_mtime_ns" == "$expected_mtime_ns" ]] ||
    fail "age restore mtime_ns was $restored_mtime_ns, expected $expected_mtime_ns"
  grep -Fq "precontact_backup.restore target_hmac=$expected_path_hmac" "$LOG_FILE" || fail "restore log did not record target HMAC"
  ! grep -Fq "precontact_backup.restore target=dir/space file.sh" "$LOG_FILE" || fail "restore log leaked selected relative path"

  python3 - "$age_file" <<'PY'
import json
import sys

payload_path = sys.argv[1]
with open(payload_path, "rb") as handle:
    magic = handle.readline()
    metadata_length = int(handle.readline().strip())
    metadata = json.loads(handle.read(metadata_length))
    content = handle.read()
metadata.pop("mtime_ns", None)
encoded = json.dumps(metadata, sort_keys=True, indent=2).encode("utf-8") + b"\n"
with open(payload_path, "wb") as handle:
    handle.write(magic)
    handle.write(str(len(encoded)).encode("ascii") + b"\n")
    handle.write(encoded)
    handle.write(content)
PY
  printf 'mutated before legacy age restore\n' >"$repo/dir/space file.sh"
  precontact_backup_restore_by_id "$RUN_PRECONTACT_BACKUP_ID" "$repo" "$identity_file" ""
  [[ "$(precontact_backup_sha256_file "$repo/dir/space file.sh")" == "$original_sha" ]] ||
    fail "legacy age payload without mtime_ns did not restore original bytes"

  PATH="$old_path"

  jq -e 'has("selected_relative_path") | not' "$sidecar" >/dev/null ||
    fail "age sidecar leaked detailed restore metadata"
}

test_age_create_rejects_stale_payload_when_target_mutates_after_metadata() {
  local repo="$TEST_TMP_ROOT/age-mismatch repo"
  local selection_file metadata_file sidecar_file path_dir backup_id rel_path target_path
  local created_utc size_bytes mode_text mtime_text repo_real repo_hmac repo_key repo_root_hmac
  local path_hmac content_sha derivation_sha rc
  make_repo "$repo"
  reset_env "$repo" age-mismatch
  rel_path="dir/space file.sh"
  selection_file="$TEST_TMP_ROOT/age-mismatch-selection.env"
  write_selection_file "$rel_path" "$selection_file"
  UPKEEPER_PRECONTACT_BACKUP_MODE=age
  UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT="age1testrecipient"
  target_path="$repo/$rel_path"
  path_dir="$UPKEEPER_PRECONTACT_BACKUP_ROOT/age-mismatch"
  backup_id="pb-$(printf '%s' "$rel_path" | tr '/ ' '-')-mismatch"
  mkdir -p "$path_dir"

  repo_real="$(precontact_backup_realpath "$repo")"
  repo_hmac="$(precontact_backup_hmac_text repo "$repo_real")"
  repo_key="repo-hmac-${repo_hmac}"
  repo_root_hmac="repo-hmac-sha256:${repo_hmac}"
  path_hmac="$(precontact_backup_path_hmac "$rel_path")"
  created_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  size_bytes="$(file_size_bytes "$target_path")"
  mode_text="$(python3 - "$target_path" <<'PY' 2>/dev/null || printf 'unknown'
from pathlib import Path
import stat
import sys

st = Path(sys.argv[1]).stat()
print(oct(stat.S_IMODE(st.st_mode))[2:])
PY
  )"
  mtime_text="$(python3 - "$target_path" <<'PY' 2>/dev/null || printf 'unknown'
from datetime import datetime, timezone
from pathlib import Path
import sys

st = Path(sys.argv[1]).stat()
print(datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat().replace("+00:00", "Z"))
PY
  )"
  content_sha="$(precontact_backup_sha256_file "$target_path")"
  derivation_sha="$(precontact_backup_sha256_text "${content_sha}-${path_hmac}-${CYCLE_ID}")"

  metadata_file="$(run_mktemp precontact-backup-metadata)"
  sidecar_file="$(run_mktemp precontact-backup-age-sidecar)"
  if ! precontact_backup_write_metadata "$metadata_file" "$repo_key" "$repo_root_hmac" \
    "$rel_path" "$path_hmac" "$(precontact_backup_content_hmac "$content_sha")" \
    "$CYCLE_ID" "$CYCLE_RUN_HASH" "$created_utc" "$size_bytes" "$mode_text" "$mtime_text" \
    "clean" "worktree-fixture" "test selected $rel_path" \
    "age" "true" "unknown" "$derivation_sha" "matches_head" "head-fixture"; then
    fail "age mismatch test failed to write metadata"
  fi
  if ! precontact_backup_write_age_public_metadata "$sidecar_file" "$derivation_sha" "$created_utc" "unknown"; then
    fail "age mismatch test failed to write sidecar"
  fi

  printf 'mutated between metadata and payload write' >"$target_path"

  set +e
  precontact_backup_create_age "$target_path" "$path_dir" "$backup_id" "$metadata_file" "$sidecar_file"
  rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || fail "age create with stale payload returned $rc, expected 1"
  [[ "$PRECONTACT_BACKUP_LAST_REASON" == "payload_hash_mismatch" ]] || fail "age create did not record payload hash mismatch reason"
  [[ ! -s "$path_dir/${backup_id}.age" ]] || fail "age artifact was written despite payload mismatch"
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

test_default_auto_mode_fails_closed_without_age() {
  local repo="$TEST_TMP_ROOT/default-auto repo"
  local selection_file rc
  make_repo "$repo"
  reset_env "$repo" default-auto
  selection_file="$TEST_TMP_ROOT/default-auto-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"

  set +e
  ( precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file" )
  rc=$?
  set -e
  [[ "$rc" -eq 7 ]] || fail "default auto backup without age exited $rc, expected 7"
  grep -Fq "reason=recipient_missing" "$FINISH_CAPTURE" || fail "default auto failure did not report missing recipient"
}

test_plain_mode_requires_explicit_unsafe_override() {
  local repo="$TEST_TMP_ROOT/plain-override repo"
  local selection_file rc
  make_repo "$repo"
  reset_env "$repo" plain-override
  selection_file="$TEST_TMP_ROOT/plain-override-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0

  set +e
  ( precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file" )
  rc=$?
  set -e
  [[ "$rc" -eq 7 ]] || fail "plain mode without unsafe override exited $rc, expected 7"
  grep -Fq "reason=plaintext_override_required" "$FINISH_CAPTURE" ||
    fail "plain override failure did not report plaintext_override_required"
}

test_plain_mode_rejects_private_key_content() {
  local repo="$TEST_TMP_ROOT/plain-sensitive-content repo"
  local selection_file rc
  make_repo "$repo"
  reset_env "$repo" plain-sensitive-content
  selection_file="$TEST_TMP_ROOT/plain-sensitive-selection.env"
  write_selection_file "dir/plain-secret.sh" "$selection_file"
  printf '%s\n' '-----BEGIN PRIVATE KEY-----' 'abc123' '-----END PRIVATE KEY-----' >"$repo/dir/plain-secret.sh"
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1

  set +e
  ( precontact_backup_selected_target_or_exit "dir/plain-secret.sh" "$selection_file" )
  rc=$?
  set -e
  [[ "$rc" -eq 7 ]] || fail "plain mode sensitive content exit was $rc, expected 7"
  grep -Fq "reason=plaintext_sensitive_content_rejected" "$FINISH_CAPTURE" ||
    fail "plain content gate did not preserve plaintext_sensitive_content_rejected"
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
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1

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
  local selection_file path_key repo_hmac path_dir other_key other_dir count other_count i
  make_repo "$repo"
  reset_env "$repo" retention
  UPKEEPER_PRECONTACT_BACKUP_KEEP_PER_FILE=2
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1
  selection_file="$TEST_TMP_ROOT/retention-selection.env"

  write_selection_file "dir/other.sh" "$selection_file"
  precontact_backup_selected_target_or_exit "dir/other.sh" "$selection_file"

  for i in 1 2 3 4; do
    CYCLE_ID="cycle-retention-$i"
    CYCLE_RUN_HASH="hash-retention-$i"
    write_selection_file "dir/space file.sh" "$selection_file"
    precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  done

  repo_hmac="$(precontact_backup_hmac_text repo "$(precontact_backup_realpath "$repo")")"
  path_key="$(precontact_backup_hmac_text path "dir/space file.sh")"
  other_key="$(precontact_backup_hmac_text path "dir/other.sh")"
  path_dir="$UPKEEPER_PRECONTACT_BACKUP_ROOT/repo-hmac-$repo_hmac/path-hmac-$path_key"
  other_dir="$UPKEEPER_PRECONTACT_BACKUP_ROOT/repo-hmac-$repo_hmac/path-hmac-$other_key"
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
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1
  original_sha="$(precontact_backup_sha256_file "$repo/dir/space file.sh")"
  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  backup_id="$RUN_PRECONTACT_BACKUP_ID"

  printf 'mutated\n' >"$repo/dir/space file.sh"
  if precontact_backup_restore_by_id "$backup_id" "$repo" "" ""; then
    fail "redacted plain backup restored without an explicit destination"
  fi
  [[ "$PRECONTACT_BACKUP_LAST_REASON" == "restore_path_redacted_requires_override" ]] ||
    fail "redacted plain restore failed as $PRECONTACT_BACKUP_LAST_REASON"
  precontact_backup_restore_by_id "$backup_id" "$repo" "" "dir/space file.sh"
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
  [[ "$PRECONTACT_BACKUP_LAST_REASON" == "absolute_path" ]] ||
    fail "absolute restore destination failed as $PRECONTACT_BACKUP_LAST_REASON"
}

test_restore_by_id_handles_newline_vault_and_duplicate_sidecars() {
  local repo="$TEST_TMP_ROOT/newline-vault repo"
  local selection_file backup_id original_sha restored_sha rc
  local -a sidecar_files=()

  make_repo "$repo"
  reset_env "$repo" newline-vault
  UPKEEPER_PRECONTACT_BACKUP_ROOT="$TEST_TMP_ROOT/newline"$'\n'"vault"
  selection_file="$TEST_TMP_ROOT/newline-vault-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1
  original_sha="$(precontact_backup_sha256_file "$repo/dir/space file.sh")"

  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  backup_id="$RUN_PRECONTACT_BACKUP_ID"
  printf 'mutated before newline restore\n' >"$repo/dir/space file.sh"
  precontact_backup_restore_by_id "$backup_id" "$repo" "" "dir/space file.sh"
  restored_sha="$(precontact_backup_sha256_file "$repo/dir/space file.sh")"
  [[ "$restored_sha" == "$original_sha" ]] || fail "newline-vault library restore changed backup bytes"

  printf 'mutated before standalone newline restore\n' >"$repo/dir/space file.sh"
  env \
    UPKEEPER_REDACTION_KEY="$UPKEEPER_REDACTION_KEY" \
    CODEX_LOG_FILE="$LOG_FILE" \
    "$PROJECT_ROOT/tools/upkeeper_precontact_restore.sh" \
      --repo-root="$repo" \
      --backup-id="$backup_id" \
      --vault-root="$UPKEEPER_PRECONTACT_BACKUP_ROOT" \
      --restore-to="dir/space file.sh"
  restored_sha="$(precontact_backup_sha256_file "$repo/dir/space file.sh")"
  [[ "$restored_sha" == "$original_sha" ]] || fail "standalone newline-vault restore changed backup bytes"

  mapfile -d '' -t sidecar_files < <(
    find "$UPKEEPER_PRECONTACT_BACKUP_ROOT" -type f -name "${backup_id}.json" -print0
  )
  [[ "${#sidecar_files[@]}" -eq 1 ]] || fail "newline-vault fixture did not create exactly one sidecar"
  mkdir -p "$UPKEEPER_PRECONTACT_BACKUP_ROOT/duplicate"
  cp -- "${sidecar_files[0]}" "$UPKEEPER_PRECONTACT_BACKUP_ROOT/duplicate/${backup_id}.json"

  set +e
  precontact_backup_restore_by_id "$backup_id" "$repo" "" "dir/space file.sh"
  rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || fail "duplicate sidecar restore returned $rc, expected 1"
  [[ "$PRECONTACT_BACKUP_LAST_REASON" == "backup_id_not_unique_or_missing" ]] ||
    fail "duplicate sidecar restore failed as $PRECONTACT_BACKUP_LAST_REASON"
}

test_standalone_restore_rejects_wrong_repo_by_default() {
  local source_repo="$TEST_TMP_ROOT/restore identity source repo"
  local destination_repo="$TEST_TMP_ROOT/restore identity destination repo"
  local selection_file backup_id destination_sha restored_sha output rc

  make_repo "$source_repo"
  make_repo "$destination_repo"
  reset_env "$source_repo" restore-identity
  selection_file="$TEST_TMP_ROOT/restore-identity-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1
  UPKEEPER_PRECONTACT_BACKUP_REDACT_PATHS=0
  printf 'source repository backup\n' >"$source_repo/dir/space file.sh"
  printf 'destination repository content\n' >"$destination_repo/dir/space file.sh"
  destination_sha="$(precontact_backup_sha256_file "$destination_repo/dir/space file.sh")"

  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  backup_id="$RUN_PRECONTACT_BACKUP_ID"
  jq -e --arg rel "dir/space file.sh" '.schema_version == 2 and .selected_relative_path == $rel' \
    "$(find "$UPKEEPER_PRECONTACT_BACKUP_ROOT" -type f -name "${backup_id}.json" -print -quit)" >/dev/null ||
    fail "explicit redaction opt-out did not preserve legacy path metadata"

  set +e
  output="$(env \
    UPKEEPER_REDACTION_KEY="$UPKEEPER_REDACTION_KEY" \
    UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_RESTORE=0 \
    CODEX_LOG_FILE="$LOG_FILE" \
    "$PROJECT_ROOT/tools/upkeeper_precontact_restore.sh" \
      --repo-root="$destination_repo" \
      --backup-id="$backup_id" \
      --vault-root="$UPKEEPER_PRECONTACT_BACKUP_ROOT" 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 2 ]] || fail "standalone restore from another repository returned $rc, expected 2"
  [[ "$output" == *"restore_repo_identity_mismatch"* ]] ||
    fail "standalone cross-repository restore did not report the stable mismatch reason"
  [[ "$(precontact_backup_sha256_file "$destination_repo/dir/space file.sh")" == "$destination_sha" ]] ||
    fail "rejected cross-repository restore changed the destination"

  env \
    UPKEEPER_REDACTION_KEY="$UPKEEPER_REDACTION_KEY" \
    UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_RESTORE=1 \
    CODEX_LOG_FILE="$LOG_FILE" \
    "$PROJECT_ROOT/tools/upkeeper_precontact_restore.sh" \
      --repo-root="$destination_repo" \
      --backup-id="$backup_id" \
      --vault-root="$UPKEEPER_PRECONTACT_BACKUP_ROOT"
  restored_sha="$(precontact_backup_sha256_file "$destination_repo/dir/space file.sh")"
  [[ "$restored_sha" == "$(precontact_backup_sha256_file "$source_repo/dir/space file.sh")" ]] ||
    fail "explicit unsafe cross-repository restore did not restore the source bytes"
}

test_secure_restore_preserves_recorded_mode() {
  local repo="$TEST_TMP_ROOT/restore-mode repo"
  local selection_file backup_id final_mode
  make_repo "$repo"
  reset_env "$repo" restore-mode
  selection_file="$TEST_TMP_ROOT/restore-mode-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1
  chmod 644 "$repo/dir/space file.sh"
  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  backup_id="$RUN_PRECONTACT_BACKUP_ID"

  printf 'mutated\n' >"$repo/dir/space file.sh"
  precontact_backup_restore_by_id "$backup_id" "$repo" "" "dir/space file.sh"

  final_mode="$(stat -Lc '%a' -- "$repo/dir/space file.sh" 2>/dev/null || printf 'missing')"
  [[ "$final_mode" == "644" ]] || fail "securely restored target mode was $final_mode, expected 644"
}

test_secure_restore_rejects_parent_swap_race() {
  local repo="$TEST_TMP_ROOT/restore-race repo"
  local outside="$TEST_TMP_ROOT/restore-race outside"
  local selection_file backup_id outside_sha rc

  make_repo "$repo"
  reset_env "$repo" restore-race
  selection_file="$TEST_TMP_ROOT/restore-race-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1
  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  backup_id="$RUN_PRECONTACT_BACKUP_ID"

  mkdir -p "$outside"
  printf 'outside sentinel\n' >"$outside/space file.sh"
  outside_sha="$(precontact_backup_sha256_file "$outside/space file.sh")"
  printf 'mutated before raced restore\n' >"$repo/dir/space file.sh"

  precontact_backup_sha256_file() {
    local path="$1"
    python3 - "$path" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
    if [[ "$path" == "$RUN_TMP_DIR"/.upkeeper-restore.* ]]; then
      command mv -- "$repo/dir" "$repo/dir-before-race"
      ln -s -- "$outside" "$repo/dir"
    fi
  }

  set +e
  precontact_backup_restore_by_id "$backup_id" "$repo" "" "dir/space file.sh"
  rc=$?
  set -e

  [[ "$rc" -eq 1 ]] || fail "restore parent-swap race returned $rc, expected 1"
  [[ "$PRECONTACT_BACKUP_LAST_REASON" == "restore_parent_symlinked" ]] ||
    fail "restore parent-swap race failed as $PRECONTACT_BACKUP_LAST_REASON"
  [[ -L "$repo/dir" ]] || fail "restore race fixture did not swap the parent for a symlink"
  [[ "$(python3 - "$outside/space file.sh" <<'PY'
import hashlib
import sys

print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
)" == "$outside_sha" ]] || fail "restore parent-swap race overwrote the outside target"
}

test_plain_restore_temporary_directory_cleaned_on_failure() {
  local repo="$TEST_TMP_ROOT/restore-cleanup repo"
  local selection_file backup_id old_tmpdir old_run_tmp rc tmp_count tmp_root

  make_repo "$repo"
  reset_env "$repo" restore-cleanup
  selection_file="$TEST_TMP_ROOT/restore-cleanup-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1
  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  backup_id="$RUN_PRECONTACT_BACKUP_ID"

  find "$UPKEEPER_PRECONTACT_BACKUP_ROOT" -type f -name "${backup_id}.bak" -delete
  old_run_tmp="$RUN_TMP_DIR"
  old_tmpdir="${TMPDIR-}"
  RUN_TMP_DIR=""
  tmp_root="$TEST_TMP_ROOT/restore-cleanup-tmp"
  mkdir -p "$tmp_root"
  TMPDIR="$tmp_root"

  set +e
  precontact_backup_restore_by_id "$backup_id" "$repo" "" "dir/space file.sh"
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

test_atomic_backup_pair_publication_contract() {
  local path_dir="$TEST_TMP_ROOT/publish-pair"
  local repo="$TEST_TMP_ROOT/publish-pair-repo"
  local backup_id="pb-publish-pair"
  local staged_dir="$path_dir/.${backup_id}.fixture.staging"
  local final_dir="$path_dir/$backup_id"
  local definition rc

  mkdir -p "$staged_dir"
  chmod 700 "$path_dir" "$staged_dir"
  printf '{}\n' >"$staged_dir/${backup_id}.json"
  set +e
  precontact_backup_publish_directory "$staged_dir" "$final_dir"
  rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || fail "incomplete backup pair was published"
  [[ ! -e "$final_dir" ]] || fail "incomplete backup pair became discoverable"
  [[ -d "$staged_dir" ]] || fail "rejected incomplete pair lost staging evidence"

  definition="$(declare -f precontact_backup_publish_directory)"
  python3 - "$definition" <<'PY' || fail "durable backup publication ordering contract changed"
import sys

text = sys.argv[1]
ordered = (
    "os.fsync(file_fd)",
    "os.fsync(staged_fd)",
    "os.replace(staged_dir.name, final_dir.name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)",
    "os.fsync(parent_fd)",
)
positions = [text.find(token) for token in ordered]
if any(position < 0 for position in positions) or positions != sorted(positions):
    raise SystemExit(1)
PY

  printf 'orphan payload\n' >"$path_dir/pb-orphan.bak"
  make_repo "$repo"
  UPKEEPER_PRECONTACT_BACKUP_ROOT="$path_dir"
  if precontact_backup_restore_by_id "pb-orphan" "$repo" "" ""; then
    fail "orphan payload without a sidecar was treated as complete"
  fi
  [[ "$PRECONTACT_BACKUP_LAST_REASON" == "backup_id_not_unique_or_missing" ]] ||
    fail "orphan payload failed as $PRECONTACT_BACKUP_LAST_REASON"
}

test_machine_preflight_skips_read_only_issue_stages() {
  local repo="$TEST_TMP_ROOT/machine-preflight-review repo"

  make_repo "$repo"
  reset_env "$repo" machine-preflight-review
  CODEX_ISSUE_WORKFLOW_STAGE="review"

  precontact_backup_machine_preflight_or_exit
}

test_selected_target_metadata_batches_python_launches() {
  local repo="$TEST_TMP_ROOT/batched-metadata repo"
  local selection_file launch_log launch_count

  make_repo "$repo"
  reset_env "$repo" batched-metadata
  selection_file="$TEST_TMP_ROOT/batched-metadata-selection.env"
  launch_log="$TEST_TMP_ROOT/batched-metadata-python-launches.log"
  write_selection_file "dir/space file.sh" "$selection_file"
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1

  python3() {
    printf '%s\n' "$*" >>"$launch_log"
    command python3 "$@"
  }
  precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  unset -f python3

  launch_count="$(wc -l <"$launch_log" | tr -d ' ')"
  # Target validation, the allowed plain-content scan, sidecar construction,
  # copy verification, publication, and pruning remain independent boundaries.
  # The former six-call metadata snapshot is one call, reducing this full plain
  # path from sixteen launches to a fixed maximum of eleven.
  [[ "$launch_count" -le 11 ]] || {
    sed 's/^/python-launch: /' "$launch_log" >&2
    fail "selected-target backup launched $launch_count Python helpers, expected at most 11"
  }
}

test_selected_target_metadata_helper_fails_closed() {
  local repo="$TEST_TMP_ROOT/batched-metadata-failure repo"
  local selection_file rc

  make_repo "$repo"
  reset_env "$repo" batched-metadata-failure
  selection_file="$TEST_TMP_ROOT/batched-metadata-failure-selection.env"
  write_selection_file "dir/space file.sh" "$selection_file"
  UPKEEPER_PRECONTACT_BACKUP_MODE=plain
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1
  set +e
  (
    precontact_backup_collect_target_metadata() { return 1; }
    precontact_backup_selected_target_or_exit "dir/space file.sh" "$selection_file"
  )
  rc=$?
  set -e

  [[ "$rc" -eq 7 ]] || fail "metadata helper failure exited $rc, expected 7"
  grep -Fq 'reason=target_metadata_failed' "$FINISH_CAPTURE" ||
    fail "metadata helper failure did not retain target_metadata_failed"
}

test_cleanup_removes_read_only_fixture() {
  local fixture_dir fixture_file

  fixture_dir="$TEST_TMP_ROOT/cleanup-read-only"
  fixture_file="$fixture_dir/read-only-backup"
  mkdir -p -- "$fixture_dir"
  printf 'fixture\n' >"$fixture_file"
  chmod 444 -- "$fixture_file"
  if [[ -n "${UPKEEPER_PRECONTACT_TEST_CLEANUP_ROOT_RECORD:-}" ]]; then
    printf '%s\n' "$TEST_TMP_ROOT" >"$UPKEEPER_PRECONTACT_TEST_CLEANUP_ROOT_RECORD"
  fi
  if [[ "${UPKEEPER_PRECONTACT_TEST_CLEANUP_FAIL:-0}" == "1" ]]; then
    return 1
  fi
}

case "${UPKEEPER_PRECONTACT_TEST_GROUP:-core}" in
  core)
    test_plain_required_backup_succeeds
    test_age_mode_uses_public_recipient_only
    test_age_create_rejects_stale_payload_when_target_mutates_after_metadata
    test_machine_preflight_blocks_before_issue_selection
    test_machine_preflight_skips_read_only_issue_stages
    test_selected_target_metadata_batches_python_launches
    test_selected_target_metadata_helper_fails_closed
    test_required_encrypted_mode_fails_closed
    test_default_auto_mode_fails_closed_without_age
    test_plain_mode_requires_explicit_unsafe_override
    test_plain_mode_rejects_private_key_content
    test_unsafe_target_rejection
    test_precontact_backup_validate_root_secure_private_dir
    test_prompt_redaction_and_replacement_rule
    test_retention_prunes_only_same_path
    test_plain_restore_and_unsafe_id
    test_restore_by_id_handles_newline_vault_and_duplicate_sidecars
    test_standalone_restore_rejects_wrong_repo_by_default
    test_secure_restore_preserves_recorded_mode
    test_plain_restore_temporary_directory_cleaned_on_failure
    test_age_restore_uses_payload_metadata
    test_secure_restore_rejects_parent_swap_race
    test_atomic_backup_pair_publication_contract
    ;;
  cleanup)
    test_cleanup_removes_read_only_fixture
    ;;
  cleanup-failure)
    UPKEEPER_PRECONTACT_TEST_CLEANUP_FAIL=1 test_cleanup_removes_read_only_fixture
    ;;
  *)
    fail "unknown UPKEEPER_PRECONTACT_TEST_GROUP=${UPKEEPER_PRECONTACT_TEST_GROUP}"
    ;;
esac

printf 'precontact_backup_test: ok\n'
