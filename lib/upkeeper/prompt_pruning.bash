# Prompt assembly.
#
# The default cycle prompt now drives a timestamp-based fresh-eyes review pass
# over one eligible script/tool file at a time. Emit it from a single-quoted
# heredoc so prompt text that includes shell metacharacters stays literal.
prune_default_prompt_sections() {
  local compiled_file="$1"
  [[ -f "$compiled_file" ]] || return 1
  python3 - "$compiled_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    text = path.read_text(encoding="utf-8", errors="replace")
except OSError:
    raise SystemExit(1)

before = len(text.encode("utf-8"))
removed = []
for pass_id in ("P2", "P8", "P16"):
    pattern = re.compile(
        rf"\n________________________________________\n\n{pass_id} - .*?"
        r"(?=\n________________________________________\n\nP(?:[1-9]|1[0-9]|2[0-3]) - )",
        re.S,
    )
    text, count = pattern.subn("", text, count=1)
    if count:
        removed.append(pass_id)

try:
    path.write_text(text, encoding="utf-8")
except OSError:
    raise SystemExit(1)

after = len(text.encode("utf-8"))
print(f"removed={','.join(removed) if removed else 'none'} bytes_before={before} bytes_after={after} bytes_saved={before - after}")
PY
}
