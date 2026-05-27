# Upkeeper

Upkeeper is a public, local control plane for running bounded Codex maintenance
cycles against real repositories.

It keeps repository care work moving without turning every loop into an
ad-hoc shell ritual. Each invocation selects one reviewable target, launches one
guarded backend task, preserves the evidence, and stops before quota or local
environment failures turn maintenance into guesswork.

Professionals can adapt it to steady project maintenance. Hobbyists can use it
to spend spare cycles on backlog, hardening, and bugs they did not know were
there yet.

The current checked-in state is always treated as the product. Help text,
release notes, prompts, comments, logs, and docs are expected to explain the
tool from tracked source, not from private chat history. P26 exists to enforce
that standard.

The tracked authority surface is split across `docs/authority.md`,
`docs/capability-profiles.md`, `docs/control-ledger.md`, and
`docs/policy-decisions.md`, with the schema-gated typed-signal boundary
decision in `docs/decisions/0003-schema-gated-airlocks.md`. Those files define
who may select targets, write source, run shell, spend quota, touch evidence,
affect GitHub, modify Lattice, record local policy decisions as structured data,
and turn raw evidence into validated records before it can drive wrapper
authority.

The security contract in `docs/security.md` defines the explicit threat model,
degraded-mode doctrine, and override doctrine for malicious or confused model
output, wrapper bugs, config mistakes, filesystem weirdness, same-user access,
secret leakage, public-doc exposure, quota/fallback behavior, backups,
validators, Lattice, dirty baselines, and unsafe targets.
In short, `docs/security.md` is the threat model, degraded-mode doctrine, and override doctrine for wrapper safety decisions.

The evidence preservation contract is tracked in
`docs/preservation-policy.md`. It defines evidence temperature, artifact privacy
classes, and promotion rules for logs, transcripts, backups, Lattice rows,
exports, recovery records, obligations, postmortems, and public evidence.
The run bill-of-materials and stable local identifier namespace in
`docs/run-bom-identifiers.md` defines `upk:` references for cycles, runs,
targets, prompts, backups, artifacts, validation, and config records so future
tools can link evidence without scraping raw logs or exposing local paths.
The source-rights contract in `docs/source-rights-metadata.md` defines the
sensitivity labels and rights fields that decide whether OSINT and citation
sources may enter prompts, exports, archives, or public evidence packets.

The compatibility surface is tracked in `docs/compatibility.md`. Public
schemas, prompt markers, docs/help examples, and Lattice JSONL output are
classified as `stable`, `experimental`, `deprecated`, or `removed`; unclassified
tracked public behavior defaults to stable.

> "Starfleet code requires a second backup?"
>
> "In case the first backup fails."
>
> "What are the chances that both a primary system and its backup would fail at
> the same time?"
>
> "It's very unlikely, but in a crunch I wouldn't like to be caught without a
> second backup."
>
> -- Gilora and O'Brien, "Destiny"

## The Short Version

Upkeeper is a launch script and local control plane that runs a carefully gated,
local-first sequence before any outside LLM backend is invoked. It checks the
repo, prior automation failures, quota state, selected target, backup state,
issue evidence, logs, and local ledgers first. Only then does it release a
backend LLM into a narrow task airlock.

The wrapper owns the operator tools and side effects. It talks to Git, GitHub,
quota/session files, backups, logs, Lattice, and the backend LLM. The backend
LLM receives the wrapper-built task packet, selected target context, and the
configured sandbox. In issue workflows, the LLM does not talk to GitHub with its
own credentials or tools; Upkeeper fetches issue evidence before launch and
posts comments or other GitHub side effects after validation.

Local policy decisions that should survive prompt wording changes have a
tracked schema in `docs/policy-decisions.md` and helper functions in
`lib/upkeeper/policy_decisions.bash`. The initial schema records whether a
cycle may contact backend Codex, write source, retarget, restore backup, use
network tools, file issues, and which action ids were denied.

Schema-gated typed-signal boundaries are the companion rule for producer input:
untrusted or semi-trusted text can be retained as evidence, but side effects and
wrapper authority should consume validated normalized records. The design
contract is tracked in `docs/decisions/0003-schema-gated-airlocks.md`.

In Upkeeper terms, the airlock is the middleware boundary between the local
control plane and the backend LLM: only selected context, allowed commands,
sandbox rules, evidence paths, and the validated return channel belong there.
The local operator-controlled side is the Good Place. The external backend,
provider, internet, and model side is the Neutral Place. The boundary is about
authority, evidence, and trust, not moral labels.

You can use the whole loop or only part of it: find bugs, file bugs, triage the
queue, leave a proposed fix, review that proposal, apply the fix, or run until
there is nothing left to improve. The best run is a correct fast no-op.

```text
operator
   |
   v
Upkeeper local gates
   |-- automation health and obligations
   |-- repo selection, backup, quota, logs, Lattice
   |-- GitHub issue fetch/post handled by wrapper
   |
   v
LLM airlock
   |-- bounded task packet
   |-- selected target context
   |-- configured sandbox
   |
   v
validated outcome
   |-- report, issue comment, patch, or clean no-op
   |-- evidence recorded locally
```

## What It Does

`Upkeeper` runs one guarded Codex backend cycle per invocation.

On each cycle it:

- reads recent Codex quota snapshots from `$CODEX_HOME/sessions`
- logs current and projected quota use before spending another run
- maintains a local file manifest and preselects one eligible script/tool target
  before Codex starts, falling back to direct local enumeration when requested or
  when a manifest cannot be used
- records file-affecting activity in Upkeeper Lattice, a default-on local
  SQLite evidence ledger under ignored `runtime/` state
- prepends that target to the default maintenance prompt so Codex does not spend
  model/tool cycles rediscovering `.git/`, ignored files, generated outputs,
  runtime evidence, or test trees by accident
- respects `.upkeeperignore` as a selection/spend firewall for files Git may
  still track but Upkeeper should not spend model cycles reviewing
- applies the P23 data-contract pass to validators, importers, exporters,
  registry loaders, config readers, data readers, and input-boundary CLIs
- can append opt-in P24/P25/P26/P27/P28/P29/P30 review modules for de-LLM-ing
  viability, contract/intent compliance, public documentation clarity,
  after-action reviews, unit-test harvesting, reuse harvesting, and permanent
  hardening
