# Upkeeper

Operator guide for the repo-local `Upkeeper` wrapper.

Keep this file in sync with `./Upkeeper --help` and the wrapper's operational
behavior. The wrapper only bootstraps this guide when it is missing; it does not
overwrite future edits.

Path examples below are normalized to repo-relative or environment-based paths.
`./Upkeeper --help` prints fully resolved local paths for the current machine.

## Behavior Summary

```text
Usage: Upkeeper [--help] [--version] [--config-file=PATH] [--no-config] [--prompt-file FILE] [--prompt TEXT] [--review-module=p24|p25|p26|p27|p28|p29] [--review-modules=p24,p25,p26,p27,p28,p29] [--p24] [--p25] [--p26] [--p27] [--p28] [--p29] [--model-override=5.5_xhigh] [--target-file=PATH] [--target-root=PATH] [--target-depth=N] [--selection-source=manifest|enumerate] [--selection-order=oldest|newest|random] [--refresh-manifest] [--manifest-file=PATH] [--include-glob=PATTERN] [--include-globs=a,b] [--exclude-glob=PATTERN] [--exclude-globs=a,b] [--selection-review-modules=p24,p25,p26,p27,p28,p29] [--ignore-failure-queue] [--prompt-pass=all]

One-cycle Codex backend worker with quota guardrails.
Version: v1.2.1

Each invocation:
  1. Reads the latest Codex rate-limit snapshot from $CODEX_HOME/sessions.
  2. Logs current 5-hour and weekly used/left percentages for the current target model bucket.
  3. Projects one more run from recent observed deltas.
  4. If the projected next run would leave at or below:
       - 5% left in a normal current-model 5-hour window,
       - 0% left in a Spark Codex 5-hour window, or
       - 15% left in the current weekly/main window,
         plus any model-specific weekly safety buffer
     then it terminates the parent shell running the loop and exits without
     starting a new Codex run, unless fallback handoff is enabled.
  5. Before launching Codex, verifies that $CODEX_HOME/sessions is writable,
     stale Codex arg0 temp shims can be cleaned or quarantined, and Codex's
     shared bubblewrap temp registry is writable.
  6. Otherwise it runs exactly one codex exec cycle and exits.
  7. If the primary model fails, blocks, or exhausts its bucket, it can hand off
     to one stronger fallback cycle in the same outer-loop iteration.

Designed for loops like:
  while ./Upkeeper; do
    sleep 60
  done

Loop stop semantics:
  - exit 0 keeps the outer shell loop running
  - exit 5 stops the outer shell loop intentionally when Codex reports
    UPKEEPER_STATUS: NO_BACKEND_TASK
  - while the worktree is dirty, a NO_BACKEND_TASK result is treated as a soft miss
    and the outer loop keeps running so Codex can try again on the next cycle
  - if Codex exits cleanly with a final agent message and a parseable terminal
    review outcome (`REVIEWED_AND_FIXED`, `REVIEWED_CLEAN`, or
    `STOPPED_ON_BLOCKER`) but omits the literal `UPKEEPER_STATUS` line, the
    wrapper recovers the equivalent machine status and logs
    `status_marker.recovered_from_review_outcome`; exact status markers remain
    the preferred contract
  - set CODEX_CONTINUE_ON_NO_BACKEND_TASK=1 to keep polling even after
    an empty cycle even when the worktree is clean
  - when the primary model stalls, fails, or exhausts its bucket, the wrapper can
    launch one stronger fallback worker inside a detached screen session and keep
    polling it every 60s before giving up
  - detached screen fallback is single-shot by default; set
    CODEX_FALLBACK_SCREEN_CONTINUOUS=1 and raise CODEX_FALLBACK_SCREEN_MAX_CHILDREN
    to opt into bounded multi-child fallback
  - by default, a fallback event also triggers a scripted post-mortem report pass
    plus one final hardening pass, then the wrapper exits non-zero so you can
    manually relaunch the loop after reviewing the incident summary
  - post-mortem report completion logs `postmortem.report.finish` with the
    report child exit, parsed marker, report path, and file existence state
  - auxiliary post-mortem and hardening Codex calls use their own exact-model
    quota preflight and are skipped, with a shell-written report, when no
    current bucket can make a decision or a current bucket is projected below
    threshold
  - live primary and auxiliary Codex calls also preflight the local session store;
    a read-only $CODEX_HOME/sessions is classified as a local environment
    failure before starting recursive fallback or post-mortem Codex work
  - live primary, fallback, and auxiliary Codex calls also preflight Codex's
    shared bubblewrap temp registry; a stale root-owned registry is classified
    as a local environment failure before launching another Codex process
  - live primary and auxiliary Codex calls also preflight `$CODEX_HOME/tmp/arg0`;
    stale flat `codex-arg0*` shim directories are removed when owned by the
    operator and moved to `$CODEX_HOME/arg0-quarantine` when they are stale but
    root-owned; if a stale root-owned child cannot be moved individually, the
    wrapper rotates the whole arg0 root and recreates it empty, avoiding Codex's
    vague stale-arg0 cleanup warning
  - if you press Ctrl-C while the primary wrapper is watching a detached recovery
    screen session, the wrapper first checks whether the child already finished,
    then tears down any still-running recovery session before exiting
  - incident directories now include a shell-written bug record artifact alongside
    the post-mortem report so a human or later agent can file or review the bug
  - successful pre-run quota handoffs and no-agent post-run quota failures write
    a primary-quota-blocked-until marker, and later primary invocations for the
    same model stop before launching another fallback/post-mortem chain until
    that reset time passes
  - root log rotation archives live logs older than 72 hours and prunes sibling
    zip archives older than 144 hours on startup.

Transcript and live terminal behavior:
  - Default live terminal mode is `basic`: routine INFO logs stay in
    `Upkeeper.log`; full Codex stdout/stderr stays in transcript artifacts; the
    terminal shows selected target, Codex start/finish, long-running heartbeats,
    status markers, checks/tests/validation/build commands, WARN, ERROR,
    separated bounded `LLM:` task-status blocks before backend tool phases, and
    a final review/finding/change/verification summary.
  - Set `CODEX_TERMINAL_VERBOSITY=verbose` for command-level search/file-view
    progress like `cmd#N search started`; `debug1` is the first diagnostic tier.
  - Set `CODEX_TERMINAL_VERBOSITY=quiet` for only major progress, status,
    WARN, and ERROR; set `silent` for no routine terminal chatter.
  - Transcript artifacts live under `runtime/upkeeper-transcripts` by default and
    are pruned after 24 hours or once the directory exceeds 200 MB.
  - Set `CODEX_TERMINAL_VERBOSITY=full` to stream the full backend transcript live.

