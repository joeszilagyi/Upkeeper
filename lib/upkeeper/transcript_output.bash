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
import errno
import hashlib
import hmac
import os
import re
import stat
import sys

label, path_raw, exit_raw, signal_raw, tail_raw, log_raw, cycle_id, run_hash = sys.argv[1:9]
path = Path(path_raw)
log_path = Path(log_raw)

def terminal_mode() -> str:
    raw = os.environ.get('CODEX_TERMINAL_VERBOSITY', 'basic').strip().lower()
    aliases = {
        '': 'basic',
        'summary': 'basic',
        'normal': 'basic',
        'default': 'basic',
        '1': 'verbose',
        'yes': 'verbose',
        'true': 'verbose',
        'debug': 'debug1',
        'none': 'silent',
        '0': 'silent',
        'no': 'silent',
        'false': 'silent',
        'raw': 'full',
    }
    return aliases.get(raw, raw)

mode = terminal_mode()
silent_terminal = mode == 'silent'
diagnostic_terminal = mode in {'verbose', 'debug1'}

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
    raw = os.fspath(path)
    redaction_key = os.environ.get('UPKEEPER_REDACTION_KEY') or os.environ.get('UPKEEPER_LATTICE_REDACTION_KEY') or ''
    material = f'path\0{raw}'.encode('utf-8', 'surrogateescape')
    if redaction_key:
        path_digest = hmac.new(redaction_key.encode('utf-8', 'surrogateescape'), material, hashlib.sha256).hexdigest()
    else:
        path_digest = hashlib.sha256(material).hexdigest()
    print(f'Upkeeper: {label} transcript unavailable transcript=path-hmac-sha256:{path_digest} path_redacted=1', file=sys.stderr)
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

def ts_log():
    return datetime.now(timezone.utc).astimezone().strftime('%Y-%m-%dT%H:%M:%S%z')


def ts_terminal():
    return datetime.now(timezone.utc).astimezone().strftime('%Y-%m-%dT%H:%M:%S')

root = os.path.realpath(os.environ.get('ROOT_DIR', os.getcwd()))
redaction_key = os.environ.get('UPKEEPER_REDACTION_KEY') or os.environ.get('UPKEEPER_LATTICE_REDACTION_KEY') or ''
redaction_key_bytes = redaction_key.encode('utf-8', 'surrogateescape')


def digest(namespace: str, value: str) -> str:
    material = f'{namespace}\0{value}'.encode('utf-8', 'surrogateescape')
    if redaction_key_bytes:
        return hmac.new(redaction_key_bytes, material, hashlib.sha256).hexdigest()
    return hashlib.sha256(material).hexdigest()


def redact_path(match: re.Match[str]) -> str:
    raw = match.group(0).rstrip('.,;:)]}\'"')
    suffix = match.group(0)[len(raw):]
    if raw == '/dev/null' or raw.startswith(('/bin/', '/usr/bin/', '/usr/local/bin/', '/opt/homebrew/bin/')):
        return raw + suffix
    try:
        resolved = os.path.realpath(raw)
        rel = os.path.relpath(resolved, root)
    except (OSError, ValueError):
        rel = ''
    if rel and not rel.startswith('..') and not os.path.isabs(rel):
        label = f'repo-path:{rel}'
    else:
        label = f'path-hmac-sha256:{digest("path", raw)}'
    return label + suffix