- provides `FlameOn`, a thin one-command launcher for the highest local
  max-cover smoke/burn cycle that defaults to filing/reporting bugs instead of
  patching source while preserving Upkeeper quota guardrails
- provides `ChimneySweep`, a separate issue-fix launcher that scripts GitHub
  issue triage before launch, exits 25 with "high five yay" when the queue is
  clean, and hands one locked issue to Upkeeper for repair
- can select the oldest open GitHub bug by priority label order
  `security > data-integrity > bug` for focused issue-repair cycles
- runs Codex once with the configured model and reasoning effort
- records terminal outcomes in `Upkeeper.log`
- tags log lines with a per-cycle `run_hash` and emits `--MARK--` heartbeat
  evidence for continuity checks
- scans recent prior log entries for incomplete cycles before launching Codex
- keeps a local queue of unaddressed script/tool command failures and prioritizes
  the oldest still-eligible failure target on the next loop
- creates a selected-target pre-contact backup before the prompt grants Codex
  target authority, with optional age public-recipient encryption
- logs a disk-space preflight before spending a backend run
- optionally hands off to a bounded fallback model and postmortem path when the
  primary run blocks, fails, or hits a quota guardrail

The wrapper is intentionally local. It is not a hosted service, CI replacement,
or repository policy engine. It gives an operator a repeatable loop with better
guardrails and better evidence than manually relaunching Codex from memory.

## Trust Contract

The perfect unattended run is the one that correctly ends quickly because there
is nothing left to improve. In a healthy empty state, Upkeeper and its focused
launchers should prove local automation health, unresolved obligations, and the
actionable work queue are clean, print a plain reason, and exit without
launching backend Codex or running broad validation. Treat a clean no-op path
that takes more than about 10 seconds as pressure to simplify the scripted
checks.

The north star is the same discipline as the oxygen-mask rule on a flight:
secure the system that does the helping before it tries to help anything else.
Upkeeper should not work a fresh project bug while its own automation layer is
known to be unhealthy.

Machine health always outranks workload. If an earlier automated cycle left an
unresolved obligation, stale control-plane failure, or broken launcher state,
the next unattended launcher run repairs or preserves that obligation before it
starts fresh GitHub issue work. This is intentional: the automation should not
pretend the bug queue is healthy while the machinery that works it is not.

Operator output should be readable without cross-referencing logs or alternate
mode names. A launcher that pauses new issue work to repair itself should say
that directly, identify the automation failure, and show the mapped repair
target file.

## When To Use It

Upkeeper fits repos that have a steady backlog of low-to-medium-risk care work:

- rotating single-file maintenance reviews
- script and tool hardening
- stale docs and paired operator guide cleanup
- small reliability fixes found while running automation
- long cleanup queues where stopping at the right quota boundary matters
- multi-repo setups where one central wrapper should serve several client repos

It is less useful for one-off feature development, broad refactors, or work that
needs product decisions before code changes.

## Quick Start

From this repository:

```sh
./Upkeeper --help
./Upkeeper --version
UPKEEPER_DRY_RUN=1 ./Upkeeper
```

Run a bounded local loop:

```sh
while ./Upkeeper; do
  sleep 60
done
```

Dry-run is the first check to run in a new repo. It verifies wrapper startup,
quota discovery, operator guide state, and target preselection without launching
a Codex backend task.

For a one-command high-coverage smoke/burn cycle, use the repo-root launcher:

```sh
FLAMEON_DRY_RUN=1 ./FlameOn
./FlameOn --basic
./FlameOn --debug1 -backup_queue
```

`FlameOn` is intentionally thin. It resolves to
`./Upkeeper --model-override=5.5_xhigh --max-cover --bug-report-only`, sets
`CODEX_TERMINAL_VERBOSITY` to `silent`, `basic`, or `debug1`, and keeps the
same startup, fallback, failure-queue, evidence, and local safety checks as
normal Upkeeper runs. The automation launcher path is intentionally full burn:
Lattice is required, encrypted pre-contact backup is required, and Codex is
pinned to `--sandbox workspace-write` before launch. Quota thresholds are set to
spend-to-zero (`CODEX_5H_STOP_PERCENT=0` and `CODEX_WEEK_STOP_PERCENT=0`), and
wrapper quota guardrail stops plus persisted quota cooldown markers are bypassed
for the launcher run. Expired-reset stale quota evidence is still recorded as
non-perfect local health before burn bypass continues. In bug-report-only mode,
Codex must not edit or touch tracked source; it investigates, runs
deterministic checks, and files issues or fully reports confirmed bugs.
`-backup_queue` and `--backup-queue` switch that one cycle to
`runtime/unaddressed-tool-failures-backup`.

For a scripted issue-fix cycle, use `ChimneySweep`:

```sh
CHIMNEYSWEEP_DRY_RUN=1 ./ChimneySweep
./ChimneySweep --basic
./ChimneySweep --model gpt-5.3-codex-spark --reasoning-effort xhigh
```

`ChimneySweep` is intentionally separate from `FlameOn`. It lists open GitHub
issues before any backend Codex process can start. A clean actionable queue
prints `high five yay` and exits 25. Otherwise it keeps security-class issues
ahead of data-integrity issues, keeps working that class until it is clear, and
then ranks the remaining queue by containment title/tag signals, severity, and
least-recently-touched age. The selected issue is passed to Upkeeper as
`--fix-issue=NUMBER`, with `--prompt-pass=all` and all P24-P30 review modules.
By default, `ChimneySweep` runs three separate backend instantiations:
`comment`, `review`, then `apply`. The comment stage leaves an
`Upkeeper ChimneySweep proposal:` comment on the selected issue without
changing tracked source, the review stage independently reviews that proposal
and leaves an `Upkeeper ChimneySweep review:` decision comment, and the apply
stage works the bug. This keeps issue selection scripted while still
exercising the full repair side end to end.

Upkeeper runs those backend instantiations under the Genie Protocol: the wrapper
fetches issue bodies/comments before launch, Codex receives only that issue
packet, and GitHub side effects stay wrapper-owned. The comment and review
stages also force backend Codex into a read-only repo sandbox and require the
proposed issue comment to be emitted in a final-message draft block that the
wrapper extracts after validation. Backend Codex launches do not inherit GitHub
token variables, use an empty per-run `gh` config directory, and have direct
`gh`, `curl`, `wget`, and `hub` commands shadowed by blocker stubs.

