# Upkeeper Dependencies

Upkeeper is a Bash wrapper around local system tools and the Codex CLI. GitHub's
dependency graph should be enabled for the repository. The current GitHub
Actions workflow may appear as a real dependency on `actions/checkout`; that is
expected. Package ecosystems such as npm, Python, Ruby, Go, or .NET should still
show no dependencies unless the repo later adds a supported manifest or lock
file such as `package.json`, `requirements.txt`, `Gemfile`, or `go.mod`, or
submits dependencies through GitHub's dependency submission API.

Upkeeper Lattice uses Python's standard-library `sqlite3` module. It does not
add a Python package manifest, ORM, daemon, service, network client, or package
manager dependency.

Do not add fake package manifests just to populate the dependency graph. Track
Upkeeper's real dependency surface here and validate it locally with:

```sh
tools/validate_upkeeper.sh --deps
tools/validate_upkeeper.sh --smoke
tools/validate_upkeeper.sh --full
```

`--deps` reports command availability. `--smoke` runs the fast local edit-loop
checks without backend work. `--full` runs the release guardrails with
`UPKEEPER_DRY_RUN=1` for startup checks and a local fake `codex` binary for
launch/capture failure classification, including central startup,
symlinked-client startup, missing-module failure, missing prompt-template
failure, and empty-transcript failure.

GitHub Actions runs the no-quota CI path from `.github/workflows/ci.yml` on
pushes and pull requests. That workflow starts on `ubuntu-latest`, installs
required tools including `jq` and `age`, and runs:

```sh
bash -n Upkeeper Upkeeper.conf configurations/default.conf lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh
for test_script in tests/*.bash; do bash "$test_script"; done
tools/check_public_docs.sh --quick
tools/validate_upkeeper.sh --quick
```

The CI workflow does not run real Codex backend work and does not upload runtime
artifacts by default.

## GitHub Settings

Recommended repository settings:

- Enable the dependency graph.
- Enable Dependabot alerts.
- Enable Dependabot security updates.
- Dependabot version updates for GitHub Actions can be added later if the repo
  wants automated action bumps. Do not add package-ecosystem version-update
  configuration until the repo has real package manifests to update.

If GitHub reports only the workflow action dependency, that is normal for the
current repo shape. The dependency graph is future-proofing for later supported
ecosystems, not the source of truth for current runtime dependencies.

The dependency submission API could be used later if Upkeeper needs generated
dependency data in GitHub, but local command dependencies are clearer and more
auditable in this tracked document and the validation harness.

GitHub references:

- [About the dependency graph](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/about-the-dependency-graph)
- [Dependency graph supported package ecosystems](https://docs.github.com/en/code-security/reference/supply-chain-security/dependency-graph-supported-package-ecosystems)

## Required Commands

These commands are required by normal Upkeeper startup/runtime paths:

- `awk`
- `cat`
- `chmod`
- `cut`
- `date`
- `df`
- `find`
- `git`
- `grep`
- `jq`
- `ln`
- `mkdir`
- `mktemp`
- `mv`
- `ps`
- `python3`
- `rm`
- `rmdir`
- `sed`
- `sort`
- `tail`
- `tee`
- `tr`
- `wc`

## Backend Dependency

- `codex` is required for non-dry-run backend cycles.

`UPKEEPER_DRY_RUN=1` can validate startup, quota discovery, target selection,
prompt compilation, symlink resolution, and failure paths without launching a
Codex backend task.

## Conditional Dependencies

- `screen` is required when detached screen fallback is enabled. That is the
  default when `CODEX_FALLBACK_ENABLED=1` and `CODEX_FALLBACK_SCREEN_ENABLED=1`.

## Full-Burn Launcher Dependencies

- `age` is required for live `FlameOn` and `ChimneySweep` runs. Those repo-root
  automation launchers force encrypted selected-target pre-contact backup before
  backend launch, so a missing `age` binary or missing
  `UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT` stops the cycle with
  `PRECONTACT_BACKUP_UNAVAILABLE` and `codex_exec_started=0`.

Install and configure a public recipient before live launcher use:

```sh
sudo apt-get update
sudo apt-get install -y age

mkdir -p "$HOME/.config/age"
chmod 700 "$HOME/.config/age"
age-keygen -o "$HOME/.config/age/upkeeper.txt"
chmod 600 "$HOME/.config/age/upkeeper.txt"
age-keygen -y "$HOME/.config/age/upkeeper.txt"
export UPKEEPER_PRECONTACT_BACKUP_AGE_RECIPIENT="age1..."
```

The exported recipient is public. The private identity file is needed only for
manual restore and must not be committed, placed in prompts, or exported to
backend-visible environments.

## Optional Dependencies

- `age` is optional only for plain `./Upkeeper` compatibility runs that do not
  require encrypted selected-target backup. If `UPKEEPER_PRECONTACT_BACKUP_MODE`
  is `age`, or `UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=1`, missing `age`
  or a missing recipient fails the cycle before backend launch.
- `realpath` is used for central implementation path resolution when available;
  `python3` is the fallback.
- `stat` is used for transcript sizing when available; `python3` is the
  fallback.
- `zip` is used for log rotation archives. If it is missing, Upkeeper disables
  wrapper log rotation for that cycle and logs a warning.

## Dependency Change Discipline

When adding, removing, or changing dependency expectations:

- update this file,
- update `tools/validate_upkeeper.sh --deps`,
- update the wrapper preflight if runtime behavior changes,
- update `README.md`, `docs/scripts/upkeeper.md`, and the current year's root
  `change_notes_YYYY.md` when the change is operator-facing,
- run `tools/validate_upkeeper.sh --deps` and `tools/validate_upkeeper.sh --full`.
