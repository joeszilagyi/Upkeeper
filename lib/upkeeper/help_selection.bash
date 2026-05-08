# Human-facing inline help. This is also the seed text for a missing tracked
# operator guide; once the guide exists, the Markdown becomes the living document.
show_help() {
  cat <<EOF
Usage: $SCRIPT_NAME [--help] [--version] [--prompt-file FILE] [--prompt TEXT] [--model-override=5.5_xhigh] [--target-file=PATH] [--prompt-pass=all]

One-cycle Codex backend worker with quota guardrails.
Version: $UPKEEPER_VERSION

Each invocation:
  1. Reads the latest Codex rate-limit snapshot from $CODEX_HOME_DIR/sessions.
  2. Logs current 5-hour and weekly used/left percentages for the current target model bucket.
  3. Projects one more run from recent observed deltas.
  4. If the projected next run would leave at or below:
       - ${CODEX_5H_STOP_PERCENT}% left in a normal current-model 5-hour window,
       - ${CODEX_SPARK_5H_STOP_PERCENT}% left in a Spark Codex 5-hour window, or
       - ${CODEX_WEEK_STOP_PERCENT}% left in the current weekly/main window,
         plus any model-specific weekly safety buffer
     then it terminates the parent shell running the loop and exits without
     starting a new Codex run, unless fallback handoff is enabled.
  5. Before launching Codex, verifies that $CODEX_HOME_DIR/sessions is writable,
     stale Codex arg0 temp shims can be cleaned or quarantined, and Codex's
     shared bubblewrap temp registry is writable.
  6. Otherwise it runs exactly one codex exec cycle and exits.
  7. If the primary model fails, blocks, or exhausts its bucket, it can hand off
     to one stronger fallback cycle in the
     same outer-loop iteration.

Designed for loops like:
  while ./$SCRIPT_NAME; do
    sleep 60
  done

Loop stop semantics:
  - exit 0 keeps the outer shell loop running
  - exit 5 stops the outer shell loop intentionally when Codex reports
    UPKEEPER_STATUS: NO_BACKEND_TASK
  - while the worktree is dirty, a NO_BACKEND_TASK result is treated as a soft miss
    and the outer loop keeps running so Codex can try again on the next cycle
  - if Codex exits cleanly with a final agent message and a parseable terminal
    review outcome (REVIEWED_AND_FIXED, REVIEWED_CLEAN, or STOPPED_ON_BLOCKER)
    but omits the literal UPKEEPER_STATUS line, the wrapper recovers the
    equivalent machine status and logs status_marker.recovered_from_review_outcome;
    exact status markers remain the preferred contract
  - set CODEX_CONTINUE_ON_NO_BACKEND_TASK=1 to keep polling even after
    an empty cycle even when the worktree is clean
  - when the primary model stalls, fails, or exhausts its bucket, the wrapper can
    launch one stronger fallback worker inside a detached screen session and keep
    polling it every ${CODEX_FALLBACK_SCREEN_POLL_SECONDS}s before giving up
  - detached screen fallback is single-shot by default; set
    CODEX_FALLBACK_SCREEN_CONTINUOUS=1 and raise CODEX_FALLBACK_SCREEN_MAX_CHILDREN
    to opt into bounded multi-child fallback
  - by default, a fallback event also triggers a scripted post-mortem report pass
    plus one final hardening pass, then the wrapper exits non-zero so you can
    manually relaunch the loop after reviewing the incident summary
  - post-mortem report completion logs postmortem.report.finish with the
    report child exit, parsed marker, report path, and file existence state
  - auxiliary post-mortem and hardening Codex calls use their own exact-model
    quota preflight and are skipped, with a shell-written report, when no
    current bucket can make a decision or a current bucket is projected below
    threshold
  - live primary and auxiliary Codex calls also preflight the local session store;
    a read-only $CODEX_HOME_DIR/sessions is classified as a local environment
    failure before starting recursive fallback or post-mortem Codex work
  - live primary, fallback, and auxiliary Codex calls also preflight Codex's
    shared bubblewrap temp registry; a stale root-owned registry is classified
    as a local environment failure before launching another Codex process
  - live primary and auxiliary Codex calls also preflight $CODEX_ARG0_TMP_ROOT;
    stale flat codex-arg0* shim directories are removed when owned by the
    operator and moved to $CODEX_ARG0_TMP_QUARANTINE_ROOT when they are stale
    but root-owned; if a stale root-owned child cannot be moved individually,
    the wrapper rotates the whole arg0 root and recreates it empty, avoiding
    Codex's vague stale-arg0 cleanup warning
  - if you press Ctrl-C while the primary wrapper is watching a detached recovery
    screen session, the wrapper first checks whether the child already finished,
    then tears down any still-running recovery session before exiting
  - incident directories now include a shell-written bug record artifact alongside
    the post-mortem report so a human or later agent can file or review the bug
  - successful pre-run quota handoffs and no-agent post-run quota failures write
    a primary-quota-blocked-until marker, and later primary invocations for the
    same model stop before launching another fallback/post-mortem chain until
    that reset time passes
  - this wrapper also self-rotates its local root log when the oldest live log
    entry is older than ${CODEX_LOG_ROTATE_AFTER_HOURS} hours; archives stay as
    sibling zip files and archives older than ${CODEX_LOG_ROTATE_KEEP_HOURS}
    hours are pruned on startup
  - by default, live terminal output is summary-first: routine INFO logs and
    full backend transcripts stay in log/transcript artifacts, while WARN,
    ERROR, live tool/Codex error lines, timestamped progress heartbeats, status,
    and bounded high-signal transcript summaries remain visible;
    transcript artifacts live under ${CODEX_TRANSCRIPT_DIR} and are pruned after
    ${CODEX_TRANSCRIPT_KEEP_HOURS} hours or ${CODEX_TRANSCRIPT_KEEP_MAX_MB} MB;
    set CODEX_TERMINAL_VERBOSITY=full to stream the full backend transcript

Important:
  - Run the loop in a dedicated shell or terminal tab.
  - The living repo-local operator guide is:
      $(resolved_operator_guide_path)
    If that guide is missing, normal startup bootstraps it once from this help
    text and then leaves it alone for repo-specific edits.
    Existing guides are never overwritten; if their embedded help snapshot
    version is missing or stale, startup logs an operator_guide warning so you
    can refresh the generated section without losing repo-local notes.
    If the guide path is ignored by the target repo, it is treated as optional
    local operator state: missing ignored guides are not bootstrapped, and
    stale/missing-version snapshots are informational only.
  - The safety stop targets the parent shell of the current cycle to break the loop.
  - Nested fallback runs inherit the original loop-parent shell target so the
    stronger cleanup pass can still stop the real outer loop intentionally.
  - Nested fallback runs also re-enter through the same repo-local script path
    used by the primary invocation, so symlinked installs keep operating on the
    target repository rather than the central wrapper source checkout.
  - The root entrypoint loads its implementation modules from:
      $UPKEEPER_MODULE_DIR
    Symlinked clients should point at the central Upkeeper entrypoint; copying
    only the launcher without the paired lib/upkeeper modules is unsupported.
    The executable module load order is the UPKEEPER_MODULES array in root
    Upkeeper; the module contract is documented in lib/upkeeper/README.md.
  - The large default review prompt is loaded from:
      $UPKEEPER_IMPLEMENTATION_DIR/prompts/default-review.md
    Symlinked clients share that central prompt; local prompt files are only
    needed for explicit --prompt-file overrides.
  - The central checkout can be validated without launching Codex with:
      tools/validate_upkeeper.sh --deps
      tools/validate_upkeeper.sh --quick
      tools/validate_upkeeper.sh --full
    Runtime/tool dependencies are documented in docs/dependencies.md. GitHub's
    dependency graph is useful future-proofing, but it will not list Bash system
    tools unless the repo later adds a supported manifest or workflow.
  - Quota detection uses Codex's machine-readable session JSONL snapshots rather than
    scraping the interactive /status TUI output.
  - Exact-model Spark quota snapshots may still report the generic Codex
    limiter identity; once snapshot selection proves the target model, that is
    treated as usable quota metadata instead of a conflict.
  - Spark Codex is allowed to drain its current-model 5-hour bucket to
    ${CODEX_SPARK_5H_STOP_PERCENT}% left; weekly/main capacity still stops at
    ${CODEX_WEEK_STOP_PERCENT}% left plus any model-specific weekly safety
    buffer.
  - For pre-run quota stops on an already-dirty worktree, the wrapper skips the
    normal backend fallback child and records the incident instead of spending a
    stronger model run on a predictable dirty-worktree block.
  - Quota logs always print both used and left explicitly as named fields
    (primary_used=... primary_left=... secondary_used=... secondary_left=...)
    so operator checks do not depend on positional interpretation.
  - Terminal cycle outcomes are written as cycle.summary and cycle.exit lines to:
      $LOG_FILE
    Review cycles also write compact review.summary lines, and
    review.fix_details lines when the final response reports fixes, so later
    commits can recover what changed and why.
  - The default prompt makes the primary agent inspect this cycle's own
    $LOG_FILE entries before its final marker. If the log review exposes a
    concrete wrapper or prompt defect and the current repo owns the central
    Upkeeper file, the agent may repair it in the same pass and report that
    self-repair explicitly.
  - Every log line includes a per-cycle run_hash. The wrapper emits --MARK--
    heartbeat lines with fractional epoch, boot id, and uptime so missing
    continuity can be detected even when both the primary process and a future
    watchdog fail.
  - Startup scans the recent live log for prior cycles that started but never
    wrote cycle.exit/run.finish, logs previous_run.anomaly lines, and injects
    those findings into the prompt for the next healthy run.
  - Startup also logs disk.preflight lines for repo, log, Codex home/session,
    temp, bwrap, arg0, and runtime paths, and injects a prompt note when any
    write-critical root is below ${CODEX_DISK_MIN_FREE_PERCENT}% free.
  - Startup anomalies are a gate by default: while prior-run, watchdog-style, or
    low-disk anomaly evidence is active, preselection is forced to the repo-local
    Upkeeper implementation and normal timestamp rotation is blocked until the
    Upkeeper suite is checked or remediated.

Prompt behavior:
  - By default, the script asks Codex to select the oldest eligible script/tool
    file by last-modified timestamp and review exactly one file per cycle.
  - Exception: when the repo-local Upkeeper implementation itself is eligible
    and has not been touched for at least
    ${CODEX_UPKEEPER_SELF_REVIEW_AFTER_DAYS} days, it is selected first. If it is
    newer than that threshold, normal oldest-file selection applies.
  - Before launching Codex, the wrapper preselects that script/tool target from
    git ls-files -co --exclude-standard and prepends the selected path to the
    prompt. That avoids spending model/tool cycles on broad tree discovery and
    keeps .git/, ignored paths, runtime evidence, generated outputs, and tests
    out of the selection scan.
  - A WRAPPER_PRESELECTED_REVIEW_TARGET section overrides every later repertoire
    selection rule for that cycle; all applicable review prompts run against
    that same target unless the file is physically impossible or unsafe to read.
  - Preselection records the selected target's git status and content hash before
    Codex starts. If the selected file is already dirty, that is baseline state,
    not a blocker by itself; touch verification must compare against the
    pre-touch content hash rather than assuming the diff against HEAD is empty.
  - Tests are not script/tool targets merely because they use a script-language
    extension; select tests only when explicit extra guidance asks for test
    review or no eligible script/tool target exists.
  - The default prompt forbids skipping a selected eligible file just because it
    was recently reviewed; if every eligible file was touched within 24 hours,
    Codex still reviews the oldest file again.
  - The default prompt requires timestamp reporting, the applicable review
    repertoire passes, and a touch of the selected file even when the review is clean.
  - P23 is included for validators, parsers, importers, exporters, registry
    loaders, schema/profile helpers, config/manifest readers, data readers,
    path-resolving shell helpers, and CLIs that consume external/operator input
    or emit machine-readable output. It focuses on strict data contracts,
    actionable malformed-input diagnostics, and negative fixtures.
  - The review body should report REVIEWED_AND_FIXED, REVIEWED_CLEAN, or
    STOPPED_ON_BLOCKER, but the literal final line still maps to the wrapper's
    UPKEEPER_STATUS marker contract.
  - --prompt-file FILE appends extra task guidance from FILE.
  - --prompt TEXT appends extra task guidance inline.
  - --model-override=5.5_xhigh runs this invoked cycle once as gpt-5.5
    with xhigh reasoning effort. It is a CLI-only operator override and does
    not persist to later loop iterations. Use the equals form; spaced form is
    rejected.
  - --target-file=PATH pins this invoked cycle to one source-safe repo file and
    bypasses timestamp selection. Use the equals form; spaced form is rejected.
  - --prompt-pass=all forces the selected target through all P1-P23 repertoire
    passes for this invoked cycle. Use the equals form; spaced form is rejected.

Environment overrides:
  CODEX_MODEL                   Default: gpt-5.3-codex-spark
  CODEX_REASONING_EFFORT        Default: xhigh
  CODEX_MODE                    Default: --sandbox workspace-write
  CODEX_FALLBACK_ENABLED        Default: 1
  CODEX_FALLBACK_MODEL          Default: gpt-5.5
  CODEX_FALLBACK_REASONING_EFFORT Default: xhigh
  CODEX_FALLBACK_MODE           Default: CODEX_MODE
  CODEX_FALLBACK_ON_PRIMARY_QUOTA Default: 1
  CODEX_FALLBACK_ON_FAILURE     Default: 1
  CODEX_FALLBACK_ON_BLOCKED     Default: 1
  CODEX_FALLBACK_ON_DIRTY_NO_BACKEND_TASK Default: 1
  CODEX_FALLBACK_SCREEN_ENABLED     Default: 1
  CODEX_FALLBACK_SCREEN_POLL_SECONDS Default: 60
  CODEX_FALLBACK_SCREEN_CONTINUOUS   Default: 0
  CODEX_FALLBACK_SCREEN_MAX_CHILDREN Default: 1
  CODEX_FALLBACK_SCREEN_MAX_SECONDS  Default: 0
  CODEX_POSTMORTEM_ENABLED       Default: 1
  CODEX_POSTMORTEM_MODEL         Default: CODEX_FALLBACK_MODEL
  CODEX_POSTMORTEM_REASONING_EFFORT Default: CODEX_FALLBACK_REASONING_EFFORT
  CODEX_POSTMORTEM_MODE          Default: CODEX_FALLBACK_MODE
  CODEX_POSTMORTEM_DIR           Default: $ROOT_DIR/runtime/journals/upkeeper-postmortems
  CODEX_OPERATOR_GUIDE_PATH      Default: docs/scripts/upkeeper.md
  CODEX_OPERATOR_GUIDE_BOOTSTRAP Default: 1
  CODEX_5H_STOP_PERCENT         Default: 5
  CODEX_SPARK_5H_STOP_PERCENT   Default: 0
  CODEX_WEEK_STOP_PERCENT       Default: 15
  CODEX_WEEK_STOP_BUFFER_PERCENT Default: 0
  CODEX_SPARK_WEEK_STOP_BUFFER_PERCENT Default: 5
  CODEX_LOG_ROTATE_AFTER_HOURS  Default: 72
  CODEX_LOG_ROTATE_KEEP_HOURS   Default: 144
  CODEX_PROCESS_ARGS_MAX_CHARS  Default: 600
  CODEX_LOOP_STOP_GRACE_SECONDS Default: 5
  CODEX_CONTINUE_ON_NO_BACKEND_TASK Default: 0
  CODEX_DISABLE_PARENT_STOP      Default: 0
  CODEX_GUARDRAIL_STOP_EXIT_CODE Default: 0
  CODEX_PARENT_STOP_SKIPPED_EXIT_CODE Default: 75
  CODEX_EXECUTION_ORIGIN         Default: primary
  CODEX_BWRAP_TMP_ROOT           Default: /tmp/codex-bwrap-synthetic-mount-targets
  CODEX_BWRAP_TMP_PREFLIGHT      Default: 1
  CODEX_ARG0_TMP_ROOT            Default: $CODEX_HOME_DIR/tmp/arg0
  CODEX_ARG0_TMP_QUARANTINE_ROOT Default: $CODEX_HOME_DIR/arg0-quarantine
  CODEX_ARG0_TMP_PREFLIGHT       Default: 1
  CODEX_ARG0_TMP_STALE_MINUTES   Default: 60
  CODEX_ARG0_TMP_ROTATE_ON_BLOCKED Default: 1
  CODEX_UPKEEPER_SELF_REVIEW_AFTER_DAYS Default: 7
  CODEX_MARK_INTERVAL_SECONDS Default: 60
  CODEX_PREVIOUS_RUN_SCAN_MINUTES Default: 240
  CODEX_DISK_MIN_FREE_PERCENT Default: 10
  CODEX_STARTUP_ANOMALY_FORCE_UPKEEPER Default: 1
  CODEX_STARTUP_ANOMALY_GATE_STATE_DIR Default: $ROOT_DIR/runtime/startup-anomaly-gates
  CODEX_ACTIVE_LOCK_DIR Default: $ROOT_DIR/runtime/upkeeper-active.lock
  CODEX_WRAPPER_HEALTH_STATE_DIR Default: $CODEX_HOME_DIR/upkeeper/active-wrapper-runs
  CODEX_SESSION_SCAN_LIMIT      Default: 200
  CODEX_LOG_FILE                Default: $ROOT_DIR/Upkeeper.log
  UPKEEPER_DRY_RUN           Default: 0

Exit codes:
  0  One cycle completed, dry-run completed, or the loop was stopped on quota guardrails
  2  Codex reported BLOCKED
  3  Wrapper/setup error
  4  Safety stop was required but parent-loop termination was not confirmed
  5  No clear backend task remained; the wrapper stops the outer loop on purpose
  6  Codex turn was aborted/interrupted before emitting a final status marker
  7  Fallback plus post-mortem sequence completed, or a persisted quota cooldown
     is active; manually relaunch after review or after the recorded reset time
  8  Fallback ran but the scripted post-mortem or hardening sequence failed
  9  Detached screen worker stopped on a guardrail without requesting parent termination
EOF
}

