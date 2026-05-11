
Read this FULL prompt before starting in

ABSOLUTE RULE -- NO SKIPPING SELECTED FILES

YOU MAY NOT SKIP A FILE.

The entire point is to behave like each iteration of this prompt,
each invocation of it, is a fresh clean-eyes review.

You -- the LLM instantiation reading this -- have never seen this file.
You did not exist a minute ago.
Prior review history is irrelevant.

If the timestamp-selection rule selects a file, you MUST review that file.

You may not skip files because:
- the file was already reviewed
- the file was touched recently
- the file was updated a minute ago
- another agent or prior run reported "no fixes needed"
- the file was modified by a previous execution
- the file appears in prior run history
- the file seems boring, trivial, or already clean

A selected file may only be bypassed if it is physically impossible or unsafe to review:

1. the file no longer exists
2. the file is unreadable
3. the file is binary/generated/vendor/cache content explicitly excluded by this prompt
4. reviewing the file would violate a hard safety constraint

If one of those physical/safety exceptions applies:

- state the exact exception
- show the command/output proving it
- do not touch that invalid file
- select the next oldest eligible file
- complete the execution on that replacement file only when this prompt does not include a
  `WRAPPER_PRESELECTED_REVIEW_TARGET` block. If this prompt includes
  `WRAPPER_PRESELECTED_REVIEW_TARGET` and the selected file is impossible, you
  must report `STOPPED_ON_BLOCKER` instead of selecting a replacement.

Scope rule -- generated and ignored artifacts:

- The review target must be a repo source, documentation, configuration, prompt,
  manifest, script, or tool file that is tracked by git or is an intentional
  untracked-but-not-ignored source file.
- Do NOT select or modify ignored files, generated files, runtime evidence,
  caches, vendor content, or VCS internals.
- Explicitly excluded paths include:
  - .git/
  - runtime/
  - Upkeeper.log
  - any path ignored by .gitignore
- Prefer this candidate source command so ignored/runtime artifacts are not
  accidentally selected:

  git ls-files -co --exclude-standard -z

- If this prompt contains a WRAPPER_PRESELECTED_REVIEW_TARGET section, Upkeeper
  has already run source-safe selection before Codex started. Treat that
  preselected target as the timestamp-selected file. This overrides every later
  P1-P23 SELECTION RULE for this cycle; run all applicable prompts against the
  same selected file. Do not spend tool calls rediscovering the whole repository
  unless that exact file no longer exists, is unreadable, is binary, or is
  explicitly excluded by this prompt.
- The preselected section includes git_status, content_state, head_blob, and
  worktree_hash captured before Codex started. If content_state is
  differs_from_head or git_status is not clean, the selected file already had
  dirty content at selection time. Preserve that baseline and do not block
  solely because `git diff` against HEAD is non-empty after touch. Verify clean
  no-edit reviews by comparing the selected file's pre-touch content hash to its
  post-touch content hash.
- Do not run broad tree inventory commands such as `find .`, `find . -maxdepth`,
  `ls -R`, or similar scans for selection. Those commands surface `.git/objects`
  and other VCS/runtime internals, waste tokens, and are outside the review
  target boundary.
- Do not use `sort | head` for candidate output; upstream commands can emit
  broken-pipe noise when `head` exits early. If a fallback preview is needed,
  use a bounded source-safe command that limits after sorting without triggering
  broken pipes, or use Python to sort and print only the needed rows.
- Do not build nested `xargs ... sh -c ... awk ...` candidate selectors. They
  are fragile under shell quoting and can produce thousands of repeated errors.

- If another scan such as find(1) surfaces an excluded file first, that is the
  generated/ignored-artifact exception. State that exception, do not touch that
  file, and select the next oldest eligible non-excluded candidate.

"No findings" is not a skip.
"No fixes needed" is not a skip.
"Already reviewed" is forbidden as a skip reason.

If no fixes are found:

- report REVIEWED_CLEAN
- touch the selected file
- verify the mtime changed
- verify no unintended content change was introduced compared with the
  pre-touch baseline, allowing for any pre-existing dirty diff reported in the
  WRAPPER_PRESELECTED_REVIEW_TARGET metadata
- count the execution as completed

Machine-readable pass-result evidence:

- Keep `UPKEEPER_LOG_REVIEW` and `UPKEEPER_STATUS` unchanged.
- For every P* pass you actually applied or explicitly found not applicable,
  include one raw final-response line that starts with `UPKEEPER_PASS_RESULT:`.
- Use key/value fields so Upkeeper Lattice can record pass rows without schema
  changes for future P30 or P999 passes.
- Examples:
  - `UPKEEPER_PASS_RESULT: pass=P23 file=lib/upkeeper/example.bash applicable=1 outcome=clean changed=0 regression=0`
  - `UPKEEPER_PASS_RESULT: pass=P24 file=lib/upkeeper/example.bash applicable=1 outcome=fixed changed=1 regression=0`
  - `UPKEEPER_PASS_RESULT: pass=P25 file=lib/upkeeper/example.bash applicable=0 outcome=not_applicable changed=0 regression=0 reason=no_matching_surface`
- Do not put these marker lines inside Markdown code fences.
- Missing pass-result lines do not fail the cycle; malformed lines are rejected
  evidence, not clean pass results.

To be clear:

You are looking for the ===ONE=== oldest file that is a script or tool that you can update and improve.

Do not select tests as the primary script/tool target merely because they use a script-language extension.
Paths under test directories or named test_* should be considered test files, not script/tool files, unless explicit added guidance asks for a test review or there are no eligible script/tool candidates.

Find the ===ONE=== oldest that has not been looked at, and look at it. Examine it.
If every relevant file has been touched in the past 24 hours pick the oldest one and that is your target.

Don't limit to just shell or just py. It may even be another language.

Is it a script? It it oldest? It counts.

Show us the epoch of the file but ALSO in human readable date/time for update

AND:

How many hours/minutes since last updated

Once the file is selected, run ALL prompts from the repertoire below that are applicable to that file type:

- For all file types: also run P22
- For scripts/tools: run P1, P3, P4, P5, P6, P7, P9, P10, P11, P12, P13, P14, P15, P17, P18, P19, P20, P21
- For test files: run P1, P8 (if test suite exists)
- For manifests/dependency files: run P1, P16
- For repo-level operations: run P2
- For data/input-boundary files: also run P23 when the selected file is a validator, parser, importer, exporter, registry loader, schema/profile helper, config/manifest reader, JSON/JSONL/YAML/CSV/SQLite reader, path-resolving shell helper, or CLI that consumes external/operator input or emits machine-readable output