Important:
  - Run the loop in a dedicated shell or terminal tab.
  - The living repo-local operator guide is:
      docs/scripts/upkeeper.md
    If that guide is missing, normal startup bootstraps it once from this help
    text and then leaves it alone for repo-specific edits.
    Existing guides are never overwritten; if their embedded help snapshot
    version is missing or stale, startup logs an `operator_guide` warning so you
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
  - The root entrypoint loads its implementation modules from `lib/upkeeper`
    beside the resolved central Upkeeper file. Symlinked clients should point at
    the central entrypoint; copying only the launcher without the paired modules
    is unsupported.
    The executable module load order is the `UPKEEPER_MODULES` array in root
    `Upkeeper`; the module contract is documented in `lib/upkeeper/README.md`.
  - The large default review prompt lives at `prompts/default-review.md` beside
    the resolved central Upkeeper file. Symlinked clients share that central
    prompt and central review modules; local prompt files are only needed for
    explicit `--prompt-file` overrides.
  - The default active config file is `Upkeeper.conf` beside the resolved
    central Upkeeper file. The central checkout also tracks
    `configurations/default.conf` as a basic profile template. Use
    `--config-file=PATH` to select one shell-compatible config file for this
    invocation, or `--no-config` to skip the default config. Relative config
    paths are resolved from the invocation repository root. Config files may set
    `CODEX_*` runtime knobs and `UPKEEPER_*` flag defaults such as
    `UPKEEPER_TARGET_FILE`, `UPKEEPER_REVIEW_MODULES`, `UPKEEPER_PROMPT_FILE`,
    `UPKEEPER_PROMPT`, `UPKEEPER_PROMPT_PASS`, `UPKEEPER_MODEL_OVERRIDE`, and
    `UPKEEPER_IGNORE_FAILURE_QUEUE`. They may also set selection defaults such
    as `UPKEEPER_SELECTION_SOURCE`, `UPKEEPER_SELECTION_ORDER`,
    `UPKEEPER_FILE_MANIFEST_MODE`, `UPKEEPER_TARGET_ROOT`,
    `UPKEEPER_TARGET_MAX_DEPTH`, `UPKEEPER_INCLUDE_GLOBS`,
    `UPKEEPER_EXCLUDE_GLOBS`, and `UPKEEPER_SELECTION_REVIEW_MODULES`. CLI
    flags remain the final one-cycle overrides.
  - Quota detection uses Codex's machine-readable session JSONL snapshots rather than
    scraping the interactive /status TUI output. The snapshot reader uses a
    tail-first scan of recent session JSONL files, with full-file fallback only
    when the tail does not contain enough quota/model metadata.
  - Exact-model Spark quota snapshots may still report the generic Codex
    limiter identity; once snapshot selection proves the target model, that is
    treated as usable quota metadata instead of a conflict.
  - Spark Codex is allowed to drain its current-model 5-hour bucket to
    0% left; weekly/main capacity still stops at
    15% left plus any model-specific weekly safety
    buffer.
  - For pre-run quota stops on an already-dirty worktree, the wrapper skips the
    normal backend fallback child and records the incident instead of spending a
    stronger model run on a predictable dirty-worktree block.
  - Quota logs always print both used and left explicitly as named fields
    (primary_used=... primary_left=... secondary_used=... secondary_left=...)
    so operator checks do not depend on positional interpretation.
  - Terminal cycle outcomes are written as cycle.summary and cycle.exit lines to:
      Upkeeper.log
    Review cycles also write compact review.summary lines, and
    review.fix_details lines when the final response reports fixes, so later
    commits can recover what changed and why.
  - The default prompt makes the primary agent inspect this cycle's own log:
      Upkeeper.log
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
    root is below 10% free.
  - Startup anomalies are a gate by default: while prior-run, watchdog-style, or
    low-disk anomaly evidence is active, preselection is forced to the repo-local
    Upkeeper implementation and normal timestamp rotation is blocked until the
    Upkeeper suite is checked or remediated.

