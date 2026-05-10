#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d)"
trap 'rm -r "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_flameon_help_documents_burn_contract() {
  local help

  help="$("$ROOT_DIR/FlameOn" --help)"
  grep -Fq "Usage: FlameOn" <<<"$help" || fail "FlameOn help missing usage"
  grep -Fq "gpt-5.5 xhigh" <<<"$help" || fail "FlameOn help missing model/effort contract"
  grep -Fq "all P1-P23 passes plus P24-P29" <<<"$help" || fail "FlameOn help missing all-pass contract"
  grep -Fq "Lattice max-cover target ranking" <<<"$help" || fail "FlameOn help missing Lattice selection contract"
  grep -Fq -- "-backup_queue" <<<"$help" || fail "FlameOn help missing backup queue flag"
}

test_flameon_dry_run_resolves_upkeeper_args() {
  local output

  output="$(UPKEEPER_OBLIGATION_DIR="$TEST_TMP_ROOT/empty-obligations" FLAMEON_DRY_RUN=1 "$ROOT_DIR/FlameOn" --silent -backup_queue)"
  grep -Fq "CODEX_TERMINAL_VERBOSITY=silent" <<<"$output" || fail "dry-run missing silent verbosity"
  grep -Fq "$ROOT_DIR/Upkeeper" <<<"$output" || fail "dry-run missing central Upkeeper path"
  grep -Fq -- "--model-override=5.5_xhigh" <<<"$output" || fail "dry-run missing 5.5 xhigh override"
  grep -Fq -- "--max-cover" <<<"$output" || fail "dry-run missing max-cover flag"
  grep -Fq -- "--backup-queue" <<<"$output" || fail "dry-run missing backup queue override"
  grep -Fq "UPKEEPER_LATTICE_REQUIRED=1" <<<"$output" || fail "dry-run missing required Lattice burn default"
  grep -Fq "UPKEEPER_PRECONTACT_BACKUP_MODE=age" <<<"$output" || fail "dry-run missing age backup burn default"
  grep -Fq "UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=1" <<<"$output" || fail "dry-run missing encrypted backup requirement"
  grep -Fq "CODEX_MODE=--sandbox\\ workspace-write" <<<"$output" || fail "dry-run missing pinned workspace-write containment"
  grep -Fq "CODEX_5H_STOP_PERCENT=0" <<<"$output" || fail "dry-run missing five-hour spend-to-zero quota default"
  grep -Fq "CODEX_WEEK_STOP_PERCENT=0" <<<"$output" || fail "dry-run missing weekly spend-to-zero quota default"
  grep -Fq "CODEX_QUOTA_GUARDRAIL_BYPASS=1" <<<"$output" || fail "dry-run missing quota guardrail bypass for launcher burn"
  grep -Fq "CODEX_QUOTA_COOLDOWN_BYPASS=1" <<<"$output" || fail "dry-run missing cooldown bypass for launcher burn"
  grep -Fq "UPKEEPER_AUTOMATION_LAUNCHER=FlameOn" <<<"$output" || fail "dry-run missing FlameOn automation identity"
  grep -Fq "UPKEEPER_AUTOMATION_VARIANT=bug-finding" <<<"$output" || fail "dry-run missing FlameOn automation variant"
  grep -Fq "UPKEEPER_AUTOMATION_POLICY=max-cover-bug-report" <<<"$output" || fail "dry-run missing FlameOn automation policy"
}

write_open_obligation() {
  local obligation_dir="$1"
  mkdir -p "$obligation_dir/open"
  cat >"$obligation_dir/open/obligation-fixture.json" <<'JSON'
{
  "schema": 1,
  "record_type": "automation_obligation",
  "status": "open",
  "id": "obligation-fixture",
  "created_at": "2026-05-10T00:00:00-0700",
  "kind": "codex_session_store_unwritable",
  "severity": "high",
  "summary": "Fixture obligation takes priority over normal FlameOn burn",
  "target_file": "lib/upkeeper/session_store_preflight.bash",
  "source_cycle_id": "fixture-cycle",
  "source_run_hash": "fixture-run",
  "required_resolution": ["repair the fixture"]
}
JSON
}