Skip prompts that don't apply to the selected file type.

Every single time this prompt is ran you MAY have something to fix!

DO EACH TASK AS A FRESH CLEAN EYES RUN

AS IF YOU HAVE NEVER DONE IT BEFORE

Then come back up here to top to begin

Note the time you began and the time you ended and elapsed time when done as well.

Detail all fixes found/implemented and why for each.

##########

Background Review Prompt Repertoire

Each prompt is self-contained, model-agnostic, and safe to run on rotation.
Upkeeper already preselects the source-safe target when possible; use that
selection instead of rediscovering candidates. If edits are made, verify the
intended content persisted and report the changed file list. For clean no-edit
reviews, touch the selected file and verify mtime changed while the content hash
remained equal to the pre-touch hash.

________________________________________

P1 - Comprehensive Code Review (Broad Pass)

Covers workflow, simplification, portability, and documentation in one sweep.

Perform a fresh, independent code review across four passes. Each pass is a
clean-eyed evaluation with no assumptions carried from prior passes. A pass
with no findings is a valid and acceptable result.

GLOBAL RULES (apply to all passes):

- Every proposed change must represent a genuine, demonstrable improvement.
- No cosmetic changes, no churn, no busy work.
- If a pass yields no honest findings, state that and move on.
- Output format per finding: [File] | [Location] | [Issue] | [Proposed fix] | [Rationale]

PASS 1 -- WORKFLOW AND EFFICIENCY

Identify redundant operations, avoidable I/O, unnecessary complexity, or logic
that produces overhead without benefit. Flag only real problems -- do not
manufacture findings.

PASS 2 -- SIMPLIFICATION

Identify any abstraction, variable name, function, class, or structural pattern
that can be removed, renamed, or collapsed without degrading correctness,
readability, or maintainability. Target: minimum necessary complexity, no dead
code, no unnecessary indirection.

PASS 3 -- PORTABILITY

Identify anything that restricts execution to a specific environment, shell
version, OS, or dependency without clear necessity. Prefer POSIX-compliant
constructs. Flag hardcoded paths, environment assumptions, non-portable syntax,
and interpreter-specific features where a portable equivalent exists at no
material cost to correctness or performance.

PASS 4 -- DOCUMENTATION

Every comment must answer: what does this do, why does it do it, and (where
non-obvious) how. A junior engineer with no prior codebase knowledge should be
able to follow every non-trivial block. Remove outdated, redundant, or
misleading comments. Add comments only where they provide clarity not already
present in the code itself.

________________________________________

P2 - Branch and PR Housekeeping

Repo-level. Run on a slower cadence (weekly or less). Goal: sustainably clean.
Perform a branch and pull request housekeeping review. Goal: sustainably clean
repository. Treat this as a fresh pass with no assumed prior state.

GLOBAL RULES:

- Every recommendation must materially advance project goals.
- No performative work, no busy work.
- If a task yields no honest findings, state that and move on.

TASK 1 -- BRANCH AUDIT

For each non-main branch, determine:
- Commits and calendar days behind main
- Whether it contains forward progress not yet in main
- Disposition: merge, rebase-and-merge, close without merge, or keep active
  with explicit rationale

TASK 2 -- DEPENDENCY MAPPING

Identify any branch or PR whose completion would unblock or substantially
simplify a meaningful body of other work. Flag any case where a single merge
or close would enable an entire category of subsequent work to proceed
more cleanly.

TASK 3 -- CHURN DETECTION

Flag: branches with large commit histories representing rework rather than
progress; PRs too diverged from main to merge cleanly; work better restarted
as a smaller, focused branch from current main. Prefer small, single-purpose
branches for all future work.

TASK 4 -- HIGHEST-LEVERAGE ACTION

Identify the single action available right now -- one merge, close, or rebase
-- that most improves the repository's forward trajectory.
OUTPUT: Structured findings per task, then a prioritized action list ordered
by impact.

________________________________________

P3 - Targeted Single-Script Deep Dive

Timestamp-selected. Deepest per-file review in the set.
This is a targeted improvement pass on a single script.

SELECTION RULE

Examine modification timestamps of all scripts in scope. Select the one script
with the oldest last-modified timestamp. If timestamps are tied or unavailable,
select alphabetically first. State which file was selected and why.

REVIEW CATEGORIES (run all against the selected script):
1. Correctness -- bugs, unhandled edge cases, failure modes
2. Efficiency -- operations slower, heavier, or more complex than necessary
3. Simplification -- names, abstractions, or structures that can be removed
   or collapsed without harm
4. Portability -- constructs that restrict the script to a specific environment
   where a portable alternative exists at no material cost
5. Documentation -- every non-obvious block must have a comment stating what
   it does, why, and how

PROCESS

1. Propose all changes before applying any.
2. Apply only changes that survive self-review.
3. Run a minimum of three independent test cycles: normal operation, edge
   cases, and failure/error conditions.
4. Record results of each test cycle explicitly.

COMPLETION

Whether or not any changes were made, update the file's modification timestamp:
  touch <filename>

OUTPUT: file selected and rationale | findings per category | changes applied
| test results | final status

RULES

- No busy work. No churn. No changes made for aesthetic reasons alone.
- A pass that finds nothing worth changing is a successful outcome --
  state it and touch the file.

________________________________________

P4 - Security and Secrets Scan

Covers what no other prompt touches. High value, always safe to run.

Perform a security and secrets hygiene pass on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Hardcoded secrets -- API keys, tokens, passwords, connection strings, private
   paths present in source rather than injected via environment or config
2. Input validation -- external inputs (args, env vars, stdin, file reads) that
   reach logic without validation or sanitization at the boundary
3. Privilege and permission assumptions -- operations that assume more access
   than the minimum required; hardcoded uid/gid/chmod values; unrestricted
   file creation
4. Injection surface -- anywhere user-controlled or external data is passed to
   a shell, eval, exec, or interpreter without escaping
5. Credential handling -- are credentials logged, echoed, stored in plaintext,
   or passed as command-line arguments where they appear in process listings?

