# Upkeeper

Operator guide for the repo-local `Upkeeper` wrapper.

Keep this file in sync with `./Upkeeper --help` and the wrapper's operational
behavior. The wrapper only bootstraps this guide when it is missing; it does not
overwrite future edits.

Path examples below are normalized to repo-relative or environment-based paths.
`./Upkeeper --help` prints fully resolved local paths for the current machine.

## Behavior Summary

```text
Usage: Upkeeper [--help] [--version] [--config-file=PATH] [--no-config] [--prompt-file FILE] [--prompt TEXT] [--review-module=p24|p25|p26|p27|p28|p29|p30] [--review-modules=p24,p25,p26,p27,p28,p29,p30] [--p24] [--p25] [--p26] [--p27] [--p28] [--p29] [--p30] [--model-override=5.5_xhigh|5.3-codex-spark_xhigh] [--target-file=PATH] [--target-root=PATH] [--target-depth=N] [--selection-source=manifest|enumerate] [--selection-order=oldest|newest|random] [--refresh-manifest] [--manifest-file=PATH] [--allow-unsafe-manifest-path] [--include-glob=PATTERN] [--include-globs=a,b] [--exclude-glob=PATTERN] [--exclude-globs=a,b] [--selection-review-modules=p24,p25,p26,p27,p28,p29,p30] [--ignore-failure-queue] [--backup-queue] [--prompt-pass=all] [--max-cover] [--bug-report-only] [--fix-next-issue] [--fix-issue=NUMBER] [--issue-workflow-stage=comment|review|apply]

One-cycle Codex backend worker with quota guardrails.
Version: v1.2.33

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
  5. After selecting a review target and before compiling its prompt authority,
     creates the configured selected-target pre-contact backup.
  6. Before launching Codex, verifies that $CODEX_HOME/sessions is writable,
     stale Codex arg0 temp shims can be cleaned or quarantined, and Codex's
     shared bubblewrap temp registry is writable.
  7. Otherwise it runs exactly one codex exec cycle and exits.
  8. If the primary model fails, blocks, or exhausts its bucket, it can hand off
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
    plus one final hardening pass, then the wrapper propagates the fallback
    child outcome unless the post-mortem/report/hardening path itself fails
  - post-mortem report completion logs `postmortem.report.finish` with the
    report child exit, parsed marker, report path, and file existence state
  - auxiliary post-mortem and hardening Codex calls use their own exact-model
    quota preflight and are skipped, with a shell-written report, when no
    current bucket can make a decision or a current bucket is projected below
    threshold
  - live primary and auxiliary Codex calls also preflight the local session store;
    missing $CODEX_HOME/sessions directories are created private, while
    read-only, symlinked, wrong-owner, non-directory, or group/other-writable
    session stores are classified as local environment failures before writing
    a probe or starting recursive fallback or post-mortem Codex work
  - live primary, fallback, and auxiliary Codex calls also preflight Codex's
    shared bubblewrap temp registry; a stale root-owned registry is classified
    as a local environment failure before launching another Codex process
  - live primary and auxiliary Codex calls also preflight `$CODEX_HOME/tmp/arg0`;
    stale flat `codex-arg0*` shim directories are removed only when they carry
    a trusted Upkeeper/Codex ownership marker, while unmarked matching
    directories are moved to `$CODEX_HOME/arg0-quarantine`; if a stale child
    cannot be moved individually, the wrapper rotates the whole arg0 root and
    recreates it empty, avoiding Codex's vague stale-arg0 cleanup warning
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
    zip archives older than 144 hours on startup. Custom `CODEX_LOG_FILE` paths
    are still honored as live log sinks, but rotation and sibling archive
    pruning stay blocked unless explicitly enabled with
    `CODEX_LOG_FILE_ALLOW_UNSAFE=1` and a trusted Upkeeper rotation marker.

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
  - Run backlog batches with `orchestration/backlog_loop.sh`, or call
    `orchestration/backlog.sh` directly for safe interactive watch mode: it
    cuts off stdin, keeps live output in the current terminal, and mirrors that
    output to the private backlog loop log. Watch mode owns and drains its
    formatter before returning control to the shell, so late child-process
    output cannot write over the next prompt. Set
    `BACKLOG_INTERACTIVE_MODE=detach` or use `orchestration/backlog_loop.sh`
    when you want a fully detached background-style loop instead. Backlog
    launcher notices are shell-comment lines so accidental terminal input
    feedback stays a no-op, and live/feed-log lines use a local
    `YYYY-MM-DDTHH:MM:SS` timestamp in column 1, a single visual block in
    column 2, and an operator-attention marker in column 3 for loose terminal
    watching. TTY output colors the block by marker: green `OK`, red blinking
    `PAGE`, white `INFO`, orange `--FYI--`, cyan `RUN`, magenta `ACTION`,
    yellow `WAIT`/`HEALTH`, and blue `WORKER`. `PAGE` and `--FYI--` also color
    their timestamp and bold marker text; `PAGE` puts the timestamp in bright
    white on a red background, renders the non-error payload text bright white,
    and highlights the `ERROR` text inside `[ERROR]` in the same red/blink style
    as the `PAGE` marker. Loop logs keep the same block and marker text without
    ANSI color for scripts and assistive tooling. Set
    `BACKLOG_ALERT_COLOR=never` to disable terminal block color,
    `BACKLOG_ALERT_COLOR=always` to force it, or `BACKLOG_ALERT_BLINK=0` to
    keep `PAGE` red without blink.
  - When a backlog invocation locks in its local job, it prints a local-only
    green `##### ##### #####` summary block before backend work starts. The
    block names the target file or selection mode, why this cycle is doing that
    work, and the expected outcome. When the invocation finishes that job and is
    about to return to the outer sleep/next invocation, it prints the matching
    local-only block with the target, outcome, start time, end time, runtime, and
    final disposition. Set `BACKLOG_JOB_SUMMARY=0` to disable these local
    summary blocks.
  - If an issue-targeted backlog pass exits successfully but leaves no tracked
    changes, the launcher defers that issue for the current backlog branch before
    returning to the outer loop. This keeps a no-op or already-addressed issue
    from being selected repeatedly while preserving the open issue for a later
    branch or manual close.
  - Once a backlog PR has recorded fixes, the next invocation waits for that
    PR's checks before selecting another issue. Passing checks allow the next
    issue, pending checks keep the local owner lease alive, and failed checks
    stop the launcher before more work stacks on a red branch. While checks are
    pending, the wait line includes local `gh`/`jq` progress details such as
    pass/pending/fail counts, the active check name, state, elapsed check time,
    Actions step when available, and the check URL. Set
    `BACKLOG_PR_CHECK_PROGRESS=0` to return to the terse pending line, or
    `BACKLOG_PR_CHECK_PROGRESS_STEPS=0` to keep the summary without the extra
    Actions job lookup. A just-created PR with no reported checks yet is treated
    as pending/settling for `BACKLOG_PR_CHECK_EMPTY_GRACE_SECONDS` seconds
    before it can fail closed as missing checks. Set
    `BACKLOG_PR_CHECK_GATE_BEFORE_NEXT_ISSUE=0` only for an intentional manual
    override.
  - Before normal GitHub issue selection, the backlog launcher scans recent
    private loop output for deviations from the healthy unattended-run shape.
    `PAGE`/`ERROR` lines, unresolved startup-anomaly residue, previous-run
    anomaly summaries, failed PR gates, non-zero exits, and degraded
    control-plane modes are written to `runtime/upkeeper-anomaly-custody` and
    opened as local automation obligations unless nearby deterministic
    test-success context proves they are expected fixture output. Selected
    obligations run as the next Upkeeper job before fresh issue work, with a
    prompt packet containing the bounded evidence excerpt. Repeated instances
    of the same anomaly class update the existing obligation with occurrence
    counts and last-seen evidence instead of opening a new obligation for each
    cycle id or run hash. Quoted backend shell/test fixture snippets that contain
    embedded `[WARN]`, `[ERROR]`, `PAGE`, control-plane log text, or quoted
    source-code fixture lines are treated as transcript content, not as new
    wrapper failures. Immediately after the
    backlog branch is checked out, before PR, merge, quota, or issue-selection
    gates, backlog also reconciles open current-root obligations deterministically: records
    with matching root, kind, reason, target, issue, and stable fingerprint are
    condensed to one active owner, and duplicates are moved to resolved evidence
    with `duplicate_of` metadata. Deterministically obsolete findings, such as a
    stale operator-guide warning after the guide matches the wrapper version, are
    moved to resolved evidence with an explicit reason. If the same obligation
    reports `BLOCKED` repeatedly, backlog records repair-attempt metadata and
    cools that obligation down so another eligible obligation can run; if every
    obligation is cooling down, backlog exits without starting fresh issue work.
    After anomaly custody and reconciliation, backlog also writes one
    deterministic issue-ready report for every open current-root obligation
    before selecting work, so system-level failures have durable issue text even
    when backend Codex never enters bug-report-only mode. These local reports
    default to
    `${XDG_STATE_HOME:-$HOME/.local/state}/upkeeper/backlog/obligation-issue-reports`.
    Wrapper-side GitHub issue creation is available only when explicitly enabled
    with `BACKLOG_OBLIGATION_GITHUB_ISSUE_WRITE=1`; otherwise the local report
    is the authoritative filing artifact.
    Set `BACKLOG_OBLIGATION_RECONCILE=0` for a
    deliberate one-cycle bypass. Set
    `BACKLOG_ANOMALY_CUSTODY=0` for a deliberate one-cycle bypass, or adjust
    `BACKLOG_ANOMALY_CUSTODY_LINES` and `BACKLOG_ANOMALY_CUSTODY_MAX_FINDINGS`
    for local scan bounds.
  - Light per-bug validation still avoids the full batch suite, but it now
    compiles changed Python files before commit. Lattice issue fixes that touch
    `tools/upkeeper_lattice.py` also run `tests/lattice_test.bash` before the
    fix is recorded.
  - Before backlog issue work starts, the launcher autoshelves dirty local work
    to a private `wip/backlog-autoshelve/*` branch. Ordinary dirty files stay
    shelved while the loop continues from a clean branch. If the dirty set
    includes Upkeeper control-plane paths such as the wrapper, modules,
    orchestration, tools, tests, prompts, or config, the launcher reapplies that
    local remediation bundle onto the active backlog branch and commits it
    before continuing, so the next cycle runs the repaired code without manual
    cherry-picking. If that local transplant cannot apply cleanly, the launcher
    stops before stale automation can run and leaves the autoshelve branch as
    evidence.
  - Backlog batches default to `gpt-5.3-codex-spark` with `xhigh` reasoning and
    a zero weekly stop floor for reset-window burn-down runs. Backlog burn mode
    also bypasses stale local quota snapshots and ordinary active
    quota-cooldown markers by default so a provider-side reset can be used
    immediately. Hard backend usage-limit markers are still honored even in
    burn mode. Override with `BACKLOG_CODEX_MODEL`,
    `BACKLOG_CODEX_REASONING_EFFORT`, `BACKLOG_WEEK_STOP_PERCENT`,
    `BACKLOG_QUOTA_GUARDRAIL_BYPASS=0`, or
    `BACKLOG_QUOTA_COOLDOWN_BYPASS=0` when a guarded or non-Spark run is wanted.
  - The backlog launcher hibernates by default when its quota preflight sees a
    stop-level quota state or an active primary quota block marker. It prints
    the blocked bucket, reset time, wake time, branch, and recent activity when
    available, sleeps locally without backend model work until the reset grace
    passes, then lets the next backlog cycle retry. Set
    `BACKLOG_QUOTA_HIBERNATE=0` to restore one-cycle deferral instead.
  - If the backend exits before any agent message and says the selected model hit
    a usage limit, Upkeeper records that reset time as a hard local quota marker
    instead of opening a target repair obligation for a missing status marker.
    A backlog loop then exits the current job cleanly, and the next preflight
    hibernates until the reset or until the operator switches models.
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
  - Client symlink lifecycle helpers live in the central checkout:
    `tools/install_client_link.sh --repo=CLIENT`,
    `tools/update_client_link.sh --repo=CLIENT --force`,
    `tools/uninstall_client_link.sh --repo=CLIENT`, and
    `tools/doctor_upkeeper.sh --repo=CLIENT`.
    Install and update write local ignore entries to the client repo's
    `.git/info/exclude`; they do not edit tracked client files unless an
    operator explicitly forces replacement of an existing tracked link path.
    The doctor command checks the central modules, symlink target, dependencies,
    ignored local artifacts, and `UPKEEPER_DRY_RUN=1` startup without launching
    real backend Codex work.
  - The large default review prompt lives at `prompts/default-review.md` beside
    the resolved central Upkeeper file. Symlinked clients share that central
    prompt and central review modules; local prompt files are only needed for
    explicit `--prompt-file` overrides. Unattended launcher runs only allow
    `--prompt-file` from `UPKEEPER_PROMPT_TRUST_ROOT` unless
    `UPKEEPER_ALLOW_EXTERNAL_PROMPT_FILE=1`.
  - The default active config file is `Upkeeper.conf` beside the resolved
    central Upkeeper file. The central checkout also tracks
    `configurations/default.conf` as a basic profile template. Use
    `--config-file=PATH` to select one shell-compatible config file for this
    invocation, or `--no-config` to skip the default config. Relative config
    paths are resolved from the invocation repository root. Config files are
    sourced by Bash, so treat them as trusted executable shell code, not inert
    config data; do not load profiles from untrusted repositories or downloaded
    snippets. Config files may set `CODEX_*` runtime knobs and `UPKEEPER_*` flag
    defaults such as
    `UPKEEPER_TARGET_FILE`, `UPKEEPER_REVIEW_MODULES`, `UPKEEPER_PROMPT_FILE`,
    `UPKEEPER_PROMPT`, `UPKEEPER_PROMPT_PASS`, `UPKEEPER_PROMPT_TRUST_ROOT`,
    `UPKEEPER_ALLOW_EXTERNAL_PROMPT_FILE`, `UPKEEPER_MODEL_OVERRIDE`,
    `UPKEEPER_IGNORE_FAILURE_QUEUE`, `UPKEEPER_MAX_COVER`,
    `UPKEEPER_BUG_REPORT_ONLY`, and `UPKEEPER_FIX_NEXT_ISSUE`. They may also
    source a trusted machine-local env file from `UPKEEPER_LOCAL_ENV_FILE`
    after the selected config file unless `UPKEEPER_LOCAL_ENV_DISABLE=1`. Use
    `tools/upkeeper_precontact_bootstrap.sh` to populate
    `UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT` there without committing machine
    setup into repo config. Config files may also
    set pre-contact backup defaults such as `UPKEEPER_PRECONTACT_BACKUP_MODE`,
    `UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED`,
    `UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT`,
    `UPKEEPER_PRECONTACT_BACKUP_ROOT`, and
    `UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT`. They may also set selection defaults such as `UPKEEPER_SELECTION_SOURCE`,
    `UPKEEPER_SELECTION_ORDER`,
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
    0% left plus any model-specific weekly safety
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
  - Every cycle also writes a shared automation run record under:
      runtime/upkeeper-automation-ledger
    Non-zero cycle exits create unresolved automation obligations under:
      runtime/upkeeper-obligations
    FlameOn, ChimneySweep, and future derivative launchers use the same
    Upkeeper-owned record format and only supply launcher identity and policy.
    Those launchers reconcile open obligations before normal bug-finding or
    issue-queue selection, handing the oldest/highest-priority obligation back
    to Upkeeper as a locked repair target.
  - The perfect run is a correct fast no-op: when automation health, unresolved
    obligations, and the actionable queue are all clean, Upkeeper or a launcher
    should print a plain reason and exit without launching backend Codex or
    broad validation. Treat a healthy empty run taking more than about 10
    seconds as an operator-ergonomics bug.
  - Machine health outranks new workload. If a prior automated run failed, the
    next unattended launcher run repairs or preserves that obligation before it
    starts fresh GitHub issue work or bug-hunting work.
  - Before the first wrapper log write, Upkeeper rejects unsafe log paths:
    symlink log files, non-regular log files, hard-linked log files, log files
    not owned by the current user, and symlink log parent directories fail
    closed before Codex launch.
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
    wrote cycle.exit/run.finish, logs one `previous_run.anomaly_summary` for
    ordinary operator output, preserves `previous_run.anomaly_detail` records in
    local evidence, and injects those findings into the prompt for the next
    healthy run.
  - Startup also logs disk.preflight lines for repo, log, Codex home/session,
    temp, bwrap, arg0, and runtime paths. Path and mount fields are hashed in
    normal logs and switch to raw shell-quoted values only in `debug1` or
    `full` terminal mode; the model prompt receives only labels plus
    free-space percentages when a write-critical root is below 10% free.
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
    Transient transcript artifacts may live under repo runtime, Upkeeper-owned
    state directories, or Upkeeper-owned temp directories; Lattice records their
    hashed identity without treating those operator-local transcript locations
    as unsafe source paths.
  - Exception: when the repo-local Upkeeper implementation itself is eligible
    and has not been touched for at least 7 days, it is selected first. If it is
    newer than that threshold, normal oldest-file selection applies.
  - Before launching Codex, the wrapper preselects that script/tool target from
    the manifest or a direct local enumeration pass and prepends the selected
    path to the prompt. That avoids spending model/tool cycles on broad tree
    discovery and keeps `.git/`, ignored paths, runtime evidence, generated
    outputs, and tests out of the selection scan.
  - After target selection and before the selected-target prompt block is
    appended, Upkeeper creates a pre-contact backup when enabled. The default
    vault is outside the repository. Auto mode uses age encryption when
    `UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT` is set and `age` is available;
    otherwise the default contract fails closed before backend launch because
    encrypted backup is required. Plain mode is a recovery aid, not a same-user
    security boundary, and now requires both
    `UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0` and
    `UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1`. Plaintext backup
    also rejects high-confidence private-key content even when that unsafe
    override is set. Backup logs and prompts include HMAC target identity, mode,
    encrypted, `protected_from_backend`, and `path_redacted=1`; the vault path
    is not prompt-visible. On live apply-stage or normal repair cycles,
    Upkeeper resolves required encrypted backup before issue selection; if the
    machine lacks an age recipient, it stops with a machine-health obligation
    and points at `tools/upkeeper_precontact_bootstrap.sh` instead of
    attributing that local setup failure to whichever issue happened to be
    next. Restore a plain backup by id with:
      `tools/upkeeper_precontact_restore.sh --repo-root=. --backup-id=BACKUP_ID`
  - A repo-root `.upkeeperignore`, or the file named by `UPKEEPER_IGNORE_FILE`,
    is a target-selection firewall. It uses simple Gitignore-style glob lines
    to block normal rotation, Lattice/max-cover candidates, failure-queue target
    eligibility, manifest entries, and explicit `--target-file` pins. It
    controls spend/selection only; it is not a Git, sandbox, or
    secret-protection rule.
  - When a prior run leaves an open local tool-failure marker, preselection
    chooses the oldest still-eligible marked target after explicit operator
    pins and startup anomaly gates, but before stale-self and normal timestamp
    rotation. This is local queue behavior, not another model pass.
    New command failures stay queued unless a later successful command of the
    same broad kind shows the failure was rechecked.
  - A `WRAPPER_PRESELECTED_REVIEW_TARGET` section overrides every later
    repertoire selection rule for that cycle; all applicable review prompts run
    against that same target. If the file is physically impossible or unsafe to
    read, Codex must report `BLOCKED` and must not choose a replacement target.
    Replacement target selection is wrapper-only because pre-contact backup
    coverage is target-specific.
  - Preselection records the selected target's git status, content state, and
    HMAC content fingerprints before Codex starts. If the selected file is
    already dirty, that is baseline state, not a blocker by itself; touch
    verification must compare against a local pre-touch content fingerprint
    rather than assuming the diff against HEAD is empty.
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
    In unattended launcher mode, FILE must be under `UPKEEPER_PROMPT_TRUST_ROOT`
    unless `UPKEEPER_ALLOW_EXTERNAL_PROMPT_FILE=1`.
    Paths containing control characters are rejected before logging or prompt
    compilation.
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
    validation patterns, and local assets, and
    `prompts/p30-stark-protocol-review.md` for permanent hardening and
    non-regression barriers after useful failures or fragile recovery paths.
    Fault-injection review is reserved for future P31 work or a later named
    module with an explicit non-breaking alias plan; P29 remains reuse
    harvesting and P30 remains Stark Protocol hardening.
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
  - --review-module=p30 appends the central P30 Stark Protocol permanent
    hardening review module for this invoked cycle.
  - Fault-injection review is reserved for future P31 work rather than
    repurposing the public P29 reuse-harvesting flag.
  - --review-modules=p24,p25,p26,p27,p28,p29,p30 appends multiple modules in a single flag;
    repeated --review-module flags are also accepted and duplicate modules are ignored.
  - --p24, --p25, --p26, --p27, --p28, --p29, and --p30 are shorthand aliases for the corresponding review modules.
    Review module flags are one-cycle guidance only and do not persist to later
    loop iterations. They are not enabled by --prompt-pass=all unless requested.
  - --model-override=5.5_xhigh runs this invoked cycle once as gpt-5.5
    with xhigh reasoning effort. --model-override=5.3-codex-spark_xhigh runs
    it once as gpt-5.3-codex-spark with xhigh reasoning effort. These are
    CLI-only operator overrides and do not persist to later loop iterations.
    Use the equals form; spaced form is rejected.
  - --target-file=PATH pins this invoked cycle to one source-safe readable text
    file and bypasses timestamp selection, selection filters, and the local
    failure queue. Explicit pins may target tracked or non-ignored untracked
    docs, prompts, configs, tests, or scripts inside the repo. They still reject
    `.git`, ignored paths, runtime evidence, generated outputs, directories,
    symlinks, unreadable files, and binary-looking files. Use the equals form;
    spaced form is rejected.
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
    Manifest paths must stay under runtime/ or another ignored local path unless
    --allow-unsafe-manifest-path is explicitly set for a trusted one-cycle run.
  - --include-glob=PATTERN and --exclude-glob=PATTERN add local path filters.
    --include-globs=a,b and --exclude-globs=a,b replace the configured lists.
  - --selection-review-modules=p24,p25,p26,p27,p28,p29,p30 filters candidates using
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
    appends P24-P30, and asks Lattice for max-cover target ranking across
    current tracked source-safe text files. Explicit targets, startup anomaly
    gates, and active failure-queue markers still keep their existing priority.
  - --bug-report-only, also accepted as --file-bug-only or --report-bug-only,
    makes the cycle investigate and file/report confirmed bugs without editing
    or touching tracked source. It intentionally supersedes the normal clean
    review touch requirement for that invocation. By default it writes a local
    issue draft under runtime/upkeeper-bug-report-drafts and blocks direct
    GitHub issue creation unless `UPKEEPER_ALLOW_GH_ISSUE_WRITE=1`.
  - --fix-next-issue, also accepted as --fix-oldest-bug, asks Upkeeper to pick
    the oldest open non-skipped GitHub issue by priority label order
    security > data-integrity > bug, infer a starting file from the issue body
    when possible, and run the cycle as a focused repair task. By default the
    wrapper withholds private issue title/body/comment text from the model; set
    `UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL=1` only when that exposure is
    explicitly required.
    Documented local taxonomy is aligned to the operator release gate intent:
    `p0-release-blocker`, `p1-trust`, `p1-validation`, `p1-safety`,
    `p1-docs`, `p2-ux`, `p2-portability`, `p2-prompt`, and `p3-polish`,
    with a conscious fallback to `security`, `data-integrity`, and `bug` when
    dedicated labels are unavailable.
  - --fix-issue=NUMBER skips Upkeeper's issue ranking and locks this cycle to
    the named open GitHub issue. This is the handoff used by scripted fix
    launchers such as ChimneySweep after they have already ranked the queue.
  - --issue-workflow-stage=comment|review|apply adds a ChimneySweep stage
    contract to an issue-fix cycle. comment and review are source read-only
    stages that leave issue comments; apply is the implementation stage.
    The read-only stages force backend Codex into a read-only repository
    sandbox and carry issue-comment text back in a final-message draft block
    that the wrapper extracts and posts after validation.

