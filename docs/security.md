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
- `runtime/upkeeper-automation-ledger/`
- `runtime/upkeeper-obligations/`
- `runtime/journals/upkeeper-postmortems/`
- `runtime/upkeeper-active.lock`
- configured wrapper health state under `$CODEX_HOME/upkeeper/`
- repo-local `docs/scripts/upkeeper.md` only when bootstrap is enabled, the path
  is not ignored, and the guide is missing

During a real backend cycle, Codex can modify repository files according to the
configured Codex sandbox mode and the task it performs. Dry-run mode
(`UPKEEPER_DRY_RUN=1`) stops before launching real backend work.

## Selected-Target Pre-Contact Backups

After Upkeeper selects a review target and before it appends the selected-target
authority block to the compiled prompt, it creates a pre-contact backup when
`UPKEEPER_PRECONTACT_BACKUP_ENABLED=1`. The default is required
(`UPKEEPER_PRECONTACT_BACKUP_REQUIRED=1`) and encrypted-required
(`UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=1`), so backup creation failures
stop the cycle before backend launch with `codex_exec_started=0`.

The default vault root is outside the repository:

```sh
${XDG_STATE_HOME:-$HOME/.local/state}/upkeeper/precontact-vault
```

Upkeeper does not put that vault path in the compiled prompt, Lattice preselect
evidence, or pre-contact backup log lines. Success logs contain only the
selected target HMAC, backup mode, encrypted flag, backend-protection flag, and
`path_redacted=1`.

Plain backup mode copies the selected file and a JSON sidecar. It is useful for
quick recovery, but it is not a security boundary: a same-user backend process
that can discover and access the vault through other means may be able to read
or delete plain artifacts. Plain mode therefore requires an explicit unsafe
operator opt-in with both `UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0` and
`UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1`, and Upkeeper rejects the
plaintext path when the selected file contains high-confidence private-key
material. Upkeeper records accepted plain backups as `encrypted=false` and
`protected_from_backend=false`.

Age mode encrypts the backup payload to a configured public recipient. Backup
creation uses only the public recipient; it must not request, read, log, or
source a private age identity. The private identity is needed only for manual
restore and must not be committed to config, included in prompts, printed in
logs, or placed in an environment visible to backend Codex processes. Without a
separate backend confinement layer, encrypted mode protects content at rest but
does not make same-user deletion impossible.

The repo-root automation launchers `FlameOn` and `ChimneySweep` run the
full-burn profile: Lattice is required, selected-target backup is required,
encrypted backup is required, and `CODEX_MODE` is pinned to
`--sandbox workspace-write`. They also set quota stop floors and weekly buffers
to `0`, bypass wrapper quota guardrail stops, and bypass persisted quota
cooldown markers, so live launcher runs can spend the selected model bucket down
to the provider floor. Live launcher runs therefore require `age` and an
`UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT` before any backend Codex task can
start. Upkeeper now resolves that prerequisite before issue selection on live
apply-stage or normal repair cycles, and records the missing-recipient path as
machine-local operator setup rather than as a target-file bug.

ChimneySweep's default issue workflow is staged across separate backend
instantiations: comment, review, then apply. The comment and review stages are
tracked-source read-only; the wrapper fingerprints tracked source before launch
and fails the stage if tracked source changes. Those stages also force backend
Codex into a read-only repository sandbox. The proposed issue comment is carried
back in a final-message draft block that the wrapper extracts only after the
source guard passes. GitHub I/O is wrapper-brokered: the wrapper fetches issue
bodies/comments before launch, backend Codex receives only that issue packet,
and the wrapper posts comments or later issue updates after validation. Backend
Codex launches do not inherit GitHub token variables, use an empty per-run `gh`
config directory, and shadow direct `gh`, `curl`, `wget`, and `hub` commands
with blocker stubs. The apply stage is the stage that may edit source, but it
still does not contact GitHub
directly.

Install `age`, then bootstrap the public recipient outside the repository:

```sh
sudo apt-get update
sudo apt-get install -y age

tools/upkeeper_precontact_bootstrap.sh
```

That command creates or reuses the private age identity under
`${XDG_CONFIG_HOME:-$HOME/.config}/age/upkeeper.txt` and writes only the public
recipient to `${XDG_CONFIG_HOME:-$HOME/.config}/upkeeper/local.env`. The
private identity path should be used for manual restore only and must not be
passed into model prompts or committed configuration.

Landlock, bubblewrap allowlists, root-owned or dedicated-user vaults, fs-verity,
and immutable file attributes are separate hardening layers. They may be useful
future defenses, but this first local slice deliberately does not install root
helpers, sudoers rules, services, ownership tricks, or a custom confinement
launcher.

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

`Upkeeper.conf`, `configurations/default.conf`, files selected with
`--config-file=PATH`, and the trusted machine-local env file named by
`UPKEEPER_LOCAL_ENV_FILE` are sourced by Bash. That means they are executable
shell code, not passive key/value data.

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
are trusted for that broader access. Upkeeper rejects `danger-full-access` and
`--dangerously-bypass-approvals-and-sandbox`, because those modes are
incompatible with the Genie Protocol rule that backend Codex stays inside a
small brokered execution space. If a task needs access outside the repo, prefer
a short manual run with reviewed inputs instead of a long unattended loop.

## CODEX_HOME Session Parsing

Upkeeper reads recent `$CODEX_HOME/sessions/**/*.jsonl` files to find quota
snapshots and session diagnostics. It does not need to publish those files.

Session JSONL may contain model names, timestamps, rate-limit state, tool-call
metadata, and fragments of prior Codex interactions. Treat `$CODEX_HOME` as
local private state. Do not commit it, attach it to public issues, or copy it
into client repositories.

If `$CODEX_HOME/sessions` is missing, stale, unreadable, unwritable, symlinked,
not owned by the current user, or cannot be made private, Upkeeper should fail
or degrade with local-environment evidence rather than spending more backend
work. An existing session directory owned by the operator but created with weak
inherited permissions is repaired to `0700` before probing. Session-store write
probes use an unpredictable private probe directory instead of a predictable
marker file.

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
- automation run records and unresolved obligation records

Because project commands may accidentally print secrets, logs and transcripts
must be treated as potentially sensitive. Keep `Upkeeper.log` and `runtime/`
ignored unless a repo has a deliberate, reviewed policy for publishing specific
sanitized artifacts.

Upkeeper refuses unsafe live log paths before its first wrapper log write. A
repo-local `Upkeeper.log` that is a symlink, non-regular file, hard-linked file,
or owned by another user is rejected before Codex launch; a symlink log parent
directory is rejected as well. This prevents a contaminated checkout from
redirecting wrapper log appends into an operator-writable file outside the repo.

## Ignored Files

Automatic rotation avoids `.git/`, ignored paths, `.upkeeperignore` paths,
runtime evidence, generated outputs, and test trees. Explicit `--target-file`
pins still reject ignored paths, `.upkeeperignore` paths, runtime evidence,
`.git`, directories, symlinks, unreadable files, and binary-like files.
Manifest-backed selection, direct enumeration, and Lattice/max-cover diagnostics
also reject source paths that are symlinks before following, statting, or
sampling them, so a tracked symlink cannot be used to hand Codex an outside-repo
target.

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