Prompt behavior:
  - By default, the wrapper maintains a local file manifest at
      runtime/upkeeper-file-manifest.json
    and selects the oldest eligible script/tool file by last-modified timestamp.
    If the manifest is missing, stale, invalid, or out of sync with local file
    metadata, startup refreshes it before selection. Set
    `--selection-source=enumerate` for a one-cycle direct scan without using the
    manifest, or `--refresh-manifest` to rebuild the manifest immediately.
  - Upkeeper Lattice is enabled by default as a local SQLite evidence ledger at:
      runtime/upkeeper-lattice/lattice.sqlite3
    It records cycle starts/finishes, preselection evidence, candidate rows,
    pass-result markers, worktree snapshots, imports, exports, backups, and
    recovery facts under ignored runtime state. Lattice does not replace live
    source-safe eligibility; explicit targets, startup anomaly gates, and the
    local failure queue still keep their existing priority.
    If Lattice is unavailable and `UPKEEPER_LATTICE_REQUIRED=0`, the wrapper
    logs one warning, spools a small recovery record when possible, and
    continues the existing cycle behavior. If `UPKEEPER_LATTICE_REQUIRED=1`,
    startup fails before Codex launch.
  - Exception: when the repo-local Upkeeper implementation itself is eligible
    and has not been touched for at least 7 days, it is selected first. If it is
    newer than that threshold, normal oldest-file selection applies.
  - Before launching Codex, the wrapper preselects that script/tool target from
    the manifest or a direct local enumeration pass and prepends the selected
    path to the prompt. That avoids spending model/tool cycles on broad tree
    discovery and keeps `.git/`, ignored paths, runtime evidence, generated
    outputs, and tests out of the selection scan.
  - When a prior run leaves an open local tool-failure marker, preselection
    chooses the oldest still-eligible marked target after explicit operator
    pins and startup anomaly gates, but before stale-self and normal timestamp
    rotation. This is local queue behavior, not another model pass.
    New command failures stay queued unless a later successful command of the
    same broad kind shows the failure was rechecked.
  - A `WRAPPER_PRESELECTED_REVIEW_TARGET` section overrides every later
    repertoire selection rule for that cycle; all applicable review prompts run
    against that same target unless the file is physically impossible or unsafe
    to read.
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
  - --prompt-file FILE appends extra task guidance from FILE; an empty value is
    rejected so the wrapper does not silently fall back to the default prompt.
    Standalone add-on prompts include
    `prompts/p23-data-contract-negative-fixture-audit.md` for explicit
    data-contract review and `prompts/p24-de-llm-ing-viability-review.md` for
    applicability-gated local-code viability review of LLM/Codex boundaries,
    plus `prompts/p25-contract-intent-compliance-review.md` for explicit
    contract and intent compliance review and
    `prompts/p26-public-documentation-review.md` for public documentation,
    comments, help text, and release-note clarity, plus
    `prompts/p27-educational-debrief-review.md` for a concise saved learning
    debrief after the fix, and
    `prompts/p28-unit-test-harvesting-review.md` for turning cheap deterministic
    discoveries into local tests or fixtures, and
    `prompts/p29-reuse-harvesting-review.md` for bounded reuse harvesting of
    helpers, fixtures, prompt language, documentation blocks, command idioms,
    validation patterns, and local assets.
  - --config-file=PATH selects a shell-compatible config file for this invoked
    cycle. Use the equals form; spaced form is rejected.
  - --no-config disables the default config for this invoked cycle.
  - --prompt TEXT appends extra task guidance inline; an empty value is rejected
    for the same reason.
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
    `.git`, ignored paths, runtime evidence, generated outputs, directories,
    unreadable files, and binary-looking files. Use the equals form; spaced
    form is rejected.
  - --target-root=PATH restricts timestamp selection to one file or directory
    tree. --target-dir=PATH is an alias.
  - --target-depth=N limits descendant depth below the selected target root.
    --target-max-depth=N is an alias.
  - --selection-order=oldest, newest, or random chooses the target ordering for
    this invoked cycle. --random-target is shorthand for random ordering.
  - --selection-source=manifest uses the local manifest; --selection-source=enumerate
    bypasses it for this cycle. --refresh-manifest rebuilds and uses the
    manifest immediately.
  - --manifest-file=PATH selects a different local manifest path for this cycle.
  - --include-glob=PATTERN and --exclude-glob=PATTERN add local path filters.
    --include-globs=a,b and --exclude-globs=a,b replace the configured lists.
  - --selection-review-modules=p24,p25,p26,p27,p28,p29 filters candidates using
    deterministic local approximations for files likely relevant to those
    optional review modules. It is a selection filter, not a review-module
    prompt request; pair it with --review-module when you want both.
  - --ignore-failure-queue bypasses local unaddressed tool-failure markers for
    this invoked cycle only. --target-file also takes priority over the queue.
  - --prompt-pass=all forces the selected target through all P1-P23 repertoire
    passes for this invoked cycle. Use the equals form; spaced form is rejected.