Environment overrides:
  UPKEEPER_CONFIG_FILE          Default: Upkeeper.conf
  UPKEEPER_CONFIG_DISABLE       Default: 0
  UPKEEPER_TARGET_FILE          Default: empty
  UPKEEPER_REVIEW_MODULES       Default: empty
  UPKEEPER_PROMPT_FILE          Default: empty
  UPKEEPER_PROMPT               Default: empty
  UPKEEPER_PROMPT_TRUST_ROOT    Default: prompts
  UPKEEPER_ALLOW_EXTERNAL_PROMPT_FILE Default: 0
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
  UPKEEPER_BUG_REPORT_ONLY     Default: 0
  UPKEEPER_ALLOW_GH_ISSUE_WRITE Default: 0
  UPKEEPER_BUG_REPORT_DRAFT_DIR Default: runtime/upkeeper-bug-report-drafts
  UPKEEPER_FIX_NEXT_ISSUE      Default: 0
  UPKEEPER_FIX_ISSUE           Default: empty
  UPKEEPER_ISSUE_WORKFLOW_STAGE Default: empty
  UPKEEPER_ALLOW_PRIVATE_ISSUE_BODY_TO_MODEL Default: 0
  UPKEEPER_ISSUE_PRIORITY_LABELS Default: security,data-integrity,bug
  UPKEEPER_ISSUE_SKIP_LABELS   Default: in-progress,blocked,duplicate,wontfix,invalid,needs-info,done,merged,has-pr
  UPKEEPER_AUTOMATION_LEDGER_ENABLED Default: 1
  UPKEEPER_AUTOMATION_LEDGER_DIR Default: runtime/upkeeper-automation-ledger
  UPKEEPER_OBLIGATION_DIR       Default: runtime/upkeeper-obligations
  UPKEEPER_OBLIGATION_ISSUE_REPORT_DIR Default: obligation issue report state root
  UPKEEPER_OBLIGATION_GITHUB_ISSUE_WRITE Default: 0
  UPKEEPER_OBLIGATION_GITHUB_ISSUE_LABELS Default: empty
  UPKEEPER_AUTOMATION_LAUNCHER  Default: current entrypoint name
  UPKEEPER_AUTOMATION_VARIANT   Default: standard
  UPKEEPER_AUTOMATION_POLICY    Default: one-cycle
  UPKEEPER_AUTOMATION_WORKFLOW  Default: empty
  UPKEEPER_AUTOMATION_OBLIGATION_ID Default: empty
  UPKEEPER_AUTOMATION_OBLIGATION_PATH Default: empty
  UPKEEPER_LATTICE_ENABLED     Default: 1
  UPKEEPER_LATTICE_REQUIRED    Default: 0
  UPKEEPER_LATTICE_DB          Default: runtime/upkeeper-lattice/lattice.sqlite3
  UPKEEPER_LATTICE_SELECTION_MODE Default: oldest-mtime
  UPKEEPER_LATTICE_RAW_STORAGE Default: limited
  UPKEEPER_LATTICE_SQLITE_JOURNAL_MODE Default: delete
  UPKEEPER_LOCAL_ENV_FILE      Default: ${XDG_CONFIG_HOME:-$HOME/.config}/upkeeper/local.env
  UPKEEPER_LOCAL_ENV_DISABLE   Default: 0
  UPKEEPER_PRECONTACT_BACKUP_ENABLED Default: 1
  UPKEEPER_PRECONTACT_BACKUP_REQUIRED Default: 1
  UPKEEPER_PRECONTACT_BACKUP_MODE Default: auto
  UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED Default: 1
  UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT Default: 0
  UPKEEPER_PRECONTACT_BACKUP_ROOT Default: ${XDG_STATE_HOME:-$HOME/.local/state}/upkeeper/precontact-vault
  UPKEEPER_PRECONTACT_BACKUP_KEEP_PER_FILE Default: 20
  UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT Default: empty
  UPKEEPER_PRECONTACT_BACKUP_REDACT_PATHS Default: 1
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
  CODEX_FALLBACK_SCREEN_STAGE_ROOT   Default: ${XDG_STATE_HOME:-$HOME/.local/state}/upkeeper/backlog/tmp/fallback-screen
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
  CODEX_QUOTA_GUARDRAIL_BYPASS Default: 0
  CODEX_QUOTA_COOLDOWN_BYPASS   Default: 0
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
  7  Fallback plus post-mortem sequence completed, a persisted quota cooldown
     is active, or a required pre-contact backup failed before backend launch;
     manually relaunch after review or after the recorded reset time
  8  Fallback ran but the scripted post-mortem or hardening sequence failed
  9  Detached screen worker stopped on a guardrail without requesting parent termination
