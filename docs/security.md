# Upkeeper Security And Trust Model

Upkeeper is a local wrapper around your shell, Git checkout, Codex CLI, and
local runtime evidence. It is not a hosted service or a security sandbox by
itself.

The practical model is simple: run Upkeeper only in repositories and terminals
where you would be willing to run a local maintenance script plus `codex exec`.
It can read project files, write local evidence, invoke shell commands through
Codex, and record enough context for later diagnosis.

## Trust Boundaries

Upkeeper crosses these local trust boundaries:

- the central Upkeeper checkout that owns `Upkeeper`, `lib/upkeeper`, `prompts`,
  `docs`, and default config
- the client repository where `./Upkeeper.sh` or `./Upkeeper` is invoked
- shell-sourced config files selected by `Upkeeper.conf`, `--config-file`, or
  `UPKEEPER_CONFIG_FILE`
- the local Codex installation and `codex exec` behavior
- `$CODEX_HOME`, especially `sessions/`, where Codex stores session JSONL data
- ignored local evidence such as `Upkeeper.log`, `runtime/`, transcripts,
  postmortem reports, active locks, manifests, and failure markers

Treat all of those as local operator-controlled state. Do not use Upkeeper to
bridge trust between mutually suspicious users, machines, or repositories.

## What Upkeeper Can Read

Normal startup and dry-run paths can read:

- tracked and non-ignored repository file metadata for selection
- the selected review target and paired prompt files
- Git status, Git object hashes, ignore rules, and file mtimes
- `Upkeeper.conf` or the selected config file
- `$CODEX_HOME/sessions` JSONL files for quota and session diagnostics
- prior `Upkeeper.log` lines for previous-run anomaly detection
- runtime state under `runtime/` and configured state directories

During a real backend cycle, Codex may read additional repository files while
reviewing the selected target. Upkeeper's preselection narrows the intended
scope, but Codex is still a local agent with the configured sandbox permissions.

## What Upkeeper Can Write

Upkeeper can write local control-plane evidence:

- `Upkeeper.log`
- `runtime/upkeeper-transcripts/`
- `runtime/upkeeper-file-manifest.json`
- `runtime/startup-anomaly-gates/`
- `runtime/unaddressed-tool-failures/`
- `runtime/journals/upkeeper-postmortems/`
- `runtime/upkeeper-active.lock`
- configured wrapper health state under `$CODEX_HOME/upkeeper/`
- repo-local `docs/scripts/upkeeper.md` only when bootstrap is enabled, the path
  is not ignored, and the guide is missing

During a real backend cycle, Codex can modify repository files according to the
configured Codex sandbox mode and the task it performs. Dry-run mode
(`UPKEEPER_DRY_RUN=1`) stops before launching real backend work.

## What Upkeeper Can Execute

The wrapper itself runs local shell commands needed for startup, validation,
selection, quota parsing, and cleanup. Examples include `git`, `find`, `jq`,
`python3`, `df`, `ps`, `sed`, `awk`, and related standard tools.

In non-dry-run mode, Upkeeper launches:

```sh
codex exec ...
```

Fallback and postmortem paths may launch additional bounded `codex exec` calls
unless disabled or stopped by quota/local-environment guardrails.

## Shell-Sourced Config Files

`Upkeeper.conf`, `configurations/default.conf`, and files selected with
`--config-file=PATH` are sourced by Bash. That means they are executable shell
code, not passive key/value data.

Only use config files from trusted locations. Do not point `--config-file` at a
file from an untrusted repo, issue attachment, shared writable directory, or
downloaded snippet. Keep scheduled-run profiles readable and boring: assignments
such as `CODEX_MODEL=...`, `UPKEEPER_TARGET_FILE=...`, and
`UPKEEPER_REVIEW_MODULES=...` are the intended shape.

CLI flags remain the final one-cycle override surface, but they do not make an
untrusted config file safe to source.

## Codex Sandbox Mode

Upkeeper defaults `CODEX_MODE` to Codex workspace-write sandboxing. That is a
useful operational boundary, not a reason to run untrusted code casually.

Review the effective sandbox mode before long loops:

```sh
./Upkeeper --help
UPKEEPER_DRY_RUN=1 ./Upkeeper
```

Do not weaken `CODEX_MODE` unless the repository, machine, credentials, and task
are trusted for that broader access. If a task needs access outside the repo,
prefer a short manual run with reviewed inputs instead of a long unattended
loop.

## CODEX_HOME Session Parsing

Upkeeper reads recent `$CODEX_HOME/sessions/**/*.jsonl` files to find quota
snapshots and session diagnostics. It does not need to publish those files.

Session JSONL may contain model names, timestamps, rate-limit state, tool-call
metadata, and fragments of prior Codex interactions. Treat `$CODEX_HOME` as
local private state. Do not commit it, attach it to public issues, or copy it
into client repositories.

If `$CODEX_HOME/sessions` is missing, stale, unreadable, or unwritable, Upkeeper
should fail or degrade with local-environment evidence rather than spending more
backend work.

## Logs, Transcripts, And Runtime Artifacts

Upkeeper intentionally records evidence so failures can be diagnosed later.
Those records can include:

- absolute local paths
- selected file names and Git status
- command lines and exit summaries
- filtered transcript signal
- final review summaries
- snippets of command output
- quota metadata
- incident classifications and postmortem context