test_flameon_dry_run_reconciles_obligations_first() {
  local output obligation_dir

  obligation_dir="$TEST_TMP_ROOT/flameon-obligations"
  write_open_obligation "$obligation_dir"
  output="$(UPKEEPER_OBLIGATION_DIR="$obligation_dir" FLAMEON_DRY_RUN=1 "$ROOT_DIR/FlameOn" --silent 2>&1)"
  grep -Fq "selected automation obligation obligation-fixture" <<<"$output" || fail "FlameOn did not select open automation obligation first"
  grep -Fq "UPKEEPER_AUTOMATION_WORKFLOW=obligation-repair" <<<"$output" || fail "FlameOn obligation run missing obligation workflow"
  grep -Fq "UPKEEPER_AUTOMATION_OBLIGATION_ID=obligation-fixture" <<<"$output" || fail "FlameOn obligation run missing obligation id"
  grep -Fq -- "--target-file=lib/upkeeper/session_store_preflight.bash" <<<"$output" || fail "FlameOn obligation run did not lock obligation target"
  grep -Fq -- "--prompt-file" <<<"$output" || fail "FlameOn obligation run did not pass wrapper-generated prompt file"
  if grep -Fq -- "--bug-report-only" <<<"$output"; then
    fail "FlameOn obligation run stayed in bug-report-only mode instead of repair mode"
  fi
}

test_flameon_rejects_unsupported_inputs() {
  local output rc

  set +e
  output="$(FLAMEON_DRY_RUN=1 "$ROOT_DIR/FlameOn" --verbose 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 64 ]] || fail "unknown FlameOn flag exited $rc, expected 64"
  grep -Fq "unknown argument: --verbose" <<<"$output" || fail "unknown FlameOn flag diagnostic missing"

  set +e
  output="$(FLAMEON_DRY_RUN=1 FLAMEON_VERBOSITY=verbose "$ROOT_DIR/FlameOn" 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 64 ]] || fail "unsupported FlameOn verbosity exited $rc, expected 64"
  grep -Fq "unsupported verbosity: verbose" <<<"$output" || fail "unsupported verbosity diagnostic missing"
}

test_upkeeper_max_cover_flags_parse_before_version() {
  local output version

  version="$(sed -n 's/^UPKEEPER_VERSION="\([^"]*\)"/\1/p' "$ROOT_DIR/Upkeeper")"
  output="$("$ROOT_DIR/Upkeeper" --max-cover --backup-queue --version)"
  [[ "$output" == "Upkeeper $version" ]] || fail "Upkeeper max-cover flags broke --version: $output"

  output="$("$ROOT_DIR/Upkeeper" -backup_queue --version)"
  [[ "$output" == "Upkeeper $version" ]] || fail "Upkeeper legacy backup queue flag broke --version: $output"
}

test_completion_script_loads_flameon_and_upkeeper() {
  local output

  output="$(
    source "$ROOT_DIR/completions/upkeeper.bash"
    complete -p ./Upkeeper >/dev/null
    complete -p ./FlameOn >/dev/null
    COMP_WORDS=(./FlameOn --d)
    COMP_CWORD=1
    _flameon_complete
    printf '%s\n' "${COMPREPLY[@]}"
  )"
  grep -Fxq -- "--debug1" <<<"$output" || fail "FlameOn completion did not suggest --debug1"

  output="$(
    source "$ROOT_DIR/completions/upkeeper.bash"
    COMP_WORDS=(./Upkeeper --target-d)
    COMP_CWORD=1
    _upkeeper_complete
    printf '%s\n' "${COMPREPLY[@]}"
  )"
  grep -Fxq -- "--target-dir=" <<<"$output" || fail "Upkeeper completion did not suggest --target-dir"

  output="$(
    source "$ROOT_DIR/completions/upkeeper.bash"
    COMP_WORDS=(./Upkeeper --prompt-file=)
    COMP_CWORD=1
    _upkeeper_complete
    printf '%s\n' "${COMPREPLY[@]}"
  )"
  [[ -z "$output" ]] || fail "Upkeeper completion suggested unsupported --prompt-file= form"
}

test_flameon_help_documents_burn_contract
test_flameon_dry_run_resolves_upkeeper_args
test_flameon_dry_run_reconciles_obligations_first
test_flameon_rejects_unsupported_inputs
test_upkeeper_max_cover_flags_parse_before_version
test_completion_script_loads_flameon_and_upkeeper
printf 'ok - flameon\n'
