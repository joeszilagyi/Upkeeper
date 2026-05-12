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

precontact_backup_realpath() {
  local path="$1"
  python3 - "$path" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).expanduser().resolve(strict=False))
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
  local require_encrypted="${UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED:-0}"

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
      PRECONTACT_BACKUP_RESOLVED_MODE="plain"
      ;;
    *)
      precontact_backup_set_reason "invalid_mode"
      return 1
      ;;
  esac
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
  local repo_root_hash="$3"
  local rel_path="$4"
  local path_sha="$5"
  local content_sha="$6"
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

  python3 - "$output_path" \
    "$repo_key" "$repo_root_hash" "$rel_path" "$path_sha" \
    "$content_sha" "$cycle_id" "$cycle_run_hash" "$created_utc" \
    "$size_bytes" "$mode" "$mtime" "$selected_git_status" \
    "$selected_worktree_hash" "$selection_basis" "$backup_mode" \
    "$encrypted" "$protected_from_backend" "$derivation_sha" \
    "$selected_content_state" "$selected_head_blob" <<'PY'
import json
import sys

(
    output_path,
    repo_key,
    repo_root_hash,
    rel_path,
    path_sha,
    content_sha,
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
) = sys.argv[1:23]

def maybe_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return value or "unknown"

def boolish(value):
    return str(value).lower() in {"1", "true", "yes"}

protected_value = protected_from_backend
if protected_from_backend in {"0", "false", "False"}:
    protected_value = False
elif protected_from_backend in {"1", "true", "True"}:
    protected_value = True
elif not protected_from_backend:
    protected_value = "unknown"