PROCESS

Propose findings only -- do not modify the file.

Flag each finding: [File] | [Line] | [Category] | [Issue] | [Recommended remediation]
After review, touch the file to update its timestamp.

RULES

No busy work. A clean file is a valid result -- state it and touch the file.

Do not generate false positives to appear thorough.

________________________________________

P5 - Dead Code Elimination

Static reachability pass. Distinct from simplification -- this is code that cannot be reached or is never used, not code that is merely redundant.

Perform a dead code detection pass on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Unreachable code -- branches, statements, or blocks that cannot be reached
   under any input or execution path
2. Unused definitions -- functions, variables, constants, classes, or imports
   defined but never referenced within the file or exported for use elsewhere
3. Commented-out code -- blocks of code left as comments with no explanatory
   note indicating why they were kept; these are almost always safe to remove
4. Redundant logic -- conditions that are always true or always false given
   surrounding context; duplicate checks; operations whose result is never used

PROCESS

1. Propose all removals before applying any.
2. For each proposed removal, confirm: is this reachable from any external
   caller? Is it part of a public interface? If uncertain, flag for human
   review rather than removing.
3. Apply only removals with high confidence.
4. Touch the file when done.

RULES

No busy work. No removals made out of aesthetic preference.

If nothing qualifies for removal, state that and touch the file.

________________________________________

P6 - Error Handling Audit

Silently swallowed errors are one of the most common sources of mysterious failures in shell and scripting environments.

Perform an error handling audit on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Swallowed errors -- operations whose failure is ignored: unchecked return
   codes, bare try/except with no handler, redirecting stderr to /dev/null
   without reason
2. Silent failures -- code paths that fail without emitting any diagnostic
   output, leaving the caller or operator with no indication something went wrong
3. Inconsistent error propagation -- functions that sometimes return error codes
   and sometimes call exit(), or that mix return-based and exception-based
   handling without a clear contract
4. Missing cleanup on failure -- resources (file handles, connections, temp
   files, locks) that are not released when an error path is taken
5. Overly broad catches -- catch-all handlers that mask distinct failure modes
   that warrant different responses

PROCESS

Propose all changes before applying any.

Apply only changes that have no ambiguity about correctness.

Test: normal operation, injected failure at each identified error surface.

Touch the file when done.

RULES

No busy work. No changes made to satisfy a category that doesn't apply.

Unclear cases: flag for human review, do not guess.

________________________________________

P7 - Configuration and Magic Values

Hardcoded values are a portability and maintainability tax that accumulates silently over time.

Perform a configuration hygiene pass on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Magic numbers and strings -- literal values embedded in logic whose meaning
   is not immediately obvious and which have no named constant or comment
   explaining what they represent and why that specific value was chosen
2. Hardcoded environment assumptions -- absolute paths, hostnames, usernames,
   port numbers, or filesystem layouts baked into logic rather than drawn from
   configuration or environment variables
3. Tunables presented as constants -- values likely to change per deployment,
   per operator, or over time (timeouts, retry counts, buffer sizes, thresholds)
   that should be externalizable but are not
4. Duplication of configuration values -- the same literal value appearing in
   multiple places; changing it requires finding every instance

For each finding, propose: a named constant, environment variable, config key,
or parameter that would replace the hardcoded value. Show the before and after.

PROCESS

Propose all changes before applying. Apply only unambiguous cases.

Touch the file when done.

RULES

No busy work. Not every literal is a magic value -- obvious counts like 0 and 1
in loop logic are not findings unless their meaning is genuinely unclear.

________________________________________

P8 - Test Gap Analysis

Only useful if the project has a test suite. Drop from the random pool if not.

Perform a test coverage gap analysis on a single source file.

SELECTION RULE

Select the source file (non-test file) with the oldest last-modified timestamp.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Untested public interface -- functions, methods, or command paths exposed for
   external use that have no corresponding test exercising them
2. Untested error paths -- error handling branches (failure returns, exception
   handlers, fallback logic) with no test that triggers them
3. Untested edge cases -- boundary conditions at the margins of expected inputs
   (empty input, max/min values, null/missing values, concurrent access)
   that are not covered by existing tests
4. Tests that test the wrong thing -- assertions that pass regardless of whether
   the code under test is correct (vacuous tests, tests of implementation detail
   rather than behavior)

OUTPUT

For each gap: [File] | [Function/path] | [Missing case] | [Suggested test description]

Do not write the tests unless explicitly asked. This pass identifies gaps only.

Touch the source file when done to record the review timestamp.

RULES

No busy work. If coverage is genuinely solid, say so and touch the file.

________________________________________

P9 - Observability and Logging Review

Easy to skip during development. Surprisingly high value in production and long-running scripts where reconstructing what happened matters.

Perform a logging and observability review on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Missing operational visibility -- code paths that perform meaningful work
   (state changes, external calls, file operations, decisions) with no log
   output, leaving operators unable to reconstruct what happened from logs alone
2. Wrong log level -- debug-level noise emitted unconditionally; significant
   events logged at a level that would be filtered in production
3. Unhelpful log messages -- messages that state what happened without enough
   context to act on: no relevant values, no indication of which code path was
   taken, no correlation identifiers
4. Excessive or noisy logging -- high-frequency events logged unconditionally
   in ways that would overwhelm log storage or obscure meaningful signal
5. No log on failure -- error paths that exit or return without emitting any
   diagnostic (distinct from silent failure in P6 -- this is specifically about
   log output, not error propagation)

PROCESS

Propose additions and changes. Apply only unambiguous improvements.

Touch the file when done.

RULES

No busy work. Not every function needs a log line.

The goal is that an operator can understand what the system did from logs alone.

________________________________________

P10 - Idempotency Review

Probably the most important prompt for automation scripts specifically. Can this script be run twice? What is the blast radius of a double-run?

Perform an idempotency review on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Non-idempotent writes -- operations that append, increment, or accumulate
   state when re-run rather than converging to the same result regardless of
   how many times they execute (e.g. appending to a file that should be written
   once, creating duplicate records, double-charging an API)
2. Missing existence checks -- destructive or creative operations (mkdir, create,
   insert, deploy) that do not first check whether the target state already exists
3. Partial failure residue -- if the script fails halfway through and is re-run,
   does it pick up cleanly, or does it leave artifacts from the first partial run
   that cause the second run to fail or behave incorrectly?
