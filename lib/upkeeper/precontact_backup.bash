# Selected-target pre-contact backups.
#
# This module owns the local backup created after shell-side target selection and
# before the selected-target block is appended to the compiled prompt.

PRECONTACT_BACKUP_LAST_REASON=""
PRECONTACT_BACKUP_RESOLVED_MODE=""
PRECONTACT_BACKUP_VALIDATED_ABS_PATH=""
PRECONTACT_BACKUP_RESOLVED_ROOT=""
RUN_PRECONTACT_BACKUP_ID=""
RUN_PRECONTACT_BACKUP_SHA256=""
RUN_PRECONTACT_BACKUP_MODE=""
RUN_PRECONTACT_BACKUP_ENCRYPTED=""
RUN_PRECONTACT_BACKUP_PROTECTED_FROM_BACKEND=""
PRECONTACT_BACKUP_SECURE_TARGET_ABS=""

precontact_backup_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

precontact_backup_enabled() {
  precontact_backup_truthy "${UPKEEPER_PRECONTACT_BACKUP_ENABLED:-1}"
}

precontact_backup_required() {
  precontact_backup_enabled && precontact_backup_truthy "${UPKEEPER_PRECONTACT_BACKUP_REQUIRED:-1}"
}

precontact_backup_allow_unsafe_plaintext() {
  precontact_backup_truthy "${UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT:-0}"
}

precontact_backup_set_reason() {
  PRECONTACT_BACKUP_LAST_REASON="$1"
  return 1
}

precontact_backup_sha256_file() {
  local path="$1"
  python3 - "$path" <<'PY'
import hashlib
import sys

path = sys.argv[1]
digest = hashlib.sha256()
with open(path, "rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
}

precontact_backup_sha256_text() {
  local value="$1"
  python3 - "$value" <<'PY'
import hashlib
import sys

print(hashlib.sha256(sys.argv[1].encode("utf-8", "surrogateescape")).hexdigest())
PY
}

precontact_backup_hmac_text() {
  local namespace="$1"
  local value="$2"
  local key

  if declare -F upkeeper_hmac_sha256_text >/dev/null 2>&1; then
    upkeeper_hmac_sha256_text "precontact_backup.$namespace" "$value"
    return 0
  fi

  key="${UPKEEPER_REDACTION_KEY:-precontact-backup-test-key}"
  python3 - "$key" "precontact_backup.$namespace" "$value" <<'PY' 2>/dev/null || printf 'unknown'
import hashlib
import hmac
import sys

key, namespace, value = sys.argv[1:4]
material = f"{namespace}\0{value}".encode("utf-8", "surrogateescape")
print(hmac.new(key.encode("utf-8", "surrogateescape"), material, hashlib.sha256).hexdigest())
PY
}

precontact_backup_path_hmac() {
  local value="$1"

  printf 'path-hmac-sha256:%s' "$(precontact_backup_hmac_text path "$value")"
}

precontact_backup_content_hmac() {
  local value="$1"

  printf 'content-hmac-sha256:%s' "$(precontact_backup_hmac_text content "$value")"
}

precontact_backup_realpath() {
  local path="$1"
  python3 - "$path" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
}

precontact_backup_file_metadata() {
  local path="$1"

  # Keep the backup sidecar's four filesystem fields in one stat call.  Aside
  # from avoiding inconsistent observations of a concurrently changed file,
  # this avoids three extra Python launches for every backup.
  python3 - "$path" <<'PY' 2>/dev/null || printf 'unknown\tunknown\tunknown\tunknown\n'
from datetime import datetime, timezone
from pathlib import Path
import stat
import sys

st = Path(sys.argv[1]).stat()
print(
    f"{st.st_size}\t{stat.S_IMODE(st.st_mode):o}\t"
    f"{datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat().replace('+00:00', 'Z')}\t"
    f"{st.st_mtime_ns}"
)
PY
}

precontact_backup_json_field() {
  local json_path="$1"
  local field="$2"
  python3 - "$json_path" "$field" <<'PY'
import json
import sys

path, field = sys.argv[1:3]
try:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
except OSError:
    raise SystemExit(1)
value = data.get(field, "")
if value is None:
    value = ""
if isinstance(value, bool):
    value = "true" if value else "false"
print(value)
PY
}

precontact_backup_content_fingerprint_field() {
  local json_path="$1"
  local value

  if value="$(precontact_backup_json_field "$json_path" "content_hmac" 2>/dev/null)" && [[ -n "$value" ]]; then
    printf '%s' "$value"
    return 0
  fi
  precontact_backup_json_field "$json_path" "content_sha256"
}

precontact_backup_selection_field() {
  local selection_file="$1"
  local key="$2"

  [[ -n "$selection_file" && -r "$selection_file" ]] || return 0
  awk -v key="$key" '
    index($0, key "=") == 1 {
      sub("^[^=]*=", "")
      print
      exit
    }
  ' "$selection_file" 2>/dev/null || true
}

precontact_backup_sensitive_target_path() {
  local rel_path="$1"
  local lowered

  lowered="$(printf '%s' "$rel_path" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    .env|.env.*|*/.env|*/.env.*|*.env|*.env.*|\
    .npmrc|*/.npmrc|\
    .pypirc|*/.pypirc|\
    .netrc|*/.netrc|\
    .aws/credentials|*/.aws/credentials|\
    .kube/config|*/.kube/config|\
    kubeconfig|*/kubeconfig|\
    id_rsa|*/id_rsa|id_dsa|*/id_dsa|id_ecdsa|*/id_ecdsa|id_ed25519|*/id_ed25519|\
    *.pem|*.key|*.p12|*.pfx)
      return 0
      ;;
  esac
  return 1
}

precontact_backup_validate_plaintext_target_content() {
  local target_abs="$1"
  local rc=0

  python3 - "$target_abs" <<'PY' || rc=$?
from pathlib import Path
import sys

data = Path(sys.argv[1]).read_bytes()
markers = (
    b"-----BEGIN OPENSSH PRIVATE KEY-----",
    b"-----BEGIN RSA PRIVATE KEY-----",
    b"-----BEGIN DSA PRIVATE KEY-----",
    b"-----BEGIN EC PRIVATE KEY-----",
    b"-----BEGIN PRIVATE KEY-----",
    b"-----BEGIN PGP PRIVATE KEY BLOCK-----",
)
for marker in markers:
    if marker in data:
        raise SystemExit(2)
PY

  case "$rc" in
    0)
      return 0
      ;;
    2)
      precontact_backup_set_reason "plaintext_sensitive_content_rejected"
      return 1
      ;;
    *)
      precontact_backup_set_reason "plaintext_content_scan_failed"
      return 1
      ;;
  esac
}