Live `FlameOn` and `ChimneySweep` runs require an encrypted pre-contact backup
configuration. Set `UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT` and install
`age`; dry-run remains available without those prerequisites.

Both launchers accept `--model-override=5.5_xhigh` and
`--model-override=5.3-codex-spark_xhigh`. They also accept the explicit
shortcut form `--model gpt-5.3-codex-spark --reasoning-effort xhigh` and pass
the equivalent Upkeeper model override to every staged backend invocation.

One-time local setup:

```sh
sudo apt-get update
sudo apt-get install -y age

mkdir -p "$HOME/.config/age"
chmod 700 "$HOME/.config/age"
age-keygen -o "$HOME/.config/age/upkeeper.txt"
chmod 600 "$HOME/.config/age/upkeeper.txt"
export UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT="$(age-keygen -y "$HOME/.config/age/upkeeper.txt")"
```

The exported age recipient is public. Keep the private identity file out of
prompts, logs, committed config, and backend-visible environments; it is needed
only for manual restore.

Bash completion for `Upkeeper`, `FlameOn`, and `ChimneySweep` is available as
an opt-in shell helper:

```sh
source completions/upkeeper.bash
```

Validate the central checkout before release or after touching module order,
prompt packaging, or symlink behavior:

```sh
tools/validate_upkeeper.sh --deps
tools/validate_upkeeper.sh --source-contracts
tools/docs_only_fast_path.sh --validate
tools/validate_upkeeper.sh --smoke
tools/validate_upkeeper.sh --quick
tools/validate_upkeeper.sh --quick --profile
tools/validate_upkeeper.sh --full
```

Source-contract validation is the narrowest source-only gate used by the
backlog launcher before per-bug commits. It catches cheap structural source
contract failures, such as oversized `log_line` call sites, without running the
broader quick suite.
For committed or local README/docs/prompt-only edits,
`tools/docs_only_fast_path.sh --validate` classifies the changed paths locally,
rejects mixed source changes, and runs the no-network docs fast path without
backend Codex, GitHub CLI, or PR polling.
Smoke validation is the fast local edit-loop path: syntax, version/module-map
contracts, prompt packaging, help/docs/diff checks, parser helpers, and launcher
argument contracts. Quick validation adds bounded static/fixture checks and
stays out of wrapper dry-run integration paths such as manifest selection,
Lattice selection, and config-file startup. Add `--profile` to any
non-dependency validation mode to print per-check timings and find the next
local bottleneck without changing coverage.
The full validation mode remains the broad deterministic local integration gate
without real backend Codex work. It runs bounded Upkeeper dry-run startup
checks under validator-owned quota/cooldown bypasses, then uses a local fake
`codex` binary to exercise launch/capture failure classification without
spending quota. Quota-specific contract tests still exercise guardrail behavior
with their own explicit fixtures.

GitHub Actions runs the no-quota CI path in
[`.github/workflows/ci.yml`](.github/workflows/ci.yml) on pull requests and on
pushes to `main`. The workflow installs required tools including `jq` and
`age`, classifies the change scope, and then takes one of two paths:

- docs-only changes: `tools/check_public_docs.sh --quick` plus
  `tools/validate_upkeeper.sh --smoke`, via
  `tools/docs_only_fast_path.sh --validate`
- broader changes: shell syntax checks, unit tests invoked with Bash from
  `tests/*.bash`, `tools/check_public_docs.sh --quick`, and
  `tools/validate_upkeeper.sh --full`

It does not launch real Codex backend work and does not upload runtime
artifacts by default.

Runtime/tool dependencies are tracked in [`docs/dependencies.md`](docs/dependencies.md).
GitHub's dependency graph should stay enabled, but it is expected to show no
package dependencies until the repo adds a real supported manifest, workflow, or
dependency submission.
`jq` is intentionally still a required runtime dependency for the current Bash
JSON bridge surface; install commands and the future removal condition are
tracked in the dependency document.

The backward-compatibility contract is tracked in
[`docs/compatibility.md`](docs/compatibility.md). Existing operator-visible
behavior should be preserved unless compatibility would be unsafe or impossible.

Upkeeper Lattice is documented in [`docs/lattice.md`](docs/lattice.md). It is a
local SQLite evidence ledger, selection-intelligence layer, and recovery/export
surface. It is on by default, writes to
`runtime/upkeeper-lattice/lattice.sqlite3`, uses Python's stdlib `sqlite3`, and
does not add a daemon, ORM, package manifest, network sync, or GitHub token
storage.

The local security and trust model is tracked in
[`docs/security.md`](docs/security.md). Read it before using unreviewed config
files, broad Codex sandbox modes, shared machines, or repositories that may
contain secrets.

Local multi-repo stress testing is implemented by
[`tools/stress_upkeeper_corpus.sh`](tools/stress_upkeeper_corpus.sh):

```sh
tools/stress_upkeeper_corpus.sh --local
```

The harness generates tiny temp repositories across Bash, Python,
Node/TypeScript, docs-only, generated-heavy, symlinked-client, dirty-worktree,
and historical-log shapes. It runs only dry-runs and local fixtures, so it does
not spend Codex quota. The broader contract is tracked in
[`docs/stress-corpus.md`](docs/stress-corpus.md).

## Configuration

The default active config file is [Upkeeper.conf](Upkeeper.conf). Upkeeper
sources it before applying built-in defaults and before parsing CLI flags. The
file is intentionally one shell-compatible top-level config, not a directory of
chained includes.

Config files are trusted executable shell code, not inert data. Upkeeper sources
them with Bash, so do not load profiles from untrusted repositories, downloaded
snippets, or any path you would not be willing to run as a shell script.

The tracked [configurations/default.conf](configurations/default.conf) is a
basic profile template for scheduled runs or future named profiles. For now,
keep profiles self-contained and select one per invocation:

```sh
./Upkeeper --config-file=configurations/default.conf
./Upkeeper --config-file=/work/upkeeper-profiles/documentation-saturday.conf
./Upkeeper --no-config
```