4. Side effects on external systems -- calls to external APIs, services, or
   databases that are not safe to repeat (non-GET requests with no deduplication,
   emails that could send twice, charges that could double)
5. Order dependency -- does the script assume it is running on a clean initial
   state that may not exist on re-run?

For each finding: [File] | [Location] | [Issue] | [What happens on double-run] | [Fix]

Touch the file when done.

RULES

No busy work. Many scripts are legitimately single-run by design -- note that
and touch the file. The question is whether the design is intentional and
documented.

________________________________________

P11 - Signal Handling and Cleanup

Shell scripts especially are notorious for leaving temp files, locks, and partial state when killed. Easy to audit, high operational value.

Perform a signal handling and cleanup audit on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Missing trap handlers -- scripts that create temporary files, acquire locks,
   open connections, or modify shared state with no trap to clean up on
   EXIT, INT, TERM, or HUP
2. Incomplete cleanup -- trap handlers that exist but do not cover all resources
   created during execution (a trap that removes one temp file but not three)
3. Cleanup ordering -- teardown that runs in an order that could leave
   inconsistent state (releasing a lock before flushing a write, removing
   a socket before closing connections using it)
4. Non-graceful termination -- long-running operations with no mechanism to
   respond to SIGTERM with a clean shutdown before SIGKILL would be required
5. Cleanup on success vs failure -- cases where cleanup only happens on
   the happy path and is skipped on error exit

For each finding: [File] | [Location] | [Resource at risk] | [Signal not handled] | [Fix]

Touch the file when done.

RULES

No busy work. Short stateless scripts may need no trap handling -- note that
explicitly rather than manufacturing findings.

________________________________________

P12 - DRY Violations / Copy-Paste Detection

Distinct from dead code (P5). This is live code that exists in multiple places and should be one thing.

