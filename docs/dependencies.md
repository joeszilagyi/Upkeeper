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
tools/validate_upkeeper.sh --source-contracts
tools/docs_only_fast_path.sh --validate
tools/validate_upkeeper.sh --smoke
tools/validate_upkeeper.sh --quick
tools/validate_upkeeper.sh --full
```

`--deps` reports command availability. `--source-contracts` runs the cheapest
source-only contracts used by backlog per-bug commit gates, including log-line
source length. `tools/docs_only_fast_path.sh --validate` is the local
README/docs/prompt-only path; it classifies changed paths without `gh`, `curl`,
`wget`, `git fetch`, or backend Codex, rejects mixed source changes, and then
runs the public-docs, smoke, and diff checks. Its classifier also reports
broader low-risk shell/config/test/tool changes so CI can keep those edits on
the shared local gates without paying for the full validator. `--smoke` runs
the fast local edit-loop checks without backend work. `--quick` adds bounded
static/fixture checks while staying out of wrapper dry-run integration paths.
`--full` runs the release guardrails with
`UPKEEPER_DRY_RUN=1` for startup checks and a local fake `codex` binary for
launch/capture failure classification, including central startup,
symlinked-client startup, missing-module failure, missing prompt-template
failure, and empty-transcript failure.

GitHub Actions runs the no-quota CI path from `.github/workflows/ci.yml` on
pull requests and on pushes to `main`. That workflow starts on
`ubuntu-latest`, runs `tools/setup_ci_dependencies.sh` to probe the runner for
expected stock commands, fails clearly if runner-provided tools disappear, and
installs only missing nonstandard tools such as `age`. The helper also prints
dependency-setup timing so CI latency stays visible. For low-risk shell/
config/test/tool changes the workflow keeps the shared local gate and skips the
full validator. For broader changes the workflow then runs:

```sh
bash -n Upkeeper Upkeeper.conf configurations/default.conf lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh
tools/run_validation_phases.sh --phases shell_syntax,unit_tests,public_docs,diff_whitespace
tools/run_tests.sh
tools/check_public_docs.sh --quick
tools/validate_upkeeper.sh --full
```

For docs-only changes, the workflow takes the cheaper path:

```sh
tools/docs_only_fast_path.sh --validate
```

That helper runs `tools/check_public_docs.sh --quick`,
`tools/validate_upkeeper.sh --smoke`, and `git diff --check`. The CI workflow
does not run real Codex backend work and does not upload runtime artifacts by
default.

## Supported Platforms And Portability

The supported unattended-run baseline is Linux with a GNU userland, matching the
`ubuntu-latest` GitHub Actions environment. That is the platform where release
validation, full validation, stress corpus checks, and live launcher behavior
are expected to work.

WSL2 is supported as a Linux environment when the required commands below are
installed and the checkout behaves like a normal Linux Git worktree. Native
Windows shells, PowerShell, and `cmd.exe` are not supported launch surfaces.

macOS is deferred. The current wrapper and validation harness still rely on
Linux/GNU assumptions around utility behavior, process inspection, filesystem
metadata, and sandbox-related tooling. The CI workflow documents this by
starting on `ubuntu-latest` only; add `macos-latest` after the GNU/BSD utility
differences are either removed or explicitly guarded.

The validator makes that boundary explicit. `tools/validate_upkeeper.sh --deps`
prints a platform row, and normal validation modes fail early on unsupported
kernels with a pointer back to this document. When future patches add platform
support, update this section, the validator platform gate, and CI together.

## Codex CLI Profiles

This repository does not commit a project `.codex/config.toml`. The decision is
intentional: Upkeeper is itself the Codex launch wrapper, and the checked-in
profile surface is `Upkeeper.conf` plus shell-compatible files under
`configurations/`. Keeping sandbox, approval, model, target-selection, and
dry-run behavior in the wrapper profile surface avoids a second Codex profile
source that can drift from validation and public operator docs.

The local Codex CLI still supports user-level profiles such as `--profile` and
layered profile files such as `--profile-v2`, but those are operator-local
state. Do not rely on a committed `.codex/config.toml` to enforce unattended
Upkeeper safety. If committed Codex profile files are added later, the same
patch must document how they compose with `Upkeeper.conf` and add validation
that proves they do not weaken the wrapper's no-real-backend-validation,
sandbox, approval, or GitHub-brokerage contracts.

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

- `bash`
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
- `timeout`
- `tr`
- `wc`

## Validation-Only Dependencies

These commands are required for local validation paths and validation-helper
scripts, but not for normal startup/runtime operation:

- `cp`
- `diff`
- `touch`
- `uname`

## jq Decision And Install Commands

`jq` remains a required runtime and validation dependency for the current
wrapper line. Upkeeper already requires Python 3, but the Bash runtime still
uses `jq` directly for JSON assignment bridges, status/session parsing,
automation-obligation checks, manifest validation, and local test fixtures.
Removing `jq` is allowed only in a future patch that replaces those bridges with
Python-backed helpers and adds deterministic compatibility tests for the same
JSON shapes.

Install `jq` with the package manager for the target machine:

```sh
# Debian/Ubuntu, including GitHub Actions ubuntu-latest
sudo apt-get update
sudo apt-get install -y jq

# Fedora/RHEL family
sudo dnf install -y jq

# Arch Linux
sudo pacman -S --needed jq

# macOS with Homebrew
brew install jq
```

The validator and wrapper missing-command diagnostics point back to this file.
Use `tools/validate_upkeeper.sh --deps` after installation to confirm the local
dependency surface before running broader validation.

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

- `age` is optional only when an operator explicitly opts into unsafe plaintext
  recovery by setting both `UPKEEPER_PRECONTACT_BACKUP_REQUIRE_ENCRYPTED=0` and
  `UPKEEPER_PRECONTACT_BACKUP_ALLOW_UNSAFE_PLAINTEXT=1`. With the central
  defaults, missing `age` or a missing recipient fails the cycle before backend
  launch.
- `realpath` is used for central implementation path resolution when available;
  `python3` is the fallback.
- `stat` is used for transcript sizing when available; `python3` is the
  fallback.
- `zip` is used for log rotation archives. If it is missing, Upkeeper disables
  wrapper log rotation for that cycle and logs a warning.
- `shellcheck` is an optional shell linting dependency for shell validation. It is
  not required for runtime startup, startup safety, or validation command success.

When `shellcheck` is available, operators and agents should run it opportunistically
on modified shell files touched in a cycle (for example:
`Upkeeper`, `lib/upkeeper/*.bash`, `tools/*.sh`, `testruns/*.sh`,
`tests/*.bash`) to catch shell abstraction and POSIX portability issues before
merge.

If `shellcheck` is unavailable, record that it is unavailable and continue; it
must never turn an operator-visible run into a hard failure.

## Dependency Change Discipline

When adding, removing, or changing dependency expectations:

- update this file,
- update `tools/validate_upkeeper.sh --deps`,
- update the wrapper preflight if runtime behavior changes,
- update `README.md`, `docs/scripts/upkeeper.md`, and the current year's root
  `change_notes_YYYY.md` when the change is operator-facing,
- run `tools/validate_upkeeper.sh --deps` and `tools/validate_upkeeper.sh --full`.