The repository intentionally does not commit a project `.codex/config.toml`.
Upkeeper's wrapper-owned profile surface is the source of truth for unattended
Codex launch policy; see [docs/security.md](docs/security.md) and
[docs/dependencies.md](docs/dependencies.md) for the rationale and future
compatibility rule.

Config files can set normal `CODEX_*` knobs and `UPKEEPER_*` defaults for
flag-like behavior:

```sh
CODEX_MODEL="gpt-5.5"
CODEX_REASONING_EFFORT="xhigh"
UPKEEPER_TARGET_FILE="docs/scripts/upkeeper.md"
UPKEEPER_REVIEW_MODULES="p26,p28"
UPKEEPER_PROMPT_PASS="all"
UPKEEPER_MAX_COVER="0"
UPKEEPER_BUG_REPORT_ONLY="0"
UPKEEPER_FIX_NEXT_ISSUE="0"
```

Selection is also configurable. The default is a local manifest-backed oldest
eligible file rotation; scheduled profiles can narrow that rotation without
adding another wrapper script:

```sh
UPKEEPER_SELECTION_SOURCE="manifest"
UPKEEPER_SELECTION_ORDER="oldest"
UPKEEPER_TARGET_ROOT="docs"
UPKEEPER_TARGET_MAX_DEPTH="3"
UPKEEPER_INCLUDE_GLOBS="*.md,*.txt"
UPKEEPER_EXCLUDE_GLOBS="vendor/**,runtime/**"
UPKEEPER_IGNORE_FILE="$ROOT_DIR/.upkeeperignore"
UPKEEPER_SELECTION_REVIEW_MODULES="p26"
```

`.upkeeperignore` is separate from `.gitignore`: Git ignore rules decide what
belongs in source control, while `.upkeeperignore` decides what Upkeeper may
select for model upkeep. Patterns use simple Gitignore-style glob lines and
block manifest entries, normal rotation, Lattice/max-cover candidates,
failure-queue eligibility, and explicit `--target-file` pins. It is a
spend/selection control, not a sandbox or secret-protection boundary.

Lattice is also configurable from the same shell-compatible profile. The
defaults keep it on, local, ignored, and compatible with the current selector:

```sh
UPKEEPER_LATTICE_ENABLED="1"
UPKEEPER_LATTICE_REQUIRED="0"
UPKEEPER_LATTICE_DB="$ROOT_DIR/runtime/upkeeper-lattice/lattice.sqlite3"
UPKEEPER_LATTICE_SELECTION_MODE="oldest-mtime"
UPKEEPER_LATTICE_RAW_STORAGE="limited"
UPKEEPER_LATTICE_SQLITE_JOURNAL_MODE="delete"
```

If the local DB is unavailable and `UPKEEPER_LATTICE_REQUIRED=0`, Upkeeper logs
one warning, spools a small recovery record when possible, and continues the
existing cycle behavior. That warning is owned instead of anonymous: it includes
the failure reason, `owner_issue=430`, the `advisory_lattice_degraded` contract,
and the fallback evidence class. Set `UPKEEPER_LATTICE_REQUIRED=1` only when a
run must fail before Codex launch unless Lattice is writable and healthy.

Selected-target pre-contact backups are enabled and required by default. The
default vault is outside the repository, and Upkeeper logs only an opaque
target HMAC, mode, encrypted flag, protection flag, and `path_redacted=1`.
Plain mode is a recovery aid, not a same-user security boundary; use age mode
when the backup content should be encrypted before storage:

```sh
UPKEEPER_PRECONTACT_BACKUP_MODE="auto"
UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT="age1..."
UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED="1"
UPKEEPER_PRECONTACT_BACKUP_KEEP_PER_FILE="20"
```

Restore a plain backup by id with:

```sh
tools/upkeeper_precontact_restore.sh --repo-root=. --backup-id=BACKUP_ID
```

CLI flags are the final one-cycle overrides. That means a cron profile can set
the normal model, target, and review modules, while an operator can still run:

```sh
./Upkeeper --config-file=configurations/default.conf --target-file=Upkeeper --p25
./Upkeeper --target-root=docs --target-depth=3 --selection-order=newest --refresh-manifest
./Upkeeper --max-cover
```

## Client Repo Setup

The most useful pattern is to keep this repository as the central source and
symlink the wrapper into each repo that should receive the same behavior.
The symlink should point at the root `Upkeeper` entrypoint; that launcher loads
its paired implementation modules from `lib/upkeeper` in the resolved central
checkout.
The module contract and load-order map are documented in
`lib/upkeeper/README.md`; the executable load order lives in root `Upkeeper`.
It also loads the default review prompt from the central checkout's
`prompts/default-review.md` and central review modules from `prompts/`;
client-local prompt files are only needed when you pass an explicit
`--prompt-file`.

Sanitized example:

```sh
/work/tools/Upkeeper/tools/install_client_link.sh --repo=/work/repos/example-index
cd /work/repos/example-index
./Upkeeper.sh --version
/work/tools/Upkeeper/tools/doctor_upkeeper.sh --repo=.
```

With a symlink, fixes made in the central Upkeeper repo are picked up by every
client the next time its local `./Upkeeper.sh` runs. If a repo has an old copied
wrapper instead of a symlink, it will drift: missing flags, stale prompt rules,
old guardrail behavior, or missing `lib/upkeeper` modules are all signs that
the client wrapper should be refreshed or replaced with a link. Copying only the
root launcher without the paired module tree is unsupported.
Use `tools/update_client_link.sh --repo=CLIENT --force` to repoint a stale
client symlink, and `tools/uninstall_client_link.sh --repo=CLIENT` to remove a
central Upkeeper link. Install and update refuse existing client paths unless
`--force` is supplied; replacing a tracked client path also requires
`--replace-tracked`.

The install and update helpers write local ignore entries to the client repo's
`.git/info/exclude` instead of editing tracked client files. The effective
client local artifacts are:

```gitignore
Upkeeper.sh
Upkeeper.log
runtime/
docs/scripts/upkeeper.md
```

Upkeeper can bootstrap a repo-local guide at `docs/scripts/upkeeper.md` when it
is missing and tracked by the client. Existing guides are not overwritten. If
the client ignores that guide path, it is treated as optional local operator
state: missing ignored guides are not created, and stale or missing guide
versions are logged as informational local-note events.

Sanitized multi-repo pattern:

```sh
# Patch wrapper behavior once in the central checkout.
cd /work/tools/Upkeeper
git pull --ff-only

# Client A picks up that central behavior through its symlink.
cd /work/repos/example-index
./Upkeeper.sh --version
UPKEEPER_DRY_RUN=1 ./Upkeeper.sh

# Client B does the same, with its own local log and target repo cwd.
cd /work/repos/example-protocol
CODEX_MODEL=gpt-5.3-codex-spark CODEX_REASONING_EFFORT=xhigh ./Upkeeper.sh
```

## Operator Examples

Environment overrides go before the command they configure, or they are exported
once before a loop. CLI flags such as `--prompt` and `--prompt-file` still go
after `./Upkeeper.sh`.

Run a Spark Codex maintenance burn-down and allow the current 5-hour Spark
bucket to drain to zero before stopping:

```sh
while CODEX_MODEL=gpt-5.3-codex-spark \
  CODEX_REASONING_EFFORT=xhigh \
  CODEX_SPARK_5H_STOP_PERCENT=0 \
  ./Upkeeper.sh; do
  sleep 60
done
```

The tracked launcher examples package common loop shapes as explicit scripts:

```sh
UPKEEPER_LOOP_DRY_RUN=1 launcher_examples/spark_5.3_burn_out_xhigh.sh
launcher_examples/spark_5.3_burn_out_xhigh.sh
FLAMEON_DRY_RUN=1 ./FlameOn --debug1
```

Tracked testruns under `testruns/` are plain shell launchers for common local
cycles:

```sh
testruns/all_p_modules_600s.sh
testruns/all_p_modules_once.sh --target-root=lib/upkeeper
testruns/manifest_refresh_dry_run.sh
testruns/enumerate_random_dry_run.sh
```

Run the same style of loop with a stronger model and an explicit 5-hour stop:

```sh
while CODEX_MODEL=gpt-5.5 \
  CODEX_REASONING_EFFORT=xhigh \
  CODEX_5H_STOP_PERCENT=5 \
  ./Upkeeper.sh; do
  sleep 60
done
```

Append one-time guidance without changing the default prompt:

```sh
./Upkeeper.sh --prompt "Focus on failing validator tests. Keep fixes scoped and verify before final status."
```

Use a tracked prompt file from the central checkout for a focused cleanup lane:

```sh
./Upkeeper --prompt-file prompts/git_hard_clean.md

# From a symlinked client repo, use the central prompt file's absolute path.
./Upkeeper.sh --prompt-file /work/tools/Upkeeper/prompts/git_hard_clean.md
```

Inspect what happened after a run:

```sh
tail -n 80 Upkeeper.log
rg 'cycle.summary|cycle.exit|review.preselect|operator_guide|UPKEEPER_STATUS' Upkeeper.log
```

A normal successful maintenance cycle ends with `cycle.exit reason=WORK_DONE`.
Quota stops, local environment failures, dirty-worktree blockers, interrupted
runs, and fallback/postmortem paths are logged with distinct reasons so the next
operator can resume from evidence instead of guessing.

## Prompt Behavior

The default prompt is a rotating single-file maintenance review. By default,
Upkeeper keeps a local runtime manifest at
`runtime/upkeeper-file-manifest.json`, refreshes it when it is missing, stale,
invalid, or out of sync with local file metadata, and reviews the oldest
eligible non-test script/tool file by modification time.

Use `--selection-source=enumerate` when a run should bypass the manifest and
scan the local tree directly. Use `--refresh-manifest` when a run should rebuild
the manifest immediately and then select from it.

When the repo-local `Upkeeper` implementation itself is eligible and has not
been touched for at least seven days, the wrapper selects it first. Otherwise it
falls back to the normal oldest eligible script/tool rotation.

The wrapper does selection before Codex starts and prepends a
`WRAPPER_PRESELECTED_REVIEW_TARGET` block to the prompt. That block is meant to
prevent expensive or unsafe rediscovery patterns such as:

- `find .` inventories that expose `.git/objects`
- `sort | head` pipelines that produce broken-pipe noise
- nested `xargs ... sh -c ... awk ...` selectors that are fragile under quoting

If the preselected file cannot be reviewed because it is gone, unreadable,
binary, generated, or explicitly excluded, Codex must state that exception and
report `BLOCKED` for the cycle. Replacement target selection is wrapper-only
because pre-contact backup coverage is target-specific.

Operators can narrow normal rotation with `--target-root=PATH`,
`--target-depth=N`, `--include-glob=PATTERN`, `--exclude-glob=PATTERN`, and
`--selection-review-modules=p24,p25,p26,p27,p28,p29,p30`. `--selection-order=random`
or `--random-target` chooses a random eligible target within the filtered set.
These filters shape target selection only; review-module prompts still require
`--review-module`, `--review-modules`, or the `--p24` through `--p30` shorthands.
`--target-file=PATH` remains the strongest one-cycle pin and takes precedence
over the failure queue and selection filters. Automatic rotation stays focused
on script/tool candidates, but an explicit operator pin may target any
source-safe readable text file inside the repo, including docs, prompts, config,
tests, and scripts. Explicit pins still reject `.git`, ignored paths, runtime
evidence, generated outputs, directories, symlinks, unreadable files, and
binary-looking files.

If a prior run saw an interesting script/tool command fail, Upkeeper writes a
local marker under `runtime/unaddressed-tool-failures/open/`. After explicit
operator pins and startup anomaly gates, the next loop selects the oldest
still-eligible marked target before stale-self review or normal timestamp
rotation, without spending another model call to rediscover it. A successful
`WORK_DONE` pass moves that marker to `runtime/unaddressed-tool-failures/resolved/`.
If a run sees a new local command failure, the marker stays open unless a later
successful command of the same broad kind shows the failure was rechecked.
Use `--target-file=PATH` or `--ignore-failure-queue` when a human intentionally
wants a different target for one cycle.

Use `--max-cover` when the run should maximize review/pass coverage rather than
stay on normal script/tool rotation. It enables `--prompt-pass=all`, appends
P24 through P30, and asks Lattice for max-cover ranking across current tracked
source-safe text files. The ranking prefers the oldest file with any unrun pass,
then files with the lowest per-pass coverage count, then oldest mtime. Explicit
targets, startup anomaly gates, and open failure-queue markers still keep their
normal priority.