def redact_text(value: str) -> str:
    text = value.replace('\r', ' ').replace('\n', ' ')
    text = re.sub(r'\s+', ' ', text).strip()
    text = re.sub(r'-----BEGIN [^-]{0,80}PRIVATE KEY-----.*?-----END [^-]{0,80}PRIVATE KEY-----', '[redacted-private-key]', text, flags=re.I)
    text = re.sub(r'\bBearer\s+[A-Za-z0-9._~+/=-]{12,}', 'Bearer [redacted-token]', text, flags=re.I)
    text = re.sub(r'\b(?:sk-[A-Za-z0-9_-]{10,}|ghp_[A-Za-z0-9_]{10,}|github_pat_[A-Za-z0-9_]{10,}|AKIA[0-9A-Z]{12,}|xox[baprs]-[A-Za-z0-9-]{10,})\b', '[redacted-token]', text)
    text = re.sub(r'\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b', '[redacted-jwt]', text)
    text = re.sub(r'(?i)\b(api[_-]?key|access[_-]?token|auth[_-]?token|secret|password|passwd|credential|authorization)\b\s*[:=]\s*[\'"]?[^\'"\s;,]{4,}', r'\1=[redacted-secret]', text)
    text = re.sub(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b', lambda m: f'email-hmac-sha256:{digest("email", m.group(0))}', text)
    text = re.sub(r'(?<![A-Za-z0-9:])/(?:[A-Za-z0-9._@%+=:,~-]+/)*[A-Za-z0-9._@%+=:,~-]+', redact_path, text)
    return text


def path_label(value: Path) -> str:
    raw = os.fspath(value)
    try:
        resolved = os.path.realpath(raw)
        rel = os.path.relpath(resolved, root)
    except (OSError, ValueError):
        rel = ''
    if rel and not rel.startswith('..') and not os.path.isabs(rel):
        return f'repo-path:{rel}'
    return f'path-hmac-sha256:{digest("path", raw)}'

def short(value: str, limit: int = 300) -> str:
    value = re.sub(r'\s+', ' ', redact_text(value).strip())
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

def command_kind(line: str) -> str:
    lowered = line.lower()
    if re.search(r'\bcommand -v\s+', lowered):
        return 'command'
    if re.search(r'\bbash\s+-n\b|\bdiff\s+--check\b|git\s+diff\s+--check|\bshellcheck\b|\bruff\b|\bmypy\b', lowered):
        return 'check'
    if re.search(r'\b(rg|grep|find|cat)\b|\bgit\s+(?:grep|ls-files|diff|show|status|log)\b|\bnl\s+-ba\b|\bsed\s+-n\b', lowered):
        return 'search'
    if re.search(r'\btools/validate_[a-z0-9_.-]+(?:\.sh)?\b|validate_upkeeper\.sh', lowered):
        return 'validation'
    if re.search(r'\b(pytest|bats)\b|\bpython[0-9.]*\s+-m\s+pytest\b|\bgo\s+test\b|\bcargo\s+test\b|\b(?:npm|pnpm|yarn)\s+(?:run\s+)?test\b|\bmake\s+(?:[^;&|]*\s+)?test\b', lowered):
        return 'tests'
    if re.search(r'\b(npm|pnpm|yarn|node|make|cargo|go)\b', lowered):
        return 'build'
    if re.search(r'\bgit\b', lowered):
        return 'git'
    return 'command'

def is_interesting_command(line: str) -> bool:
    return command_kind(line) in {'tests', 'validation', 'check', 'build'}

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
    f'codex.transcript.summary label={label} transcript={path_label(path)} path_redacted=1 exit={exit_raw} lines={len(lines)} '
    f'diff_blocks={diff_count} hook_lines={hook_count} prompt_like_lines={prompt_count} signal_lines={len(signals)}'
)
log_lines = [f'{ts_log()} [INFO] cycle={cycle_id} run_hash={run_hash} {summary}']
for item in signals[-signal_limit:]:
    log_lines.append(f'{ts_log()} [INFO] cycle={cycle_id} run_hash={run_hash} codex.transcript.signal label={label} text={field_value(item)}')