```

## FlameOn Launcher

`./FlameOn` is a repo-root convenience launcher for one high-coverage
smoke/burn cycle without typing the long Upkeeper flag set. It invokes
`./Upkeeper --model-override=5.5_xhigh --max-cover --bug-report-only` and
enables full-burn launcher defaults before backend launch: Lattice is required,
pre-contact backup is required, encrypted backup is required, and the Codex
sandbox mode is pinned to `--sandbox workspace-write`. The launcher also sets
quota stop floors and weekly buffers to `0`, bypasses wrapper quota guardrail
stops, and bypasses persisted quota cooldown markers from older guarded runs, so
scheduled burn runs can spend the selected model bucket down to the provider
floor. Its default cycle files issues or fully reports confirmed bugs instead of
patching tracked source.

Use `FLAMEON_DRY_RUN=1 ./FlameOn` to print the resolved command without
launching Codex. Use `./FlameOn -backup_queue` or `./FlameOn --backup-queue`
when that cycle should read and write the backup local failure queue instead of
the default queue. Live FlameOn runs require `age` plus
`UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT`.

Optional Bash completion is available with:

```sh
source completions/upkeeper.bash
```

## ChimneySweep Launcher

`./ChimneySweep` is a repo-root issue-fix launcher with its own scripted
pre-launch queue ranking. It lists open GitHub issues before any backend Codex
process can start. If the actionable queue is clean, it prints `high five yay`
and exits 25. Otherwise it prefers security-class issues, then data-integrity
issues, then the remaining queue ranked by containment title/tag signals,
severity, and least-recently-touched age. The selected issue is handed to
Upkeeper as `--fix-issue=NUMBER`, with `--prompt-pass=all` and all P24-P30
review modules enabled. Its default workflow runs separate comment, review, and
apply stages with `--issue-workflow-stage=comment|review|apply`, so the first
two stages are source read-only and run backend Codex in a read-only repository
sandbox, while the final stage owns implementation.
Before ranking GitHub issues, ChimneySweep reconciles unresolved Upkeeper
automation obligations. If an obligation exists, ChimneySweep is repairing the
automation system first, not skipping the issue queue accidentally. It should
make that plain in terminal output by naming the prior automation failure and
the mapped repair target file.
Those stages use the Genie Protocol boundary: the wrapper fetches issue
evidence before launch, backend Codex receives that packet only, direct
`gh`/GitHub command access is blocked in the backend environment, comment/review
issue text returns through a final-message draft block, and the wrapper performs
issue comments or other GitHub side effects after validation. Wrapper-posted
stage comments are visibly prefixed as `Upkeeper ChimneySweep proposal:` and
`Upkeeper ChimneySweep review:` so they are distinguishable from human comments.

Use `CHIMNEYSWEEP_DRY_RUN=1 ./ChimneySweep` or `./ChimneySweep --dry-run` to
print the resolved command without launching Codex. Its terminal verbosity flags
match FlameOn: `--silent`, `--basic`, and `--debug1`; `--workflow=...` selects
`comment-review-apply`, `comment-review`, `comment`, `review`, or `apply`.
Both FlameOn and ChimneySweep accept `--model-override=5.5_xhigh`,
`--model-override=5.3-codex-spark_xhigh`, or the shortcut form
`--model gpt-5.3-codex-spark --reasoning-effort xhigh`; the selected override
is passed to every backend Upkeeper invocation.
Live ChimneySweep runs
use the same full-burn launcher defaults as FlameOn: Lattice required,
encrypted pre-contact backup required, quota guardrail stops bypassed, cooldown
markers bypassed, quota stop floors set to `0`, and `--sandbox workspace-write`
pinned. Run `tools/upkeeper_precontact_bootstrap.sh` before using it live.

Recommended one-time setup for live full-burn launchers:

```sh
sudo apt-get update
sudo apt-get install -y age

