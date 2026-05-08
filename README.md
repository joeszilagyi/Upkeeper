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

## What It Does

`Upkeeper` runs one guarded Codex backend cycle per invocation.

On each cycle it:

- reads recent Codex quota snapshots from `$CODEX_HOME/sessions`
- logs current and projected quota use before spending another run
- preselects one eligible script/tool target with `git ls-files -co --exclude-standard`
- prepends that target to the default maintenance prompt so Codex does not scan
  `.git/`, ignored files, generated outputs, runtime evidence, or test trees by accident
- applies the P23 data-contract pass to validators, importers, exporters,
  registry loaders, config readers, data readers, and input-boundary CLIs
- can append opt-in P24/P25/P26/P27 review modules for de-LLM-ing viability,
  contract/intent compliance, public documentation clarity, and educational
  debriefs
- runs Codex once with the configured model and reasoning effort
- records terminal outcomes in `Upkeeper.log`
- tags log lines with a per-cycle `run_hash` and emits `--MARK--` heartbeat
  evidence for continuity checks
- scans recent prior log entries for incomplete cycles before launching Codex
- logs a disk-space preflight before spending a backend run
- optionally hands off to a bounded fallback model and postmortem path when the
  primary run blocks, fails, or hits a quota guardrail

The wrapper is intentionally local. It is not a hosted service, CI replacement,
or repository policy engine. It gives an operator a repeatable loop with better
guardrails and better evidence than manually relaunching Codex from memory.

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

Validate the central checkout before release or after touching module order,
prompt packaging, or symlink behavior:

```sh
tools/validate_upkeeper.sh --deps
tools/validate_upkeeper.sh --quick
tools/validate_upkeeper.sh --full
```

The full validation mode still avoids real backend Codex work. It runs Upkeeper
with `UPKEEPER_DRY_RUN=1` for startup checks, then uses a local fake `codex`
binary to exercise launch/capture failure classification without spending quota.

Runtime/tool dependencies are tracked in [`docs/dependencies.md`](docs/dependencies.md).
GitHub's dependency graph should stay enabled, but it is expected to show no
package dependencies until the repo adds a real supported manifest, workflow, or
dependency submission.

The backward-compatibility contract is tracked in
[`docs/compatibility.md`](docs/compatibility.md). Existing operator-visible
behavior should be preserved unless compatibility would be unsafe or impossible.

Future multi-repo stress testing is tracked in
[`docs/stress-corpus.md`](docs/stress-corpus.md). The contract starts with
locally generated sample repositories across common language/toolchain shapes
and keeps real backend Codex runs behind explicit opt-in commands.

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
cd /work/repos/example-index
ln -s /work/tools/Upkeeper/Upkeeper ./Upkeeper.sh
./Upkeeper.sh --version
UPKEEPER_DRY_RUN=1 ./Upkeeper.sh
```

With a symlink, fixes made in the central Upkeeper repo are picked up by every
client the next time its local `./Upkeeper.sh` runs. If a repo has an old copied
wrapper instead of a symlink, it will drift: missing flags, stale prompt rules,
old guardrail behavior, or missing `lib/upkeeper` modules are all signs that
the client wrapper should be refreshed or replaced with a link. Copying only the
root launcher without the paired module tree is unsupported.

In client repositories, keep Upkeeper's local artifacts ignored:

```gitignore
Upkeeper.sh
Upkeeper.log
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

The default prompt is a rotating single-file maintenance review. It asks Codex
to review the oldest eligible non-test script/tool file by modification time.

When the repo-local `Upkeeper` implementation itself is eligible and has not
been touched for at least seven days, the wrapper selects it first. Otherwise it
falls back to the normal oldest eligible script/tool rotation.

The wrapper does that selection before Codex starts and prepends a
`WRAPPER_PRESELECTED_REVIEW_TARGET` block to the prompt. That block is meant to
prevent expensive or unsafe rediscovery patterns such as:

- `find .` inventories that expose `.git/objects`
- `sort | head` pipelines that produce broken-pipe noise
- nested `xargs ... sh -c ... awk ...` selectors that are fragile under quoting

If the preselected file cannot be reviewed because it is gone, unreadable,
binary, generated, or explicitly excluded, Codex must state that exception and
choose a replacement from the same source-safe boundary.

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

P24 through P27 are opt-in review modules. They are loaded from the central
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

P27 applies when a run should leave a concise learning note after the fix. It
captures what went wrong, why it probably happened, why it mattered, how to
avoid the pattern, how it was fixed, what was already good, and what can still
improve.

```sh
./Upkeeper --review-module=p24
./Upkeeper --review-module=p25
./Upkeeper --review-module=p26
./Upkeeper --review-module=p27
./Upkeeper --review-modules=p24,p25,p26,p27

# Shorthand aliases are also available.
./Upkeeper --p24 --p25 --p26 --p27
```

Before the primary Codex response emits its final marker, the prompt now requires
a current-cycle `Upkeeper.log` review and a machine-readable acknowledgment:
`UPKEEPER_LOG_REVIEW: CHECKED cycle=<cycle_id> anomalies=none|listed`. If that
review exposes a concrete central wrapper or prompt defect while running in this
repo, Codex may apply the smallest safe self-repair immediately and report it as
a log self-repair.

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
- `runtime/startup-anomaly-gates/`
- repo-local copied or linked wrappers such as `Upkeeper.sh`, when the client
  repo chooses to ignore them

Promote durable lessons into tracked docs or wrapper behavior. Leave raw logs,
transcripts, temporary outputs, and postmortem evidence local unless a repo has a
specific policy for publishing them.

## Repository Layout

```text
.
|-- docs/
|   |-- compatibility.md
|   |-- dependencies.md
|   |-- public-documentation-policy.md
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
|   `-- p27-educational-debrief-review.md
|-- templates/
|   |-- README.md
|   `-- prompt-template.md
|-- tools/
|   |-- check_public_docs.sh
|   `-- validate_upkeeper.sh
|-- Upkeeper
|-- LICENSE
|-- .editorconfig
|-- .gitignore
|-- change_notes.md
`-- README.md
```

## Related Docs

- [docs/scripts/upkeeper.md](docs/scripts/upkeeper.md): detailed operator guide
  and environment knobs
- [docs/compatibility.md](docs/compatibility.md): binding backward-compatible
  operator-visible feature surface
- [docs/dependencies.md](docs/dependencies.md): runtime/tool dependency surface
  and GitHub dependency-graph expectations
- [docs/public-documentation-policy.md](docs/public-documentation-policy.md):
  public-by-default documentation, comment, release-note, and help-text policy
- [docs/stress-corpus.md](docs/stress-corpus.md): future local sample-repo
  stress-corpus contract
- [lib/upkeeper/README.md](lib/upkeeper/README.md): module contract, load-order
  ownership, and module groups
- [tools/validate_upkeeper.sh](tools/validate_upkeeper.sh): local validation
  harness for dependencies, syntax, module map, prompts, dry-runs, symlink
  behavior, launch/capture classification, and fail-fast guardrails
- [tools/check_public_docs.sh](tools/check_public_docs.sh): deterministic
  public documentation policy checks
- [launcher_examples/README.md](launcher_examples/README.md): tracked shell
  launcher examples for common Upkeeper loops
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
  P27 review module for concise saved educational debriefs
- [prompts/git_hard_clean.md](prompts/git_hard_clean.md): explicit branch and backup cleanup
  workflow notes
- [templates/prompt-template.md](templates/prompt-template.md): starter format
  for reusable prompt files

## License

This repository is released under the `0BSD` license.