metadata = {
    "schema_version": 1,
    "backup_id_derivation_sha256": derivation_sha,
    "repo_key": repo_key,
    "repo_root_sha256": repo_root_hash,
    "selected_relative_path": rel_path,
    "relative_path_sha256": path_sha,
    "content_sha256": content_sha,
    "cycle_id": cycle_id,
    "cycle_run_hash": cycle_run_hash,
    "created_utc": created_utc,
    "size_bytes": maybe_int(size_bytes),
    "mode": mode or "unknown",
    "mtime": mtime or "unknown",
    "selected_git_status": selected_git_status or "unknown",
    "selected_worktree_hash": selected_worktree_hash or "unknown",
    "selection_basis": selection_basis or "unknown",
    "backup_mode": backup_mode,
    "encrypted": boolish(encrypted),
    "protected_from_backend": protected_value,
    "selected_content_state": selected_content_state or "unknown",
    "selected_head_blob": selected_head_blob or "unknown",
}

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
  local tmp_bak tmp_json final_bak final_json copied_sha

  if ! mkdir -p -- "$path_dir"; then
    precontact_backup_set_reason "mkdir_failed"
    return 1
  fi
  chmod 700 "$path_dir" 2>/dev/null || true

  tmp_bak="$path_dir/.${backup_id}.$$.bak.tmp"
  tmp_json="$path_dir/.${backup_id}.$$.json.tmp"
  final_bak="$path_dir/${backup_id}.bak"
  final_json="$path_dir/${backup_id}.json"
  rm -f -- "$tmp_bak" "$tmp_json"

  if ! precontact_backup_copy_file "$target_abs" "$tmp_bak"; then
    rm -f -- "$tmp_bak" "$tmp_json"
    precontact_backup_set_reason "copy_failed"
    return 1
  fi
  if ! copied_sha="$(precontact_backup_sha256_file "$tmp_bak")"; then
    rm -f -- "$tmp_bak" "$tmp_json"
    precontact_backup_set_reason "copy_hash_failed"
    return 1
  fi
  if [[ "$copied_sha" != "$content_sha" ]]; then
    rm -f -- "$tmp_bak" "$tmp_json"
    precontact_backup_set_reason "copy_hash_mismatch"
    return 1
  fi
  if ! precontact_backup_copy_file "$metadata_file" "$tmp_json"; then
    rm -f -- "$tmp_bak" "$tmp_json"
    precontact_backup_set_reason "metadata_copy_failed"
    return 1
  fi
  chmod 600 "$tmp_bak" "$tmp_json" 2>/dev/null || true
  if ! mv -- "$tmp_bak" "$final_bak"; then
    rm -f -- "$tmp_bak" "$tmp_json"
    precontact_backup_set_reason "backup_rename_failed"
    return 1
  fi
  if ! mv -- "$tmp_json" "$final_json"; then
    rm -f -- "$tmp_json"
    precontact_backup_set_reason "metadata_rename_failed"
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
  local tmp_age tmp_json final_age final_json payload_file

  if ! mkdir -p -- "$path_dir"; then
    precontact_backup_set_reason "mkdir_failed"
    return 1
  fi
  chmod 700 "$path_dir" 2>/dev/null || true

  if ! payload_file="$(run_mktemp precontact-backup-payload)"; then
    precontact_backup_set_reason "payload_temp_failed"
    return 1
  fi
  tmp_age="$path_dir/.${backup_id}.$$.age.tmp"
  tmp_json="$path_dir/.${backup_id}.$$.json.tmp"
  final_age="$path_dir/${backup_id}.age"
  final_json="$path_dir/${backup_id}.json"
  rm -f -- "$tmp_age" "$tmp_json"

  if ! precontact_backup_write_payload "$metadata_file" "$target_abs" "$payload_file"; then
    rm -f -- "$payload_file" "$tmp_age" "$tmp_json"
    precontact_backup_set_reason "payload_write_failed"
    return 1
  fi
  if ! age --encrypt --recipient "$UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT" --output "$tmp_age" <"$payload_file"; then
    rm -f -- "$payload_file" "$tmp_age" "$tmp_json"
    precontact_backup_set_reason "age_failed"
    return 1
  fi
  rm -f -- "$payload_file"
  if [[ ! -s "$tmp_age" ]]; then
    rm -f -- "$tmp_age" "$tmp_json"
    precontact_backup_set_reason "age_empty_artifact"
    return 1
  fi
  if ! precontact_backup_copy_file "$sidecar_file" "$tmp_json"; then
    rm -f -- "$tmp_age" "$tmp_json"
    precontact_backup_set_reason "metadata_copy_failed"
    return 1
  fi
  chmod 600 "$tmp_age" "$tmp_json" 2>/dev/null || true
  if ! mv -- "$tmp_age" "$final_age"; then
    rm -f -- "$tmp_age" "$tmp_json"
    precontact_backup_set_reason "backup_rename_failed"
    return 1
  fi
  if ! mv -- "$tmp_json" "$final_json"; then
    rm -f -- "$tmp_json"
    precontact_backup_set_reason "metadata_rename_failed"
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
import sys

path_dir = Path(sys.argv[1])
keep = int(sys.argv[2])
rows = []
try:
    sidecars = list(path_dir.glob("*.json"))
except OSError:
    print(0)
    raise SystemExit(0)

for sidecar in sidecars:
    try:
        with sidecar.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        continue
    if sidecar.suffix != ".json":
        continue
    backup_id = sidecar.stem
    rows.append((data.get("created_utc", ""), backup_id, sidecar))

deleted = 0
for _, backup_id, sidecar in sorted(rows)[:-keep]:
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
  local target_hash=""

  if [[ "$unavailable" == "1" ]]; then
    log_line "ERROR" "precontact_backup.unavailable reason=$(shell_quote "$reason") required=$(precontact_backup_required && printf 1 || printf 0)"
    if precontact_backup_required; then
      finish_cycle 7 PRECONTACT_BACKUP_UNAVAILABLE ERROR "codex_exec_started=0 reason=$(shell_quote "$reason")"
    fi
  else
    target_hash="$(precontact_backup_sha256_text "$rel_path")"
    log_line "ERROR" "precontact_backup.failed target_hash=$target_hash reason=$(shell_quote "$reason") path_redacted=1"
    if precontact_backup_required; then
      finish_cycle 7 PRECONTACT_BACKUP_FAILED ERROR "codex_exec_started=0 target_hash=$target_hash reason=$(shell_quote "$reason") path_redacted=1"
    fi
  fi
  return 0
}