Use `--bug-report-only` when a cycle should investigate and file/report bugs
without fixing them. It is also accepted as `--file-bug-only` or
`--report-bug-only`. This mode explicitly overrides the normal clean-review
touch requirement; if Codex changes tracked source anyway, the wrapper compares
the source mutation fingerprint from before and after the run and fails the
cycle as a source mutation guard violation. ChimneySweep's comment and review
issue-workflow stages use the same tracked-source mutation guard and are
launched with a read-only backend sandbox. Their issue-comment text is carried
back in a final-message draft block and posted by the wrapper only after the
guard passes.

Use `--fix-next-issue` when Upkeeper itself should pick a GitHub issue to fix
before launching Codex. It selects the oldest open issue in priority order:
`security`, then `data-integrity`, then `bug`, skipping issues with labels such
as `in-progress`, `blocked`, `duplicate`, `wontfix`, `invalid`, `needs-info`,
`done`, `merged`, or `has-pr`. It infers a starting `--target-file` from the
issue title/body when a repo-local path is present, then injects the issue body
as evidence for a focused repair task. The alias `--fix-oldest-bug` is accepted
for the same mode. Use `--fix-issue=NUMBER` when a deterministic caller such as
`ChimneySweep` has already selected the issue and Upkeeper should only lock and
repair that one issue. `--issue-workflow-stage=comment|review|apply` is the
stage contract used by `ChimneySweep`; comment and review stages are
source-read-only and apply is allowed to patch. GitHub I/O remains
wrapper-brokered for every stage: the backend reads wrapper-fetched evidence and
writes local artifacts, while the wrapper posts comments or other issue updates
after validation.

Backlog batch merges treat failed local validation as mandatory machine-health
work. When a batch validation phase fails, `orchestration/backlog.sh` writes or
updates a local automation obligation with the phase, command, exit code,
bounded output tail, stable fingerprint, likely owner path, and required proof
command. The next backlog invocation selects that obligation before retrying the
merge or starting fresh GitHub issue work.

Backlog PR check and merge gates also protect against stale remote evidence. If
the active backlog branch is clean and locally ahead of `origin/<branch>`, the
launcher pushes those commits before waiting on PR checks or merging. Dirty,
missing-remote, or diverged local-ahead branch states stop with a clear reason
instead of treating older remote checks as current.

For an explicit one-cycle Upkeeper self-review with all built-in P1-P23 passes,
use equals-form operator flags:

```sh
./Upkeeper --model-override=5.5_xhigh --target-file=Upkeeper --prompt-pass=all
```

P23 is now part of the live default prompt. It applies only to selected files
that touch data or operator-input boundaries, and it asks Codex to inventory
boundaries, reject malformed/non-contract input, improve diagnostics safely, and
add focused negative fixtures for any data-contract fix. The same pass is also
available as a standalone prompt file:

```sh
./Upkeeper --prompt-file prompts/p23-data-contract-negative-fixture-audit.md

# From a symlinked client repo, use the central prompt file's absolute path.
./Upkeeper.sh --prompt-file /work/tools/Upkeeper/prompts/p23-data-contract-negative-fixture-audit.md
```

P24 through P30 are opt-in review modules. They are loaded from the central
Upkeeper checkout, so symlinked clients can use the same flags without knowing
absolute prompt-file paths.

P24 applies only when the selected file invokes, supervises, prompts, parses,
classifies, summarizes, recovers from, or otherwise depends on LLM/Codex
behavior. It asks whether any stable, fixture-testable model-adjacent behavior
can move into deterministic local code with no operator-facing loss and without
heavy new infrastructure.

P25 applies when the selected file touches operator-visible behavior, wrapper
contracts, module ownership, dependency assumptions, validation, docs, prompts,
logs, markers, exit codes, symlink behavior, or central/client boundaries. It
checks whether the file remains aligned with Upkeeper's documented contracts and
design intent.

P26 applies when the selected file touches documentation, comments, prompts,
help output, release notes, validation messages, logs, errors, examples,
operator guides, module docs, or public policy. It treats every patch and
release as public material and checks whether a future reader can understand the
important intent from the repository itself.

P27 applies when a run should leave a concise after-action review after
meaningful work. It captures the outcome, what went right, what went wrong,
what was wasteful, what can improve next time, and whether the system learned
anything reusable.

P28 applies when a bug, reusable exploratory command, parser edge case,
validation path, or deterministic LLM-discovered fact can become a cheap local
test or fixture. It favors existing validation scripts and local fixtures over
framework or service overhead.

P29 applies when project knowledge should become a reusable helper, fixture,
prompt section, documentation reference, command idiom, validation pattern,
template, or local asset instead of being rediscovered or rewritten in later
cycles. It requires a stable contract, a clear owner, local verification, and a
smaller or safer future maintenance path.

P30 is the Stark Protocol pass for permanent hardening. It applies when a
failure, near miss, or fragile recovery path should leave a guard, deterministic
validation, documented invariant, automation obligation, or explicit blocked
follow-up so the same weakness cannot silently recur.

Fault-injection review is reserved for future P31 work, or for a later named
module with a non-breaking alias plan. P29 remains the public reuse-harvesting
contract and P30 remains Stark Protocol hardening; existing P29 aliases are not
renamed or repurposed. The tracked
[`prompts/p31-fault-injection-review.md`](prompts/p31-fault-injection-review.md)
file defines the future P31 contract before CLI wiring exists, and
[`docs/fault-injection-scenarios.md`](docs/fault-injection-scenarios.md)
tracks candidate scenarios with stable ids and priority fields.

```sh
./Upkeeper --review-module=p24
./Upkeeper --review-module=p25
./Upkeeper --review-module=p26
./Upkeeper --review-module=p27
./Upkeeper --review-module=p28
./Upkeeper --review-module=p29
./Upkeeper --review-module=p30
./Upkeeper --review-modules=p24,p25,p26,p27,p28,p29,p30

# Shorthand aliases are also available.
./Upkeeper --p24 --p25 --p26 --p27 --p28 --p29 --p30
```

Before the primary Codex response emits its final marker, the prompt now requires
a current-cycle `Upkeeper.log` review and a machine-readable acknowledgment:
`UPKEEPER_LOG_REVIEW: CHECKED cycle=<cycle_id> anomalies=none|listed`. If that
review exposes a concrete central wrapper or prompt defect while running in this
repo, Codex may apply the smallest safe self-repair immediately and report it as
a log self-repair.

