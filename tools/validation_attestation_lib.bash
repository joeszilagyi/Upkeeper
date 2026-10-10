#!/usr/bin/env bash

# Validation-phase attestations are deliberately checkout-local proof, not a
# cache.  A consumer accepts one only when its exact command set, complete
# tracked worktree inputs, toolchain identity, and environment still match.

UPKEEPER_VALIDATION_ATTESTATION_REASON="not_requested"

upkeeper_validation_environment_class() {
  if [[ -n "${CI:-}" ]]; then
    printf 'ci\n'
  else
    printf 'local\n'
  fi
}

upkeeper_validation_attestation_snapshot() {
  local root_dir="$1"

  python3 - "$root_dir" "$(upkeeper_validation_environment_class)" <<'PY'
import hashlib
import json
import os
import subprocess
import sys

root, environment = sys.argv[1:]

def git(*args):
    return subprocess.check_output(["git", "-C", root, *args])

def version(command):
    try:
        output = subprocess.check_output(command, stderr=subprocess.STDOUT, text=True)
    except (OSError, subprocess.CalledProcessError):
        return "unavailable"
    return next((line.strip() for line in output.splitlines() if line.strip()), "unknown")

rows = []
paths = []
for raw_path in git("ls-files", "-z").split(b"\0"):
    if raw_path:
        paths.append((raw_path, True))
for raw_path in git("ls-files", "--others", "--exclude-standard", "-z").split(b"\0"):
    if raw_path:
        paths.append((raw_path, False))
for raw_path, tracked in sorted(paths):
    path = raw_path.decode("utf-8", "surrogateescape")
    full_path = os.path.join(root, path)
    row = {"path": path, "tracked": tracked}
    try:
        mode = os.lstat(full_path).st_mode
        if os.path.islink(full_path):
            payload = os.readlink(full_path).encode("utf-8", "surrogateescape")
            row["kind"] = "symlink"
        elif os.path.isfile(full_path):
            with open(full_path, "rb") as handle:
                payload = handle.read()
            row["kind"] = "file"
        else:
            payload = b""
            row["kind"] = "unsupported"
        row["mode"] = format(mode & 0o7777, "04o")
        row["sha256"] = hashlib.sha256(payload).hexdigest()
    except FileNotFoundError:
        row.update({"kind": "missing", "mode": "0000", "sha256": ""})
    rows.append(row)

canonical_rows = json.dumps(rows, sort_keys=True, separators=(",", ":")).encode()
print(json.dumps({
    "git_head": git("rev-parse", "HEAD").decode().strip(),
    "git_tree": git("rev-parse", "HEAD^{tree}").decode().strip(),
    "environment": environment,
    "input_hashes": rows,
    "worktree_fingerprint": hashlib.sha256(canonical_rows).hexdigest(),
    "tool_versions": {
        "bash": version(["bash", "--version"]),
        "git": version(["git", "--version"]),
        "jq": version(["jq", "--version"]),
        "python3": version(["python3", "--version"]),
        "timeout": version(["timeout", "--version"]),
    },
}, sort_keys=True, separators=(",", ":")))
PY
}

upkeeper_validation_attestation_write() {
  local root_dir="$1"
  local output_file="$2"
  local phase_file="$3"
  local duration_ms="$4"
  local producer_command="${5:-tools/run_validation_phases.sh}"
  local snapshot output_dir temp_file

  [[ -n "$output_file" ]] || return 0
  [[ -r "$phase_file" ]] || return 1
  snapshot="$(upkeeper_validation_attestation_snapshot "$root_dir")" || return $?
  output_dir="$(dirname -- "$output_file")"
  mkdir -p -- "$output_dir"
  chmod 700 -- "$output_dir" 2>/dev/null || true
  temp_file="$output_file.tmp.${BASHPID:-$$}"
  python3 - "$temp_file" "$snapshot" "$phase_file" "$duration_ms" "$producer_command" <<'PY'
import datetime
import json
import os
import sys

output, snapshot_json, phase_file, duration_ms, producer_command = sys.argv[1:]
snapshot = json.loads(snapshot_json)
phases = []
for line in open(phase_file, encoding="utf-8"):
    name, command, status, exit_status, elapsed_ms = line.rstrip("\n").split("\t")
    phases.append({
        "command": command,
        "duration_ms": int(elapsed_ms),
        "exit_status": int(exit_status),
        "name": name,
        "status": status,
    })
payload = {
    "command": producer_command,
    "duration_ms": int(duration_ms),
    "environment": snapshot["environment"],
    "exit_status": 0,
    "git_head": snapshot["git_head"],
    "git_tree": snapshot["git_tree"],
    "input_hashes": snapshot["input_hashes"],
    "phases": phases,
    "schema": "upkeeper.validation-attestation.v1",
    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
    "tool_versions": snapshot["tool_versions"],
    "worktree_fingerprint": snapshot["worktree_fingerprint"],
}
old_umask = os.umask(0o077)
try:
    with open(output, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, sort_keys=True, separators=(",", ":"))
        handle.write("\n")
    os.chmod(output, 0o600)
finally:
    os.umask(old_umask)
PY
  mv -f -- "$temp_file" "$output_file"
  printf 'validation_attestation: wrote=%s phases=%s\n' "$output_file" "$(wc -l <"$phase_file" | tr -d ' ')"
}

