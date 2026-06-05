#!/usr/bin/env bash
set -euo pipefail

EXPECTED_RUNNER_COMMANDS_CSV="${UPKEEPER_CI_EXPECTED_RUNNER_COMMANDS:-bash timeout find awk git grep jq python3 sed zip}"
INSTALLABLE_COMMANDS_CSV="${UPKEEPER_CI_INSTALLABLE_COMMANDS:-age}"
INSTALLABLE_PACKAGES_CSV="${UPKEEPER_CI_INSTALLABLE_PACKAGES:-age}"
SUDO_BIN="${UPKEEPER_CI_SUDO_BIN:-sudo}"
APT_GET_BIN="${UPKEEPER_CI_APT_GET_BIN:-apt-get}"

usage() {
  cat <<'USAGE'
Usage: tools/setup_ci_dependencies.sh

Probe the GitHub Actions ubuntu-latest runner for stock commands, fail clearly
if expected runner tools are absent, and install only missing nonstandard
packages such as age.
USAGE
}

fail() {
  printf 'setup_ci_dependencies: ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf 'setup_ci_dependencies: %s\n' "$*"
}

now_us() {
  local now="${EPOCHREALTIME:-}"
  if [[ -n "$now" ]]; then
    printf '%s\n' "${now/./}"
    return 0
  fi
  date +%s%6N
}

parse_csv_words() {
  local input="${1:-}"
  local item trimmed
  local -a raw_items=()

  IFS=', ' read -r -a raw_items <<<"$input"
  for item in "${raw_items[@]}"; do
    trimmed="${item#"${item%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -n "$trimmed" ]] || continue
    printf '%s\n' "$trimmed"
  done
}

command_available() {
  command -v "$1" >/dev/null 2>&1
}

main() {
  local start_us end_us elapsed_us
  local missing_expected=0 missing_installable=0
  local command_name package_name index
  local -a expected_runner_commands=()
  local -a installable_commands=()
  local -a installable_packages=()
  local -a missing_expected_commands=()
  local -a missing_packages=()

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi
  [[ $# -eq 0 ]] || fail "unknown argument: $1"

  mapfile -t expected_runner_commands < <(parse_csv_words "$EXPECTED_RUNNER_COMMANDS_CSV")
  mapfile -t installable_commands < <(parse_csv_words "$INSTALLABLE_COMMANDS_CSV")
  mapfile -t installable_packages < <(parse_csv_words "$INSTALLABLE_PACKAGES_CSV")

  [[ "${#expected_runner_commands[@]}" -gt 0 ]] || fail "expected runner command list is empty"
  [[ "${#installable_commands[@]}" -eq "${#installable_packages[@]}" ]] ||
    fail "installable command/package lists must have matching lengths"

  start_us="$(now_us)"

  for command_name in "${expected_runner_commands[@]}"; do
    if ! command_available "$command_name"; then
      missing_expected_commands+=("$command_name")
      missing_expected=1
    fi
  done
  if [[ "$missing_expected" -ne 0 ]]; then
    fail "expected ubuntu-latest command(s) missing: ${missing_expected_commands[*]}; runner image drift is explicit and CI will not fall back to a blanket apt install"
  fi

  for index in "${!installable_commands[@]}"; do
    command_name="${installable_commands[$index]}"
    package_name="${installable_packages[$index]}"
    if ! command_available "$command_name"; then
      missing_packages+=("$package_name")
      missing_installable=1
    fi
  done

  if [[ "$missing_installable" -eq 0 ]]; then
    end_us="$(now_us)"
    elapsed_us=$((end_us - start_us))
    log "status=already_satisfied expected_runner_commands=${#expected_runner_commands[@]} installed_packages=0 elapsed=$((elapsed_us / 1000000)).$(((elapsed_us % 1000000) / 1000))s"
    return 0
  fi

  command_available "$SUDO_BIN" || fail "missing required privilege helper: $SUDO_BIN"
  command_available "$APT_GET_BIN" || fail "missing required package manager: $APT_GET_BIN"

  log "status=installing packages=${missing_packages[*]}"
  "$SUDO_BIN" "$APT_GET_BIN" update
  "$SUDO_BIN" "$APT_GET_BIN" install -y --no-install-recommends "${missing_packages[@]}"

  for index in "${!installable_commands[@]}"; do
    command_name="${installable_commands[$index]}"
    package_name="${installable_packages[$index]}"
    if [[ " ${missing_packages[*]} " == *" $package_name "* ]] && ! command_available "$command_name"; then
      fail "package install reported success but command is still missing: $command_name (package $package_name)"
    fi
  done

  end_us="$(now_us)"
  elapsed_us=$((end_us - start_us))
  log "status=installed packages=${missing_packages[*]} expected_runner_commands=${#expected_runner_commands[@]} elapsed=$((elapsed_us / 1000000)).$(((elapsed_us % 1000000) / 1000))s"
}

main "$@"