The prompt also asks for additive `UPKEEPER_PASS_RESULT` lines for each P* pass
that was actually applied or explicitly found not applicable. For
`--prompt-pass=all`, missing or incomplete pass-result coverage now blocks the
cycle after the final response is parsed. Outside all-pass runs, missing lines
remain additive-only. Malformed lines are preserved as rejected Lattice
evidence instead of being treated as clean pass results.

At script startup, Upkeeper also scans the recent live log for prior cycles that
started without a terminal `cycle.exit` or `run.finish`, writes
`previous_run.anomaly` evidence, and injects that evidence into the prompt for
the next healthy run. Disk preflight warnings and `--MARK--` heartbeat continuity
are included in the same final log-review obligation.

Startup anomalies are a gate. While prior-run, watchdog-style, unresolved
log-review, or low-disk evidence is active, Upkeeper forces the next cycle back
onto the central `Upkeeper` suite and blocks normal timestamp rotation until that
suite has been checked or remediated. The gate also writes ignored runtime state
under `runtime/startup-anomaly-gates/` so a truncated or rotated live log is not
the only durable signal.

The gated self-repair surface is intentionally narrow: the root `Upkeeper`
entrypoint, `lib/upkeeper` modules, central operator docs and release notes,
prompts/templates, launcher examples, and the validation harness.

Each invocation also acquires a repo-level active lock at
`runtime/upkeeper-active.lock` before local guide bootstrap, anomaly scanning, or
Codex launch. If a matching live PID/start fingerprint still owns that lock, the
new invocation exits instead of running a second maintenance lane in the same
checkout.

Symlinked clients also share a wrapper-code health state under
`$CODEX_HOME/upkeeper/active-wrapper-runs/`, keyed by the resolved central
`Upkeeper` path and its blob hash. If a prior same-code run is stale, wedged, or
ambiguous, later client starts fail closed before normal target selection instead
of propagating potentially bad wrapper behavior into unrelated repos.

## Evidence And Cleanup

Local runtime evidence is deliberately ignored by git:

- `Upkeeper.log`
- `runtime/`
- `runtime/upkeeper-file-manifest.json`
- `runtime/startup-anomaly-gates/`
- `runtime/unaddressed-tool-failures/`
- `runtime/unaddressed-tool-failures-backup/`
- repo-local copied or linked wrappers such as `Upkeeper.sh`, when the client
  repo chooses to ignore them

Promote durable lessons into tracked docs or wrapper behavior. Leave raw logs,
transcripts, temporary outputs, and postmortem evidence local unless a repo has a
specific policy for publishing them.

Tracked source paths matched by `.upkeeperignore` are not runtime evidence and
may remain in Git; they are simply blocked from Upkeeper target selection so a
test loop does not spend cycles on known low-value or generated material.

## Repository Layout

```text
.
|-- .github/
|   `-- workflows/
|       `-- ci.yml
|-- configurations/
|   `-- default.conf
|-- completions/
|   `-- upkeeper.bash
|-- docs/
|   |-- compatibility.md
|   |-- decisions/
|   |   |-- README.md
|   |   `-- 0001-upkeeper-baseline-contracts.md
|   |-- dependencies.md
|   |-- fault-injection-scenarios.md
|   |-- known-issues.md
|   |-- ownership.md
|   |-- prd.md
|   |-- public-documentation-policy.md
|   |-- release-checklist.md
|   |-- risk-register.md
|   |-- roadmap.md
|   |-- security.md
|   |-- stress-corpus.md
|   `-- scripts/
|       `-- upkeeper.md
|-- launcher_examples/
|   |-- README.md
|   `-- spark_5.3_burn_out_xhigh.sh
|-- lib/
|   `-- upkeeper/
|       |-- README.md
|       `-- *.bash
|-- prompts/
|   |-- README.md
|   |-- caretaking_23_items.md
|   |-- default-review.md
|   |-- git_hard_clean.md
|   |-- p23-data-contract-negative-fixture-audit.md
|   |-- p24-de-llm-ing-viability-review.md
|   |-- p25-contract-intent-compliance-review.md
|   |-- p26-public-documentation-review.md
|   |-- p27-educational-debrief-review.md
|   |-- p28-unit-test-harvesting-review.md
|   |-- p29-reuse-harvesting-review.md
|   `-- p30-stark-protocol-review.md
|-- templates/
|   |-- README.md
|   `-- prompt-template.md
|-- testruns/
|   `-- *.sh
|-- tools/
|   |-- check_public_docs.sh
|   |-- docs_only_fast_path.sh
|   |-- doctor_upkeeper.sh
|   |-- install_client_link.sh
|   |-- stress_upkeeper_corpus.sh
|   |-- uninstall_client_link.sh
|   |-- update_client_link.sh
|   `-- validate_upkeeper.sh
|-- Upkeeper
|-- Upkeeper.conf
|-- FlameOn
|-- ChimneySweep
|-- LICENSE
|-- PLANS.md
|-- .editorconfig
|-- .gitignore
|-- change_notes_2026.md
`-- README.md
```

## Related Docs

- [docs/scripts/upkeeper.md](docs/scripts/upkeeper.md): detailed operator guide
  and environment knobs
- [docs/compatibility.md](docs/compatibility.md): binding backward-compatible
  operator-visible feature surface
- [docs/dependencies.md](docs/dependencies.md): runtime/tool dependency surface
  and GitHub dependency-graph expectations
- [docs/prd.md](docs/prd.md): product requirements, user model, required
  capabilities, and non-goals
- [docs/roadmap.md](docs/roadmap.md): tracked near/next/later direction without
  relying on chat history
- [docs/release-checklist.md](docs/release-checklist.md): release-readiness
  validation, docs, merge, and cleanup checklist
- [docs/known-issues.md](docs/known-issues.md): tracked release-relevant risks
  and operational caveats
- [docs/ownership.md](docs/ownership.md): responsibility areas for product,
  shell, prompts, docs, validation, security, compatibility, and releases
- [docs/decisions/README.md](docs/decisions/README.md): durable architecture
  and product decision log
- [docs/risk-register.md](docs/risk-register.md): high-impact risk register
  with current mitigations
- [docs/public-documentation-policy.md](docs/public-documentation-policy.md):
  public-by-default documentation, comment, release-note, and help-text policy
- [docs/security.md](docs/security.md): local trust boundaries, safety model,
  secret handling, and what not to commit
- [docs/source-rights-metadata.md](docs/source-rights-metadata.md): source
  sensitivity, rights, and reuse metadata for OSINT and citation artifacts
- [docs/negative-space-testing.md](docs/negative-space-testing.md):
  deterministic "must not happen" validation contracts for safety boundaries
- [docs/kirk-invariants.md](docs/kirk-invariants.md): Kirk Protocol `KP-###`
  invariant registry for control-plane audit findings, remediation policy, and
  before/after snapshot boundaries
