# Human-facing inline help. This is also the seed text for a missing tracked
# operator guide; once the guide exists, the Markdown becomes the living document.
show_help() {
  cat <<EOF
Usage: $SCRIPT_NAME [--help] [--version] [--config-file=PATH] [--no-config] [--prompt-file FILE] [--prompt TEXT] [--review-module=p24|p25|p26|p27|p28|p29] [--review-modules=p24,p25,p26,p27,p28,p29] [--p24] [--p25] [--p26] [--p27] [--p28] [--p29] [--model-override=5.5_xhigh] [--target-file=PATH] [--target-root=PATH] [--target-depth=N] [--selection-source=manifest|enumerate] [--selection-order=oldest|newest|random] [--refresh-manifest] [--manifest-file=PATH] [--include-glob=PATTERN] [--include-globs=a,b] [--exclude-glob=PATTERN] [--exclude-globs=a,b] [--selection-review-modules=p24,p25,p26,p27,p28,p29] [--ignore-failure-queue] [--backup-queue] [--prompt-pass=all] [--max-cover]

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
     to one stronger fallback cycle in the same outer-loop iteration.

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
  - root log rotation archives live logs older than ${CODEX_LOG_ROTATE_AFTER_HOURS} hours
    and prunes sibling zip archives older than ${CODEX_LOG_ROTATE_KEEP_HOURS} hours on startup.
  - by default, live terminal output is basic: routine INFO logs and full
    backend transcripts stay in log/transcript artifacts, while selected target,
    Codex start/finish, long-running heartbeats, status, checks/tests/validation
    progress, WARN, ERROR, separated bounded "LLM:" task-status blocks before
    backend tool phases, and a final review/finding/change/verification summary
    remain visible;
    transcript artifacts live under:
      ${CODEX_TRANSCRIPT_DIR}
    and are pruned after ${CODEX_TRANSCRIPT_KEEP_HOURS} hours or when the
    directory exceeds ${CODEX_TRANSCRIPT_KEEP_MAX_MB} MB;
    use CODEX_TERMINAL_VERBOSITY=verbose for command-level progress,
    debug1 for the first diagnostic tier, quiet for only major progress and
    problems, silent for no routine terminal chatter, or full to stream the raw
    backend transcript

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
    Symlinked clients share that central prompt and central review modules;
    local prompt files are only needed for explicit --prompt-file overrides.
  - The central checkout can be validated without launching real Codex work with:
      tools/validate_upkeeper.sh --deps
      tools/validate_upkeeper.sh --quick
      tools/validate_upkeeper.sh --full
    Full validation uses dry-runs plus a local fake codex binary, not real
    backend work.
    GitHub Actions runs the no-quota CI path in .github/workflows/ci.yml on
    pushes and pull requests: shell syntax, tests/*.bash, public docs, and
    tools/validate_upkeeper.sh --quick.
    Sample-repo stress coverage is available without backend quota with:
      tools/stress_upkeeper_corpus.sh --local
    Full validation runs that local stress corpus after the central wrapper
    checks.
    Runtime/tool dependencies are documented in docs/dependencies.md. GitHub's
    dependency graph is useful future-proofing, but it will not list Bash system
    tools unless the repo later adds a supported manifest, workflow, or
    dependency submission.
    Backward compatibility is documented in docs/compatibility.md. Existing
    operator-visible behavior should be preserved unless compatibility would be
    unsafe or impossible.
    Security and local trust boundaries are documented in docs/security.md.
    Read that page before using unreviewed config files, broad sandbox modes,
    shared machines, or repositories that may contain secrets.
    Local sample-repo stress testing is documented in docs/stress-corpus.md;
    those checks default to no real backend Codex work and keep model-backed
    sample runs behind explicit future opt-in commands.
  - The default active config file is:
      $UPKEEPER_CONFIG_DEFAULT_FILE
    The central checkout tracks that file plus configurations/default.conf as a
    basic profile template. Use --config-file=PATH to select one shell-compatible
    config file for this invocation, or --no-config to skip the default config.
    Relative config paths are resolved from the invocation repository root.
    Config files may set CODEX_* runtime knobs and UPKEEPER_* flag defaults such
    as UPKEEPER_TARGET_FILE, UPKEEPER_REVIEW_MODULES, UPKEEPER_PROMPT_FILE,
    UPKEEPER_PROMPT, UPKEEPER_PROMPT_PASS, UPKEEPER_MODEL_OVERRIDE, and
    UPKEEPER_IGNORE_FAILURE_QUEUE. They may also set selection defaults such as
    UPKEEPER_SELECTION_SOURCE, UPKEEPER_SELECTION_ORDER,
    UPKEEPER_FILE_MANIFEST_MODE, UPKEEPER_TARGET_ROOT,
    UPKEEPER_TARGET_MAX_DEPTH, UPKEEPER_INCLUDE_GLOBS,
    UPKEEPER_EXCLUDE_GLOBS, and UPKEEPER_SELECTION_REVIEW_MODULES. CLI flags
    remain the final one-cycle overrides.
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
  - The default prompt makes the primary agent inspect this cycle's own log:
      $LOG_FILE
    before its final marker. If the log review exposes a concrete wrapper or
    prompt defect and the current repo owns the central Upkeeper file, the agent
    may repair it in the same pass and report that self-repair explicitly.
  - Every log line includes a per-cycle run_hash. The wrapper emits --MARK--
    heartbeat lines with fractional epoch, boot id, and uptime so missing
    continuity can be detected even when both the primary process and a future
    watchdog fail.
  - Startup scans the recent live log for prior cycles that started but never
    wrote cycle.exit/run.finish, logs previous_run.anomaly lines, and injects
    those findings into the prompt for the next healthy run.
  - Startup also logs disk.preflight lines for repo, log, Codex home/session,
    temp, bwrap, arg0, and runtime paths. Path-like fields are shell-quoted for
    parseable logs, and startup injects a prompt note when any write-critical
    root is below ${CODEX_DISK_MIN_FREE_PERCENT}% free.
  - Startup anomalies are a gate by default: while prior-run, watchdog-style, or
    low-disk anomaly evidence is active, preselection is forced to the repo-local
    Upkeeper implementation and normal timestamp rotation is blocked until the
    Upkeeper suite is checked or remediated.

Prompt behavior:
  - By default, the wrapper maintains a local file manifest at
      $CODEX_FILE_MANIFEST_PATH
    and selects the oldest eligible script/tool file by last-modified timestamp.
    If the manifest is missing, stale, invalid, or out of sync with local file
    metadata, startup refreshes it before selection. Set
    --selection-source=enumerate for a one-cycle direct scan without using the
    manifest, or --refresh-manifest to rebuild the manifest immediately.
  - Upkeeper Lattice is enabled by default as a local SQLite evidence ledger at:
      $UPKEEPER_LATTICE_DB
    It records cycle starts/finishes, preselection evidence, candidate rows,
    pass-result markers, worktree snapshots, imports, exports, backups, and
    recovery facts under ignored runtime state. Lattice does not replace live
    source-safe eligibility; explicit targets, startup anomaly gates, and the
    local failure queue still keep their existing priority.
    If Lattice is unavailable and UPKEEPER_LATTICE_REQUIRED=0, the wrapper logs
    one warning, spools a small recovery record when possible, and continues the
    existing cycle behavior. If UPKEEPER_LATTICE_REQUIRED=1, startup fails
    before Codex launch.
  - Exception: when the repo-local Upkeeper implementation itself is eligible
    and has not been touched for at least
    ${CODEX_UPKEEPER_SELF_REVIEW_AFTER_DAYS} days, it is selected first. If it is
    newer than that threshold, normal oldest-file selection applies.
  - Before launching Codex, the wrapper preselects that script/tool target from
    the manifest or a local enumeration pass and prepends the selected path to
    the prompt. That avoids spending model/tool cycles on broad tree discovery
    and keeps .git/, ignored paths, runtime evidence, generated outputs, and
    tests out of the selection scan.
  - A repo-root .upkeeperignore, or the file named by UPKEEPER_IGNORE_FILE,
    is a target-selection firewall. It uses simple Gitignore-style glob lines
    to block normal rotation, Lattice/max-cover candidates, failure-queue target
    eligibility, manifest entries, and explicit --target-file pins. It controls
    spend/selection only; it is not a Git, sandbox, or secret-protection rule.
  - When a prior run leaves an open local tool-failure marker, preselection
    chooses the oldest still-eligible marked target after explicit operator
    pins and startup anomaly gates, but before stale-self and normal timestamp
    rotation. This is local queue behavior, not another model pass.
    New command failures stay queued unless a later successful command of the
    same broad kind shows the failure was rechecked.
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
  - --config-file=PATH selects a shell-compatible config file for this invoked
    cycle. Use the equals form; spaced form is rejected.
  - --no-config disables the default config for this invoked cycle.
  - --prompt-file FILE appends extra task guidance from FILE.
  - --prompt TEXT appends extra task guidance inline.
  - --review-module=p24 appends the central P24 de-LLM-ing viability review
    module for this invoked cycle.
  - --review-module=p25 appends the central P25 contract and intent compliance
    review module for this invoked cycle.
  - --review-module=p26 appends the central P26 public documentation review
    module for this invoked cycle.
  - --review-module=p27 appends the central P27 educational debrief review
    module for this invoked cycle.
  - --review-module=p28 appends the central P28 unit test harvesting review
    module for this invoked cycle.
  - --review-module=p29 appends the central P29 reuse harvesting review module
    for this invoked cycle.
  - --review-modules=p24,p25,p26,p27,p28,p29 appends multiple modules in a single flag;
    repeated --review-module flags are also accepted and duplicate modules are ignored.
  - --p24, --p25, --p26, --p27, --p28, and --p29 are shorthand aliases for the corresponding review modules.
    Review module flags are one-cycle guidance only and do not persist to later
    loop iterations. They are not enabled by --prompt-pass=all unless requested.
  - --model-override=5.5_xhigh runs this invoked cycle once as gpt-5.5
    with xhigh reasoning effort. It is a CLI-only operator override and does
    not persist to later loop iterations. Use the equals form; spaced form is
    rejected.
  - --target-file=PATH pins this invoked cycle to one source-safe readable text
    file and bypasses timestamp selection, selection filters, and the local
    failure queue. Explicit pins may target tracked or non-ignored untracked
    docs, prompts, configs, tests, or scripts inside the repo. They still reject
    .git, ignored paths, runtime evidence, generated outputs, directories,
    unreadable files, and binary-looking files. Use the equals form; spaced form
    is rejected.
  - --target-root=PATH restricts timestamp selection to one file or directory
    tree; --target-depth=N limits descendant depth below that root.
  - --selection-order=oldest, newest, or random chooses the target ordering for
    this invoked cycle. --random-target is shorthand for random ordering.
  - --selection-source=manifest uses the local manifest; --selection-source=enumerate
    bypasses it for this cycle. --refresh-manifest rebuilds and uses the
    manifest immediately.
  - --manifest-file=PATH selects a different local manifest path for this cycle.
  - --include-glob=PATTERN and --exclude-glob=PATTERN add local path filters;
    --include-globs=a,b and --exclude-globs=a,b replace the configured lists.
  - --selection-review-modules=p24,p25,p26,p27,p28,p29 filters candidates using
    deterministic local approximations for files likely relevant to those
    optional review modules. It is a selection filter, not a review-module
    prompt request; pair it with --review-module when you want both.
  - --ignore-failure-queue bypasses local unaddressed tool-failure markers for
    this invoked cycle only. --target-file also takes priority over the queue.
  - --backup-queue, or legacy spelling -backup_queue, uses
    runtime/unaddressed-tool-failures-backup for this invoked cycle instead of
    the normal local failure queue.
  - --prompt-pass=all forces the selected target through all P1-P23 repertoire
    passes for this invoked cycle. Use the equals form; spaced form is rejected.
  - --max-cover is a one-cycle high-coverage mode. It sets --prompt-pass=all,
    appends P24-P29, and asks Lattice for max-cover target ranking across
    current tracked source-safe text files. Explicit targets, startup anomaly
    gates, and active failure-queue markers still keep their existing priority.

Environment overrides:
  UPKEEPER_CONFIG_FILE          Default: $UPKEEPER_CONFIG_DEFAULT_FILE
  UPKEEPER_CONFIG_DISABLE       Default: 0
  UPKEEPER_TARGET_FILE          Default: empty
  UPKEEPER_REVIEW_MODULES       Default: empty
  UPKEEPER_PROMPT_FILE          Default: empty
  UPKEEPER_PROMPT               Default: empty
  UPKEEPER_PROMPT_PASS          Default: empty
  UPKEEPER_MODEL_OVERRIDE       Default: empty
  UPKEEPER_IGNORE_FAILURE_QUEUE Default: 0
  UPKEEPER_SELECTION_SOURCE     Default: manifest
  UPKEEPER_SELECTION_ORDER      Default: oldest
  UPKEEPER_FILE_MANIFEST_MODE   Default: auto
  UPKEEPER_FILE_MANIFEST_PATH   Default: runtime/upkeeper-file-manifest.json
  UPKEEPER_IGNORE_FILE          Default: .upkeeperignore
  UPKEEPER_TARGET_ROOT          Default: empty
  UPKEEPER_TARGET_MAX_DEPTH     Default: empty
  UPKEEPER_INCLUDE_GLOBS        Default: empty
  UPKEEPER_EXCLUDE_GLOBS        Default: empty
  UPKEEPER_SELECTION_REVIEW_MODULES Default: empty
  UPKEEPER_MAX_COVER           Default: 0
  UPKEEPER_LATTICE_ENABLED     Default: 1
  UPKEEPER_LATTICE_REQUIRED    Default: 0
  UPKEEPER_LATTICE_DB          Default: runtime/upkeeper-lattice/lattice.sqlite3
  UPKEEPER_LATTICE_SELECTION_MODE Default: oldest-mtime
  UPKEEPER_LATTICE_RAW_STORAGE Default: limited
  UPKEEPER_LATTICE_SQLITE_JOURNAL_MODE Default: delete
  CODEX_FILE_MANIFEST_MAX_AGE_SECONDS Default: 300
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
  CODEX_TOOL_FAILURE_QUEUE_ENABLED Default: 1
  CODEX_TOOL_FAILURE_QUEUE_DIR Default: $ROOT_DIR/runtime/unaddressed-tool-failures
  CODEX_ACTIVE_LOCK_DIR Default: $ROOT_DIR/runtime/upkeeper-active.lock
  CODEX_WRAPPER_HEALTH_STATE_DIR Default: $CODEX_HOME_DIR/upkeeper/active-wrapper-runs
  CODEX_WRAPPER_HEALTH_ARCHIVE_DIR Default: $CODEX_HOME_DIR/upkeeper/retired-wrapper-runs
  CODEX_SESSION_SCAN_LIMIT      Default: 200
  CODEX_LOG_FILE                Default: $ROOT_DIR/Upkeeper.log
  UPKEEPER_DRY_RUN           Default: 0

Exit codes:
  0  One cycle completed, dry-run completed, or the loop was stopped on quota guardrails
  2  Codex reported BLOCKED
  3  Wrapper/setup or Codex launch/capture error
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
  python3 - "$ROOT_DIR" "$SELF_PATH" "$CODEX_UPKEEPER_SELF_REVIEW_AFTER_DAYS" "$STARTUP_ANOMALY_GATE" "$CODEX_STARTUP_ANOMALY_FORCE_UPKEEPER" "$CODEX_TARGET_FILE" "$CODEX_TOOL_FAILURE_QUEUE_DIR" "$CODEX_TOOL_FAILURE_QUEUE_ENABLED" "$CODEX_TOOL_FAILURE_QUEUE_BYPASS" "$CODEX_SELECTION_SOURCE" "$CODEX_FILE_MANIFEST_PATH" "$CODEX_SELECTION_ORDER" "$CODEX_TARGET_ROOT" "$CODEX_TARGET_MAX_DEPTH" "$CODEX_SELECTION_INCLUDE_GLOBS" "$CODEX_SELECTION_EXCLUDE_GLOBS" "$CODEX_SELECTION_REVIEW_MODULES" "$CODEX_SELECTION_RANDOM_SEED" "$CODEX_MAX_COVER_MODE" "$UPKEEPER_LATTICE_ENABLED" "$UPKEEPER_LATTICE_SELECTION_MODE" "$(lattice_tool_path)" "$UPKEEPER_LATTICE_DB" "$UPKEEPER_LATTICE_SQLITE_JOURNAL_MODE" "$CODEX_UPKEEPER_IGNORE_FILE" <<'PY'
import datetime
import fnmatch
import json
import os
import random
import stat as statmod
import subprocess
import sys
import time
from pathlib import Path

(
    root,
    self_path,
    self_review_after_days,
    startup_anomaly_gate,
    startup_force_upkeeper,
    forced_target,
    failure_queue_dir,
    failure_queue_enabled,
    failure_queue_bypass,
    selection_source,
    manifest_path,
    selection_order,
    target_root,
    target_max_depth,
    include_globs,
    exclude_globs,
    selection_review_modules,
    selection_random_seed,
    max_cover_mode,
    lattice_enabled,
    lattice_selection_mode,
    lattice_tool_path,
    lattice_db_path,
    lattice_journal_mode,
    upkeeper_ignore_file,
) = sys.argv[1:26]
os.chdir(root)
root_path = Path(root).resolve()
ignore_file = Path(upkeeper_ignore_file).expanduser()
if not ignore_file.is_absolute():
    ignore_file = (root_path / ignore_file).resolve()
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


def load_upkeeperignore_patterns() -> list[tuple[bool, str]]:
    patterns: list[tuple[bool, str]] = []
    try:
        lines = ignore_file.read_text(encoding="utf-8").splitlines()
    except OSError:
        return patterns
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        negated = line.startswith("!")
        if negated:
            line = line[1:].strip()
            if not line:
                continue
        patterns.append((negated, line.replace("\\", "/")))
    return patterns


upkeeperignore_patterns = load_upkeeperignore_patterns()


def upkeeperignore_pattern_matches(path: str, pattern: str) -> bool:
    pattern = pattern.strip()
    if not pattern:
        return False
    anchored = pattern.startswith("/")
    if anchored:
        pattern = pattern.lstrip("/")
    directory_only = pattern.endswith("/")
    if directory_only:
        pattern = pattern.rstrip("/")
    if not pattern:
        return False

    if directory_only:
        if "/" in pattern or anchored:
            return path == pattern or path.startswith(pattern + "/")
        return pattern in path.split("/")

    name = os.path.basename(path)
    if anchored or "/" in pattern:
        return fnmatch.fnmatch(path, pattern)
    return fnmatch.fnmatch(name, pattern) or any(fnmatch.fnmatch(part, pattern) for part in path.split("/"))


def upkeeper_path_ignored(path: str) -> bool:
    ignored = False
    for negated, pattern in upkeeperignore_patterns:
        if upkeeperignore_pattern_matches(path, pattern):
            ignored = not negated
    return ignored


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


def git_path_is_ignored(path: str) -> bool:
    try:
        result = subprocess.run(
            ["git", "check-ignore", "-q", "--", path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        return False
    return result.returncode == 0


def explicit_target_error(path: str) -> str:
    if not path:
        return "target path is outside the repository"
    if path in excluded_exact or path.startswith(excluded_prefixes):
        return "target path is excluded from Upkeeper review"
    if upkeeper_path_ignored(path):
        return "target path is ignored by .upkeeperignore"
    if git_path_is_ignored(path):
        return "target path is ignored by git"
    try:
        stat_result = os.stat(path)
    except OSError:
        return "target path is missing or unreadable"
    if not statmod.S_ISREG(stat_result.st_mode):
        return "target path is not a regular file"
    if not os.access(path, os.R_OK):
        return "target path is not readable"
    if not executable_text_candidate(path):
        return "target path appears to be binary"
    return ""


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


def split_csv(raw: str) -> list[str]:
    return [item.strip() for item in raw.split(",") if item.strip()]


def path_matches_any(path: str, patterns: list[str]) -> bool:
    if not patterns:
        return True
    name = os.path.basename(path)
    return any(fnmatch.fnmatch(path, pattern) or fnmatch.fnmatch(name, pattern) for pattern in patterns)


def path_excluded(path: str, patterns: list[str]) -> bool:
    if not patterns:
        return False
    name = os.path.basename(path)
    return any(fnmatch.fnmatch(path, pattern) or fnmatch.fnmatch(name, pattern) for pattern in patterns)


def module_filter_match(path: str, modules: set[str]) -> bool:
    if not modules:
        return True

    lowered = path.lower()
    name = os.path.basename(lowered)
    ext = os.path.splitext(name)[1]
    parts = set(lowered.split("/"))

    def p24() -> bool:
        tokens = (
            "codex",
            "llm",
            "prompt",
            "transcript",
            "postmortem",
            "fallback",
            "report",
            "status",
            "session",
        )
        return lowered.startswith("prompts/") or any(token in lowered for token in tokens)

    def p25() -> bool:
        return (
            path in {"Upkeeper", "Upkeeper.conf", "AGENTS.md"}
            or lowered.startswith(("lib/upkeeper/", "docs/", "prompts/", "configurations/"))
            or "compatibility" in lowered
        )

    def p26() -> bool:
        return (
            ext in {".md", ".txt", ".rst"}
            or lowered.startswith(("docs/", "prompts/"))
            or name in {"readme.md", "agents.md"}
            or lowered.endswith(".conf")
        )

    def p27() -> bool:
        return "educational" in lowered or "debrief" in lowered or "p27" in lowered

    def p28() -> bool:
        return (
            "test" in parts
            or "tests" in parts
            or "spec" in parts
            or "specs" in parts
            or "validate" in lowered
            or name.endswith(("_test.py", ".bats"))
            or name.startswith("test_")
        )

    def p29() -> bool:
        reuse_tokens = {
            "artifact",
            "command",
            "config",
            "fixture",
            "format",
            "helper",
            "json",
            "marker",
            "parse",
            "parser",
            "prompt",
            "reuse",
            "status",
            "template",
            "transcript",
            "validate",
            "validation",
        }
        return (
            lowered.startswith(("lib/upkeeper/", "tools/", "tests/", "prompts/", "docs/"))
            or name in {"readme.md", "agents.md"}
            or any(token in lowered for token in reuse_tokens)
        )

    checks = {
        "p24": p24,
        "p25": p25,
        "p26": p26,
        "p27": p27,
        "p28": p28,
        "p29": p29,
    }
    return any(checks[module]() for module in modules if module in checks)


def manifest_paths(path: str) -> tuple[list[tuple[float, str]], str]:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return [], "manifest_unreadable"
    if not isinstance(payload, dict) or payload.get("schema_version") != 1:
        return [], "manifest_invalid"
    if payload.get("root") != os.path.realpath(root):
        return [], "manifest_root_mismatch"
    files = payload.get("files")
    if not isinstance(files, list):
        return [], "manifest_invalid_files"

    paths: list[tuple[float, str]] = []
    for item in files:
        if not isinstance(item, dict):
            continue
        rel_path = str(item.get("rel_path", ""))
        if not rel_path:
            continue
        try:
            mtime = float(item.get("mtime", 0))
        except (TypeError, ValueError):
            mtime = 0.0
        paths.append((mtime, rel_path))
    return paths, "manifest"


def enumerate_paths() -> tuple[list[tuple[float, str]], str]:
    try:
        raw_paths = subprocess.check_output(["git", "ls-files", "-co", "--exclude-standard", "-z"])
        raw = raw_paths.decode("utf-8", "surrogateescape").split("\0")
        source = "enumerate"
    except (OSError, subprocess.CalledProcessError):
        raw = []
        source = "enumerate"
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [name for name in dirnames if name not in {".git", "runtime"}]
            for filename in filenames:
                rel = root_relative(os.path.join(dirpath, filename))
                if rel:
                    raw.append(rel)

    paths: list[tuple[float, str]] = []
    for path in raw:
        if not path:
            continue
        try:
            stat_result = os.stat(path)
        except OSError:
            continue
        if statmod.S_ISREG(stat_result.st_mode):
            paths.append((stat_result.st_mtime, path))
    return sorted(paths, key=lambda item: (item[0], item[1])), source


def path_within_target_root(path: str, root_filter: str, max_depth: str) -> bool:
    if not root_filter:
        return True
    normalized = normalized_repo_target(root_filter)
    if not normalized:
        return False
    if path == normalized:
        depth = 0
    elif path.startswith(normalized.rstrip("/") + "/"):
        remainder = path[len(normalized.rstrip("/")) + 1 :]
        depth = len([part for part in remainder.split("/") if part])
    else:
        return False
    if max_depth:
        try:
            return depth <= int(max_depth)
        except ValueError:
            return True
    return True


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


def open_failure_markers(candidate_paths: set[str]) -> list[dict[str, object]]:
    if failure_queue_enabled != "1" or failure_queue_bypass == "1":
        return []
    open_dir = Path(failure_queue_dir) / "open"
    if not open_dir.is_dir():
        return []

    markers = []
    for marker_path in sorted(open_dir.glob("*.json")):
        try:
            with marker_path.open("r", encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(data, dict) or data.get("status") not in ("", None, "open"):
            continue
        target = str(data.get("target_path", ""))
        if target not in candidate_paths:
            continue
        try:
            first_seen = int(data.get("first_seen_epoch", data.get("last_seen_epoch", 0)) or 0)
        except (TypeError, ValueError):
            first_seen = 0
        markers.append(
            {
                "target_path": target,
                "first_seen_epoch": first_seen,
                "marker_id": str(data.get("marker_id", marker_path.stem)),
                "marker_path": str(marker_path),
                "failure_count": str(data.get("failure_count", "unknown")),
                "first_failure_kind": str(data.get("first_failure_kind", "unknown")),
                "first_failure_exit_line": str(data.get("first_failure_exit_line", "unknown")),
            }
        )
    return sorted(markers, key=lambda item: (item["first_seen_epoch"], item["target_path"], item["marker_id"]))


def source_safe_text_paths() -> list[tuple[float, str]]:
    if not git_output(["git", "rev-parse", "--is-inside-work-tree"]):
        return []
    try:
        raw = subprocess.check_output(["git", "ls-files", "-z"])
    except (OSError, subprocess.CalledProcessError):
        return []
    result: list[tuple[float, str]] = []
    for path in raw.decode("utf-8", "surrogateescape").split("\0"):
        if not path:
            continue
        if explicit_target_error(path):
            continue
        if not path_within_target_root(path, target_root, target_max_depth):
            continue
        if not path_matches_any(path, include_patterns):
            continue
        if path_excluded(path, exclude_patterns):
            continue
        if not module_filter_match(path, module_filter):
            continue
        try:
            result.append((os.stat(path).st_mtime, path))
        except OSError:
            continue
    return sorted(result, key=lambda item: (item[0], item[1]))


def lattice_ranked_max_cover_paths() -> tuple[list[dict[str, object]], str]:
    if max_cover_mode != "1":
        return [], "max_cover_disabled"
    if lattice_enabled not in ("1", "true", "TRUE", "yes", "YES", "on", "ON"):
        return [], "lattice_disabled"
    if lattice_selection_mode != "max-cover":
        return [], "lattice_mode_not_max_cover"
    if not lattice_tool_path or not os.path.isfile(lattice_tool_path):
        return [], "lattice_tool_missing"
    args = [
        "python3",
        lattice_tool_path,
        "--root",
        root,
        "--db",
        lattice_db_path,
        "--journal-mode",
        lattice_journal_mode,
        "--upkeeper-ignore-file",
        str(ignore_file),
        "query",
        "selection-candidates",
        "--mode",
        "max-cover",
        "--format",
        "jsonl",
    ]
    try:
        output = subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError):
        return [], "lattice_query_failed"

    rows: list[dict[str, object]] = []
    for line in output.splitlines():
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows, "lattice_query"


selection_source_used = selection_source
manifest_status = "not_used"
if selection_source == "manifest":
    paths, manifest_status = manifest_paths(manifest_path)
    if not paths:
        paths, selection_source_used = enumerate_paths()
        manifest_status = f"{manifest_status}_fallback_to_{selection_source_used}"
else:
    paths, selection_source_used = enumerate_paths()
    manifest_status = "enumerated"

now = time.time()
candidates = []
repo_local_self_candidates = set()
forced_target = normalized_repo_target(forced_target)
forced_target_error = explicit_target_error(forced_target) if forced_target else ""
self_rel = root_relative(self_path)
if self_rel:
    repo_local_self_candidates.add(self_rel)
if os.path.isfile("Upkeeper"):
    repo_local_self_candidates.add("Upkeeper")
if os.path.isfile("Upkeeper.sh"):
    repo_local_self_candidates.add("Upkeeper.sh")

include_patterns = split_csv(include_globs)
exclude_patterns = split_csv(exclude_globs)
module_filter = set(split_csv(selection_review_modules))

for manifest_mtime, path in paths:
    if not path:
        continue
    if path in excluded_exact or path.startswith(excluded_prefixes) or is_test_path(path):
        continue
    if upkeeper_path_ignored(path):
        continue
    is_forced_path = bool(forced_target and path == forced_target)
    if not is_forced_path:
        if not path_within_target_root(path, target_root, target_max_depth):
            continue
        if not path_matches_any(path, include_patterns):
            continue
        if path_excluded(path, exclude_patterns):
            continue
        if not module_filter_match(path, module_filter):
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
        mtime = manifest_mtime if selection_source_used == "manifest" else stat_result.st_mtime
        candidates.append((mtime, path))

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

all_self_candidates = [item for item in candidates if item[1] in repo_local_self_candidates]
stale_self_candidates = [
    item
    for item in all_self_candidates
    if now - item[0] >= self_review_threshold_seconds
]
candidate_map = {path: mtime for mtime, path in candidates}
max_cover_candidates = source_safe_text_paths() if max_cover_mode == "1" else []
max_cover_candidate_map = {path: mtime for mtime, path in max_cover_candidates}
failure_queue_candidate_map = max_cover_candidate_map if max_cover_mode == "1" and max_cover_candidate_map else candidate_map
failure_queue_markers = open_failure_markers(set(failure_queue_candidate_map))
selected_failure_marker = {}
if forced_target:
    if forced_target_error:
        print(
            f"--target-file={forced_target} is not an eligible explicit target: {forced_target_error}",
            file=sys.stderr,
        )
        sys.exit(8)
    mtime = os.stat(forced_target).st_mtime
    path = forced_target
    selection_mode = "explicit_target"
    selection_basis = (
        f"operator --target-file={forced_target} override; "
        "normal oldest eligible selection bypassed for this invoked cycle"
    )
elif not candidates and not (max_cover_mode == "1" and max_cover_candidates):
    sys.exit(0)
elif startup_anomaly_gate == "1" and startup_force_upkeeper == "1" and not all_self_candidates:
    print(
        "startup anomaly gate requires a repo-local Upkeeper candidate; "
        "normal oldest eligible selection is blocked",
        file=sys.stderr,
    )
    sys.exit(7)
elif startup_anomaly_gate == "1" and startup_force_upkeeper == "1" and all_self_candidates:
    selection_mode = "startup_anomaly_gate"
    mtime, path = sorted(all_self_candidates, key=lambda item: (item[0], item[1]))[0]
    selection_basis = (
        "startup anomaly gate forced repo-local Upkeeper first; "
        "normal oldest eligible selection blocked until Upkeeper suite is checked/remediated"
    )
elif failure_queue_markers:
    selected_failure_marker = failure_queue_markers[0]
    path = str(selected_failure_marker["target_path"])
    mtime = failure_queue_candidate_map[path]
    selection_mode = "failure_queue"
    selection_basis = (
        "oldest unaddressed local tool-failure marker forced this target; "
        "normal oldest eligible selection bypassed until the failure is checked/remediated"
    )
elif max_cover_mode == "1":
    ranked_rows, lattice_status = lattice_ranked_max_cover_paths()
    selected_row = {}
    for row in ranked_rows:
        row_path = str(row.get("path", ""))
        if row.get("candidate_state") != "eligible" or not row_path:
            continue
        if row_path not in max_cover_candidate_map:
            continue
        selected_row = row
        break
    if selected_row:
        path = str(selected_row["path"])
        mtime = max_cover_candidate_map[path]
        selection_mode = "lattice_max_cover"
        selection_basis = (
            "Lattice max-cover ranking selected the oldest current tracked text "
            "file with any unrun pass; after full pass coverage, it prefers the "
            "least-covered pass count, then oldest mtime"
        )
    elif max_cover_candidates:
        mtime, path = max_cover_candidates[0]
        selection_mode = "max_cover_fallback"
        selection_basis = (
            f"Lattice max-cover ranking unavailable ({lattice_status}); "
            "fallback selected the oldest current tracked source-safe text file"
        )
    else:
        sys.exit(0)
elif stale_self_candidates:
    mtime, path = sorted(stale_self_candidates, key=lambda item: (item[0], item[1]))[0]
    selection_mode = "stale_self_review"
    selection_basis = (
        "stale repo-local Upkeeper script first "
        f"(age >= {self_review_after_days}d threshold); normal oldest eligible selection bypassed"
    )
else:
    selection_mode = "automatic_rotation"
    sorted_candidates = sorted(candidates, key=lambda item: (item[0], item[1]))
    if selection_order == "newest":
        mtime, path = sorted(candidates, key=lambda item: (-item[0], item[1]))[0]
        selection_basis = f"newest eligible non-test script/tool from {selection_source_used} selection"
    elif selection_order == "random":
        rng = random.Random(selection_random_seed) if selection_random_seed else random.SystemRandom()
        mtime, path = rng.choice(sorted_candidates)
        selection_basis = f"random eligible non-test script/tool from {selection_source_used} selection"
    else:
        mtime, path = sorted_candidates[0]
        selection_basis = f"oldest eligible non-test script/tool from {selection_source_used} selection"

    active_filters = []
    if target_root:
        active_filters.append(f"target_root={target_root}")
    if target_max_depth:
        active_filters.append(f"target_depth={target_max_depth}")
    if include_patterns:
        active_filters.append(f"include={include_globs}")
    if exclude_patterns:
        active_filters.append(f"exclude={exclude_globs}")
    if module_filter:
        active_filters.append(f"selection_review_modules={selection_review_modules}")
    if active_filters:
        selection_basis = f"{selection_basis}; filters: " + "; ".join(active_filters)

age_seconds = max(0, int(now - mtime))
mtime_text = datetime.datetime.fromtimestamp(mtime).astimezone().strftime(
    "%Y-%m-%d %H:%M:%S %z"
)
metadata = selected_git_metadata(path)
eligible_output_count = len(max_cover_candidates) if max_cover_mode == "1" and max_cover_candidates else len(candidates)

print(f"path={path}")
print(f"epoch={int(mtime)}")
print(f"mtime={mtime_text}")
print(f"age={age_seconds // 3600}h {(age_seconds % 3600) // 60}m")
print(f"git_status={metadata['git_status']}")
print(f"content_state={metadata['content_state']}")
print(f"head_blob={metadata['head_blob']}")
print(f"worktree_hash={metadata['worktree_hash']}")
print(f"eligible_count={eligible_output_count}")
print(f"selection_mode={selection_mode}")
print(f"selection_source={selection_source_used}")
print(f"manifest_status={manifest_status}")
print(f"selection_order={selection_order}")
print(f"target_root={target_root or 'none'}")
print(f"target_max_depth={target_max_depth or 'none'}")
print(f"include_globs={include_globs or 'none'}")
print(f"exclude_globs={exclude_globs or 'none'}")
print(f"selection_review_modules={selection_review_modules or 'none'}")
print(f"self_review_threshold_days={self_review_after_days}")
if selected_failure_marker:
    print("failure_queue_selected=1")
    print(f"failure_marker_id={selected_failure_marker['marker_id']}")
    print(f"failure_marker_path={selected_failure_marker['marker_path']}")
    print(f"failure_marker_first_seen_epoch={selected_failure_marker['first_seen_epoch']}")
    print(f"failure_marker_failure_count={selected_failure_marker['failure_count']}")
    print(f"failure_marker_first_failure_kind={selected_failure_marker['first_failure_kind']}")
    print(f"failure_marker_first_failure_exit_line={selected_failure_marker['first_failure_exit_line']}")
else:
    print("failure_queue_selected=0")
print(f"selection_basis={selection_basis}")
PY
}

append_preselected_review_target() {
  local compiled_file="$1"
  local selection selector_rc err_file detail selected_path selected_epoch selected_age eligible_count selected_git_status selected_content_state selected_worktree_hash selected_basis
  local selection_mode selection_source manifest_status selection_order target_root target_max_depth include_globs exclude_globs selection_review_modules
  local failure_queue_selected failure_marker_id failure_marker_path failure_marker_first_seen_epoch failure_marker_failure_count failure_marker_first_failure_kind failure_marker_first_failure_exit_line
  local selection_file

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
  selection_mode="$(sed -n 's/^selection_mode=//p' <<<"$selection")"
  selection_source="$(sed -n 's/^selection_source=//p' <<<"$selection")"
  manifest_status="$(sed -n 's/^manifest_status=//p' <<<"$selection")"
  selection_order="$(sed -n 's/^selection_order=//p' <<<"$selection")"
  target_root="$(sed -n 's/^target_root=//p' <<<"$selection")"
  target_max_depth="$(sed -n 's/^target_max_depth=//p' <<<"$selection")"
  include_globs="$(sed -n 's/^include_globs=//p' <<<"$selection")"
  exclude_globs="$(sed -n 's/^exclude_globs=//p' <<<"$selection")"
  selection_review_modules="$(sed -n 's/^selection_review_modules=//p' <<<"$selection")"
  failure_queue_selected="$(sed -n 's/^failure_queue_selected=//p' <<<"$selection")"
  failure_marker_id="$(sed -n 's/^failure_marker_id=//p' <<<"$selection")"
  failure_marker_path="$(sed -n 's/^failure_marker_path=//p' <<<"$selection")"
  failure_marker_first_seen_epoch="$(sed -n 's/^failure_marker_first_seen_epoch=//p' <<<"$selection")"
  failure_marker_failure_count="$(sed -n 's/^failure_marker_failure_count=//p' <<<"$selection")"
  failure_marker_first_failure_kind="$(sed -n 's/^failure_marker_first_failure_kind=//p' <<<"$selection")"
  failure_marker_first_failure_exit_line="$(sed -n 's/^failure_marker_first_failure_exit_line=//p' <<<"$selection")"
  RUN_SELECTED_REVIEW_PATH="$selected_path"
  RUN_SELECTED_REVIEW_BASIS="$selected_basis"
  RUN_SELECTED_FROM_FAILURE_QUEUE="${failure_queue_selected:-0}"
  RUN_SELECTED_FAILURE_MARKER_ID="$failure_marker_id"
  RUN_SELECTED_FAILURE_MARKER_PATH="$failure_marker_path"
  if selection_file="$(run_mktemp lattice-preselect)"; then
    printf '%s\n' "$selection" >"$selection_file"
    lattice_record_preselect "$selection_file" ""
  fi

  {
    printf 'WRAPPER_PRESELECTED_REVIEW_TARGET\n'
    printf '%s\n' "$selection"
    printf '\nRules for this preselected target:\n'
    printf -- '- This block is authoritative. Start by verifying and reading this selected file; do not run candidate-discovery scans first.\n'
    if [[ "${selection_mode:-unknown}" == "explicit_target" ]]; then
      printf -- '- This target was explicitly pinned by the operator for this cycle; normal timestamp rotation, failure queue, and selection filters were bypassed.\n'
    else
      printf -- '- This target came from Upkeeper preselection mode `%s` for this cycle.\n' "${selection_mode:-unknown}"
    fi
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
    if [[ "${failure_queue_selected:-0}" == "1" ]]; then
      printf -- '- This target was forced by the local unaddressed tool-failure queue. Treat the queued failure as the priority repair/upkeep task before normal timestamp care.\n'
      printf -- '- Queue marker: id=%s first_seen_epoch=%s failure_count=%s first_failure_kind=%s first_failure_exit=%s\n' "$failure_marker_id" "${failure_marker_first_seen_epoch:-unknown}" "${failure_marker_failure_count:-unknown}" "${failure_marker_first_failure_kind:-unknown}" "${failure_marker_first_failure_exit_line:-unknown}"
      printf -- '- If the failure is resolved or no longer reproducible, finish with WORK_DONE so the local marker can be moved out of the active queue.\n'
    fi
    if [[ "${target_root:-none}" != "none" || "${include_globs:-none}" != "none" || "${exclude_globs:-none}" != "none" || "${selection_review_modules:-none}" != "none" ]]; then
      printf -- '- This cycle used a deterministic selection subset: source=%s order=%s target_root=%s target_depth=%s include=%s exclude=%s review_module_filter=%s.\n' "${selection_source:-unknown}" "${selection_order:-unknown}" "${target_root:-none}" "${target_max_depth:-none}" "${include_globs:-none}" "${exclude_globs:-none}" "${selection_review_modules:-none}"
    fi
  } >>"$compiled_file"

  log_line "INFO" "review.preselect path=$(shell_quote "$selected_path") epoch=${selected_epoch:-unknown} age=$(shell_quote "${selected_age:-unknown}") git_status=${selected_git_status:-unknown} content_state=${selected_content_state:-unknown} worktree_hash=${selected_worktree_hash:-unknown} eligible_count=${eligible_count:-unknown} selection_mode=${selection_mode:-unknown} selection_source=${selection_source:-unknown} manifest_status=$(shell_quote "${manifest_status:-unknown}") selection_order=${selection_order:-unknown} target_root=$(shell_quote "${target_root:-none}") target_depth=$(shell_quote "${target_max_depth:-none}") include_globs=$(shell_quote "${include_globs:-none}") exclude_globs=$(shell_quote "${exclude_globs:-none}") selection_review_modules=$(shell_quote "${selection_review_modules:-none}") failure_queue_selected=${failure_queue_selected:-0} failure_marker_id=$(shell_quote "${failure_marker_id:-none}") basis=$(shell_quote "${selected_basis:-unknown}")"
  terminal_emit_progress "selected file ${selected_path:-unknown} (age=${selected_age:-unknown}; mode=${selection_mode:-unknown}; source=${selection_source:-unknown}; order=${selection_order:-unknown}; reason=${selected_basis:-unknown}; eligible=${eligible_count:-unknown})"
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