precontact_backup_validate_target() {
  local rel_path="$1"
  local target_path resolved_target
  local -a parts=()

  PRECONTACT_BACKUP_VALIDATED_ABS_PATH=""

  if [[ -z "$rel_path" ]]; then
    precontact_backup_set_reason "empty_relative_path"
    return 1
  fi
  if [[ "$rel_path" == /* ]]; then
    precontact_backup_set_reason "absolute_path"
    return 1
  fi
  if [[ "$rel_path" == *$'\n'* ]]; then
    precontact_backup_set_reason "unsafe_relative_path"
    return 1
  fi

  local part
  IFS='/' read -r -a parts <<<"$rel_path"
  for part in "${parts[@]}"; do
    case "$part" in
      ''|.|..)
        precontact_backup_set_reason "unsafe_relative_path"
        return 1
        ;;
    esac
  done

  case "$rel_path" in
    .git|.git/*)
      precontact_backup_set_reason "git_path_rejected"
      return 1
      ;;
    runtime|runtime/*)
      precontact_backup_set_reason "runtime_path_rejected"
      return 1
      ;;
  esac
  if precontact_backup_sensitive_target_path "$rel_path"; then
    precontact_backup_set_reason "sensitive_target_rejected"
    return 1
  fi

  target_path="$ROOT_DIR/$rel_path"
  if [[ -L "$target_path" ]]; then
    precontact_backup_set_reason "symlink_target_rejected"
    return 1
  fi
  if [[ ! -e "$target_path" ]]; then
    precontact_backup_set_reason "missing_file"
    return 1
  fi
  if [[ -d "$target_path" ]]; then
    precontact_backup_set_reason "directory_target_rejected"
    return 1
  fi
  if [[ ! -f "$target_path" ]]; then
    precontact_backup_set_reason "not_regular_file"
    return 1
  fi
  if [[ ! -r "$target_path" ]]; then
    precontact_backup_set_reason "unreadable_file"
    return 1
  fi

  if ! resolved_target="$(python3 - "$ROOT_DIR" "$target_path" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
target = Path(sys.argv[2]).resolve()
try:
    target.relative_to(root)
except ValueError:
    raise SystemExit(1)
print(target)
PY
  )"; then
    precontact_backup_set_reason "target_outside_repo"
    return 1
  fi

  PRECONTACT_BACKUP_VALIDATED_ABS_PATH="$resolved_target"
  return 0
}

precontact_backup_validate_private_dir_path_components() {
  local path="$1"
  local candidate="$path"

  while [[ "$candidate" != "/" && -n "$candidate" ]]; do
    if [[ -L "$candidate" ]]; then
      precontact_backup_set_reason "backup_root_contains_symlink"
      return 1
    fi
    candidate="$(dirname -- "$candidate")"
  done
  return 0
}

precontact_backup_prepare_private_dir() {
  local path="$1"
  local owner mode

  if [[ -z "$path" ]]; then
    precontact_backup_set_reason "backup_root_empty"
    return 1
  fi
  if ! mkdir -p -- "$path"; then
    precontact_backup_set_reason "backup_root_uncreatable"
    return 1
  fi
  if ! precontact_backup_validate_private_dir_path_components "$path"; then
    return 1
  fi
  if [[ ! -d "$path" ]]; then
    precontact_backup_set_reason "backup_root_not_directory"
    return 1
  fi
  if ! chmod 700 "$path"; then
    precontact_backup_set_reason "backup_root_unsecure_permissions"
    return 1
  fi
  owner="$(stat -Lc '%u' -- "$path" 2>/dev/null || printf '')"
  if [[ "$owner" != "$(id -u)" ]]; then
    precontact_backup_set_reason "backup_root_wrong_owner"
    return 1
  fi
  mode="$(stat -Lc '%a' -- "$path" 2>/dev/null || printf '000')"
  if [[ "$mode" != "700" ]]; then
    precontact_backup_set_reason "backup_root_unsecure_permissions"
    return 1
  fi
  return 0
}

precontact_backup_validate_root() {
  local raw_root="${UPKEEPER_PRECONTACT_BACKUP_ROOT:-}"
  local repo_root="${1:-}"
  local resolved_root resolved_repo

  PRECONTACT_BACKUP_RESOLVED_ROOT=""
  if [[ -z "$raw_root" ]]; then
    precontact_backup_set_reason "backup_root_empty"
    return 1
  fi
  if [[ -z "$repo_root" ]]; then
    precontact_backup_set_reason "repo_root_required"
    return 1
  fi

  if ! resolved_root="$(precontact_backup_realpath "$raw_root")"; then
    precontact_backup_set_reason "backup_root_unresolvable"
    return 1
  fi
  if ! resolved_repo="$(precontact_backup_realpath "$repo_root")"; then
    precontact_backup_set_reason "repo_root_unresolvable"
    return 1
  fi

  if [[ "$resolved_root" == "$resolved_repo" || "$resolved_root" == "$resolved_repo"/* ]]; then
    precontact_backup_set_reason "unsafe_backup_root"
    return 1
  fi
  if ! precontact_backup_validate_private_dir_path_components "$raw_root"; then
    precontact_backup_set_reason "backup_root_contains_symlink"
    return 1
  fi
  if ! precontact_backup_prepare_private_dir "$resolved_root"; then
    return 1
  fi

  PRECONTACT_BACKUP_RESOLVED_ROOT="$resolved_root"
  return 0
}

precontact_backup_resolve_mode() {
  local mode="${UPKEEPER_PRECONTACT_BACKUP_MODE:-auto}"
  local require_encrypted="${UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED:-1}"

  PRECONTACT_BACKUP_RESOLVED_MODE=""
  mode="${mode,,}"
  if ! precontact_backup_enabled || [[ "$mode" == "off" ]]; then
    PRECONTACT_BACKUP_RESOLVED_MODE="off"
    return 0
  fi

  case "$mode" in
    auto)
      if [[ -n "${UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT:-}" ]]; then
        if command -v age >/dev/null 2>&1; then
          PRECONTACT_BACKUP_RESOLVED_MODE="age"
          return 0
        fi
        if precontact_backup_truthy "$require_encrypted"; then
          precontact_backup_set_reason "age_missing"
          return 1
        fi
      fi
      if precontact_backup_truthy "$require_encrypted"; then
        if [[ -z "${UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT:-}" ]]; then
          precontact_backup_set_reason "recipient_missing"
          return 1
        fi
        precontact_backup_set_reason "age_missing"
        return 1
      fi
      if ! precontact_backup_allow_unsafe_plaintext; then
        precontact_backup_set_reason "plaintext_override_required"
        return 1
      fi
      PRECONTACT_BACKUP_RESOLVED_MODE="plain"
      ;;
    age)
      if [[ -z "${UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT:-}" ]]; then
        precontact_backup_set_reason "recipient_missing"
        return 1
      fi
      if ! command -v age >/dev/null 2>&1; then
        precontact_backup_set_reason "age_missing"
        return 1
      fi
      PRECONTACT_BACKUP_RESOLVED_MODE="age"
      ;;
    plain)
      if precontact_backup_truthy "$require_encrypted"; then
        precontact_backup_set_reason "encrypted_required"
        return 1
      fi
      if ! precontact_backup_allow_unsafe_plaintext; then
        precontact_backup_set_reason "plaintext_override_required"
        return 1
      fi
      PRECONTACT_BACKUP_RESOLVED_MODE="plain"
      ;;
    *)
      precontact_backup_set_reason "invalid_mode"
      return 1
      ;;
  esac
}

precontact_backup_local_env_file() {
  printf '%s' "${UPKEEPER_LOCAL_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/upkeeper/local.env}"
}

precontact_backup_bootstrap_tool_path() {
  printf '%s/tools/upkeeper_precontact_bootstrap.sh' "$ROOT_DIR"
}

precontact_backup_cycle_requires_machine_preflight() {
  [[ "${UPKEEPER_DRY_RUN:-0}" != "1" ]] || return 1
  case "${CODEX_ISSUE_WORKFLOW_STAGE:-apply}" in
    comment|review)
      return 1
      ;;
  esac
  precontact_backup_required
}

precontact_backup_machine_preflight_or_exit() {
  local bootstrap_path local_env_path reason hint

  precontact_backup_cycle_requires_machine_preflight || return 0
  if precontact_backup_resolve_mode; then
    return 0
  fi

  reason="${PRECONTACT_BACKUP_LAST_REASON:-mode_unavailable}"
  bootstrap_path="$(precontact_backup_bootstrap_tool_path)"
  local_env_path="$(precontact_backup_local_env_file)"

  case "$reason" in
    recipient_missing)
      hint="run $(shell_quote "$bootstrap_path") to create an age identity and write UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT into $(shell_quote "$local_env_path")"
      ;;
    age_missing)
      hint="install age, then run $(shell_quote "$bootstrap_path") so encrypted pre-contact backup can proceed"
      ;;
    plaintext_override_required)
      hint="either configure encrypted backup through $(shell_quote "$bootstrap_path") or explicitly opt into unsafe plaintext backup in machine-local config"
      ;;
    encrypted_required)
      hint="configure an age recipient through $(shell_quote "$bootstrap_path") or explicitly relax the encrypted-backup requirement in machine-local config"
      ;;
    *)
      hint="repair the pre-contact backup machine-local configuration before rerunning live mutating cycles"
      ;;
  esac

  printf 'Upkeeper: machine health blocked live cycle before issue selection: pre-contact backup prerequisite missing (%s)\n' "$reason" >&2
  printf 'Upkeeper: %s\n' "$hint" >&2
  if [[ "$reason" == "recipient_missing" || "$reason" == "age_missing" ]]; then
    printf 'Upkeeper: expected machine-local env file: %s\n' "$local_env_path" >&2
  fi
  log_line "ERROR" "precontact_backup.preflight_blocked reason=$(shell_quote "$reason") bootstrap=$(shell_quote "$bootstrap_path") local_env_file=$(shell_quote "$local_env_path") action=$(shell_quote "$hint")"
  finish_cycle 7 PRECONTACT_BACKUP_PREREQ_MISSING ERROR "codex_exec_started=0 preflight_reason=$(shell_quote "$reason") bootstrap=$(shell_quote "$bootstrap_path") local_env_file=$(shell_quote "$local_env_path")"
}

precontact_backup_copy_file() {
  local source_path="$1"
  local dest_path="$2"
  python3 - "$source_path" "$dest_path" <<'PY'
import shutil
import sys

shutil.copy2(sys.argv[1], sys.argv[2], follow_symlinks=False)
PY
}

precontact_backup_write_metadata() {
  local output_path="$1"
  local repo_key="$2"
  local repo_root_hmac="$3"
  local rel_path="$4"
  local path_hmac="$5"
  local content_hmac="$6"
  local cycle_id="$7"
  local cycle_run_hash="$8"
  local created_utc="${9}"
  local size_bytes="${10}"
  local mode="${11}"
  local mtime="${12}"
  local selected_git_status="${13}"
  local selected_worktree_hash="${14}"
  local selection_basis="${15}"
  local backup_mode="${16}"
  local encrypted="${17}"
  local protected_from_backend="${18}"
  local derivation_sha="${19}"
  local selected_content_state="${20}"
  local selected_head_blob="${21}"
  local redact_paths="${22:-1}"
  local mtime_ns="${23:-}"

  python3 - "$output_path" \
    "$repo_key" "$repo_root_hmac" "$rel_path" "$path_hmac" \
    "$content_hmac" "$cycle_id" "$cycle_run_hash" "$created_utc" \
    "$size_bytes" "$mode" "$mtime" "$selected_git_status" \
    "$selected_worktree_hash" "$selection_basis" "$backup_mode" \
    "$encrypted" "$protected_from_backend" "$derivation_sha" \
    "$selected_content_state" "$selected_head_blob" "$redact_paths" "$mtime_ns" <<'PY'
import json
import sys

(
    output_path,
    repo_key,
    repo_root_hmac,
    rel_path,
    path_hmac,
    content_hmac,
    cycle_id,
    cycle_run_hash,
    created_utc,
    size_bytes,
    mode,
    mtime,
    selected_git_status,
    selected_worktree_hash,
    selection_basis,
    backup_mode,
    encrypted,
    protected_from_backend,
    derivation_sha,
    selected_content_state,
    selected_head_blob,
    redact_paths,
    mtime_ns,
) = sys.argv[1:25]

def maybe_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return value or "unknown"

def boolish(value):
    return str(value).lower() in {"1", "true", "yes", "on"}

protected_value = protected_from_backend
if protected_from_backend in {"0", "false", "False"}:
    protected_value = False
elif protected_from_backend in {"1", "true", "True"}:
    protected_value = True
elif not protected_from_backend:
    protected_value = "unknown"

path_redacted = backup_mode == "plain" and boolish(redact_paths)
metadata = {
    "schema_version": 3 if path_redacted else 2,
    "backup_id_derivation_sha256": derivation_sha,
    "repo_key": repo_key,
    "repo_root_hmac": repo_root_hmac,
    "relative_path_hmac": path_hmac,
    "content_hmac": content_hmac,
    "cycle_id": cycle_id,
    "cycle_run_hash": cycle_run_hash,
    "created_utc": created_utc,
    "size_bytes": maybe_int(size_bytes),
    "mode": mode or "unknown",
    "mtime": mtime or "unknown",
    "selected_git_status": selected_git_status or "unknown",
    "selected_worktree_hash": selected_worktree_hash or "unknown",
    "selection_basis": "redacted" if path_redacted else (selection_basis or "unknown"),
    "backup_mode": backup_mode,
    "encrypted": boolish(encrypted),
    "protected_from_backend": protected_value,
    "selected_content_state": selected_content_state or "unknown",
    "selected_head_blob": selected_head_blob or "unknown",
}
if backup_mode == "age":
    try:
        metadata["mtime_ns"] = int(mtime_ns)
    except (TypeError, ValueError):
        pass
if path_redacted:
    metadata["selected_relative_path_redacted"] = True
else:
    metadata["selected_relative_path"] = rel_path

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(metadata, handle, sort_keys=True, indent=2)
    handle.write("\n")
PY
}

precontact_backup_write_age_public_metadata() {
  local output_path="$1"
  local derivation_sha="$2"
  local created_utc="$3"
  local protected_from_backend="$4"

  python3 - "$output_path" "$derivation_sha" "$created_utc" "$protected_from_backend" <<'PY'
import json
import sys

output_path, derivation_sha, created_utc, protected_from_backend = sys.argv[1:5]

metadata = {
    "schema_version": 1,
    "backup_id_derivation_sha256": derivation_sha or "unknown",
    "created_utc": created_utc or "unknown",
    "backup_mode": "age",
    "encrypted": True,
    "protected_from_backend": protected_from_backend,
}

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(metadata, handle, sort_keys=True, indent=2)
    handle.write("\n")
PY
}

precontact_backup_write_payload() {
  local metadata_file="$1"
  local target_file="$2"
  local payload_file="$3"

  python3 - "$metadata_file" "$target_file" "$payload_file" <<'PY'
import sys

metadata_path, target_path, payload_path = sys.argv[1:4]
metadata = open(metadata_path, "rb").read()
with open(payload_path, "wb") as output:
    output.write(b"UPKEEPER_PRECONTACT_BACKUP_V1\n")
    output.write(str(len(metadata)).encode("ascii") + b"\n")
    output.write(metadata)
    with open(target_path, "rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            output.write(chunk)
PY
}

precontact_backup_write_payload_and_sha() {
  local metadata_file="$1"
  local target_file="$2"
  local payload_file="$3"

  python3 - "$metadata_file" "$target_file" "$payload_file" <<'PY'
import hashlib
import sys

metadata_path, target_path, payload_path = sys.argv[1:4]
digest = hashlib.sha256()

with open(metadata_path, "rb") as handle:
    metadata = handle.read()

with open(payload_path, "wb") as output:
    output.write(b"UPKEEPER_PRECONTACT_BACKUP_V1\n")
    output.write(str(len(metadata)).encode("ascii") + b"\n")
    output.write(metadata)
    with open(target_path, "rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
            output.write(chunk)

print(digest.hexdigest())
PY
}

precontact_backup_cleanup_staged_dir() {
  local staged_dir="${1:-}"

  [[ -n "$staged_dir" && -e "$staged_dir" ]] || return 0
  rm -rf -- "$staged_dir"
}

# Publish the payload and its indexing sidecar with one directory rename. Every
# file and directory sync is fail-closed so success means the complete pair has
# reached the filesystem's durability boundary.
precontact_backup_publish_directory() {
  local staged_dir="$1"
  local final_dir="$2"

  python3 - "$staged_dir" "$final_dir" <<'PY'
import os
import stat
import sys
from pathlib import Path

staged_dir = Path(sys.argv[1])
final_dir = Path(sys.argv[2])
if staged_dir.parent != final_dir.parent:
    raise SystemExit(2)
if final_dir.exists() or final_dir.is_symlink():
    raise SystemExit(3)

nofollow = getattr(os, "O_NOFOLLOW", 0)
directory = getattr(os, "O_DIRECTORY", 0)
if nofollow == 0:
    raise SystemExit(4)

staged_fd = os.open(staged_dir, os.O_RDONLY | directory | nofollow)
parent_fd = None
try:
    entries = sorted(os.listdir(staged_fd))
    backup_id = final_dir.name
    expected_json = f"{backup_id}.json"
    expected_payloads = {f"{backup_id}.bak", f"{backup_id}.age"}
    if expected_json not in entries or len(expected_payloads.intersection(entries)) != 1 or len(entries) != 2:
        raise SystemExit(5)

    for entry in entries:
        file_fd = os.open(entry, os.O_RDONLY | nofollow, dir_fd=staged_fd)
        try:
            if not stat.S_ISREG(os.fstat(file_fd).st_mode):
                raise SystemExit(6)
            os.fsync(file_fd)
        finally:
            os.close(file_fd)

    os.fsync(staged_fd)
    parent_fd = os.open(staged_dir.parent, os.O_RDONLY | directory | nofollow)
    os.replace(staged_dir.name, final_dir.name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
    os.fsync(parent_fd)
finally:
    if parent_fd is not None:
        os.close(parent_fd)
    os.close(staged_fd)
PY
}

precontact_backup_extract_payload() {
  local payload_file="$1"
  local restored_file="$2"
  local metadata_file="${3:-}"

  python3 - "$payload_file" "$restored_file" "$metadata_file" <<'PY'
import sys

payload_path, restored_path, metadata_path = sys.argv[1:4]
with open(payload_path, "rb") as handle:
    magic = handle.readline()
    if magic != b"UPKEEPER_PRECONTACT_BACKUP_V1\n":
        raise SystemExit(2)
    length_line = handle.readline()
    try:
        metadata_length = int(length_line.strip())
    except ValueError:
        raise SystemExit(2)
    metadata = handle.read(metadata_length)
    if len(metadata) != metadata_length:
        raise SystemExit(2)
    if metadata_path:
        with open(metadata_path, "wb") as output:
            output.write(metadata)
    with open(restored_path, "wb") as output:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            output.write(chunk)
PY
}

precontact_backup_create_plain() {
  local target_abs="$1"
  local path_dir="$2"
  local backup_id="$3"
  local metadata_file="$4"
  local content_sha="$5"
  local staged_dir="" final_dir staged_bak staged_json copied_sha

  if ! mkdir -p -- "$path_dir"; then
    precontact_backup_set_reason "mkdir_failed"
    return 1
  fi
  chmod 700 "$path_dir" 2>/dev/null || true

  if ! staged_dir="$(mktemp -d "$path_dir/.${backup_id}.XXXXXX.staging")"; then
    precontact_backup_set_reason "staging_dir_failed"
    return 1
  fi
  final_dir="$path_dir/${backup_id}"
  staged_bak="$staged_dir/${backup_id}.bak"
  staged_json="$staged_dir/${backup_id}.json"

  if ! precontact_backup_copy_file "$target_abs" "$staged_bak"; then
    precontact_backup_cleanup_staged_dir "$staged_dir"
    precontact_backup_set_reason "copy_failed"
    return 1
  fi
  if ! copied_sha="$(precontact_backup_sha256_file "$staged_bak")"; then
    precontact_backup_cleanup_staged_dir "$staged_dir"
    precontact_backup_set_reason "copy_hash_failed"
    return 1
  fi
  if [[ "$copied_sha" != "$content_sha" ]]; then
    precontact_backup_cleanup_staged_dir "$staged_dir"
    precontact_backup_set_reason "copy_hash_mismatch"
    return 1
  fi
  if ! precontact_backup_copy_file "$metadata_file" "$staged_json"; then
    precontact_backup_cleanup_staged_dir "$staged_dir"
    precontact_backup_set_reason "metadata_copy_failed"
    return 1
  fi
  chmod 700 "$staged_dir" 2>/dev/null || true
  chmod 600 "$staged_bak" "$staged_json" 2>/dev/null || true
  if ! precontact_backup_publish_directory "$staged_dir" "$final_dir"; then
    precontact_backup_cleanup_staged_dir "$staged_dir"
    precontact_backup_set_reason "backup_publish_failed"
    return 1
  fi
  return 0
}

precontact_backup_create_age() {
  local target_abs="$1"
  local path_dir="$2"
  local backup_id="$3"
  local metadata_file="$4"
  local sidecar_file="$5"
  local staged_dir="" final_dir staged_age staged_json payload_file payload_sha expected_fingerprint actual_fingerprint

  if ! mkdir -p -- "$path_dir"; then
    precontact_backup_set_reason "mkdir_failed"
    return 1
  fi
  chmod 700 "$path_dir" 2>/dev/null || true

  if ! staged_dir="$(mktemp -d "$path_dir/.${backup_id}.XXXXXX.staging")"; then
    precontact_backup_set_reason "staging_dir_failed"
    return 1
  fi
  if ! payload_file="$(run_mktemp precontact-backup-payload)"; then
    precontact_backup_cleanup_staged_dir "$staged_dir"
    precontact_backup_set_reason "payload_temp_failed"
    return 1
  fi
  final_dir="$path_dir/${backup_id}"
  staged_age="$staged_dir/${backup_id}.age"
  staged_json="$staged_dir/${backup_id}.json"

  if ! expected_fingerprint="$(precontact_backup_content_fingerprint_field "$metadata_file")"; then
    rm -f -- "$payload_file"
    precontact_backup_cleanup_staged_dir "$staged_dir"
    precontact_backup_set_reason "metadata_read_failed"
    return 1
  fi
  if ! payload_sha="$(precontact_backup_write_payload_and_sha "$metadata_file" "$target_abs" "$payload_file")"; then
    rm -f -- "$payload_file"
    precontact_backup_cleanup_staged_dir "$staged_dir"
    precontact_backup_set_reason "payload_write_failed"
    return 1
  fi
  case "$expected_fingerprint" in
    content-hmac-sha256:*)
      actual_fingerprint="$(precontact_backup_content_hmac "$payload_sha")"
      ;;
    *)
      actual_fingerprint="$payload_sha"
      ;;
  esac
  if [[ "$actual_fingerprint" != "$expected_fingerprint" ]]; then
    rm -f -- "$payload_file"
    precontact_backup_cleanup_staged_dir "$staged_dir"
    precontact_backup_set_reason "payload_hash_mismatch"
    return 1
  fi
  if ! age --encrypt --recipient "$UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT" --output "$staged_age" <"$payload_file"; then
    rm -f -- "$payload_file"
    precontact_backup_cleanup_staged_dir "$staged_dir"
    precontact_backup_set_reason "age_failed"
    return 1
  fi
  rm -f -- "$payload_file"
  if [[ ! -s "$staged_age" ]]; then
    precontact_backup_cleanup_staged_dir "$staged_dir"
    precontact_backup_set_reason "age_empty_artifact"
    return 1
  fi
  if ! precontact_backup_copy_file "$sidecar_file" "$staged_json"; then
    precontact_backup_cleanup_staged_dir "$staged_dir"
    precontact_backup_set_reason "metadata_copy_failed"
    return 1
  fi
  chmod 700 "$staged_dir" 2>/dev/null || true
  chmod 600 "$staged_age" "$staged_json" 2>/dev/null || true
  if ! precontact_backup_publish_directory "$staged_dir" "$final_dir"; then
    precontact_backup_cleanup_staged_dir "$staged_dir"
    precontact_backup_set_reason "backup_publish_failed"
    return 1
  fi
  return 0
}

precontact_backup_prune_for_path() {
  local path_dir="$1"
  local keep="${UPKEEPER_PRECONTACT_BACKUP_KEEP_PER_FILE:-20}"
  local pruned_count

  if [[ ! "$keep" =~ ^[0-9]+$ || "$keep" -lt 1 ]]; then
    log_line "WARN" "precontact_backup.prune_skip reason=invalid_keep keep=$(shell_quote "$keep") path_redacted=1"
    return 0
  fi

  pruned_count="$(
    python3 - "$path_dir" "$keep" <<'PY'
import json
from pathlib import Path
import shutil
import sys

path_dir = Path(sys.argv[1])
keep = int(sys.argv[2])
rows = []
try:
    entries = list(path_dir.iterdir())
except OSError:
    print(0)
    raise SystemExit(0)

for entry in entries:
    if entry.name.startswith("."):
        continue
    backup_id = ""
    sidecar = None
    layout = ""
    if entry.is_dir():
        backup_id = entry.name
        sidecar = entry / f"{backup_id}.json"
        if not sidecar.is_file():
            continue
        layout = "dir"
    elif entry.is_file() and entry.suffix == ".json":
        backup_id = entry.stem
        sidecar = entry
        layout = "flat"
    else:
        continue
    try:
        with sidecar.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        continue
    rows.append((data.get("created_utc", ""), backup_id, sidecar, layout))

deleted = 0
for _, backup_id, sidecar, layout in sorted(rows)[:-keep]:
    if layout == "dir":
        container = sidecar.parent
        removed = 0
        for suffix in (".json", ".bak", ".age"):
            candidate = container / f"{backup_id}{suffix}"
            if candidate.is_file():
                removed += 1
        try:
            shutil.rmtree(container)
            deleted += removed or 1
        except OSError:
            pass
        continue
    for suffix in (".json", ".bak", ".age"):
        candidate = path_dir / f"{backup_id}{suffix}"
        try:
            if candidate.is_file():
                candidate.unlink()
                deleted += 1
        except OSError:
            pass
print(deleted)
PY
  )"

  if [[ "${pruned_count:-0}" != "0" ]]; then
    log_line "INFO" "precontact_backup.pruned count=${pruned_count:-0} keep=$keep path_redacted=1"
  fi
}

precontact_backup_fail_or_continue() {
  local rel_path="$1"
  local reason="$2"
  local unavailable="${3:-0}"
  local target_hmac=""

  if [[ "$unavailable" == "1" ]]; then
    log_line "ERROR" "precontact_backup.unavailable reason=$(shell_quote "$reason") required=$(precontact_backup_required && printf 1 || printf 0)"
    if precontact_backup_required; then
      finish_cycle 7 PRECONTACT_BACKUP_UNAVAILABLE ERROR "codex_exec_started=0 reason=$(shell_quote "$reason")"
    fi
  else
    target_hmac="$(precontact_backup_path_hmac "$rel_path")"
    log_line "ERROR" "precontact_backup.failed target_hmac=$target_hmac reason=$(shell_quote "$reason") path_redacted=1"
    if precontact_backup_required; then
      finish_cycle 7 PRECONTACT_BACKUP_FAILED ERROR "codex_exec_started=0 target_hmac=$target_hmac reason=$(shell_quote "$reason") path_redacted=1"
    fi
  fi
  return 0
}

precontact_backup_selected_target_or_exit() {
  local rel_path="$1"
  local selection_file="${2:-}"
  local resolved_mode target_abs content_sha content_hmac path_hmac path_key repo_real repo_hmac repo_key path_dir
  local created_utc compact_utc derivation_sha backup_id metadata_file size_bytes file_metadata
  local sidecar_file
  local mode_text mtime_text mtime_ns_text selected_git_status selected_worktree_hash
  local selection_basis selected_content_state selected_head_blob encrypted protected

  RUN_PRECONTACT_BACKUP_ID=""
  RUN_PRECONTACT_BACKUP_SHA256=""
  RUN_PRECONTACT_BACKUP_MODE=""
  RUN_PRECONTACT_BACKUP_ENCRYPTED=""
  RUN_PRECONTACT_BACKUP_PROTECTED_FROM_BACKEND=""

  if ! precontact_backup_validate_target "$rel_path"; then
    precontact_backup_fail_or_continue "$rel_path" "${PRECONTACT_BACKUP_LAST_REASON:-target_validation_failed}" 0
    return 0
  fi

  if ! precontact_backup_resolve_mode; then
    precontact_backup_fail_or_continue "$rel_path" "${PRECONTACT_BACKUP_LAST_REASON:-mode_unavailable}" 1
    return 0
  fi
  resolved_mode="$PRECONTACT_BACKUP_RESOLVED_MODE"
  if [[ "$resolved_mode" == "off" ]]; then
    log_line "INFO" "precontact_backup.skip reason=disabled required=$(precontact_backup_required && printf 1 || printf 0)"
    return 0
  fi
  if ! precontact_backup_validate_root "$ROOT_DIR"; then
    precontact_backup_fail_or_continue "$rel_path" "${PRECONTACT_BACKUP_LAST_REASON:-backup_root_invalid}" 0
    return 0
  fi

  target_abs="$PRECONTACT_BACKUP_VALIDATED_ABS_PATH"
  if ! content_sha="$(precontact_backup_sha256_file "$target_abs")"; then
    precontact_backup_fail_or_continue "$rel_path" "target_hash_failed" 0
    return 0
  fi
  if [[ "$resolved_mode" == "plain" ]] && ! precontact_backup_validate_plaintext_target_content "$target_abs"; then
    precontact_backup_fail_or_continue "$rel_path" "${PRECONTACT_BACKUP_LAST_REASON:-plaintext_content_rejected}" 0
    return 0
  fi
  content_hmac="$(precontact_backup_content_hmac "$content_sha")"
  path_key="$(precontact_backup_hmac_text path "$rel_path")"
  path_hmac="path-hmac-sha256:$path_key"
  repo_real="$(precontact_backup_realpath "$ROOT_DIR")"
  repo_hmac="$(precontact_backup_hmac_text repo "$repo_real")"
  repo_key="repo-hmac-$repo_hmac"
  created_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  compact_utc="$(date -u '+%Y%m%dT%H%M%SZ')"
  derivation_sha="$(precontact_backup_sha256_text "$content_hmac|$path_hmac|$CYCLE_ID|$CYCLE_RUN_HASH|$created_utc")"
  backup_id="pb-${compact_utc}-${derivation_sha:0:32}"
  path_dir="$PRECONTACT_BACKUP_RESOLVED_ROOT/$repo_key/path-hmac-$path_key"

  if ! mkdir -p -- "$PRECONTACT_BACKUP_RESOLVED_ROOT/$repo_key" "$path_dir"; then
    precontact_backup_fail_or_continue "$rel_path" "mkdir_failed" 0
    return 0
  fi
  chmod 700 "$PRECONTACT_BACKUP_RESOLVED_ROOT" "$PRECONTACT_BACKUP_RESOLVED_ROOT/$repo_key" "$path_dir" 2>/dev/null || true

  file_metadata="$(precontact_backup_file_metadata "$target_abs")"
  IFS=$'\t' read -r size_bytes mode_text mtime_text mtime_ns_text <<<"$file_metadata"
  selected_git_status="$(precontact_backup_selection_field "$selection_file" "git_status")"
  selected_worktree_hash="$(precontact_backup_selection_field "$selection_file" "worktree_hash")"
  selection_basis="$(precontact_backup_selection_field "$selection_file" "selection_basis")"
  selected_content_state="$(precontact_backup_selection_field "$selection_file" "content_state")"
  selected_head_blob="$(precontact_backup_selection_field "$selection_file" "head_blob")"

  if [[ "$resolved_mode" == "age" ]]; then
    encrypted="true"
    protected="unknown"
  else
    encrypted="false"
    protected="false"
  fi

  if ! metadata_file="$(run_mktemp precontact-backup-metadata)"; then
    precontact_backup_fail_or_continue "$rel_path" "metadata_temp_failed" 0
    return 0
  fi
  if ! precontact_backup_write_metadata "$metadata_file" "$repo_key" "repo-hmac-sha256:$repo_hmac" \
    "$rel_path" "$path_hmac" "$content_hmac" "$CYCLE_ID" "$CYCLE_RUN_HASH" \
    "$created_utc" "$size_bytes" "$mode_text" "$mtime_text" "$selected_git_status" \
    "$selected_worktree_hash" "$selection_basis" "$resolved_mode" "$encrypted" \
    "$protected" "$derivation_sha" "$selected_content_state" "$selected_head_blob" \
    "${UPKEEPER_PRECONTACT_BACKUP_REDACT_PATHS:-1}" "$mtime_ns_text"; then
    precontact_backup_fail_or_continue "$rel_path" "metadata_write_failed" 0
    return 0
  fi

  case "$resolved_mode" in
    age)
      if ! sidecar_file="$(run_mktemp precontact-backup-age-sidecar)"; then
        precontact_backup_fail_or_continue "$rel_path" "sidecar_temp_failed" 0
        return 0
      fi
      if ! precontact_backup_write_age_public_metadata "$sidecar_file" "$derivation_sha" "$created_utc" "$protected"; then
        rm -f -- "$sidecar_file"
        precontact_backup_fail_or_continue "$rel_path" "sidecar_write_failed" 0
        return 0
      fi
      if ! precontact_backup_create_age "$target_abs" "$path_dir" "$backup_id" "$metadata_file" "$sidecar_file"; then
        rm -f -- "$sidecar_file"
        precontact_backup_fail_or_continue "$rel_path" "${PRECONTACT_BACKUP_LAST_REASON:-age_create_failed}" 0
        return 0
      fi
      rm -f -- "$sidecar_file"
      ;;
    plain)
      if ! precontact_backup_create_plain "$target_abs" "$path_dir" "$backup_id" "$metadata_file" "$content_sha"; then
        precontact_backup_fail_or_continue "$rel_path" "${PRECONTACT_BACKUP_LAST_REASON:-plain_create_failed}" 0
        return 0
      fi
      ;;
    *)
      precontact_backup_fail_or_continue "$rel_path" "invalid_resolved_mode" 0
      return 0
      ;;
  esac

  RUN_PRECONTACT_BACKUP_ID="$backup_id"
  RUN_PRECONTACT_BACKUP_SHA256="$content_sha"
  RUN_PRECONTACT_BACKUP_MODE="$resolved_mode"
  RUN_PRECONTACT_BACKUP_ENCRYPTED=$([[ "$encrypted" == "true" ]] && printf 1 || printf 0)
  if [[ "$protected" == "true" ]]; then
    RUN_PRECONTACT_BACKUP_PROTECTED_FROM_BACKEND="1"
  elif [[ "$protected" == "false" ]]; then
    RUN_PRECONTACT_BACKUP_PROTECTED_FROM_BACKEND="0"
  else
    RUN_PRECONTACT_BACKUP_PROTECTED_FROM_BACKEND="unknown"
  fi

  log_line "INFO" "precontact_backup.created target_hmac=$path_hmac backup_status=created mode=$resolved_mode encrypted=$RUN_PRECONTACT_BACKUP_ENCRYPTED protected_from_backend=$RUN_PRECONTACT_BACKUP_PROTECTED_FROM_BACKEND path_redacted=1"
  precontact_backup_prune_for_path "$path_dir"
}

precontact_backup_find_sidecar_by_id() {
  local backup_id="$1"
  local vault_root="$2"

  [[ -d "$vault_root" ]] || return 0
  find "$vault_root" -type f -name "${backup_id}.json" -print0 2>/dev/null
}

precontact_backup_restore_log() {
  local level="$1"
  shift
  if declare -F log_line >/dev/null 2>&1; then
    log_line "$level" "$*"
  else
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$level" "$*" >&2
  fi
}

precontact_backup_secure_install_restored_file() {
  local repo_root="$1"
  local rel_path="$2"
  local override_path="${3:-}"
  local tmp_restore="$4"
  local mode="${5:-}"
  local mtime_ns="${6:-}"
  local result status reason target_abs

  PRECONTACT_BACKUP_SECURE_TARGET_ABS=""

  if ! result="$(
    python3 - "$repo_root" "$rel_path" "$override_path" "$tmp_restore" "$mode" "$mtime_ns" <<'PY'
import errno
import os
import re
import stat
import sys
from pathlib import Path

repo_root, rel_path, override_path, tmp_restore, mode_text, mtime_ns_text = sys.argv[1:7]


def emit(status: str, reason: str = "", target_abs: str = "") -> None:
    print(f"status={status}")
    if reason:
        print(f"reason={reason}")
    if target_abs:
        print(f"target_abs={target_abs}")


candidate_text = override_path or rel_path
candidate = Path(candidate_text)
if candidate.is_absolute():
    emit("error", "absolute_path")
    raise SystemExit(0)

parts = candidate.parts
if not parts or any(part in {"", ".", ".."} for part in parts):
    emit("error", "unsafe_relative_path")
    raise SystemExit(0)
if parts[0] == ".git":
    emit("error", "git_path_rejected")
    raise SystemExit(0)
if parts[0] == "runtime":
    emit("error", "runtime_path_rejected")
    raise SystemExit(0)
if not os.path.isfile(tmp_restore):
    emit("error", "restore_temp_missing")
    raise SystemExit(0)

root = Path(repo_root).resolve()
target_abs = root.joinpath(*parts)
try:
    target_abs.relative_to(root)
except ValueError:
    emit("error", "target_outside_repo")
    raise SystemExit(0)

open_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
nofollow_flag = getattr(os, "O_NOFOLLOW", 0)
if nofollow_flag == 0:
    emit("error", "restore_nofollow_unsupported")
    raise SystemExit(0)

mode_value = None
if mode_text and re.fullmatch(r"[0-7]{3,4}", mode_text):
    mode_value = int(mode_text, 8)

mtime_ns_value = None
if mtime_ns_text:
    if not re.fullmatch(r"-?[0-9]+", mtime_ns_text):
        emit("error", "invalid_restore_mtime_ns")
        raise SystemExit(0)
    mtime_ns_value = int(mtime_ns_text)
    try:
        restored_stat = os.stat(tmp_restore, follow_symlinks=False)
        os.utime(
            tmp_restore,
            ns=(restored_stat.st_atime_ns, mtime_ns_value),
            follow_symlinks=False,
        )
    except (OSError, OverflowError, ValueError) as exc:
        emit("error", f"restore_mtime_failed:{exc.__class__.__name__}")
        raise SystemExit(0)

dir_fd = None
next_fd = None
verify_dir_fd = None
verify_next_fd = None
target_fd = None

try:
    dir_fd = os.open(root, open_flags)
    for part in parts[:-1]:
        try:
            existing_stat = os.lstat(part, dir_fd=dir_fd)
        except FileNotFoundError:
            existing_stat = None
        except OSError as exc:
            emit("error", f"restore_parent_stat_failed:{exc.__class__.__name__}")
            raise SystemExit(0)

        if existing_stat is None:
            try:
                os.mkdir(part, 0o700, dir_fd=dir_fd)
            except FileExistsError:
                pass
            except OSError as exc:
                emit("error", f"restore_parent_create_failed:{exc.__class__.__name__}")
                raise SystemExit(0)
        elif stat.S_ISLNK(existing_stat.st_mode):
            emit("error", "restore_parent_symlinked")
            raise SystemExit(0)
        elif not stat.S_ISDIR(existing_stat.st_mode):
            emit("error", "restore_parent_not_directory")
            raise SystemExit(0)

        try:
            next_fd = os.open(part, open_flags | nofollow_flag, dir_fd=dir_fd)
        except OSError as exc:
            if exc.errno == errno.ELOOP:
                emit("error", "restore_parent_symlinked")
            elif exc.errno == errno.ENOTDIR:
                emit("error", "restore_parent_not_directory")
            else:
                emit("error", f"restore_parent_open_failed:{exc.__class__.__name__}")
            raise SystemExit(0)

        os.close(dir_fd)
        dir_fd = next_fd
        next_fd = None

    final_name = parts[-1]
    try:
        target_stat = os.lstat(final_name, dir_fd=dir_fd)
    except FileNotFoundError:
        target_stat = None
    except OSError as exc:
        emit("error", f"restore_target_stat_failed:{exc.__class__.__name__}")
        raise SystemExit(0)

    if target_stat is not None:
        if stat.S_ISLNK(target_stat.st_mode):
            emit("error", "symlink_target_rejected")
            raise SystemExit(0)
        if stat.S_ISDIR(target_stat.st_mode):
            emit("error", "directory_target_rejected")
            raise SystemExit(0)

    try:
        verify_dir_fd = os.open(root, open_flags)
    except OSError as exc:
        emit("error", f"restore_parent_root_open_failed:{exc.__class__.__name__}")
        raise SystemExit(0)

    for verify_part in parts[:-1]:
        try:
            verify_stat = os.lstat(verify_part, dir_fd=verify_dir_fd)
        except FileNotFoundError:
            emit("error", "restore_parent_disappeared")
            raise SystemExit(0)
        except OSError as exc:
            emit("error", f"restore_parent_recheck_failed:{exc.__class__.__name__}")
            raise SystemExit(0)

        if stat.S_ISLNK(verify_stat.st_mode):
            emit("error", "restore_parent_symlinked")
            raise SystemExit(0)
        if not stat.S_ISDIR(verify_stat.st_mode):
            emit("error", "restore_parent_not_directory")
            raise SystemExit(0)

        try:
            verify_next_fd = os.open(verify_part, open_flags | nofollow_flag, dir_fd=verify_dir_fd)
        except OSError as exc:
            if exc.errno == errno.ELOOP:
                emit("error", "restore_parent_symlinked")
            elif exc.errno == errno.ENOTDIR:
                emit("error", "restore_parent_not_directory")
            else:
                emit("error", f"restore_parent_reopen_failed:{exc.__class__.__name__}")
            raise SystemExit(0)

        os.close(verify_dir_fd)
        verify_dir_fd = verify_next_fd
        verify_next_fd = None

    if (os.fstat(dir_fd).st_dev, os.fstat(dir_fd).st_ino) != (os.fstat(verify_dir_fd).st_dev, os.fstat(verify_dir_fd).st_ino):
        emit("error", "restore_parent_race_detected")
        raise SystemExit(0)

    os.close(dir_fd)
    dir_fd = verify_dir_fd
    verify_dir_fd = None
    verify_next_fd = None

    os.replace(tmp_restore, final_name, dst_dir_fd=dir_fd)

    if mode_value is not None:
        try:
            target_fd = os.open(final_name, os.O_RDONLY | nofollow_flag, dir_fd=dir_fd)
            os.fchmod(target_fd, mode_value)
        except OSError:
            pass
        finally:
            if target_fd is not None:
                os.close(target_fd)
                target_fd = None

    emit("ok", target_abs=str(target_abs))
finally:
    if target_fd is not None:
        os.close(target_fd)
    if next_fd is not None:
        os.close(next_fd)
    if verify_next_fd is not None:
        os.close(verify_next_fd)
    if verify_dir_fd is not None:
        os.close(verify_dir_fd)
    if dir_fd is not None:
        os.close(dir_fd)
PY
  )"; then
    precontact_backup_set_reason "restore_secure_install_failed"
    return 1
  fi

  status="$(awk -F= 'index($0, "status=") == 1 { print substr($0, 8); exit }' <<<"$result")"
  reason="$(awk -F= 'index($0, "reason=") == 1 { print substr($0, 8); exit }' <<<"$result")"
  target_abs="$(awk -F= 'index($0, "target_abs=") == 1 { print substr($0, 12); exit }' <<<"$result")"
  if [[ "$status" != "ok" || -z "$target_abs" ]]; then
    precontact_backup_set_reason "${reason:-unsafe_restore_destination}"
    return 1
  fi

  PRECONTACT_BACKUP_SECURE_TARGET_ABS="$target_abs"
  return 0
}

precontact_backup_validate_restore_repo_identity() {
  local metadata_path="$1"
  local repo_root="$2"
  local expected_repo_root_hmac expected_repo_key current_repo_real
  local repo_root_hmac_from_metadata repo_key_from_metadata

  repo_root_hmac_from_metadata="$(precontact_backup_json_field "$metadata_path" "repo_root_hmac")" || {
    precontact_backup_set_reason "metadata_read_failed"
    return 1
  }
  repo_key_from_metadata="$(precontact_backup_json_field "$metadata_path" "repo_key")" || {
    precontact_backup_set_reason "metadata_read_failed"
    return 1
  }
  if [[ -z "$repo_root_hmac_from_metadata" || -z "$repo_key_from_metadata" ]]; then
    precontact_backup_set_reason "metadata_read_failed"
    return 1
  fi
  if ! current_repo_real="$(precontact_backup_realpath "$repo_root")"; then
    precontact_backup_set_reason "repo_root_unresolvable"
    return 1
  fi
  expected_repo_root_hmac="repo-hmac-sha256:$(precontact_backup_hmac_text repo "$current_repo_real")"
  expected_repo_key="repo-hmac-${expected_repo_root_hmac#repo-hmac-sha256:}"
  if [[ "$repo_root_hmac_from_metadata" == "$expected_repo_root_hmac" && "$repo_key_from_metadata" == "$expected_repo_key" ]]; then
    return 0
  fi
  if [[ "${UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_RESTORE:-0}" == "1" ]]; then
    precontact_backup_restore_log "WARN" "precontact_backup.restore unsafe_cross_repo_restore blocked=0 allowed=1 reason=repo_identity_mismatch sidecar_repo_key=$(shell_quote "$repo_key_from_metadata") sidecar_repo_root_hmac=$(shell_quote "$repo_root_hmac_from_metadata") current_repo_key=$(shell_quote "$expected_repo_key") current_repo_root_hmac=$(shell_quote "$expected_repo_root_hmac")"
    return 0
  fi
  precontact_backup_restore_log "WARN" "precontact_backup.restore blocked=1 allowed=0 reason=repo_identity_mismatch sidecar_repo_key=$(shell_quote "$repo_key_from_metadata") sidecar_repo_root_hmac=$(shell_quote "$repo_root_hmac_from_metadata") current_repo_key=$(shell_quote "$expected_repo_key") current_repo_root_hmac=$(shell_quote "$expected_repo_root_hmac")"
  precontact_backup_set_reason "restore_repo_identity_mismatch"
}

precontact_backup_restore_by_id() {
  local backup_id="$1"
  local repo_root="$2"
  local identity_path="${3:-${UPKEEPER_PRECONTACT_BACKUP_AGE_IDENTITY:-}}"
  local restore_to="${4:-}"
  local vault_root sidecar rel_path content_fingerprint encrypted mode mtime_ns=""
  local -a sidecars=()
  local target_abs tmp_restore="" artifact payload_tmp="" payload_metadata="" restored_sha
  local restore_tmp_dir=""
  local restore_tmp_dir_is_temp=0

  if [[ -z "$repo_root" ]]; then
    precontact_backup_set_reason "repo_root_required"
    return 1
  fi
  if [[ ! "$backup_id" =~ ^[A-Za-z0-9_.:-]+$ || "$backup_id" == *"/"* ]]; then
    precontact_backup_set_reason "unsafe_backup_id"
    return 1
  fi

  if ! precontact_backup_validate_root "$repo_root"; then
    return 1
  fi
  vault_root="$PRECONTACT_BACKUP_RESOLVED_ROOT"

  mapfile -d '' -t sidecars < <(precontact_backup_find_sidecar_by_id "$backup_id" "$vault_root")
  if [[ "${#sidecars[@]}" -ne 1 ]]; then
    precontact_backup_set_reason "backup_id_not_unique_or_missing"
    return 1
  fi
  sidecar="${sidecars[0]}"

  if ! encrypted="$(precontact_backup_json_field "$sidecar" "encrypted")"; then
    precontact_backup_set_reason "metadata_read_failed"
    return 1
  fi
  if [[ "$encrypted" == "true" ]]; then
    :
  else
    if ! precontact_backup_validate_restore_repo_identity "$sidecar" "$repo_root"; then
      return 1
    fi
    rel_path="$(precontact_backup_json_field "$sidecar" "selected_relative_path")" || rel_path=""
    if [[ -z "$rel_path" ]]; then
      if [[ -z "$restore_to" ]]; then
        precontact_backup_set_reason "restore_path_redacted_requires_override"
        return 1
      fi
      rel_path="$restore_to"
    fi
    if ! content_fingerprint="$(precontact_backup_content_fingerprint_field "$sidecar")"; then
      precontact_backup_set_reason "metadata_read_failed"
      return 1
    fi
    mode="$(precontact_backup_json_field "$sidecar" "mode")" || mode=""
  fi

  if [[ -z "$RUN_TMP_DIR" ]] && declare -F ensure_run_tmp_dir >/dev/null; then
    if ! ensure_run_tmp_dir; then
      precontact_backup_set_reason "restore_tmp_init_failed"
      return 1
    fi
  fi
  trap 'trap - RETURN; precontact_backup_restore_cleanup_tmp "${tmp_restore-}" "${payload_tmp-}" "${payload_metadata-}" "${restore_tmp_dir-}" "${restore_tmp_dir_is_temp-0}"' RETURN
  restore_tmp_dir="${RUN_TMP_DIR:-}"
  if [[ -z "$restore_tmp_dir" ]]; then
    if ! restore_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-restore-XXXXXX")"; then
      precontact_backup_set_reason "restore_tmp_init_failed"
      return 1
    fi
    restore_tmp_dir_is_temp=1
  fi
  if [[ ! -d "$restore_tmp_dir" || -L "$restore_tmp_dir" ]]; then
    [[ "$restore_tmp_dir_is_temp" == "1" ]] && rm -rf -- "$restore_tmp_dir"
    precontact_backup_set_reason "restore_tmp_invalid_permissions"
    return 1
  fi
  if [[ "$(stat -Lc '%u' -- "$restore_tmp_dir" 2>/dev/null || printf '')" != "$(id -u)" ]]; then
    [[ "$restore_tmp_dir_is_temp" == "1" ]] && rm -rf -- "$restore_tmp_dir"
    precontact_backup_set_reason "restore_tmp_invalid_permissions"
    return 1
  fi
  if [[ "$(stat -Lc '%a' -- "$restore_tmp_dir" 2>/dev/null || printf '000')" != "700" ]]; then
    [[ "$restore_tmp_dir_is_temp" == "1" ]] && rm -rf -- "$restore_tmp_dir"
    precontact_backup_set_reason "restore_tmp_invalid_permissions"
    return 1
  fi

  if ! tmp_restore="$(mktemp "${restore_tmp_dir}/.upkeeper-restore.XXXXXX")"; then
    precontact_backup_set_reason "restore_temp_failed"
    return 1
  fi

  if [[ "$encrypted" == "true" ]]; then
    artifact="$(dirname -- "$sidecar")/${backup_id}.age"
    [[ -s "$artifact" ]] || {
      precontact_backup_set_reason "age_artifact_missing"
      return 1
    }
    [[ -n "$identity_path" ]] || {
      precontact_backup_set_reason "age_identity_required"
      return 1
    }
    [[ -r "$identity_path" ]] || {
      precontact_backup_set_reason "age_identity_unreadable"
      return 1
    }
    if ! payload_tmp="$(run_mktemp precontact-restore-payload)"; then
      precontact_backup_set_reason "restore_payload_temp_failed"
      return 1
    fi
    if ! age --decrypt --identity "$identity_path" --output "$payload_tmp" "$artifact"; then
      precontact_backup_set_reason "age_decrypt_failed"
      return 1
    fi
    if ! payload_metadata="$(run_mktemp precontact-restore-metadata)"; then
      precontact_backup_set_reason "restore_metadata_temp_failed"
      return 1
    fi
    if ! precontact_backup_extract_payload "$payload_tmp" "$tmp_restore" "$payload_metadata"; then
      precontact_backup_set_reason "payload_extract_failed"
      return 1
    fi
    if ! precontact_backup_validate_restore_repo_identity "$payload_metadata" "$repo_root"; then
      return 1
    fi
    if ! rel_path="$(precontact_backup_json_field "$payload_metadata" "selected_relative_path")"; then
      precontact_backup_set_reason "metadata_read_failed"
      return 1
    fi
    if ! content_fingerprint="$(precontact_backup_content_fingerprint_field "$payload_metadata")"; then
      precontact_backup_set_reason "metadata_read_failed"
      return 1
    fi
    if ! mode="$(precontact_backup_json_field "$payload_metadata" "mode")"; then
      precontact_backup_set_reason "metadata_read_failed"
      return 1
    fi
    mtime_ns="$(precontact_backup_json_field "$payload_metadata" "mtime_ns")" || mtime_ns=""
  else
    artifact="$(dirname -- "$sidecar")/${backup_id}.bak"
    [[ -s "$artifact" ]] || {
      precontact_backup_set_reason "plain_artifact_missing"
      return 1
    }
    if ! precontact_backup_copy_file "$artifact" "$tmp_restore"; then
      precontact_backup_set_reason "restore_copy_failed"
      return 1
    fi
  fi

  restored_sha="$(precontact_backup_sha256_file "$tmp_restore")" || {
    precontact_backup_set_reason "restore_hash_failed"
    return 1
  }
  case "$content_fingerprint" in
    content-hmac-sha256:*)
      if [[ "$(precontact_backup_content_hmac "$restored_sha")" != "$content_fingerprint" ]]; then
        precontact_backup_set_reason "restore_hash_mismatch"
        return 1
      fi
      ;;
    *)
      if [[ "$restored_sha" != "$content_fingerprint" ]]; then
        precontact_backup_set_reason "restore_hash_mismatch"
        return 1
      fi
      ;;
  esac
  if ! precontact_backup_secure_install_restored_file "$repo_root" "$rel_path" "$restore_to" "$tmp_restore" "$mode" "$mtime_ns"; then
    return 1
  fi
  target_abs="$PRECONTACT_BACKUP_SECURE_TARGET_ABS"
  precontact_backup_restore_log "INFO" "precontact_backup.restore target_hmac=$(precontact_backup_path_hmac "$rel_path") path_redacted=1"
}

precontact_backup_restore_cleanup_tmp() {
  local tmp_restore="$1"
  local payload_tmp="$2"
  local payload_metadata="$3"
  local restore_tmp_dir="$4"
  local restore_tmp_dir_is_temp="$5"

  [[ -n "${tmp_restore:-}" ]] && rm -f -- "$tmp_restore"
  [[ -n "${payload_tmp:-}" ]] && rm -f -- "$payload_tmp"
  [[ -n "${payload_metadata:-}" ]] && rm -f -- "$payload_metadata"
  if [[ "$restore_tmp_dir_is_temp" == "1" && -n "$restore_tmp_dir" ]]; then
    rm -rf -- "$restore_tmp_dir"
  fi
}
