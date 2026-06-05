#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upkeeper-ci-deps.XXXXXX")"
SYSTEM_PATH="$PATH"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

write_fake_tool() {
  local path="$1"
  local body="$2"
  printf '%s\n' "$body" >"$path"
  chmod +x "$path"
}

write_passthrough_tool() {
  local name="$1"
  local path="$TEST_TMP_ROOT/bin/$name"
  write_fake_tool "$path" "#!/bin/sh
exit 0"
}

setup_fake_runner() {
  mkdir -p "$TEST_TMP_ROOT/bin" "$TEST_TMP_ROOT/logs"
  : >"$TEST_TMP_ROOT/logs/apt.log"

  write_fake_tool "$TEST_TMP_ROOT/bin/sudo" "#!/bin/sh
printf '%s\n' \"\$*\" >>\"$TEST_TMP_ROOT/logs/apt.log\"
exec \"\$@\""

  write_fake_tool "$TEST_TMP_ROOT/bin/apt-get" "#!/bin/sh
printf '%s\n' \"\$*\" >>\"$TEST_TMP_ROOT/logs/apt.log\"
if [ \"\${1:-}\" = \"install\" ]; then
  cat >\"$TEST_TMP_ROOT/bin/\${FAKE_INSTALL_COMMAND_NAME}\" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x \"$TEST_TMP_ROOT/bin/\${FAKE_INSTALL_COMMAND_NAME}\"
fi"

  write_fake_tool "$TEST_TMP_ROOT/bin/bash" "#!/bin/sh
exec /bin/bash \"\$@\""
}

run_helper() {
  local stdout_file="$1"
  local stderr_file="$2"
  shift 2

  (
    export PATH="$TEST_TMP_ROOT/bin:$SYSTEM_PATH"
    export UPKEEPER_CI_EXPECTED_RUNNER_COMMANDS="$1"
    export UPKEEPER_CI_INSTALLABLE_COMMANDS="$2"
    export UPKEEPER_CI_INSTALLABLE_PACKAGES="$3"
    export FAKE_INSTALL_COMMAND_NAME="$4"
    exec /bin/bash "$PROJECT_ROOT/tools/setup_ci_dependencies.sh"
  ) >"$stdout_file" 2>"$stderr_file"
}

test_no_install_when_runner_and_installable_commands_exist() {
  local stdout_file="$TEST_TMP_ROOT/no-install.out"
  local stderr_file="$TEST_TMP_ROOT/no-install.err"

  rm -rf "$TEST_TMP_ROOT/bin" "$TEST_TMP_ROOT/logs"
  setup_fake_runner
  write_passthrough_tool runner-bash
  write_passthrough_tool runner-jq
  write_passthrough_tool age-fixture

  run_helper "$stdout_file" "$stderr_file" "runner-bash runner-jq" "age-fixture" "age-fixture" "age-fixture" ||
    fail "helper unexpectedly failed when all commands were already present"
  grep -Fq "status=already_satisfied" "$stdout_file" ||
    fail "helper did not report already_satisfied"
  [[ ! -s "$TEST_TMP_ROOT/logs/apt.log" ]] ||
    fail "helper called apt-get even though installable command was already present"
  [[ ! -s "$stderr_file" ]] || fail "helper emitted unexpected stderr for already-satisfied case"
}

test_missing_installable_command_triggers_targeted_install() {
  local stdout_file="$TEST_TMP_ROOT/install.out"
  local stderr_file="$TEST_TMP_ROOT/install.err"

  rm -rf "$TEST_TMP_ROOT/bin" "$TEST_TMP_ROOT/logs"
  setup_fake_runner
  write_passthrough_tool runner-bash
  write_passthrough_tool runner-jq

  run_helper "$stdout_file" "$stderr_file" "runner-bash runner-jq" "age-fixture" "age-fixture" "age-fixture" ||
    fail "helper unexpectedly failed when only the installable command was missing"
  grep -Fq "status=installing packages=age-fixture" "$stdout_file" ||
    fail "helper did not log the targeted install start"
  grep -Fq "status=installed packages=age-fixture" "$stdout_file" ||
    fail "helper did not log the targeted install completion"
  grep -Fq "apt-get update" "$TEST_TMP_ROOT/logs/apt.log" ||
    fail "helper did not run apt-get update for the targeted install"
  grep -Fq "apt-get install -y --no-install-recommends age-fixture" "$TEST_TMP_ROOT/logs/apt.log" ||
    fail "helper did not run the targeted age install"
  [[ ! -s "$stderr_file" ]] || fail "helper emitted unexpected stderr for targeted-install case"
}

test_missing_expected_runner_command_fails_closed() {
  local stdout_file="$TEST_TMP_ROOT/missing-runner.out"
  local stderr_file="$TEST_TMP_ROOT/missing-runner.err"

  rm -rf "$TEST_TMP_ROOT/bin" "$TEST_TMP_ROOT/logs"
  setup_fake_runner
  write_passthrough_tool runner-bash
  write_passthrough_tool age-fixture

  set +e
  run_helper "$stdout_file" "$stderr_file" "runner-bash runner-jq" "age-fixture" "age-fixture" "age-fixture"
  rc=$?
  set -e

  [[ "$rc" -ne 0 ]] || fail "helper succeeded even though an expected runner command was missing"
  grep -Fq "expected ubuntu-latest command(s) missing: runner-jq" "$stderr_file" ||
    fail "helper did not report the missing runner command clearly"
  [[ ! -s "$stdout_file" ]] || fail "helper emitted stdout before failing on missing runner command"
  [[ ! -s "$TEST_TMP_ROOT/logs/apt.log" ]] ||
    fail "helper attempted apt-get even though an expected runner command was missing"
}

test_no_install_when_runner_and_installable_commands_exist
test_missing_installable_command_triggers_targeted_install
test_missing_expected_runner_command_fails_closed

printf 'ci_dependency_setup_test: ok\n'
