emit_codex_transcript_summary() {
  local label="$1"
  local transcript_file="$2"
  local codex_exit="$3"
  local signal_lines="${CODEX_TRANSCRIPT_SIGNAL_LINES:-80}"
  local error_tail_lines="${CODEX_TRANSCRIPT_ERROR_TAIL_LINES:-120}"

  terminal_wants_full_output && return 0
  [[ -n "$transcript_file" && -f "$transcript_file" ]] || return 0

  python3 - "$label" "$transcript_file" "$codex_exit" "$signal_lines" "$error_tail_lines" "$LOG_FILE" "$CYCLE_ID" "$CYCLE_RUN_HASH" <<'PY'
from datetime import datetime, timezone
from pathlib import Path
import re
import sys

label, path_raw, exit_raw, signal_raw, tail_raw, log_raw, cycle_id, run_hash = sys.argv[1:9]
path = Path(path_raw)
log_path = Path(log_raw)
try:
    signal_limit = max(0, int(signal_raw))
except ValueError:
    signal_limit = 80
try:
    tail_limit = max(0, int(tail_raw))
except ValueError:
    tail_limit = 120
try:
    text = path.read_text(encoding='utf-8', errors='replace')
except OSError:
    print(f'Upkeeper: {label} transcript unavailable path={path}', file=sys.stderr)
    raise SystemExit(0)
lines = text.splitlines()

def strip_initial_prompt_echo(raw_lines: list[str]) -> tuple[list[str], bool]:
    filtered = []
    in_user_echo = False
    saw_codex_marker = False
    stripped_prompt_echo = False
    for item in raw_lines:
        stripped = item.strip()
        if not saw_codex_marker:
            if in_user_echo:
                if stripped == 'codex':
                    in_user_echo = False
                    saw_codex_marker = True
                    stripped_prompt_echo = True
                continue
            if stripped == 'user':
                in_user_echo = True
                continue
        filtered.append(item)
    return filtered, stripped_prompt_echo

runtime_lines, stripped_prompt_echo = strip_initial_prompt_echo(lines)

def ts():
    return datetime.now(timezone.utc).astimezone().strftime('%Y-%m-%dT%H:%M:%S%z')

def short(value: str, limit: int = 300) -> str:
    value = re.sub(r'\s+', ' ', value.strip())
    if len(value) > limit:
        return value[: limit - 15].rstrip() + '...<truncated>'
    return value

def field_value(value: str) -> str:
    return short(value).replace(' ', '\\ ')

promptish = re.compile(r'^(WRAPPER_|ABSOLUTE RULE|Background Review Prompt Repertoire|Summary Table|P\d+ - |-{8,}$|workdir: |model: |provider: |approval: |sandbox: |reasoning effort: |session id: |user$|hook: )')
contractish = re.compile(
    r'^(?:[-*] |\d+[.] |[|] ).*(UPKEEPER_STATUS|UPKEEPER_LOG_REVIEW|REVIEWED_AND_FIXED|REVIEWED_CLEAN|STOPPED_ON_BLOCKER|RUN_RESULT|rate limit|quota|failed)'
    r'|^(REVIEWED_AND_FIXED|REVIEWED_CLEAN|STOPPED_ON_BLOCKER|failed)$'
    r'|^RUN_RESULT=\{\{'
)
boilerplateish = re.compile(
    r'^(Check for wrapper/prompt/logging defects|If no anomalies were found|If anomalies were found|Report the review outcome|'
    r'If the review outcome|The literal final line|Do not emit UPKEEPER_STATUS|Wrapper control marker compatibility|'
    r'Current-cycle log self-review|Current-cycle Upkeeper log review found no anomalies|'
    r'The current-cycle log lines show .*no ERROR/WARN)'
)
diff_count = sum(1 for line in lines if line.startswith('diff --git '))
hook_count = sum(1 for line in lines if line.startswith('hook: '))
prompt_count = sum(1 for line in lines if promptish.search(line))

def is_prompt_or_contract(line: str) -> bool:
    stripped = line.strip()
    normalized = re.sub(r'^\s*(?:[-*]|\d+[.])\s+', '', stripped)
    if promptish.search(stripped) or contractish.search(stripped) or boilerplateish.search(normalized):
        return True
    if re.search(r'\bno ERROR/WARN\b|\bno ERROR\b|\bno WARN\b', normalized, re.I):
        return True
    return False

def is_signal(line: str) -> bool:
    if line.startswith(('UPKEEPER_STATUS:', 'UPKEEPER_LOG_REVIEW:')):
        return True
    if is_prompt_or_contract(line):
        return False
    if re.search(r'\[(WARN|ERROR)\]', line):
        return True
    if re.search(r'\b(cycle\.exit|cycle\.summary|status_marker|signal\.received)\b', line):
        return True
    if re.search(r'\b(Command blocked by PreToolUse hook|HTTP request failed|rmcp::|KeyboardInterrupt|interrupted)\b', line):
        return True
    if re.search(r'\bERROR\b', line) and not re.search(r'\b(add_error|JSON_PARSE_ERROR|INPUT_DECODE_ERROR|EXPORT_JSON_PARSE_ERROR)\b', line):
        return True
    if re.search(r'exited [1-9][0-9]* in ', line):
        return True
    if re.search(r'\bRate limit\b|\brate limit reached\b', line):
        return True
    return False

def is_interesting_command(line: str) -> bool:
    lowered = line.lower()
    if re.search(r'\bcommand -v\s+', lowered):
        return False
    return any(
        token in lowered
        for token in (
            'pytest',
            ' test',
            '/test',
            'bash -n',
            '--check',
            'diff --check',
            'python',
            'node',
            'npm',
            'make',
            'cargo',
            'go test',
            'ruff',
            'mypy',
            'shellcheck',
        )
    )

def collect_signals(raw_lines: list[str]) -> list[str]:
    collected = []
    expecting_command = False
    current_command_interesting = False
    in_command_output = False
    in_codex_message = stripped_prompt_echo
    in_diff_block = False

    for line in raw_lines:
        stripped = line.strip()

        if stripped == 'codex' or stripped.startswith('tokens used'):
            expecting_command = False
            current_command_interesting = False
            in_command_output = False
            in_codex_message = True
            in_diff_block = False
            continue

        if stripped == 'exec':
            expecting_command = True
            current_command_interesting = False
            in_command_output = False
            in_codex_message = False
            in_diff_block = False
            continue

        if line.startswith('diff --git '):
            in_diff_block = True
            continue

        if in_diff_block:
            continue

        if expecting_command and stripped:
            expecting_command = False
            current_command_interesting = is_interesting_command(stripped)
            in_command_output = False
            in_codex_message = False
            continue

        if re.match(r'succeeded in [0-9]+', stripped):
            in_command_output = True
            in_codex_message = False
            continue

        if re.match(r'exited [1-9][0-9]* in ', stripped):
            if current_command_interesting:
                collected.append(short(stripped))
            in_command_output = True
            in_codex_message = False
            continue

        if in_command_output:
            if current_command_interesting and is_signal(line):
                collected.append(short(line))
            continue

        if stripped.startswith(('UPKEEPER_STATUS:', 'UPKEEPER_LOG_REVIEW:')):
            collected.append(short(stripped))
            continue

        if in_codex_message:
            continue

        if is_signal(line):
            collected.append(short(line))

    return collected

def dedupe_signals(raw_signals: list[str]) -> list[str]:
    seen = set()
    deduped = []
    for item in raw_signals:
        if item in seen:
            continue
        seen.add(item)
        deduped.append(item)
    return deduped

signals = dedupe_signals(collect_signals(runtime_lines))
summary = (
    f'codex.transcript.summary label={label} path={path} exit={exit_raw} lines={len(lines)} '
    f'diff_blocks={diff_count} hook_lines={hook_count} prompt_like_lines={prompt_count} signal_lines={len(signals)}'
)
log_lines = [f'{ts()} [INFO] cycle={cycle_id} run_hash={run_hash} {summary}']
for item in signals[-signal_limit:]:
    log_lines.append(f'{ts()} [INFO] cycle={cycle_id} run_hash={run_hash} codex.transcript.signal label={label} text={field_value(item)}')
try:
    with log_path.open('a', encoding='utf-8') as handle:
        for item in log_lines:
            handle.write(item + '\n')
except OSError:
    pass
print(f'Upkeeper: {label} transcript captured path={path} exit={exit_raw} lines={len(lines)} diff_blocks={diff_count} hook_lines={hook_count} prompt_like_lines={prompt_count}', file=sys.stderr)
if signals and signal_limit:
    print(f'Upkeeper: {label} high-signal transcript tail (last {min(signal_limit, len(signals))}):', file=sys.stderr)
    for line in signals[-signal_limit:]:
        print(f'  {line}', file=sys.stderr)
if exit_raw not in {'0', ''} and tail_limit:
    tail_lines = runtime_lines if runtime_lines else lines
    print(f'Upkeeper: {label} failure transcript tail (last {min(tail_limit, len(tail_lines))} lines):', file=sys.stderr)
    for line in tail_lines[-tail_limit:]:
        print(f'  {short(line)}', file=sys.stderr)
PY
}