Environment overrides:
  UPKEEPER_CONFIG_FILE          Default: Upkeeper.conf
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
  UPKEEPER_TARGET_ROOT          Default: empty
  UPKEEPER_TARGET_MAX_DEPTH     Default: empty
  UPKEEPER_INCLUDE_GLOBS        Default: empty
  UPKEEPER_EXCLUDE_GLOBS        Default: empty
  UPKEEPER_SELECTION_REVIEW_MODULES Default: empty
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
  CODEX_POSTMORTEM_DIR           Default: runtime/journals/upkeeper-postmortems
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
  CODEX_TERMINAL_VERBOSITY     Default: basic
  CODEX_TRANSCRIPT_DIR         Default: runtime/upkeeper-transcripts
  CODEX_TRANSCRIPT_KEEP_HOURS  Default: 24
  CODEX_TRANSCRIPT_KEEP_MAX_MB Default: 200
  CODEX_TRANSCRIPT_SIGNAL_LINES Default: 80
  CODEX_TRANSCRIPT_ERROR_TAIL_LINES Default: 120
  CODEX_LOOP_STOP_GRACE_SECONDS Default: 5
  CODEX_CONTINUE_ON_NO_BACKEND_TASK Default: 0
  CODEX_DISABLE_PARENT_STOP      Default: 0
  CODEX_GUARDRAIL_STOP_EXIT_CODE Default: 0
  CODEX_PARENT_STOP_SKIPPED_EXIT_CODE Default: 75
  CODEX_EXECUTION_ORIGIN         Default: primary
  CODEX_BWRAP_TMP_ROOT           Default: /tmp/codex-bwrap-synthetic-mount-targets
  CODEX_BWRAP_TMP_PREFLIGHT      Default: 1
  CODEX_ARG0_TMP_ROOT            Default: $CODEX_HOME/tmp/arg0
  CODEX_ARG0_TMP_QUARANTINE_ROOT Default: $CODEX_HOME/arg0-quarantine
  CODEX_ARG0_TMP_PREFLIGHT       Default: 1
  CODEX_ARG0_TMP_STALE_MINUTES   Default: 60
  CODEX_ARG0_TMP_ROTATE_ON_BLOCKED Default: 1
  CODEX_UPKEEPER_SELF_REVIEW_AFTER_DAYS Default: 7
  CODEX_MARK_INTERVAL_SECONDS Default: 60
  CODEX_PREVIOUS_RUN_SCAN_MINUTES Default: 240
  CODEX_DISK_MIN_FREE_PERCENT Default: 10
  CODEX_STARTUP_ANOMALY_FORCE_UPKEEPER Default: 1
  CODEX_STARTUP_ANOMALY_GATE_STATE_DIR Default: runtime/startup-anomaly-gates
  CODEX_TOOL_FAILURE_QUEUE_ENABLED Default: 1
  CODEX_TOOL_FAILURE_QUEUE_DIR Default: runtime/unaddressed-tool-failures
  CODEX_ACTIVE_LOCK_DIR Default: runtime/upkeeper-active.lock
  CODEX_WRAPPER_HEALTH_STATE_DIR Default: $CODEX_HOME/upkeeper/active-wrapper-runs
  CODEX_WRAPPER_HEALTH_ARCHIVE_DIR Default: $CODEX_HOME/upkeeper/retired-wrapper-runs
  CODEX_SESSION_SCAN_LIMIT      Default: 200
  CODEX_LOG_FILE                Default: Upkeeper.log
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
```

## Operational Notes

- `CODEX_MODE` defaults to `--sandbox workspace-write`. Set `CODEX_MODE` only
  when testing a newer Codex sandbox flag or temporarily matching an older local
  Codex install. Startup rejects malformed mode strings whose first token is
  missing, lacks `--`, or uses a triple-hyphen token such as `---sandbox`.
- Before/after quota reset epochs may jitter by a second between otherwise
  current exact-model snapshots. Upkeeper treats small reset-epoch jitter as the
  same quota window and logs `quota.reset_jitter` at INFO instead of emitting a
  non-authoritative `quota.jump` warning.
- `--prompt-pass=all` final reports must include parseable `P<N>:` lines for
  P1 through P23. Upkeeper logs `review.pass_coverage` so all-pass cycles are
  auditable from machine logs, not only from prose. The parser accepts common
  Markdown line prefixes such as bullets and bold/code emphasis around `P<N>`.
- Final responses may include additive `UPKEEPER_PASS_RESULT` lines for every
  P* pass actually applied or explicitly found not applicable. Missing lines do
  not fail a cycle; malformed lines are rejected evidence for Lattice instead
  of clean pass results.
- Review prompts avoid legacy editor-specific persistence instructions and keep
  only the Codex-relevant mtime/content verification contract, reducing prompt
  tokens without weakening the review workflow.
- Default review prompts prune P2, P8, and P16 section bodies because normal
  Upkeeper selection targets non-test script/tool files; `--prompt-pass=all`
  keeps the full P1-P23 repertoire.
- Hot-path wrapper helpers avoid Python subprocesses for simple path, timestamp,
  size, and threshold operations; Python remains reserved for structured
  parsing and heavier filesystem/session analysis.
- Quota snapshot and post-run diagnostic handling extract all needed fields in
  one quoted `jq` pass per JSON object instead of spawning `jq` repeatedly for
  each field.
- Notable operator-facing wrapper changes are recorded in the current year's
  root `change_notes_YYYY.md`; version bumps should keep that file current.
- The central checkout has a tracked validation harness at
  `tools/validate_upkeeper.sh`. Use `--deps` for runtime/tool dependency
  status, `--quick` for syntax/version/module-map checks, and `--full` before
  release or after touching module order, prompt packaging, symlink behavior, or
  failure-path guardrails. Full validation uses dry-runs plus a local fake
  `codex` binary; it does not launch real backend work.
  GitHub Actions runs the no-quota CI path in `.github/workflows/ci.yml` on
  pushes and pull requests: shell syntax, `tests/*.bash`, public docs, and
  `tools/validate_upkeeper.sh --quick`.
  Sample-repo stress coverage is available without backend quota with
  `tools/stress_upkeeper_corpus.sh --local`; full validation runs that local
  corpus after the central wrapper checks.
- Runtime/tool dependencies are tracked in `docs/dependencies.md`. GitHub's
  dependency graph should remain enabled, but it is expected to show no package
  dependencies until this repo adds a real supported manifest, workflow, or
  dependency submission.
- Backward compatibility is documented in `docs/compatibility.md`. Existing
  operator-visible behavior should be preserved unless compatibility would be
  unsafe or impossible.
- Security and local trust boundaries are documented in `docs/security.md`.
  Read that page before using unreviewed config files, broad sandbox modes,
  shared machines, or repositories that may contain secrets.
- Local sample-repo stress testing is documented in `docs/stress-corpus.md`;
  those checks default to no real backend Codex work and keep model-backed
  sample runs behind explicit future opt-in commands.
- Startup-anomaly scans suppress older log-only `previous_run.anomaly` entries
  after a later `startup_anomaly.gate_resolved` has acknowledged
  `previous_run_anomaly`; unresolved gate state files still trigger the gate.
- Startup-anomaly self-review gates accept ignored local `Upkeeper.sh` symlinks
  to the central wrapper as valid local gate targets; normal timestamp rotation
  still excludes ignored wrapper artifacts.
- Root `Upkeeper` remains the only operator entrypoint. The implementation now
  lives in sourced `lib/upkeeper/*.bash` modules loaded from the resolved central
  wrapper directory, preserving symlinked client behavior while reducing review
  scope inside the wrapper source.
- Module load order is intentionally explicit in root `Upkeeper` instead of
  relying on filename order. Missing modules fail before lock acquisition,
  Codex launch, fallback, or parent-shell stop logic.
- The default review prompt body lives in tracked `prompts/default-review.md`
  and is loaded from the resolved central wrapper directory. Prompt overrides
  still use the operator-supplied `--prompt-file` path.
- `Upkeeper.log` and `runtime/` are local evidence artifacts and are ignored by
  git. Promote only durable operating rules, postmortem conclusions, or wrapper
  behavior changes into tracked files.
- `runtime/upkeeper-file-manifest.json` is local selector state. It can be
  rebuilt with `--refresh-manifest`, bypassed with `--selection-source=enumerate`,
  or relocated for one run with `--manifest-file=PATH`.
- Open tool-failure queue markers live under
  `runtime/unaddressed-tool-failures/open/`; resolved markers move to
  `runtime/unaddressed-tool-failures/resolved/`.
- A repo-level active lock at `runtime/upkeeper-active.lock` prevents two
  Upkeeper loops from running the same checkout concurrently; stale locks are
  reclaimed only when the recorded PID/start fingerprint no longer matches.
- A shared central-wrapper health state under `$CODEX_HOME/upkeeper/` is keyed
  by resolved wrapper path and wrapper blob hash. If a prior same-code run is
  stale, wedged, or ambiguous, later client starts fail closed before normal
  target selection.
- The default review prompt explicitly excludes ignored files, generated files,
  runtime evidence, caches, vendor content, and `.git/` internals from target
  selection. If a scan finds one of those first, the agent should state the
  generated/ignored-artifact exception and select the next eligible source file.
- Review-cycle final responses are summarized in `review.summary` log lines.
  Responses that report `REVIEWED_AND_FIXED` also emit `review.fix_details`
  lines so later commits can recover the bug, fix, and verification details.
- Tracked launchers live under `launcher_examples/`. Validate them with
  `bash -n launcher_examples/*.sh` and their own dry-run knobs before changing
  loop behavior.
- Tracked local test launchers live under `testruns/`. They provide ready-made
  cycles for all-pass P-module runs, documentation-focused P26 loops, manifest
  refresh dry-runs, and enumerate/random selector dry-runs. Validate them with
  `bash -n testruns/*.sh` before changing loop behavior.
- Log continuity is now script-visible before Codex starts: `previous_run.scan`,
  `previous_run.anomaly`, `disk.preflight`, and `--MARK--` lines are primary
  evidence for follow-up self-repair.
- If a startup anomaly gate is active and the final response omits the required
  raw-line `UPKEEPER_LOG_REVIEW: CHECKED cycle=<cycle_id> anomalies=none` or
  `UPKEEPER_LOG_REVIEW: CHECKED cycle=<cycle_id> anomalies=listed`
  acknowledgment, the wrapper logs `startup_anomaly.gate_unresolved`; the next
  startup scan treats that marker and the runtime gate state file as another
  anomaly and forces the next cycle back onto the Upkeeper suite. Agents must
  choose one concrete value and must not emit the placeholder
  `anomalies=none|listed`.
- The gated self-repair surface is intentionally narrow: the root `Upkeeper`
  entrypoint, `lib/upkeeper` modules, central operator docs and release notes,
  prompts/templates, launcher examples, and the validation harness.

## Repo-Local Living Notes

- Record local relaunch conventions, recurring incident lessons, and environment-specific guardrail decisions here.
- Keep transient run logs and generated postmortems under `runtime/`; promote only durable operating rules into this guide.
