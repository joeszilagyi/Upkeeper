#!/usr/bin/env bash

# Shared private fixtures for the independently timed client-link scenarios.

client_link_resolve_abs() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).resolve(strict=False))
PY
}

client_link_init_repo() {
  local repo="$1"

  mkdir -p "$repo"
  chmod 700 "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "client-link-test@example.invalid"
  git -C "$repo" config user.name "Client Link Test"
  printf '#!/usr/bin/env bash\nprintf client-tool\\n\n' >"$repo/client-tool.sh"
  chmod +x "$repo/client-tool.sh"
  git -C "$repo" add client-tool.sh
  git -C "$repo" commit -qm "add client tool"
}

client_link_install_fake_age() {
  mkdir -p "$TEST_TMP_ROOT/bin"
  cat >"$TEST_TMP_ROOT/bin/age" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exit 0
SH
  chmod +x "$TEST_TMP_ROOT/bin/age"
}
