# Upkeeper

Upkeeper is a local control-plane wrapper for running Codex maintenance cycles
against real repositories without turning every loop into an ad hoc shell script.

It is built for the kind of work where you want Codex to keep taking one
bounded, reviewable maintenance pass at a time: clean up old scripts, patch
small bugs, refresh docs, preserve incident evidence, and stop before quota or
environment failures make the run noisy.

## What It Does

`Upkeeper` runs one guarded Codex backend cycle per invocation.

On each cycle it:

- reads recent Codex quota snapshots from `$CODEX_HOME/sessions`
- logs current and projected quota use before spending another run
- preselects one eligible script/tool target with `git ls-files -co --exclude-standard`
- prepends that target to the default maintenance prompt so Codex does not scan
  `.git/`, ignored files, generated outputs, runtime evidence, or test trees by accident
- runs Codex once with the configured model and reasoning effort
- records terminal outcomes in `Upkeeper.log`
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

## Client Repo Setup

The most useful pattern is to keep this repository as the central source and
symlink the wrapper into each repo that should receive the same behavior.

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
and old guardrail behavior are all signs that the client wrapper should be
refreshed or replaced with a link.

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

Run a Spark Codex maintenance burn-down and allow the current 5-hour Spark
bucket to drain to zero before stopping:

```sh
CODEX_MODEL=gpt-5.3-codex-spark \
CODEX_REASONING_EFFORT=xhigh \
CODEX_SPARK_5H_STOP_PERCENT=0 \
while ./Upkeeper.sh; do
  sleep 60
done
```

Run the same style of loop with a stronger model and an explicit 5-hour stop:

```sh
CODEX_MODEL=gpt-5.5 \
CODEX_REASONING_EFFORT=xhigh \
CODEX_5H_STOP_PERCENT=5 \
while ./Upkeeper.sh; do
  sleep 60
done
```

Append one-time guidance without changing the default prompt:

```sh
./Upkeeper.sh --prompt "Focus on failing validator tests. Keep fixes scoped and verify before final status."
```

Use a prompt file for a focused cleanup lane:

```sh
./Upkeeper.sh --prompt-file prompts/review-release-blockers.md
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

The wrapper now does that selection before Codex starts and prepends a
`WRAPPER_PRESELECTED_REVIEW_TARGET` block to the prompt. That block is meant to
prevent expensive or unsafe rediscovery patterns such as:

- `find .` inventories that expose `.git/objects`
- `sort | head` pipelines that produce broken-pipe noise
- nested `xargs ... sh -c ... awk ...` selectors that are fragile under quoting

If the preselected file cannot be reviewed because it is gone, unreadable,
binary, generated, or explicitly excluded, Codex must state that exception and
choose a replacement from the same source-safe boundary.

## Evidence And Cleanup

Local runtime evidence is deliberately ignored by git:

- `Upkeeper.log`
- `runtime/`
- repo-local copied or linked wrappers such as `Upkeeper.sh`, when the client
  repo chooses to ignore them

Promote durable lessons into tracked docs or wrapper behavior. Leave raw logs,
transcripts, temporary outputs, and postmortem evidence local unless a repo has a
specific policy for publishing them.

## Repository Layout

```text
.
|-- docs/
|   `-- scripts/
|       `-- upkeeper.md
|-- prompts/
|   `-- README.md
|-- templates/
|   |-- README.md
|   `-- prompt-template.md
|-- Upkeeper
|-- caretaking_22_items.md
|-- git_hard_clean.md
|-- LICENSE
|-- .editorconfig
|-- .gitignore
`-- README.md
```

## Related Docs

- [docs/scripts/upkeeper.md](docs/scripts/upkeeper.md): detailed operator guide
  and environment knobs
- [caretaking_22_items.md](caretaking_22_items.md): the rotating maintenance
  review repertoire used by the default prompt family
- [git_hard_clean.md](git_hard_clean.md): explicit branch and backup cleanup
  workflow notes
- [templates/prompt-template.md](templates/prompt-template.md): starter format
  for reusable prompt files

## License

This repository is released under the `0BSD` license.