codex_live_output_filter() {
  local label="$1"

  python3 /dev/fd/3 "$label" 3<<'PY'
from datetime import datetime, timezone
import os
import re
import sys

label = sys.argv[1]
verbosity = os.environ.get("CODEX_TERMINAL_VERBOSITY", "summary").lower()
silent = verbosity in {"none", "silent", "0", "no", "false"}

promptish = re.compile(
    r"^(WRAPPER_|ABSOLUTE RULE|Background Review Prompt Repertoire|Summary Table|P\d+ - |-{8,}$|"
    r"workdir: |model: |provider: |approval: |sandbox: |reasoning effort: |session id: |user$|hook: )"
)
boilerplateish = re.compile(
    r"^(Check for wrapper/prompt/logging defects|If no anomalies were found|If anomalies were found|Report the review outcome|"
    r"If the review outcome|The literal final line|Do not emit UPKEEPER_STATUS|Wrapper control marker compatibility|"
    r"Current-cycle log self-review|Current-cycle Upkeeper log review found no anomalies|"
    r"The current-cycle log lines show .*no ERROR/WARN)"
)
contractish = re.compile(
    r"^(?:[-*] |\d+[.] |[|] ).*(UPKEEPER_STATUS|UPKEEPER_LOG_REVIEW|REVIEWED_AND_FIXED|REVIEWED_CLEAN|STOPPED_ON_BLOCKER|RUN_RESULT|rate limit|quota|failed)"
    r"|^RUN_RESULT=\{\{"
)


def ts() -> str:
    return datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def short(value: str, limit: int = 260) -> str:
    value = re.sub(r"\s+", " ", value.strip())
    if len(value) > limit:
        return value[: limit - 15].rstrip() + "...<truncated>"
    return value


def is_prompt_or_contract(line: str) -> bool:
    stripped = line.strip()
    normalized = re.sub(r"^\s*(?:[-*]|\d+[.])\s+", "", stripped)
    if promptish.search(stripped) or contractish.search(stripped) or boilerplateish.search(normalized):
        return True
    if re.search(r"\bno ERROR/WARN\b|\bno ERROR\b|\bno WARN\b", normalized, re.I):
        return True
    return False


def is_error_line(line: str) -> bool:
    if not line or is_prompt_or_contract(line):
        return False
    patterns = (
        r"\[(?:WARN|ERROR)\]",
        r"\bERROR\b",
        r"\bWARN(?:ING)?\b",
        r"\bError:",
        r"\berror:",
        r"\berror=",
        r"\bfailed\b",
        r"\bTraceback\b",
        r"\bException\b",
        r"\bpanic\b",
        r"HTTP request failed",
        r"Command blocked by PreToolUse hook",
        r"rmcp::",
        r"exited [1-9][0-9]* in ",
        r"KeyboardInterrupt",
        r"interrupted",
    )
    if any(re.search(pattern, line) for pattern in patterns):
        if re.search(r"\b(add_error|JSON_PARSE_ERROR|INPUT_DECODE_ERROR|EXPORT_JSON_PARSE_ERROR)\b", line):
            return False
        return True
    return False


def command_kind(line: str) -> str:
    lowered = line.lower()
    if "pytest" in lowered or " test" in lowered or "/test" in lowered:
        return "tests"
    if "bash -n" in lowered or "--check" in lowered or "diff --check" in lowered:
        return "check"
    return "command"


def is_interesting_command(line: str) -> bool:
    lowered = line.lower()
    if re.search(r"\bcommand -v\s+", lowered):
        return False
    return any(
        token in lowered
        for token in (
            "pytest",
            " test",
            "/test",
            "bash -n",
            "--check",
            "diff --check",
            "python",
            "node",
            "npm",
            "make",
            "cargo",
            "go test",
            "ruff",
            "mypy",
            "shellcheck",
        )
    )


expecting_command = False
last_kind = "command"
current_command_interesting = False
in_command_output = False
in_codex_message = False
in_diff_block = False
in_user_echo = False
saw_codex_marker = False
emitted_status_markers = set()

try:
    for raw in sys.stdin:
        line = raw.rstrip("\r\n")
        stripped = line.strip()

        if not saw_codex_marker:
            if in_user_echo:
                if stripped == "codex":
                    in_user_echo = False
                    saw_codex_marker = True
                    in_codex_message = True
                continue
            if stripped == "user":
                in_user_echo = True
                continue

        if stripped == "codex" or stripped.startswith("tokens used"):
            expecting_command = False
            current_command_interesting = False
            in_command_output = False
            in_codex_message = True
            in_diff_block = False
            continue

        if stripped == "exec":
            expecting_command = True
            current_command_interesting = False
            in_command_output = False
            in_codex_message = False
            in_diff_block = False
            continue

        if line.startswith("diff --git "):
            in_diff_block = True
            continue

        if in_diff_block:
            continue

        if expecting_command and stripped:
            expecting_command = False
            last_kind = command_kind(stripped)
            current_command_interesting = is_interesting_command(stripped)
            in_command_output = False
            in_codex_message = False
            if not silent and current_command_interesting:
                print(f"{ts()} Upkeeper: {label} running {last_kind}: {short(stripped)}", file=sys.stderr, flush=True)
            continue

        if re.match(r"succeeded in [0-9]+", stripped):
            in_command_output = True
            in_codex_message = False
            if not silent and current_command_interesting:
                print(f"{ts()} Upkeeper: {label} {last_kind} completed: {short(stripped)}", file=sys.stderr, flush=True)
            continue

        if re.match(r"exited [1-9][0-9]* in ", stripped):
            in_command_output = True
            in_codex_message = False
            if current_command_interesting:
                print(f"{ts()} Upkeeper: {label} ERROR {last_kind} failed: {short(stripped)}", file=sys.stderr, flush=True)
            continue

        if in_command_output:
            if current_command_interesting and is_error_line(stripped):
                print(f"{ts()} Upkeeper: {label} ERROR: {short(stripped)}", file=sys.stderr, flush=True)
            continue

        if stripped.startswith(("UPKEEPER_STATUS:", "UPKEEPER_LOG_REVIEW:")):
            if not silent and stripped not in emitted_status_markers:
                emitted_status_markers.add(stripped)
                print(f"{ts()} Upkeeper: {label} status: {short(stripped)}", file=sys.stderr, flush=True)
            continue

        if in_codex_message:
            continue

        if is_error_line(stripped):
            print(f"{ts()} Upkeeper: {label} ERROR: {short(stripped)}", file=sys.stderr, flush=True)
except KeyboardInterrupt:
    raise SystemExit(130)
PY
}