def append_log_lines_secure(path: Path, items: list[str]) -> None:
    path_raw = os.fspath(path)
    parent = os.path.dirname(path_raw) or "."
    name = os.path.basename(path_raw)
    uid = os.getuid()
    if not name or name in {".", ".."}:
        raise OSError("invalid log filename")

    parent_stat = os.lstat(parent)
    if stat.S_ISLNK(parent_stat.st_mode) or not stat.S_ISDIR(parent_stat.st_mode):
        raise OSError("unsafe log parent")

    try:
        path_stat = os.lstat(path_raw)
    except FileNotFoundError:
        path_stat = None
    if path_stat is not None:
        if stat.S_ISLNK(path_stat.st_mode) or not stat.S_ISREG(path_stat.st_mode):
            raise OSError("unsafe log file type")
        if path_stat.st_uid != uid:
            raise OSError("unsafe log owner")
        if path_stat.st_nlink != 1:
            raise OSError("unsafe log hardlink count")

    dir_flags = os.O_RDONLY
    for attr in ("O_DIRECTORY", "O_CLOEXEC", "O_NOFOLLOW"):
        dir_flags |= getattr(os, attr, 0)
    parent_fd = os.open(parent, dir_flags)
    file_flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND
    for attr in ("O_CLOEXEC", "O_NONBLOCK", "O_NOFOLLOW"):
        file_flags |= getattr(os, attr, 0)
    try:
        try:
            fd = os.open(name, file_flags, 0o600, dir_fd=parent_fd)
        except OSError as exc:
            if exc.errno == errno.ELOOP:
                raise OSError("unsafe log symlink") from exc
            raise
        try:
            opened_stat = os.fstat(fd)
            if not stat.S_ISREG(opened_stat.st_mode):
                raise OSError("unsafe log file type")
            if opened_stat.st_uid != uid:
                raise OSError("unsafe log owner")
            if opened_stat.st_nlink != 1:
                raise OSError("unsafe log hardlink count")
            os.fchmod(fd, 0o600)
            for item in items:
                data = (item + "\n").encode("utf-8", errors="surrogateescape")
                while data:
                    written = os.write(fd, data)
                    if written <= 0:
                        raise OSError("log write returned zero bytes")
                    data = data[written:]
        finally:
            os.close(fd)
    finally:
        os.close(parent_fd)

try:
    append_log_lines_secure(log_path, log_lines)
except OSError:
    pass
if not silent_terminal and (diagnostic_terminal or exit_raw not in {'0', ''}):
    print(f'{ts_terminal()} [INFO] Upkeeper: {label} transcript captured transcript={path_label(path)} path_redacted=1 exit={exit_raw} lines={len(lines)} diff_blocks={diff_count} hook_lines={hook_count} prompt_like_lines={prompt_count}', file=sys.stderr)
if not silent_terminal and diagnostic_terminal and signals and signal_limit:
    print(f'{ts_terminal()} [INFO] Upkeeper: {label} high-signal transcript tail (last {min(signal_limit, len(signals))}):', file=sys.stderr)
    for line in signals[-signal_limit:]:
        print(f'  {line}', file=sys.stderr)
if not silent_terminal and exit_raw not in {'0', ''} and tail_limit:
    tail_lines = runtime_lines if runtime_lines else lines
    print(f'{ts_terminal()} [ERROR] Upkeeper: {label} failure transcript tail (last {min(tail_limit, len(tail_lines))} lines):', file=sys.stderr)
    for line in tail_lines[-tail_limit:]:
        print(f'  {short(line)}', file=sys.stderr)
PY
}