tools/upkeeper_precontact_bootstrap.sh
```

That writes the public `UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT` into
`${XDG_CONFIG_HOME:-$HOME/.config}/upkeeper/local.env`. Keep the private
identity file out of prompts, logs, committed config, and backend-visible
environments; use it only when manually restoring encrypted backup payloads.

## Pre-Contact Backup Examples

Plain local backup mode keeps a copy outside the repository. It is useful for
manual recovery, but it is not protected from same-user deletion and now
requires an explicit unsafe override:

```sh
UPKEEPER_PRECONTACT_BACKUP_ENABLED=1
UPKEEPER_PRECONTACT_BACKUP_REQUIRED=1
UPKEEPER_PRECONTACT_BACKUP_MODE=plain
UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0
UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1
UPKEEPER_PRECONTACT_BACKUP_KEEP_PER_FILE=20
```

Age encrypted mode writes encrypted backup payloads using only a public
recipient. Do not put the private identity in prompts, logs, committed config,
or backend-visible environment:

```sh
UPKEEPER_PRECONTACT_BACKUP_MODE=age
UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT=age1...
```

Require encrypted backup mode when a cycle must fail before backend launch
unless age encryption is available:

```sh
UPKEEPER_PRECONTACT_BACKUP_MODE=auto
UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT=age1...
UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=1
```

Restore by opaque backup id:

```sh
tools/upkeeper_precontact_restore.sh --repo-root=. --backup-id=BACKUP_ID
tools/upkeeper_precontact_restore.sh --repo-root=. --backup-id=BACKUP_ID --identity=/path/to/age-identity.txt
```

`UPKEEPER_PRECONTACT_BACKUP_ROOT` may point at an operator-local vault outside
the repository. The wrapper never includes the generated vault path in compiled
prompts, backup log lines, or Lattice preselect evidence.

## Operational Notes

- `CODEX_MODE` defaults to `--sandbox workspace-write`. Set `CODEX_MODE` only
  when testing a newer Codex sandbox flag or temporarily matching an older local
  Codex install. Startup rejects malformed mode strings whose first token is
  missing, lacks `--`, uses a triple-hyphen token such as `---sandbox`, requests
  `danger-full-access`, or requests `--dangerously-bypass-approvals-and-sandbox`.
- Before/after quota reset epochs may jitter by a second between otherwise
  current exact-model snapshots. Upkeeper treats small reset-epoch jitter as the
  same quota window and logs `quota.reset_jitter` at INFO instead of emitting a
  non-authoritative `quota.jump` warning.
- Default quota logging is privacy-minimized: session-source paths and quota
  identity fields are hashed in normal loop logs, cooldown markers keep only
  enforcement-critical fields, and the fuller quota/session diagnostics remain
  behind explicit `UPKEEPER_VERBOSE_METADATA=1` plus private local artifact
  permissions.
- `--prompt-pass=all` final reports must include parseable `P<N>:` lines for
  P1 through P23. Upkeeper logs `review.pass_coverage` so all-pass cycles are
  auditable from machine logs, not only from prose. The parser accepts common
  Markdown line prefixes such as bullets and bold/code emphasis around `P<N>`.
- Final responses may include additive `UPKEEPER_PASS_RESULT` lines for every
  P* pass actually applied or explicitly found not applicable. For
  `--prompt-pass=all`, incomplete or unavailable pass-result coverage now
  blocks the cycle after parsing. Outside all-pass runs, missing lines remain
  additive-only. Malformed lines are rejected evidence for Lattice instead of
  clean pass results.
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
  status, `--smoke` for the fast local edit loop, `--quick` for bounded
  static/fixture checks, and `--full` for the broad deterministic integration
  gate before release or after touching module order, prompt packaging,
  symlink behavior, or failure-path guardrails.
  Smoke mode covers fast syntax, help, docs, parser, and launcher contracts;
  heavier config, manifest, Lattice, and review-module dry-run fixtures stay in
  full mode. Add `--profile` to validation runs to print per-check elapsed
  timings without changing coverage. Full validation uses bounded dry-runs plus
  a local fake `codex` binary; it does not launch real backend work.
  GitHub Actions runs the no-quota CI path in `.github/workflows/ci.yml` on
  pull requests and on pushes to `main`. It installs required tools including
  `jq` and `age`, classifies the change scope, and then runs either the
  docs-only path (`tools/check_public_docs.sh --quick` plus
  `tools/validate_upkeeper.sh --smoke`) or the broader shell/tests/docs/full
  validation path.
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
- Startup-anomaly scans suppress older log-only `previous_run.anomaly_detail`
  entries
  after a later `startup_anomaly.gate_resolved` has acknowledged
  `previous_run_anomaly`; unresolved gate state files still trigger the gate.
- Startup-anomaly self-review gates require a repo-local regular Upkeeper file
  for this pre-contact backup slice. Symlinked clients still invoke the central
  wrapper through `Upkeeper.sh`, but that symlink is not selected as a backed-up
  review target.
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
  or relocated for one run with `--manifest-file=PATH`. Custom manifest paths
  must stay under runtime/ or another ignored local path unless
  `--allow-unsafe-manifest-path` is explicitly set for a trusted one-cycle run.
- Open tool-failure queue markers live under
  `runtime/unaddressed-tool-failures/open/`; resolved markers move to
  `runtime/unaddressed-tool-failures/resolved/`.
- Backup queue runs use `runtime/unaddressed-tool-failures-backup/open/` and
  `runtime/unaddressed-tool-failures-backup/resolved/` for that one cycle.
- A repo-level active lock at `runtime/upkeeper-active.lock` prevents two
  Upkeeper loops from running the same checkout concurrently; stale locks are
  reclaimed only when the recorded PID/start fingerprint no longer matches.
  Custom `CODEX_ACTIVE_LOCK_DIR` values must stay under the checkout's
  `runtime/` tree and carry Upkeeper's ownership marker before stale cleanup can
  remove lock contents.
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
  `previous_run.anomaly_summary`, `previous_run.anomaly_detail`,
  `disk.preflight`, and `--MARK--` lines are primary evidence for follow-up
  self-repair.
- If a startup anomaly gate is active and the final response omits the required
  raw-line `UPKEEPER_LOG_REVIEW: CHECKED cycle=<cycle_id> anomalies=none log_sha256=<64-hex>` or
  `UPKEEPER_LOG_REVIEW: CHECKED cycle=<cycle_id> anomalies=listed log_sha256=<64-hex>`
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