precontact_backup_selected_target_or_exit() {
  local rel_path="$1"
  local selection_file="${2:-}"
  local resolved_mode target_abs content_sha path_sha repo_real repo_sha repo_key path_dir
  local created_utc compact_utc derivation_sha backup_id metadata_file size_bytes
  local sidecar_file
  local mode_text mtime_text selected_git_status selected_worktree_hash
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
  path_sha="$(precontact_backup_sha256_text "$rel_path")"
  repo_real="$(precontact_backup_realpath "$ROOT_DIR")"
  repo_sha="$(precontact_backup_sha256_text "$repo_real")"
  repo_key="repo-$repo_sha"
  created_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  compact_utc="$(date -u '+%Y%m%dT%H%M%SZ')"
  derivation_sha="$(precontact_backup_sha256_text "$content_sha|$path_sha|$CYCLE_ID|$CYCLE_RUN_HASH|$created_utc")"
  backup_id="pb-${compact_utc}-${derivation_sha:0:32}"
  path_dir="$PRECONTACT_BACKUP_RESOLVED_ROOT/$repo_key/path-$path_sha"

  if ! mkdir -p -- "$PRECONTACT_BACKUP_RESOLVED_ROOT/$repo_key" "$path_dir"; then
    precontact_backup_fail_or_continue "$rel_path" "mkdir_failed" 0
    return 0
  fi
  chmod 700 "$PRECONTACT_BACKUP_RESOLVED_ROOT" "$PRECONTACT_BACKUP_RESOLVED_ROOT/$repo_key" "$path_dir" 2>/dev/null || true

  size_bytes="$(file_size_bytes "$target_abs")"
  mode_text="$(python3 - "$target_abs" <<'PY' 2>/dev/null || printf 'unknown'
from pathlib import Path
import stat
import sys

st = Path(sys.argv[1]).stat()
print(oct(stat.S_IMODE(st.st_mode))[2:])
PY
  )"
  mtime_text="$(python3 - "$target_abs" <<'PY' 2>/dev/null || printf 'unknown'
from datetime import datetime, timezone
from pathlib import Path
import sys

st = Path(sys.argv[1]).stat()
print(datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat().replace("+00:00", "Z"))
PY
  )"
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
  if ! precontact_backup_write_metadata "$metadata_file" "$repo_key" "$repo_sha" \
    "$rel_path" "$path_sha" "$content_sha" "$CYCLE_ID" "$CYCLE_RUN_HASH" \
    "$created_utc" "$size_bytes" "$mode_text" "$mtime_text" "$selected_git_status" \
    "$selected_worktree_hash" "$selection_basis" "$resolved_mode" "$encrypted" \
    "$protected" "$derivation_sha" "$selected_content_state" "$selected_head_blob"; then
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

  log_line "INFO" "precontact_backup.created target_hash=$path_sha backup_status=created mode=$resolved_mode encrypted=$RUN_PRECONTACT_BACKUP_ENCRYPTED protected_from_backend=$RUN_PRECONTACT_BACKUP_PROTECTED_FROM_BACKEND path_redacted=1"
  precontact_backup_prune_for_path "$path_dir"
}

precontact_backup_find_sidecar_by_id() {
  local backup_id="$1"
  local vault_root="$2"

  [[ -d "$vault_root" ]] || return 0
  find "$vault_root" -type f -name "${backup_id}.json" -print 2>/dev/null
}