codex_live_output_filter() {
  local label="$1"

  python3 /dev/fd/3 "$label" 3<<'PY'
from datetime import datetime, timezone
import hashlib
import hmac
import os
import re
import sys

label = sys.argv[1]


def terminal_mode() -> str:
    raw = os.environ.get("CODEX_TERMINAL_VERBOSITY", "basic").strip().lower()
    aliases = {
        "": "basic",
        "summary": "basic",
        "normal": "basic",
        "default": "basic",
        "1": "verbose",
        "yes": "verbose",
        "true": "verbose",
        "debug": "debug1",
        "none": "silent",
        "0": "silent",
        "no": "silent",
        "false": "silent",
        "raw": "full",
    }
    return aliases.get(raw, raw)


mode = terminal_mode()
silent = mode in {"silent", "full"}
quiet = mode == "quiet"
basic = mode == "basic"
diagnostic = mode in {"verbose", "debug1"}
llm_status_enabled = mode in {"basic", "verbose", "debug1"}

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
    return datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%dT%H:%M:%S")


root = os.path.realpath(os.environ.get("ROOT_DIR", os.getcwd()))
redaction_key = os.environ.get("UPKEEPER_REDACTION_KEY") or os.environ.get("UPKEEPER_LATTICE_REDACTION_KEY") or ""
redaction_key_bytes = redaction_key.encode("utf-8", "surrogateescape")


def digest(namespace: str, value: str) -> str:
    material = f"{namespace}\0{value}".encode("utf-8", "surrogateescape")
    if redaction_key_bytes:
        return hmac.new(redaction_key_bytes, material, hashlib.sha256).hexdigest()
    return hashlib.sha256(material).hexdigest()


def redact_path(match: re.Match[str]) -> str:
    raw = match.group(0).rstrip(".,;:)]}'\"")
    suffix = match.group(0)[len(raw):]
    if raw == "/dev/null" or raw.startswith(("/bin/", "/usr/bin/", "/usr/local/bin/", "/opt/homebrew/bin/")):
        return raw + suffix
    try:
        resolved = os.path.realpath(raw)
        rel = os.path.relpath(resolved, root)
    except (OSError, ValueError):
        rel = ""
    if rel and not rel.startswith("..") and not os.path.isabs(rel):
        label = f"repo-path:{rel}"
    else:
        label = f"path-hmac-sha256:{digest('path', raw)}"
    return label + suffix


def redact_text(value: str) -> str:
    text = value.replace("\r", " ").replace("\n", " ")
    text = re.sub(r"\s+", " ", text).strip()
    text = re.sub(r"-----BEGIN [^-]{0,80}PRIVATE KEY-----.*?-----END [^-]{0,80}PRIVATE KEY-----", "[redacted-private-key]", text, flags=re.I)
    text = re.sub(r"\bBearer\s+[A-Za-z0-9._~+/=-]{12,}", "Bearer [redacted-token]", text, flags=re.I)
    text = re.sub(r"\b(?:sk-[A-Za-z0-9_-]{10,}|ghp_[A-Za-z0-9_]{10,}|github_pat_[A-Za-z0-9_]{10,}|AKIA[0-9A-Z]{12,}|xox[baprs]-[A-Za-z0-9-]{10,})\b", "[redacted-token]", text)
    text = re.sub(r"\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b", "[redacted-jwt]", text)
    text = re.sub(r"(?i)\b(api[_-]?key|access[_-]?token|auth[_-]?token|secret|password|passwd|credential|authorization)\b\s*[:=]\s*['\"]?[^'\"\s;,]{4,}", r"\1=[redacted-secret]", text)
    text = re.sub(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b", lambda m: f"email-hmac-sha256:{digest('email', m.group(0))}", text)
    text = re.sub(r"(?<![A-Za-z0-9:])/(?:[A-Za-z0-9._@%+=:,~-]+/)*[A-Za-z0-9._@%+=:,~-]+", redact_path, text)
    return text


def short(value: str, limit: int = 260) -> str:
    value = re.sub(r"\s+", " ", redact_text(value).strip())
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
    if re.search(r"\bcommand -v\s+", lowered):
        return "command"
    if re.search(r"\bbash\s+-n\b|\bdiff\s+--check\b|git\s+diff\s+--check|\bshellcheck\b|\bruff\b|\bmypy\b", lowered):
        return "check"
    if re.search(r"\b(rg|grep|find|cat)\b|\bgit\s+(?:grep|ls-files|diff|show|status|log)\b|\bnl\s+-ba\b|\bsed\s+-n\b", lowered):
        return "search"
    if re.search(r"\btools/validate_[a-z0-9_.-]+(?:\.sh)?\b|validate_upkeeper\.sh", lowered):
        return "validation"
    if re.search(r"\b(pytest|bats)\b|\bpython[0-9.]*\s+-m\s+pytest\b|\bgo\s+test\b|\bcargo\s+test\b|\b(?:npm|pnpm|yarn)\s+(?:run\s+)?test\b|\bmake\s+(?:[^;&|]*\s+)?test\b", lowered):
        return "tests"
    if re.search(r"\b(npm|pnpm|yarn|node|make|cargo|go)\b", lowered):
        return "build"
    if re.search(r"\bgit\b", lowered):
        return "git"
    return "command"


def should_announce_start(kind: str) -> bool:
    if diagnostic:
        return kind in {"tests", "validation", "check", "build", "search"}
    if basic:
        return kind in {"tests", "validation", "check", "build"}
    return False


def should_report_success(kind: str) -> bool:
    if diagnostic or basic:
        return kind in {"tests", "validation", "check", "build"}
    return False


def should_report_failure_as_error(kind: str) -> bool:
    return kind in {"tests", "validation", "check", "build"}


def emit(level: str, message: str) -> None:
    if silent:
        return
    print(f"{ts()} [{level}] Upkeeper: {message}", file=sys.stderr, flush=True)


def emit_llm_status(message: str) -> None:
    if silent:
        return
    print("", file=sys.stderr, flush=True)
    emit("INFO", f"{label} LLM: {message}")
    print("", file=sys.stderr, flush=True)


def maybe_assistant_status(line: str) -> str:
    candidate = line.strip()
    if not candidate:
        return ""
    if candidate.startswith(("hook:", "UPKEEPER_STATUS:", "UPKEEPER_LOG_REVIEW:", "diff --git ")):
        return ""
    if candidate.startswith(("REVIEWED_", "STOPPED_ON_BLOCKER", "RUN_RESULT=", "tokens used")):
        return ""
    if is_prompt_or_contract(candidate):
        return ""
    if re.match(r"^(?:---|\+\+\+|@@|\+|-)\s", candidate):
        return ""
    return short(candidate, 440)


expecting_command = False
last_kind = "command"
last_command_id = 0
current_command_interesting = False
current_command_reports_success = False
current_command_exit_reported = False
current_command_success_reported = False
in_command_output = False
in_codex_message = False
in_diff_block = False
in_user_echo = False
saw_codex_marker = False
emitted_status_markers = set()
assistant_status = ""
last_emitted_assistant_status = ""

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
            current_command_reports_success = False
            current_command_exit_reported = False
            current_command_success_reported = False
            in_command_output = False
            in_codex_message = True
            in_diff_block = False
            assistant_status = ""
            continue

        if stripped == "exec":
            if llm_status_enabled and assistant_status and assistant_status != last_emitted_assistant_status:
                emit_llm_status(assistant_status)
                last_emitted_assistant_status = assistant_status
            assistant_status = ""
            expecting_command = True
            current_command_interesting = False
            current_command_reports_success = False
            current_command_exit_reported = False
            current_command_success_reported = False
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
            last_command_id += 1
            last_kind = command_kind(stripped)
            current_command_interesting = should_announce_start(last_kind)
            current_command_reports_success = should_report_success(last_kind)
            current_command_exit_reported = False
            current_command_success_reported = False
            in_command_output = False
            in_codex_message = False
            if not silent and current_command_interesting:
                if diagnostic:
                    emit("INFO", f"{label} cmd#{last_command_id} {last_kind} started: {short(stripped)}")
                else:
                    emit("INFO", f"{label} running {last_kind} cmd#{last_command_id}: {short(stripped)}")
            continue

        if re.match(r"succeeded in [0-9]+", stripped):
            in_command_output = True
            in_codex_message = False
            if not silent and current_command_reports_success and not current_command_success_reported:
                current_command_success_reported = True
                if diagnostic:
                    emit("INFO", f"{label} cmd#{last_command_id} {last_kind} passed: {short(stripped)}")
                else:
                    emit("INFO", f"{label} finished {last_kind} cmd#{last_command_id}: {short(stripped)}")
            continue

        if re.match(r"exited [1-9][0-9]* in ", stripped):
            in_command_output = True
            in_codex_message = False
            if not current_command_exit_reported:
                current_command_exit_reported = True
                if should_report_failure_as_error(last_kind):
                    emit("ERROR", f"{label} cmd#{last_command_id} {last_kind} failed: {short(stripped)}")
                elif not silent and current_command_interesting:
                    emit("INFO", f"{label} cmd#{last_command_id} {last_kind} exited nonzero: {short(stripped)}")
            continue

        if in_command_output:
            if current_command_reports_success and is_error_line(stripped):
                emit("ERROR", f"{label}: {short(stripped)}")
            continue

        if stripped.startswith(("UPKEEPER_STATUS:", "UPKEEPER_LOG_REVIEW:")):
            if not silent and stripped not in emitted_status_markers:
                emitted_status_markers.add(stripped)
                emit("INFO", f"{label} status: {short(stripped)}")
            continue

        if in_codex_message:
            if llm_status_enabled:
                status_candidate = maybe_assistant_status(stripped)
                if status_candidate:
                    assistant_status = status_candidate
            continue

        if is_error_line(stripped):
            emit("ERROR", f"{label}: {short(stripped)}")
except KeyboardInterrupt:
    raise SystemExit(130)
PY
}