Because project commands may accidentally print secrets, logs and transcripts
must be treated as potentially sensitive. Keep `Upkeeper.log` and `runtime/`
ignored unless a repo has a deliberate, reviewed policy for publishing specific
sanitized artifacts.

## Ignored Files

Automatic rotation avoids `.git/`, ignored paths, `.upkeeperignore` paths,
runtime evidence, generated outputs, and test trees. Explicit `--target-file`
pins still reject ignored paths, `.upkeeperignore` paths, runtime evidence,
`.git`, directories, unreadable files, and binary-like files.

That selection policy is a safety guardrail, not a data-loss prevention system.
If a real backend task runs commands that print or read ignored files, that
output can still enter transcripts. Keep secrets out of repository-adjacent
files when possible, and make sure `.env`, tokens, private keys, credentials,
and build caches stay ignored.

## Symlinked Central Checkout

The recommended client setup is:

```sh
ln -s /path/to/central/Upkeeper ./Upkeeper.sh
```

With that shape, the client repo invokes a local `./Upkeeper.sh`, but modules,
prompts, default config, and docs resolve from the central Upkeeper checkout.
That central checkout is trusted code. Protect it like any other operational
tooling repository.

Do not replace a symlink with a copied root launcher unless you also keep the
paired `lib/upkeeper`, `prompts`, and docs tree in sync. A copied partial
launcher is unsupported and should fail before doing dangerous work.

## Client Repo Trust

Running Upkeeper in a client repo means trusting that repo enough to:

- inspect its files and Git metadata
- run local validation or test commands if Codex chooses them
- let Codex propose or apply bounded maintenance edits
- write ignored local Upkeeper evidence

Do not run Upkeeper in a repo from an untrusted source without first reviewing
its scripts, hooks, config files, generated files, and test commands. Disable or
avoid project-local automation that can run unexpected code before using long
loops.

## Fallback And Postmortem Behavior

Fallback and postmortem paths are designed for controlled recovery and incident
evidence, not for bypassing safety decisions.

When enabled, Upkeeper may launch a stronger fallback model or auxiliary
postmortem/hardening Codex calls after a primary failure, quota block, or
blocked run. Those auxiliary calls inherit the same trust assumptions: local
repo, local config, local Codex installation, configured sandbox mode, and local
logs/transcripts.

Disable fallback and postmortem paths for the narrowest test runs:

```sh
CODEX_FALLBACK_ENABLED=0 CODEX_POSTMORTEM_ENABLED=0 UPKEEPER_DRY_RUN=1 ./Upkeeper
```

For live backend runs, leave fallback enabled only when the repository and
machine are trusted for the extra model calls and evidence capture.

## Secret Handling

Upkeeper does not intentionally ask for secrets, but it can record outputs from
tools and Codex. Avoid running it where ordinary project commands print secrets.

Before running Upkeeper:

- keep `.env`, credentials, private keys, local tokens, and generated secret
  material ignored
- avoid passing secrets in CLI flags or prompt text
- avoid putting secrets in `Upkeeper.conf` or named config profiles
- prefer environment variables managed by the shell or OS credential store
- review transcripts and logs before sharing them outside the machine

If a secret appears in `Upkeeper.log`, a transcript, a postmortem, or a queued
failure marker, treat that artifact as compromised local evidence. Rotate the
secret before publishing any sanitized excerpt.

## What Not To Commit

Do not commit:

- `Upkeeper.log`
- `runtime/`
- `runtime/upkeeper-transcripts/`
- `runtime/journals/upkeeper-postmortems/`
- `runtime/unaddressed-tool-failures/`
- `$CODEX_HOME`
- Codex session JSONL files
- local copied wrappers from client repos
- credentials, tokens, private keys, `.env` files, or secret-bearing fixtures
- raw transcripts or postmortems unless they have been deliberately sanitized

Commit durable lessons instead: docs, prompt changes, validation fixtures,
source fixes, or explicit sanitized excerpts.

## When Not To Run Upkeeper

Do not run Upkeeper when:

- the repo, config file, or symlink target is untrusted
- the working tree contains secrets that project commands might print
- a branch contains destructive scripts or tests you have not reviewed
- you cannot afford local edits, logs, or transcript creation
- quota state is unknown and you are not using dry-run
- the Codex sandbox mode has been broadened beyond what the task needs
- the repo has legal, privacy, export-control, or customer-data constraints that
  forbid model-backed review
- the machine is shared with users who should not access the repo or evidence
- you need a human design/product decision before code maintenance can proceed

Use dry-run first when in doubt.

## Safe Default Commands

These commands are safe starting points because they do not launch real backend
Codex work:

```sh
./Upkeeper --help
./Upkeeper --version
UPKEEPER_DRY_RUN=1 ./Upkeeper
tools/validate_upkeeper.sh --deps
tools/validate_upkeeper.sh --quick
tools/check_public_docs.sh --quick
tools/stress_upkeeper_corpus.sh --local
```

For a new client repo, first verify the symlink and dry-run behavior:

```sh
ln -s /path/to/central/Upkeeper ./Upkeeper.sh
./Upkeeper.sh --version
UPKEEPER_DRY_RUN=1 ./Upkeeper.sh
```

Move to a live backend loop only after the repo, config, sandbox mode, ignored
files, and expected evidence paths are understood.