precontact_backup_validate_restore_destination() {
  local repo_root="$1"
  local rel_path="$2"
  local override_path="$3"

  python3 - "$repo_root" "$rel_path" "$override_path" <<'PY'
from pathlib import Path
import sys

repo_root, rel_path, override_path = sys.argv[1:4]
root = Path(repo_root).resolve()
candidate_text = override_path or rel_path
candidate = Path(candidate_text)
if candidate.is_absolute():
    raise SystemExit(2)
parts = candidate.parts
if not parts or any(part in {"", ".", ".."} for part in parts):
    raise SystemExit(2)
if parts[0] in {".git", "runtime"}:
    raise SystemExit(2)
resolved = (root / candidate).resolve(strict=False)
try:
    resolved.relative_to(root)
except ValueError:
    raise SystemExit(2)
if resolved.exists() and resolved.is_dir():
    raise SystemExit(3)
if resolved.is_symlink():
    raise SystemExit(4)
print(resolved)
PY
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

precontact_backup_restore_by_id() {
  local backup_id="$1"
  local repo_root="$2"
  local identity_path="${3:-${UPKEEPER_PRECONTACT_BACKUP_AGE_IDENTITY:-}}"
  local restore_to="${4:-}"
  local vault_root sidecars sidecar_count sidecar rel_path content_sha encrypted mode
  local target_abs target_dir tmp_restore="" artifact payload_tmp="" payload_metadata="" restored_sha
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

  sidecars="$(precontact_backup_find_sidecar_by_id "$backup_id" "$vault_root")"
  sidecar_count="$(printf '%s\n' "$sidecars" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$sidecar_count" != "1" ]]; then
    precontact_backup_set_reason "backup_id_not_unique_or_missing"
    return 1
  fi
  sidecar="$(printf '%s\n' "$sidecars" | sed -n '1p')"

  if ! encrypted="$(precontact_backup_json_field "$sidecar" "encrypted")"; then
    precontact_backup_set_reason "metadata_read_failed"
    return 1
  fi
  if [[ "$encrypted" == "true" ]]; then
    :
  else
    if ! rel_path="$(precontact_backup_json_field "$sidecar" "selected_relative_path")"; then
      precontact_backup_set_reason "metadata_read_failed"
      return 1
    fi
    if ! content_sha="$(precontact_backup_json_field "$sidecar" "content_sha256")"; then
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
    if ! rel_path="$(precontact_backup_json_field "$payload_metadata" "selected_relative_path")"; then
      precontact_backup_set_reason "metadata_read_failed"
      return 1
    fi
    if ! content_sha="$(precontact_backup_json_field "$payload_metadata" "content_sha256")"; then
      precontact_backup_set_reason "metadata_read_failed"
      return 1
    fi
    if ! mode="$(precontact_backup_json_field "$payload_metadata" "mode")"; then
      precontact_backup_set_reason "metadata_read_failed"
      return 1
    fi
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

  if ! target_abs="$(precontact_backup_validate_restore_destination "$repo_root" "$rel_path" "$restore_to")"; then
    precontact_backup_set_reason "unsafe_restore_destination"
    return 1
  fi
  target_dir="$(dirname -- "$target_abs")"
  if ! mkdir -p -- "$target_dir"; then
    precontact_backup_set_reason "restore_parent_mkdir_failed"
    return 1
  fi

  restored_sha="$(precontact_backup_sha256_file "$tmp_restore")" || {
    precontact_backup_set_reason "restore_hash_failed"
    return 1
  }
  if [[ "$restored_sha" != "$content_sha" ]]; then
    precontact_backup_set_reason "restore_hash_mismatch"
    return 1
  fi
  if [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
    chmod "$mode" "$tmp_restore" 2>/dev/null || true
  fi
  if ! mv -- "$tmp_restore" "$target_abs"; then
    precontact_backup_set_reason "restore_rename_failed"
    return 1
  fi
  precontact_backup_restore_log "INFO" "precontact_backup.restore target_hash=$(precontact_backup_sha256_text "$rel_path") path_redacted=1"
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