resolved_operator_guide_path() {
  if [[ "$CODEX_OPERATOR_GUIDE_PATH" == /* ]]; then
    printf '%s' "$CODEX_OPERATOR_GUIDE_PATH"
  else
    printf '%s/%s' "$ROOT_DIR" "$CODEX_OPERATOR_GUIDE_PATH"
  fi
}

repo_local_upkeeper_gate_target() {
  python3 - "$ROOT_DIR" "$SELF_PATH" <<'PY'
import os
import stat as statmod
import subprocess
import sys

root, self_path = sys.argv[1:3]
os.chdir(root)


def root_relative(path: str) -> str:
    try:
        rel_path = os.path.relpath(path, root)
    except ValueError:
        return ""
    if rel_path == "." or rel_path.startswith("../") or os.path.isabs(rel_path):
        return ""
    return rel_path.replace(os.sep, "/")


eligible_names = set()
self_rel = root_relative(self_path)
if self_rel:
    eligible_names.add(self_rel)
eligible_names.add("Upkeeper")
eligible_names.add("Upkeeper.sh")

try:
    raw_paths = subprocess.check_output(["git", "ls-files", "-co", "--exclude-standard", "-z"])
except subprocess.CalledProcessError:
    raise SystemExit(1)

repo_paths = set(raw_paths.decode("utf-8", "surrogateescape").split("\0"))
matches = []
for path in sorted(eligible_names):
    # Client checkouts commonly use ignored local Upkeeper.sh symlinks to the
    # central wrapper. Startup-anomaly gates should accept that local execution
    # handle even though normal timestamp rotation must not treat ignored
    # wrapper artifacts as source files.
    if path not in repo_paths and path != "Upkeeper.sh":
        continue
    try:
        stat_result = os.stat(path)
    except OSError:
        continue
    if statmod.S_ISREG(stat_result.st_mode):
        matches.append(path)

if not matches:
    raise SystemExit(1)
print(matches[0])
PY
}

enforce_startup_anomaly_gate_target_or_exit() {
  local target
  [[ "$STARTUP_ANOMALY_GATE" == "1" ]] || return 0
  [[ "$CODEX_STARTUP_ANOMALY_FORCE_UPKEEPER" == "1" ]] || return 0

  if target="$(repo_local_upkeeper_gate_target)"; then
    log_line "INFO" "startup_anomaly.gate_target status=eligible path=$(shell_quote "$target")"
    return 0
  fi

  log_line "ERROR" "startup_anomaly.gate_target status=missing action=fail_closed reason=no_repo_local_upkeeper_candidate implementation=$(shell_quote "$SELF_PATH") root=$(shell_quote "$ROOT_DIR")"
  if ! write_startup_anomaly_gate_state "unresolved" "no_repo_local_upkeeper_candidate"; then
    finish_cycle 7 STARTUP_ANOMALY_STATE_UNWRITABLE ERROR "codex_exec_started=0 implementation=$(shell_quote "$SELF_PATH") root=$(shell_quote "$ROOT_DIR")"
  fi
  finish_cycle 7 STARTUP_ANOMALY_REQUIRES_CENTRAL_UPKEEPER WARN "codex_exec_started=0 implementation=$(shell_quote "$SELF_PATH") root=$(shell_quote "$ROOT_DIR")"
}

preselect_review_target() {
  python3 - "$ROOT_DIR" "$SELF_PATH" "$CODEX_UPKEEPER_SELF_REVIEW_AFTER_DAYS" "$STARTUP_ANOMALY_GATE" "$CODEX_STARTUP_ANOMALY_FORCE_UPKEEPER" "$CODEX_TARGET_FILE" <<'PY'
import datetime
import os
import stat as statmod
import subprocess
import sys
import time

root, self_path, self_review_after_days, startup_anomaly_gate, startup_force_upkeeper, forced_target = sys.argv[1:7]
os.chdir(root)
try:
    self_review_threshold_seconds = max(0, int(self_review_after_days)) * 86400
except ValueError:
    self_review_after_days = "7"
    self_review_threshold_seconds = 7 * 86400

script_exts = {
    ".awk",
    ".bash",
    ".cjs",
    ".fish",
    ".go",
    ".js",
    ".jsx",
    ".ksh",
    ".lua",
    ".mjs",
    ".pl",
    ".ps1",
    ".psm1",
    ".py",
    ".rb",
    ".rs",
    ".sh",
    ".ts",
    ".tsx",
    ".zsh",
}
build_names = {
    "Dockerfile",
    "Justfile",
    "Makefile",
    "Rakefile",
    "dockerfile",
    "justfile",
    "makefile",
}
excluded_prefixes = (".git/", "runtime/")
excluded_exact = {"Upkeeper.log"}
test_dirs = {"__tests__", "test", "tests"}


def is_test_path(path: str) -> bool:
    parts = path.split("/")
    name = parts[-1]
    return (
        any(part in test_dirs for part in parts)
        or name.startswith("test_")
        or name.endswith("_test.py")
    )


def executable_text_candidate(path: str) -> bool:
    try:
        with open(path, "rb") as handle:
            sample = handle.read(4096)
    except OSError:
        return False
    return b"\0" not in sample


def git_output(args: list[str]) -> str:
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()
    except subprocess.CalledProcessError:
        return ""


def root_relative(path: str) -> str:
    try:
        rel_path = os.path.relpath(path, root)
    except ValueError:
        return ""
    if rel_path == "." or rel_path.startswith("../") or os.path.isabs(rel_path):
        return ""
    return rel_path.replace(os.sep, "/")


def normalized_repo_target(path: str) -> str:
    if not path:
        return ""
    expanded = os.path.expanduser(path)
    if os.path.isabs(expanded):
        rel_path = root_relative(expanded)
    else:
        rel_path = os.path.normpath(expanded).replace(os.sep, "/")
        if rel_path == "." or rel_path.startswith("../") or os.path.isabs(rel_path):
            rel_path = ""
    return rel_path


def selected_git_metadata(path: str) -> dict[str, str]:
    status_output = git_output(["git", "status", "--porcelain=v1", "--", path])
    status_code = status_output[:2] if status_output else "clean"
    worktree_hash = git_output(["git", "hash-object", "--", path]) or "unknown"
    head_blob = git_output(["git", "rev-parse", f"HEAD:{path}"]) or "none"
    if head_blob == "none":
        content_state = "untracked"
    elif worktree_hash == head_blob:
        content_state = "matches_head"
    else:
        content_state = "differs_from_head"

    return {
        "git_status": status_code.replace(" ", "_"),
        "content_state": content_state,
        "head_blob": head_blob,
        "worktree_hash": worktree_hash,
    }


raw_paths = subprocess.check_output(["git", "ls-files", "-co", "--exclude-standard", "-z"])
paths = raw_paths.decode("utf-8", "surrogateescape").split("\0")
now = time.time()
candidates = []
repo_local_self_candidates = set()
self_rel = root_relative(self_path)
if self_rel:
    repo_local_self_candidates.add(self_rel)
if os.path.isfile("Upkeeper"):
    repo_local_self_candidates.add("Upkeeper")
if os.path.isfile("Upkeeper.sh"):
    repo_local_self_candidates.add("Upkeeper.sh")

for path in paths:
    if not path:
        continue
    if path in excluded_exact or path.startswith(excluded_prefixes) or is_test_path(path):
        continue
    try:
        stat_result = os.stat(path)
    except OSError:
        continue
    if not statmod.S_ISREG(stat_result.st_mode):
        continue

    name = os.path.basename(path)
    ext = os.path.splitext(name)[1].lower()
    is_candidate = name in build_names or ext in script_exts
    if not is_candidate and stat_result.st_mode & 0o111:
        is_candidate = executable_text_candidate(path)
    if is_candidate:
        candidates.append((stat_result.st_mtime, path))

if startup_anomaly_gate == "1" and startup_force_upkeeper == "1":
    for path in sorted(repo_local_self_candidates):
        if any(candidate_path == path for _, candidate_path in candidates):
            continue
        try:
            stat_result = os.stat(path)
        except OSError:
            continue
        if statmod.S_ISREG(stat_result.st_mode):
            candidates.append((stat_result.st_mtime, path))

if not candidates:
    sys.exit(0)

all_self_candidates = [item for item in candidates if item[1] in repo_local_self_candidates]
stale_self_candidates = [
    item
    for item in all_self_candidates
    if now - item[0] >= self_review_threshold_seconds
]
forced_target = normalized_repo_target(forced_target)
if forced_target:
    forced_candidates = [item for item in candidates if item[1] == forced_target]
    if not forced_candidates:
        print(
            f"--target-file={forced_target} is not an eligible source-safe script/tool target",
            file=sys.stderr,
        )
        sys.exit(8)
    mtime, path = forced_candidates[0]
    selection_basis = (
        f"operator --target-file={forced_target} override; "
        "normal oldest eligible selection bypassed for this invoked cycle"
    )
elif startup_anomaly_gate == "1" and startup_force_upkeeper == "1" and not all_self_candidates:
    print(
        "startup anomaly gate requires a repo-local Upkeeper candidate; "
        "normal oldest eligible selection is blocked",
        file=sys.stderr,
    )
    sys.exit(7)
elif startup_anomaly_gate == "1" and startup_force_upkeeper == "1" and all_self_candidates:
    mtime, path = sorted(all_self_candidates, key=lambda item: (item[0], item[1]))[0]
    selection_basis = (
        "startup anomaly gate forced repo-local Upkeeper first; "
        "normal oldest eligible selection blocked until Upkeeper suite is checked/remediated"
    )
elif stale_self_candidates:
    mtime, path = sorted(stale_self_candidates, key=lambda item: (item[0], item[1]))[0]
    selection_basis = (
        "stale repo-local Upkeeper script first "
        f"(age >= {self_review_after_days}d threshold); normal oldest eligible selection bypassed"
    )
else:
    mtime, path = sorted(candidates, key=lambda item: (item[0], item[1]))[0]
    selection_basis = "oldest eligible non-test script/tool from git ls-files -co --exclude-standard"
age_seconds = max(0, int(now - mtime))
mtime_text = datetime.datetime.fromtimestamp(mtime).astimezone().strftime(
    "%Y-%m-%d %H:%M:%S %z"
)
metadata = selected_git_metadata(path)

print(f"path={path}")
print(f"epoch={int(mtime)}")
print(f"mtime={mtime_text}")
print(f"age={age_seconds // 3600}h {(age_seconds % 3600) // 60}m")
print(f"git_status={metadata['git_status']}")
print(f"content_state={metadata['content_state']}")
print(f"head_blob={metadata['head_blob']}")
print(f"worktree_hash={metadata['worktree_hash']}")
print(f"eligible_count={len(candidates)}")
print(f"self_review_threshold_days={self_review_after_days}")
print(f"selection_basis={selection_basis}")
PY
}

append_preselected_review_target() {
  local compiled_file="$1"
  local selection selector_rc err_file detail selected_path selected_epoch selected_age eligible_count selected_git_status selected_content_state selected_worktree_hash selected_basis

  if ! err_file="$(run_mktemp preselect-error)"; then
    log_line "WARN" "review.preselect.skip reason=tempfile_failed"
    return 0
  fi

  set +e
  selection="$(preselect_review_target 2>"$err_file")"
  selector_rc=$?
  set -e
  if [[ "$selector_rc" -ne 0 ]]; then
    detail="$(tr '\n' ' ' <"$err_file" | sed 's/[[:space:]]\+/ /g' | cut -c1-400)"
    rm -f "$err_file"
    if [[ "$selector_rc" -eq 7 ]]; then
      log_line "ERROR" "review.preselect.blocked reason=startup_anomaly_requires_repo_local_upkeeper detail=$(shell_quote "${detail:-unknown_error}") implementation=$(shell_quote "$SELF_PATH") root=$(shell_quote "$ROOT_DIR")"
      if ! write_startup_anomaly_gate_state "unresolved" "preselect_no_repo_local_upkeeper_candidate"; then
        finish_cycle 7 STARTUP_ANOMALY_STATE_UNWRITABLE ERROR "codex_exec_started=0 implementation=$(shell_quote "$SELF_PATH") root=$(shell_quote "$ROOT_DIR")"
      fi
      finish_cycle 7 STARTUP_ANOMALY_REQUIRES_CENTRAL_UPKEEPER WARN "codex_exec_started=0 implementation=$(shell_quote "$SELF_PATH") root=$(shell_quote "$ROOT_DIR")"
    fi
    if [[ "$selector_rc" -eq 8 ]]; then
      log_line "ERROR" "review.preselect.blocked reason=target_file_not_eligible target_file=$(shell_quote "$CODEX_TARGET_FILE") detail=$(shell_quote "${detail:-unknown_error}")"
      finish_cycle 3 TARGET_FILE_NOT_ELIGIBLE ERROR "codex_exec_started=0 target_file=$(shell_quote "$CODEX_TARGET_FILE") detail=$(shell_quote "${detail:-unknown_error}")"
    fi
    log_line "WARN" "review.preselect.skip reason=selector_failed detail=$(shell_quote "${detail:-unknown_error}")"
    return 0
  fi
  rm -f "$err_file"

  if [[ -z "$selection" ]]; then
    log_line "WARN" "review.preselect.none reason=no_eligible_script_tool"
    return 0
  fi

  selected_path="$(sed -n 's/^path=//p' <<<"$selection")"
  selected_epoch="$(sed -n 's/^epoch=//p' <<<"$selection")"
  selected_age="$(sed -n 's/^age=//p' <<<"$selection")"
  selected_git_status="$(sed -n 's/^git_status=//p' <<<"$selection")"
  selected_content_state="$(sed -n 's/^content_state=//p' <<<"$selection")"
  selected_worktree_hash="$(sed -n 's/^worktree_hash=//p' <<<"$selection")"
  selected_basis="$(sed -n 's/^selection_basis=//p' <<<"$selection")"
  eligible_count="$(sed -n 's/^eligible_count=//p' <<<"$selection")"
  RUN_SELECTED_REVIEW_PATH="$selected_path"
  RUN_SELECTED_REVIEW_BASIS="$selected_basis"

  {
    printf 'WRAPPER_PRESELECTED_REVIEW_TARGET\n'
    printf '%s\n' "$selection"
    printf '\nRules for this preselected target:\n'
    printf -- '- This block is authoritative. Start by verifying and reading this selected file; do not run candidate-discovery scans first.\n'
    printf -- '- This target is the timestamp-selected file for this cycle.\n'
    printf -- '- Verify only this file exists, is readable, and is eligible before reviewing it.\n'
    printf -- '- This preselected target overrides all later P1-P23 selection rules; run applicable prompts against this same file.\n'
    printf -- '- Use git_status/content_state/head_blob/worktree_hash above as the pre-run baseline for this file.\n'
    printf -- '- If content_state differs_from_head or git_status is not clean, that dirty content existed before this review; do not reset it or block solely because git diff versus HEAD is non-empty.\n'
    printf -- '- For a clean no-edit pass, record the selected file hash before touch, touch it, then verify the mtime changed and the content hash is unchanged from the pre-touch hash.\n'
    printf -- '- Do not run broad repository discovery commands to second-guess this selection.\n'
    printf -- '- If this target is physically impossible or unsafe to review, state the exception and then use the same source-safe selection boundary for the replacement.\n'
    if [[ -n "$CODEX_TARGET_FILE" ]]; then
      printf -- '- This target was pinned by operator flag `--target-file=%s`; do not replace it unless the physical/safety exception above applies.\n' "$CODEX_TARGET_FILE"
    fi
  } >>"$compiled_file"

  log_line "INFO" "review.preselect path=$(shell_quote "$selected_path") epoch=${selected_epoch:-unknown} age=$(shell_quote "${selected_age:-unknown}") git_status=${selected_git_status:-unknown} content_state=${selected_content_state:-unknown} worktree_hash=${selected_worktree_hash:-unknown} eligible_count=${eligible_count:-unknown} basis=$(shell_quote "${selected_basis:-unknown}")"
  terminal_emit_progress "file selected is ${selected_path:-unknown}; reason: ${selected_basis:-unknown}; age=${selected_age:-unknown}"
}

operator_guide_snapshot_version() {
  local guide_path="$1"
  local line version

  while IFS= read -r line; do
    case "$line" in
      "Version: "*)
        version="${line#Version: }"
        version="${version%%[[:space:]]*}"
        [[ -n "$version" ]] || return 1
        printf '%s' "$version"
        return 0
        ;;
    esac
  done <"$guide_path"

  return 1
}

operator_guide_is_ignored() {
  local guide_path="$1"
  local rel_path

  [[ "$guide_path" == "$ROOT_DIR/"* ]] || return 1
  rel_path="${guide_path#"$ROOT_DIR/"}"
  git -C "$ROOT_DIR" check-ignore -q --no-index -- "$rel_path" 2>/dev/null
}

check_existing_operator_guide() {
  local guide_path="$1"
  local guide_version

  if [[ ! -f "$guide_path" ]]; then
    log_line "WARN" "operator_guide.invalid path=$guide_path reason=not_regular_file current_version=$UPKEEPER_VERSION action=manual_fix"
    return 0
  fi

  if [[ ! -r "$guide_path" ]]; then
    log_line "WARN" "operator_guide.unreadable path=$guide_path current_version=$UPKEEPER_VERSION action=manual_fix"
    return 0
  fi

  if ! guide_version="$(operator_guide_snapshot_version "$guide_path")"; then
    if operator_guide_is_ignored "$guide_path"; then
      log_line "INFO" "operator_guide.local_version_missing path=$guide_path current_version=$UPKEEPER_VERSION action=ignored_local_notes"
      return 0
    fi
    log_line "WARN" "operator_guide.version_missing path=$guide_path current_version=$UPKEEPER_VERSION action=manual_refresh_preserve_local_notes"
    return 0
  fi

  if [[ "$guide_version" != "$UPKEEPER_VERSION" ]]; then
    if operator_guide_is_ignored "$guide_path"; then
      log_line "INFO" "operator_guide.local_stale path=$guide_path guide_version=$guide_version current_version=$UPKEEPER_VERSION action=ignored_local_notes"
      return 0
    fi
    log_line "WARN" "operator_guide.stale path=$guide_path guide_version=$guide_version current_version=$UPKEEPER_VERSION action=manual_refresh_preserve_local_notes"
  fi
}
