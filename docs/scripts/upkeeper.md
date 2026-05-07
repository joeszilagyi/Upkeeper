# Upkeeper

Operator guide for the repo-local `Upkeeper` wrapper.

Keep this file in sync with `./Upkeeper --help` and the wrapper's operational
behavior. The wrapper only bootstraps this guide when it is missing; it does not
overwrite future edits.

Path examples below are normalized to repo-relative or environment-based paths.
`./Upkeeper --help` prints fully resolved local paths for the current machine.

## Behavior Summary

```text
Usage: Upkeeper [--help] [--version] [--prompt-file FILE] [--prompt TEXT] [--model-override=5.5_xhigh] [--target-file=PATH] [--prompt-pass=all]

One-cycle Codex backend worker with quota guardrails.
Version: v1.0.32

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
     to one stronger fallback cycle in the
     same outer-loop iteration.

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
  - this wrapper also self-rotates its local root log when the oldest live log
    entry is older than 72 hours; archives stay as
    sibling zip files and archives older than 144
    hours are pruned on startup

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
  - Quota detection uses Codex's machine-readable session JSONL snapshots rather than
    scraping the interactive /status TUI output.
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
  - The default prompt makes the primary agent inspect this cycle's own
    Upkeeper.log entries before its final marker. If the log review exposes a
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
    write-critical root is below 10% free.
  - Startup anomalies are a gate by default: while prior-run, watchdog-style, or
    low-disk anomaly evidence is active, preselection is forced to the repo-local
    Upkeeper implementation and normal timestamp rotation is blocked until the
    Upkeeper suite is checked or remediated.

Prompt behavior:
  - By default, the script asks Codex to select the oldest eligible script/tool
    file by last-modified timestamp and review exactly one file per cycle.
  - Exception: when the repo-local Upkeeper implementation itself is eligible
    and has not been touched for at least 7 days, it is selected first. If it is
    newer than that threshold, normal oldest-file selection applies.
  - Before launching Codex, the wrapper preselects that script/tool target from
    `git ls-files -co --exclude-standard` and prepends the selected path to the
    prompt. That avoids spending model/tool cycles on broad tree discovery and
    keeps `.git/`, ignored paths, runtime evidence, generated outputs, and tests
    out of the selection scan.
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
  CODEX_LOOP_STOP_GRACE_SECONDS Default: 5
  CODEX_CONTINUE_ON_NO_BACKEND_TASK Default: 0
  CODEX_DISABLE_PARENT_STOP      Default: 0
  CODEX_GUARDRAIL_STOP_EXIT_CODE Default: 0
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
  CODEX_ACTIVE_LOCK_DIR Default: runtime/upkeeper-active.lock
  CODEX_WRAPPER_HEALTH_STATE_DIR Default: $CODEX_HOME/upkeeper/active-wrapper-runs
  CODEX_SESSION_SCAN_LIMIT      Default: 200
  CODEX_LOG_FILE                Default: Upkeeper.log
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
```

## Operational Notes

- `CODEX_MODE` defaults to `--sandbox workspace-write`. Set `CODEX_MODE` only
  when testing a newer Codex sandbox flag or temporarily matching an older local
  Codex install. Startup rejects malformed triple-hyphen mode tokens such as
  `---sandbox`.
- Before/after quota reset epochs may jitter by a second between otherwise
  current exact-model snapshots. Upkeeper treats small reset-epoch jitter as the
  same quota window and logs `quota.reset_jitter` at INFO instead of emitting a
  non-authoritative `quota.jump` warning.
- `--prompt-pass=all` final reports must include parseable `P<N>:` lines for
  P1 through P23. Upkeeper logs `review.pass_coverage` so all-pass cycles are
  auditable from machine logs, not only from prose.
- Startup-anomaly scans suppress older log-only `previous_run.anomaly` entries
  after a later `startup_anomaly.gate_resolved` has acknowledged
  `previous_run_anomaly`; unresolved gate state files still trigger the gate.
- `Upkeeper.log` and `runtime/` are local evidence artifacts and are ignored by
  git. Promote only durable operating rules, postmortem conclusions, or wrapper
  behavior changes into tracked files.
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

## Repo-Local Living Notes

- Record local relaunch conventions, recurring incident lessons, and environment-specific guardrail decisions here.
- Keep transient run logs and generated postmortems under `runtime/`; promote only durable operating rules into this guide.
