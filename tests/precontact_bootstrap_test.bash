#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$TEST_TMP_ROOT/bin"

cat >"$TEST_TMP_ROOT/bin/age" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exit 0
SH
chmod +x "$TEST_TMP_ROOT/bin/age"

cat >"$TEST_TMP_ROOT/bin/age-keygen" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-o" ]]; then
  printf 'AGE-SECRET-KEY-1 fixture\n' >"$2"
  exit 0
fi
if [[ "${1:-}" == "-y" ]]; then
  printf 'age1fixturepublicrecipient\n'
  exit 0
fi
printf 'unexpected fake age-keygen invocation: %s\n' "$*" >&2
exit 2
SH
chmod +x "$TEST_TMP_ROOT/bin/age-keygen"

test_bootstrap_creates_private_identity_and_local_env() {
  local home_dir="$TEST_TMP_ROOT/home"
  local identity_file="$home_dir/.config/age/upkeeper.txt"
  local local_env_file="$home_dir/.config/upkeeper/local.env"
  local output

  mkdir -p "$home_dir"
  output="$(
    PATH="$TEST_TMP_ROOT/bin:$PATH" \
      HOME="$home_dir" \
      "$ROOT_DIR/tools/upkeeper_precontact_bootstrap.sh" \
      --identity-file="$identity_file" \
      --local-env-file="$local_env_file"
  )"

  [[ -s "$identity_file" ]] || fail "bootstrap did not create identity file"
  [[ -s "$local_env_file" ]] || fail "bootstrap did not create local env file"
  [[ "$(stat -Lc '%a' -- "$identity_file" 2>/dev/null || printf '')" == "600" ]] || fail "identity file mode is not 600"
  [[ "$(stat -Lc '%a' -- "$local_env_file" 2>/dev/null || printf '')" == "600" ]] || fail "local env file mode is not 600"
  grep -Fq "export UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT=age1fixturepublicrecipient" "$local_env_file" || fail "bootstrap did not write public recipient"
  grep -Fq "wrote public recipient" <<<"$output" || fail "bootstrap output did not report env file write"
}

test_bootstrap_preserves_unrelated_local_env_lines_without_duplicates() {
  local home_dir="$TEST_TMP_ROOT/home-preserve"
  local identity_file="$home_dir/.config/age/upkeeper.txt"
  local local_env_file="$home_dir/.config/upkeeper/local.env"
  local recipient_count

  mkdir -p "$(dirname -- "$local_env_file")"
  cat >"$local_env_file" <<'EOF'
# existing local setting
export KEEP_ME=1
export UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT=age1oldrecipient
EOF
  chmod 600 "$local_env_file"

  PATH="$TEST_TMP_ROOT/bin:$PATH" \
    HOME="$home_dir" \
    "$ROOT_DIR/tools/upkeeper_precontact_bootstrap.sh" \
    --identity-file="$identity_file" \
    --local-env-file="$local_env_file" >/dev/null

  grep -Fq "export KEEP_ME=1" "$local_env_file" || fail "bootstrap removed unrelated local env lines"
  grep -Fq "export UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT=age1fixturepublicrecipient" "$local_env_file" || fail "bootstrap did not refresh recipient"
  recipient_count="$(grep -c '^export UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT=' "$local_env_file" | tr -d ' ')"
  [[ "$recipient_count" == "1" ]] || fail "bootstrap left duplicate recipient lines"
}

test_bootstrap_creates_private_identity_and_local_env
test_bootstrap_preserves_unrelated_local_env_lines_without_duplicates

printf 'precontact_bootstrap_test: ok\n'