Perform a duplication and DRY (Don't Repeat Yourself) audit on a single file,
or across a small set of closely related files if the file has known siblings.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Duplicated logic blocks -- sections of code that perform the same operation
   or implement the same algorithm in two or more places within scope
2. Near-duplicates -- blocks that are almost identical with only minor variation
   (different variable names, slight parameter differences) that could be unified
   into a parameterized function
3. Repeated literal sequences -- the same sequence of operations (open, validate,
   transform, write) performed in multiple places with no shared abstraction
4. Copy-paste with drift -- duplicated blocks that have diverged slightly over
   time, creating inconsistent behavior between the copies that is unlikely
   to be intentional

For each finding:

- Show the two (or more) locations
- Describe what they share
- Propose the abstraction that would unify them
- Note any meaningful differences that would need to be preserved as parameters

Touch the file when done.

RULES

No busy work. Not all repetition is bad -- sometimes clarity is worth the repeat.
Only flag cases where a shared abstraction would be simpler and more maintainable
than the current duplication, without introducing indirection for its own sake.

________________________________________

P13 - External Call Resilience

API calls, service calls, subprocess calls -- does anything handle the other side being unavailable?

Perform an external call resilience audit on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Missing timeout -- calls to external services, APIs, subprocesses, or network
   resources with no timeout configured, risking indefinite hang
2. No retry logic -- transient failures (network blip, rate limit, temporary
   unavailability) that cause permanent failure with no retry or backoff
3. No backoff -- retry logic that hammers a failing service at full rate rather
   than using exponential or linear backoff with jitter
4. Undifferentiated failure handling -- treating all errors from an external call
   identically when some (rate limit, auth failure, not found, server error)
   warrant different responses
5. No circuit breaker or fallback -- calls where repeated failure of the external
   service will cascade into broader system failure with no degraded-mode fallback
6. Unbounded response consumption -- reading external responses into memory
   without size limits, risking OOM on unexpectedly large payloads

For each finding: [File] | [Call site] | [Service or target] | [Risk] | [Recommended fix]

Touch the file when done.

RULES

No busy work. Internal calls between trusted local components may not need
the same treatment as external network calls -- distinguish clearly.

________________________________________

P14 - Naming Consistency Audit

Convention drift is invisible until you are onboarding someone or debugging at 2am.

Perform a naming consistency audit on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Convention inconsistency -- mixed use of naming styles within the same scope
   (snake_case and camelCase for the same category of identifier, SCREAMING_SNAKE
   for some constants but not others)
2. Misleading names -- identifiers whose name implies behavior or content
   different from what they actually do or contain
3. Abbreviated vs spelled-out inconsistency -- the same concept referred to as
   both "cfg" and "config", "err" and "error", "msg" and "message" within scope
4. Plural/singular inconsistency -- collections named as singular, scalar values
   named as plural
5. Verb/noun role mismatch -- functions named as nouns, variables named as verbs

This audit does not require renaming everything -- it identifies drift from
whatever convention is dominant in the file. The dominant convention wins.
For each finding: [File] | [Identifier] | [Current name] | [Issue] | [Suggested name]

Touch the file when done.

RULES

No busy work. Minor inconsistencies in a file that is otherwise consistent
with a clear dominant convention are not findings unless they cause genuine
confusion.

________________________________________

P15 - Assumption Documentation

The most dangerous code is code whose assumptions are invisible. This prompt surfaces them without changing any logic.

Perform an assumption documentation pass on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Undocumented preconditions -- functions or scripts that will fail or misbehave
   if called under certain conditions, with no documentation of what those
   conditions are (e.g. must run as root, requires network access, assumes a
   directory exists, expects input pre-sorted)
2. Undocumented environment assumptions -- implicit dependencies on environment
   variables, system tools, installed packages, or runtime state that are not
   stated in comments, a header block, or a README
3. Undocumented data format assumptions -- parsing or processing logic that
   assumes a specific format, encoding, delimiter, or schema with no comment
   explaining what is expected and what happens if the expectation is violated
4. Undocumented ordering requirements -- operations that must happen in a specific
   order with no explanation of why; callers who get the order wrong will see
   silent misbehavior rather than a clear error
5. Undocumented state dependencies -- code that assumes some prior operation has
   already run (a migration, an init, a connection being established)

For each finding: add a comment at the relevant location stating the assumption
explicitly. Do not change the logic -- only surface what is already true.

Touch the file when done.

RULES

No busy work. Obvious assumptions (a sort function assumes a list) are not
findings. Target assumptions that would surprise a competent engineer
encountering the code for the first time.

________________________________________

P16 - Dependency Audit

Manifest-level. Run on a slower cadence (weekly or less). Not a per-file pass.

Perform a dependency audit on the project's dependency manifest(s).

SCOPE

Package manifests, lockfiles, requirements files, vendor directories,
or import blocks -- whatever dependency declaration mechanism the project uses.

REVIEW CATEGORIES:

1. Unused dependencies -- packages declared as dependencies that are not
   imported or invoked anywhere in the project
2. Outdated dependencies -- packages with known newer stable releases,
   particularly where the delta includes security fixes
3. Unpinned dependencies -- dependencies specified with open version ranges
   (*, ^, ~, >=) where a breaking change in a dependency could silently
   alter behavior on next install
4. Over-pinned dependencies -- dependencies pinned to an exact patch version
   in ways that block receiving security fixes without manual intervention
5. Duplicate functionality -- two dependencies that provide substantially the
   same capability, suggesting one could be removed
6. Known vulnerabilities -- any dependency with a published CVE against
   the version in use

For each finding: [Package] | [Category] | [Current version] | [Issue] | [Recommended action]

RULES

No busy work. Do not flag every package -- only genuine findings.

Do not recommend upgrading a dependency without noting the migration cost or
breaking change risk.

________________________________________

P17 - Atomicity and Partial Failure

Different from idempotency (P10). This is about what the world looks like if the script dies mid-write -- the state left behind, not the re-run behavior.

Perform an atomicity and partial failure audit on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Non-atomic writes -- files written incrementally without a write-to-temp-then-
   rename pattern, meaning a crash mid-write leaves a corrupt partial file
   at the destination path
2. Multi-step operations without rollback -- sequences of operations that together
   constitute a logical transaction, where failure partway through leaves the
   system in an inconsistent intermediate state with no recovery path
3. Lock files without expiry -- locks acquired with no TTL or staleness check,
   meaning a crashed prior run leaves the lock held indefinitely and blocks
   all future runs
4. State written before work is complete -- logging success, updating a status
   flag, or moving a file to a "done" location before the actual work it
   represents is fully committed
5. Missing fsync or flush -- data written to a buffer without an explicit flush
   or sync before the script considers the operation complete, risking data loss
   on unexpected shutdown

For each finding: [File] | [Location] | [Risk] | [Failure scenario] | [Fix]

Touch the file when done.

RULES

No busy work. Not all scripts need transactional semantics. Flag only cases
where partial failure would produce a result worse than a clean failure with
no side effects.

________________________________________

P18 - Concurrency and Race Conditions

Any script that touches shared files, shared state, or runs parallel jobs needs this review. Completely distinct from the other passes.

Perform a concurrency and race condition audit on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Shared file access without locking -- multiple processes or jobs that could
   read-modify-write the same file concurrently with no coordination mechanism
2. Check-then-act races -- logic that checks a condition and then acts on it
   without atomicity, where the condition could change between the check and
   the act (TOCTOU: time-of-check to time-of-use)
3. Uncoordinated parallel jobs -- background processes or parallel subshells
   writing to the same output, log, or state file without serialization
4. Shared environment mutation -- parallel execution paths that modify shared
   environment variables, global state, or working directory
5. Signal races -- signal handlers that access or modify state also touched
   by the main execution path without protection

For each finding: [File] | [Location] | [Shared resource] | [Race scenario] | [Fix]

Touch the file when done.

RULES

No busy work. Single-process, single-run scripts with no parallelism need
minimal review here -- note that and touch the file.

________________________________________

P19 - Exit Code and Output Contract

Critical for pipeline use and completely distinct from error handling (P6). Scripts that do not honor exit code conventions silently break everything downstream.

Perform an exit code and output contract audit on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Exit code correctness -- does the script exit 0 only on genuine success?
   Does it exit non-zero on all failure paths? Does it ever exit 0 after
   a failure that a caller would need to know about?
2. Exit code granularity -- where callers may need to distinguish between types
   of failure (not found vs permission denied vs network error), does the script
   use distinct exit codes, or does everything collapse to 1?
3. stdout vs stderr discipline -- is informational/diagnostic output going to
   stderr and only machine-readable or pipeable output going to stdout? Mixed
   output breaks pipeline use silently.
4. Silent success -- operations that fail but emit nothing and exit 0, giving
   callers no way to detect the failure
5. Output stability -- does the script's stdout format change based on verbosity
   flags, terminal detection, or locale in ways that would break a caller
   parsing its output?

For each finding: [File] | [Location] | [Issue] | [Impact on callers] | [Fix]

Touch the file when done.

RULES

No busy work. A script that is never used in a pipeline or called by another
process has different requirements -- note the usage context.

________________________________________

P20 - Resource Exhaustion and Bounds

The script works fine in dev and silently destroys production. Disk, memory, file descriptors.

Perform a resource exhaustion and bounds audit on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Unbounded disk writes -- operations that write to disk with no size check,
   quota awareness, or guard against filling the filesystem
2. Unbounded memory growth -- data structures that accumulate input without a
   size limit, or operations that load entire large files into memory when
   streaming would suffice
3. File descriptor leaks -- files, sockets, or pipes opened and not explicitly
   closed, particularly in loops or long-running processes where handle
   exhaustion is possible
4. No space preflight -- writes to disk with no check that sufficient space
   exists before beginning, leaving partial output on a full filesystem
5. Runaway loops -- loops whose termination depends on external state (file
   appears, process exits, service responds) with no iteration limit or timeout,
   risking indefinite resource consumption

For each finding: [File] | [Location] | [Resource] | [Exhaustion scenario] | [Fix]

Touch the file when done.

RULES

No busy work. Short scripts processing known-bounded inputs need minimal review
here -- note that and touch the file.

________________________________________

P21 - Documentation Drift

Different from P1 documentation quality pass and P15 assumption surfacing. This is specifically about comments that were once true and are no longer.

Perform a documentation drift audit on a single file.

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in scope.
On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Stale comments -- comments that describe behavior, logic, or values that the
   code no longer implements; the comment and the code have diverged
2. Outdated function signatures in docstrings -- documented parameter names,
   types, or return values that no longer match the actual function definition
3. Wrong examples -- code examples in comments that would not execute correctly
   against the current implementation
4. Orphaned TODO/FIXME -- items marked TODO or FIXME that either have already
   been addressed (and the marker not removed) or are so old they no longer
   describe a real issue
5. Version references that have passed -- comments referencing workarounds for
   specific versions of dependencies or runtimes that are no longer in use

For each finding: [File] | [Location] | [Comment] | [What has drifted] | [Correction]

Apply corrections directly -- these are documentation fixes, not logic changes.

Touch the file when done.

RULES

No busy work. A file whose comments accurately reflect its code is a valid and
good result. State that and touch the file.

________________________________________

P22 - Tool Serviceability and Supportability

A tool is not done when it works once. A tool is done when an engineer who did
not write it can understand, test, debug, safely dry-run, and modify it without
guessing. This pass verifies that the file is serviceable as an operational
artifact, not merely correct code.

SCOPE

This prompt applies to any file type. For scripts/tools, apply the full review.
For tests, manifests, docs, templates, and config files, apply the relevant
parts only:

- Does the file explain its purpose and operational role?
- Can a reviewer understand why each non-obvious action exists?
- Are debug/test/dry-run paths documented where applicable?
- Is related documentation discoverable and kept in sync?
- Is the file clean of accumulated cruft?

SELECTION RULE

Select the file with the oldest last-modified timestamp among all files in
scope. On ties, select alphabetically first. State selection and reason.

REVIEW CATEGORIES:

1. Purpose and operator intent

   The file must make clear:

   - what it does
   - why it exists
   - who or what is expected to run/use it
   - what systems, files, APIs, databases, or external services it may affect

   For scripts/tools, this should usually be stated in a top-level docstring,
   header comment, --help output, README, or paired documentation file.

   Findings:

   - Missing or vague purpose statement
   - Code actions whose intent is not obvious locally
   - Operationally important behavior only discoverable by reading all logic
   - Comments saying what code does but not why it does it

2. Local explainability at point of action

   Wherever the file performs meaningful work, the intent should be clear at
   the point where the work occurs.

   Examples of meaningful work:

   - writes, deletes, renames, moves, or mutates files
   - changes database rows
   - calls external APIs
   - starts/stops services
   - invokes subprocesses
   - parses non-trivial formats
   - applies thresholds, filters, or matching rules
   - chooses one branch of behavior over another
   - intentionally ignores or suppresses errors

   Findings:

   - Non-obvious logic with no explanation nearby
   - A future reviewer would need domain knowledge not present in the file
   - Magic behavior hidden behind terse names or unexplained constants
   - Comments too far away from the code they explain

   Fix:

   Add the smallest useful comment/docstring/constant name that explains intent,
   not a noisy restatement of syntax.

3. Built-in test/debug affordance

   Scripts and tools should provide at least one safe way to validate behavior
   without damaging real data or external systems.

   Review whether the tool has one or more of:

   - --dry-run
   - --check
   - --validate
   - --self-test
   - --debug
   - --verbose
   - --help with examples
   - a callable internal self-test function
   - a small documented test fixture path
   - a command-line mode that exercises parsing/validation only
   - unit tests dedicated to the tool

   Findings:

   - Tool mutates state but has no dry-run/check mode
   - Parser has no sample/fixture/test path
   - Debugging requires editing source code
   - No documented way to verify dependencies before running
   - Tool can affect external systems but cannot show planned actions first

   Fix:

   Prefer the smallest safe affordance:

   - add --dry-run for write paths
   - add --check for validation-only mode
   - add --self-test only if it can be genuinely useful and safe
   - document existing tests if they already exist

   Any new test/debug option must be documented in --help or file documentation.
   Any new test/debug option must be exercised before final report.

4. Dry-run and blast-radius control

   Any tool that writes, deletes, modifies, imports, fetches, syncs, pushes,
   commits, stages, regenerates, migrates, or calls external systems must either:

   - have a dry-run/check mode, or
   - explicitly document why dry-run is not practical and what safeguards exist

   Findings:

   - Destructive or mutating operation with no preview
   - Network/API operation with no no-op mode
   - Database import/update with no transaction or dry-run
   - Git operation with no status/diff audit before mutation
   - File writes with no output path disclosure before writing

   Fix:

   Add dry-run/check behavior if straightforward and safe.

   Otherwise add explicit documentation of safeguards and limitations.

5. Paired documentation discoverability

   Determine whether this tool/file has or should have a dedicated paired
   documentation file.

   A paired doc is recommended when:

   - the tool has operational risk
   - the tool has multiple modes
   - the tool has external dependencies
   - the tool is run manually by humans
   - the tool is run by cron/CI/agents
   - the tool has non-obvious input/output formats
   - the tool mutates files, databases, remotes, or services
   - the tool has important safety rules

   Findings:

   - Tool deserves a paired doc but none exists
   - Paired doc exists but is not referenced near the top of the tool
   - Tool says one thing while paired doc says another
   - No instruction that tool changes must update paired docs

   Fix:

   Prefer minimal discoverability improvement:

   - add "Documentation: docs/<tool>.md" near the top of the tool
   - add "When modifying this tool, update docs/<tool>.md"
   - if the doc does not exist, either create a concise one or flag for human
     review if creating it would be broad

   Do not create large documentation files unless the tool truly needs it.

6. Debug/man-style introspection

   For scripts/tools, check whether an operator can ask the tool what it does
   without reading source.

   Preferred affordances:

   - --help
   - --debug
   - --show-config
   - --show-plan
   - --show-inputs
   - --show-defaults
   - --version
   - --self-test
   - examples in help text

   Findings:

   - Tool lacks useful --help
   - --help omits side effects
   - --help omits environment variables
   - --help omits examples
   - --debug exists but does not expose useful state
   - Operators cannot see resolved paths/config before mutation

   Fix:

   Add or improve help/debug output only where it provides operational value.

   Do not add flags for aesthetics.

7. Cruft, detritus, and unnecessary action removal

   Look for accumulated leftovers that reduce serviceability:

   - dead flags
   - obsolete comments
   - unused constants
   - redundant branches
   - old compatibility shims no longer needed
   - duplicate helper functions
   - unnecessary wrappers
   - repeated literals
   - needless temp variables
   - needless abstractions
   - commented-out code
   - stale TODO/FIXME
   - overly verbose logic that obscures intent

   Also look for small simplifications:

   - Can a 20-character expression become 18 or 10 characters with no loss of
     clarity, behavior, portability, or debuggability?
   - Can a name be clearer and shorter?
   - Can repeated code be replaced by one obvious helper?
   - Can a needless helper be inlined?

   Rules:

   - Shorter is better only if it is equally or more clear.
   - Do not golf code.
   - Do not create clever one-liners.
   - Prefer boring obvious code over dense code.
   - Remove cruft only when removal is high-confidence.

8. Support handoff readiness

   Ask whether a support engineer, SRE, lab engineer, or future LLM agent could
   safely answer these questions in under five minutes:

   - What does this do?
   - Why does this exist?
   - What can this break?
   - What does this read?
   - What does this write?
   - How do I run it safely?
   - How do I dry-run it?
   - How do I test it?
   - How do I debug it?
   - What logs/output should I expect?
   - What documentation must I update if I change it?
   - What concurrency/idempotency assumptions exist?

   Findings:

   - Any answer requires tribal knowledge
   - Any answer requires reading unrelated files without a pointer
   - Any answer is absent, misleading, or stale
   - Any answer is only implicit in code

   Fix:

   Add concise documentation, help text, comments, or references where needed.

PROCESS:

1. Inspect the selected file and any directly paired docs/tests if they exist.
2. Identify serviceability gaps using the categories above.
3. Propose all changes before applying.
4. Apply only changes that are genuinely useful and low-risk.
5. If adding or changing CLI flags, dry-run behavior, debug behavior, or self-test
   behavior, run that path and show output.
6. If adding documentation references, verify referenced paths exist or clearly
   state that creation is deferred.
7. Touch the selected file when done.
8. Verify:
   - file timestamp changed
   - intended changes persisted on disk
   - no unintended files changed
   - tests/checks relevant to the file pass or were not applicable

OUTPUT:

- selected file and timestamp rationale
- serviceability findings by category
- changes proposed
- changes applied
- test/debug/dry-run/self-test output, if applicable
- paired documentation status
- any deferred documentation or test recommendations
- verification that changes persisted
- final git diff/stat for changed files
- final status:
  REVIEWED_AND_FIXED
  REVIEWED_AND_REPORTED
  REVIEWED_CLEAN
  STOPPED_ON_BLOCKER

RULES:

- No busy work.
- No churn.
- No cosmetic-only rewrites.
- Do not add comments that merely restate syntax.
- Do not add tests or debug flags that are fake, brittle, or unsafe.
- Do not add dry-run behavior that claims safety but still mutates state.
- Do not create broad documentation unless the file warrants it.
- Prefer small local improvements that make the tool easier to support.
- A file that is already serviceable is a valid result: state that, touch it,
  and move on.

________________________________________

P23 - Data Contract and Negative Fixture Audit

This pass applies only when the selected file touches a data or operator-input
boundary. Apply it when the selected file is a validator, parser, importer,
exporter, registry loader, schema/profile helper, config/manifest reader,
JSON/JSONL/YAML/CSV/SQLite reader, path-resolving shell helper, or CLI tool that
reads user/operator-supplied files or emits machine-readable output.

If the selected file does not touch a data/input boundary, state:

P23: not applicable

Goal:

Find places where malformed, ambiguous, unsafe, or non-contract data is accepted,
coerced, silently ignored, partially applied, or reported without actionable
diagnostics.

Core principle:

A tool is not contract-safe merely because valid fixtures pass. It must reject
malformed inputs early, explicitly, and with diagnostics that make the bad
field, row, path, or logical target clear without leaking secrets.

REVIEW CATEGORIES:

1. Boundary inventory

   Identify every external or semi-external input boundary in the selected file.
   Check for argv/CLI flags, environment variables, stdin, filesystem paths,
   JSON files, JSONL rows, YAML or JSON-compatible YAML registries, CSV or
   delimiter-based records, SQLite rows, schema/profile/manifest documents, URL
   fields, subprocess stdout/stderr, generated artifacts from earlier pipeline
   stages, caller-provided dictionaries/lists, and shell function parameters.

   For each meaningful boundary, ask: where is the first trusted point, and is
   validation performed before the data influences behavior?

2. Contract strictness

   For every boundary, check whether malformed or non-contract data is rejected
   rather than accepted, coerced, skipped, or silently defaulted.

   Look specifically for failure to reject:

   - unexpected fields where the contract is meant to be closed
   - missing required fields
   - wrong top-level container types
   - wrong nested container types
   - non-object rows inside object arrays
   - duplicate normalized IDs, keys, predicates, claim types, aliases, schemes,
     or policy IDs
   - blank strings where nonblank strings are required
   - strings accepted where booleans are required
   - strings accepted where numbers are required
   - booleans accepted where integers or numbers are required
   - NaN, Infinity, -Infinity, or any non-standard JSON numeric constants
   - non-finite floats
   - out-of-range scores, thresholds, counts, limits, or confidence values
   - negative counts where only nonnegative counts are meaningful
   - invalid timestamp format or timestamps without explicit timezone when
     timezone matters
   - invalid URL schemes
   - credential-bearing URLs such as https://user:pass@example.org
   - local paths that are actually URLs
   - path traversal or resolved paths escaping the allowed root
   - paths accepted because they merely contain a directory name rather than
     matching the exact required layout
   - conflicting duplicate fields between top-level and nested representations
   - ambiguous records that should be rejected or require human review
   - unknown enum values
   - deprecated enum aliases that should warn or normalize explicitly
   - unsupported schema/profile versions

3. No silent coercion

   Search for coercion or fallback patterns that can convert bad input into
   plausible output. Flag uses of:

   - str(value) on contract fields where non-string types should be rejected
   - bool(value) on JSON/config values, especially where "false" becomes truthy
   - int(value) or float(value) without finite/range checks
   - default {} or [] that hides malformed caller data
   - row.get(...) followed by quiet skip when the field is required
   - list comprehensions that silently drop non-object rows
   - broad except Exception that treats malformed input as absence
   - json.loads(...) without rejecting non-standard constants when strict JSON is
     expected
   - duplicate-key or duplicate-normalized-value overwrites
   - "first match wins" behavior where duplicates should be errors
   - fallback-to-empty behavior that causes validators/exporters to pass with
     partial data

   Do not mechanically remove every coercion. Only flag it when it can hide a
   real contract violation or produce misleading output.

4. Diagnostics and failure contract

   For each validation failure path, check whether the error is useful and safe.
   Good diagnostics should include, where practical, the field name, nested path,
   row index, JSONL line number, registry row index, offending enum/key name,
   expected type/range/pattern, target path or logical target ID, and clear exit
   code behavior for CLI tools.

   Diagnostics must not leak embedded credentials, tokens, full sensitive URLs
   if credentials are present, large raw payloads, or private/local-only content
   beyond what is needed to debug safely.

   Flag failures that only say invalid input, KeyError, AttributeError,
   ValueError, failed, or emit a Python traceback for normal malformed operator
   input.

5. Negative fixture requirement

   If you implement a P23 boundary fix, add or update a focused negative test or
   fixture unless there is a clear reason not to. A valid negative test should
   prove the previous permissive behavior is now rejected. Prefer small tests
   that exercise one defect at a time.

   Strong negative fixture examples:

   - JSONL line with NaN
   - JSON boolean in an integer field
   - duplicate normalized registry keys
   - non-object row inside an array
   - unexpected key in closed contract
   - credential-bearing remote URL
   - path with correct-looking words but wrong root layout
   - top-level and nested retention/status fields disagree
   - unknown enum value
   - invalid timestamp without timezone
   - missing required field inside one array row
   - malformed profile condition
   - missing --work-id target that previously returned success

   Normal-path tests alone are not enough for P23 fixes.

6. Schema-code-doc alignment

   When the selected file has paired schemas, docs, fixtures, or callers, inspect
   only enough adjacent context to verify alignment. Compare schema vs
   validator, validator vs parser/importer, parser/importer vs exporter, registry
   file vs registry loader, CLI help vs behavior, docs vs code, existing
   tests/fixtures vs expected contract, and output report shape vs documented
   output contract.

   Flag drift in any direction. A schema that is stricter than the validator is
   a bug. A validator that is stricter than the docs may be a docs bug or a
   behavior bug; decide based on surrounding contract evidence.

7. Output/export integrity

   For exporters and report writers, check that malformed or ambiguous internal
   records do not create plausible but wrong downstream output.

   Look for inverse relationships projected as forward relationships, lossy
   fields emitted without warning when the format cannot represent them,
   identifiers dropped when multiple standard values exist, unsafe escaping in
   text formats, invalid XML/JSON/CSV/BibTeX/RIS escaping, whitespace/newline
   behavior that changes record meaning, local/private data leaking into public
   formats, missing loss report entries for known omissions, and non-atomic
   output writes where partial output would be misleading.

8. Read-only, dry-run, and mutation claims

   If the tool claims to be read-only, dry-run, validation-only, metadata-only,
   or temp-copy-only, verify that claim against the actual code.

   Flag read-only tools opening SQLite through normal write-capable connections,
   dry-run modes that still mutate durable state, validation-only modes that
   write artifacts outside explicit report paths, temp-copy import flows that can
   write the source DB, report writers that can leave partial files on
   interruption, copy flows that race on predictable filenames, and cleanup paths
   that leave stale temp files after failure.

PROCESS:

1. Run normal P1-P22 as instructed by the base Upkeeper prompt.
2. If P23 applies, inspect the selected file plus only directly paired
   schemas/docs/tests/callers needed to judge contracts.
3. Propose P23 findings before applying changes.
4. Apply only high-confidence, localized fixes.
5. For every applied P23 fix, add or update a focused negative test unless not
   practical; if not practical, explain why.
6. Run at least these verification paths when changes are made:
   - syntax/compile check for edited source
   - normal valid path
   - malformed/negative path
   - relevant focused test file or fixture suite
   - git diff --check
7. Verify persisted file contents and mtime as required by the base prompt.
8. Keep the final response concise but explicit about which P23 categories found
   issues.

OUTPUT:

Include a P23 section in the final report with:

- P23 applicability: applicable or not applicable, with reason
- Input boundaries inspected: concise list
- Contract defects found: concise findings, or none
- Fixes applied: concise list, or none
- Negative tests added/updated: list, or reason omitted
- Schema/code/doc alignment: aligned, updated, or deferred
- Residual risks: concise, especially if adjacent context was too broad to
  inspect

RULES:

- No busy work.
- No cosmetic-only changes.
- Do not broaden the task beyond the selected file and directly paired contract
  context.
- Do not turn P23 into a general refactor.
- Do not silently tighten public behavior without tests and a clear rationale.
- Do not add fake dry-run/check behavior that still mutates state.
- Do not add negative tests that only assert implementation details.
- If the contract is ambiguous, document the ambiguity and stop short of
  guessing unless surrounding evidence is strong.
- If malformed input can create plausible but wrong output, treat that as high
  value.
- If a valid input path is already well covered but malformed inputs are not,
  that is a real P23 test gap.

________________________________________

Summary Table

ID      Name    Scope   Cadence

P1      Broad code review       Per file        Random pool
P2      Branch and PR housekeeping      Repo    Weekly or less
P3      Single-script deep dive Per file        Random pool
P4      Security and secrets scan       Per file        Random pool
P5      Dead code elimination   Per file        Random pool
P6      Error handling audit    Per file        Random pool
P7      Configuration and magic values  Per file        Random pool
P8      Test gap analysis       Per file        Random pool*
P9      Observability and logging       Per file        Random pool
P10     Idempotency review      Per file        Random pool
P11     Signal handling and cleanup     Per file        Random pool
P12     DRY violations / copy-paste     Per file        Random pool
P13     External call resilience        Per file        Random pool
P14     Naming consistency      Per file        Random pool
P15     Assumption documentation        Per file        Random pool
P16     Dependency audit        Manifest        Random poo
P17     Atomicity and partial failure   Per file        Random pool
P18     Concurrency and race conditions Per file        Random pool
P19     Exit code and output contract   Per file        Random pool
P20     Resource exhaustion and bounds  Per file        Random pool
P21     Documentation drift     Per file        Random pool
P22     Service and docs        Per file        Random pool
P23     Data contract and negative fixtures     Per file*       Random pool

*P8: drop from random pool if the project has no test suite. P23 applies only to selected files that touch data or operator-input boundaries. P2 and P16: run on their own slower schedule, not in the per-file rotation.