upkeeper_validation_attestation_load() {
  local root_dir="$1"
  local input_file="${2:-}"
  local phase_file="$3"
  local max_age_seconds="${UPKEEPER_VALIDATION_ATTESTATION_MAX_AGE_SECONDS:-900}"
  local expected_producer_command="${4:-tools/run_validation_phases.sh}"
  local snapshot result status reason

  UPKEEPER_VALIDATION_ATTESTATION_REASON="missing"
  [[ -n "$input_file" && -f "$input_file" && ! -L "$input_file" && -O "$input_file" && -r "$phase_file" ]] || return 1
  [[ "$max_age_seconds" =~ ^[0-9]+$ ]] || {
    UPKEEPER_VALIDATION_ATTESTATION_REASON="invalid_max_age"
    return 1
  }
  snapshot="$(upkeeper_validation_attestation_snapshot "$root_dir")" || {
    UPKEEPER_VALIDATION_ATTESTATION_REASON="snapshot_failed"
    return 1
  }
  result="$(python3 - "$input_file" "$snapshot" "$phase_file" "$max_age_seconds" "$expected_producer_command" <<'PY'
import datetime
import json
import os
import stat
import sys

artifact_path, snapshot_json, phase_file, max_age_text, expected_producer_command = sys.argv[1:]
max_age = int(max_age_text)

try:
    mode = stat.S_IMODE(os.stat(artifact_path).st_mode)
    if mode & 0o022:
        print("rejected\tunsafe_permissions")
        raise SystemExit
    artifact = json.load(open(artifact_path, encoding="utf-8"))
    snapshot = json.loads(snapshot_json)
except (OSError, ValueError, json.JSONDecodeError):
    print("rejected\tmalformed")
    raise SystemExit

expected = []
try:
    for line in open(phase_file, encoding="utf-8"):
        name, command = line.rstrip("\n").split("\t")
        expected.append({"name": name, "command": command})
except ValueError:
    print("rejected\tinvalid_expected_commands")
    raise SystemExit

required = {
    "schema": "upkeeper.validation-attestation.v1",
    "command": expected_producer_command,
    "exit_status": 0,
}
if not isinstance(artifact, dict) or any(artifact.get(k) != v for k, v in required.items()):
    print("rejected\tmetadata_mismatch")
    raise SystemExit
for field in ("git_head", "git_tree", "environment"):
    if artifact.get(field) != snapshot[field]:
        print(f"rejected\t{field}_mismatch")
        raise SystemExit
if artifact.get("tool_versions") != snapshot["tool_versions"]:
    print("rejected\ttool_versions_mismatch")
    raise SystemExit
if artifact.get("input_hashes") != snapshot["input_hashes"] or artifact.get("worktree_fingerprint") != snapshot["worktree_fingerprint"]:
    print("rejected\tinput_hashes_mismatch")
    raise SystemExit
if not isinstance(artifact.get("phases"), list) or len(artifact["phases"]) != len(expected):
    print("rejected\tphase_set_mismatch")
    raise SystemExit
for actual, wanted in zip(artifact["phases"], expected):
    if not isinstance(actual, dict) or actual.get("name") != wanted["name"] or actual.get("command") != wanted["command"]:
        print("rejected\tcommand_mismatch")
        raise SystemExit
    if actual.get("status") != "pass" or actual.get("exit_status") != 0:
        print("rejected\tphase_not_passed")
        raise SystemExit
try:
    timestamp = datetime.datetime.fromisoformat(artifact["timestamp"].replace("Z", "+00:00"))
    age = (datetime.datetime.now(datetime.timezone.utc) - timestamp).total_seconds()
except (KeyError, TypeError, ValueError):
    print("rejected\ttimestamp_malformed")
    raise SystemExit
if age < -60 or age > max_age:
    print("rejected\tstale_timestamp")
    raise SystemExit
print("valid\tsame_inputs_commands_environment_and_toolchain")
PY
)" || {
    UPKEEPER_VALIDATION_ATTESTATION_REASON="loader_failed"
    return 1
  }
  IFS=$'\t' read -r status reason <<<"$result"
  UPKEEPER_VALIDATION_ATTESTATION_REASON="$reason"
  [[ "$status" == "valid" ]]
}