- [docs/stress-corpus.md](docs/stress-corpus.md): local sample-repo
  stress-corpus contract and current coverage
- [.github/workflows/ci.yml](.github/workflows/ci.yml): GitHub Actions
  no-quota PR/push validation path
- [lib/upkeeper/README.md](lib/upkeeper/README.md): module contract, load-order
  ownership, and module groups
- [tools/validate_upkeeper.sh](tools/validate_upkeeper.sh): local validation
  harness for dependencies, syntax, module map, prompts, dry-runs, symlink
  behavior, launch/capture classification, and fail-fast guardrails
- [tools/install_client_link.sh](tools/install_client_link.sh),
  [tools/update_client_link.sh](tools/update_client_link.sh),
  [tools/uninstall_client_link.sh](tools/uninstall_client_link.sh), and
  [tools/doctor_upkeeper.sh](tools/doctor_upkeeper.sh): no-backend client
  symlink install, refresh, removal, and diagnostics helpers
- [tools/stress_upkeeper_corpus.sh](tools/stress_upkeeper_corpus.sh): local
  no-quota sample-repo stress harness; run
  `tools/stress_upkeeper_corpus.sh --local`
- [tools/backlog_merge_steward.py](tools/backlog_merge_steward.py): local
  no-backend guard for green backlog PR merge and clean-sheet cleanup
- [tools/backlog_triage.py](tools/backlog_triage.py): local no-backend
  stopped-loop restart triage for backlog runs
- [tools/upkeeper_control_plane_audit.py](tools/upkeeper_control_plane_audit.py):
  local no-backend inventory for unexpected control-plane state such as tracked
  runtime evidence, root scratch artifacts, active locks, open obligations, and
  recent hard loop markers. With `--remediate-safe`, it removes only
  policy-listed untracked scratch artifacts such as literal root `$db` sidecars
  and Python bytecode caches. With `--write-obligations`, blocker and
  actionable findings are preserved under automation obligation custody before
  staging or model work continues. Audit output includes `KP-###` invariant ids
  and can write before/after snapshots with `--snapshot-out`. With
  `--write-lineage`, findings also leave local closed-loop lineage records that
  preserve first/last seen, classifier version, invariant id, remediation
  decision, and whether an unknown class still needs classifier/invariant/fixture
  promotion.
- [tools/backlog_parallel_leases.py](tools/backlog_parallel_leases.py): local
  no-backend issue/target lease registry and accepted base primitive for future
  isolated parallel backlog workers
- [tools/check_public_docs.sh](tools/check_public_docs.sh): deterministic
  public documentation policy checks
- [tools/docs_only_fast_path.sh](tools/docs_only_fast_path.sh): local
  no-backend, no-GitHub docs-only classifier and validation path
- [launcher_examples/README.md](launcher_examples/README.md): tracked shell
  launcher examples for common Upkeeper loops
- [completions/upkeeper.bash](completions/upkeeper.bash): optional Bash
  completion for `Upkeeper`, `Upkeeper.sh`, and `FlameOn`
- `testruns/*.sh`: tracked local launchers for repeatable Upkeeper test cycles
- [PLANS.md](PLANS.md): brief implementation plans for complex Upkeeper changes
- [prompts/default-review.md](prompts/default-review.md): runtime default review
  prompt template loaded by Upkeeper
- [prompts/caretaking_23_items.md](prompts/caretaking_23_items.md): full
  rotating maintenance review repertoire reference
- [prompts/p23-data-contract-negative-fixture-audit.md](prompts/p23-data-contract-negative-fixture-audit.md):
  standalone P23 add-on prompt for explicit data-contract audit runs
- [prompts/p24-de-llm-ing-viability-review.md](prompts/p24-de-llm-ing-viability-review.md):
  P24 review module for explicit LLM-boundary localization review
- [prompts/p25-contract-intent-compliance-review.md](prompts/p25-contract-intent-compliance-review.md):
  P25 review module for explicit contract and intent compliance review
- [prompts/p26-public-documentation-review.md](prompts/p26-public-documentation-review.md):
  P26 review module for public documentation and code-comment clarity
- [prompts/p27-educational-debrief-review.md](prompts/p27-educational-debrief-review.md):
  P27 review module for concise saved after-action reviews
- [prompts/p28-unit-test-harvesting-review.md](prompts/p28-unit-test-harvesting-review.md):
  P28 review module for turning useful discoveries into local tests or fixtures
- [prompts/p29-reuse-harvesting-review.md](prompts/p29-reuse-harvesting-review.md):
  P29 review module for extracting bounded reusable project knowledge
- [prompts/p30-stark-protocol-review.md](prompts/p30-stark-protocol-review.md):
  P30 review module for permanent hardening and non-regression barriers
- Fault-injection review is reserved for future P31 work so P29 reuse
  harvesting and P30 Stark Protocol aliases remain backward compatible.
- [prompts/p31-fault-injection-review.md](prompts/p31-fault-injection-review.md):
  reserved future P31 contract for deterministic fault-injection scenarios with
  explicit oracles and recovery proof; not wired as a review-module flag yet
- [docs/fault-injection-scenarios.md](docs/fault-injection-scenarios.md):
  tracked P31 scenario registry and priority matrix with stable `FI-###` ids
- [prompts/git_hard_clean.md](prompts/git_hard_clean.md): explicit branch and backup cleanup
  workflow notes
- [templates/prompt-template.md](templates/prompt-template.md): starter format
  for reusable prompt files

## License

This repository is released under the `MIT` license.
