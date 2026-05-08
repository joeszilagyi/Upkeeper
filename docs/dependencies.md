# Upkeeper Dependencies

Upkeeper is a Bash wrapper around local system tools and the Codex CLI. GitHub's
dependency graph should be enabled for the repository, but it is expected to
show no package dependencies unless the repo later adds a supported manifest or
lock file such as `package.json`, `requirements.txt`, `Gemfile`, `go.mod`, or
GitHub Actions workflows, or submits dependencies through GitHub's dependency
submission API.

Do not add fake package manifests just to populate the dependency graph. Track
Upkeeper's real dependency surface here and validate it locally with:

```sh
tools/validate_upkeeper.sh --deps
tools/validate_upkeeper.sh --full
```

`--deps` reports command availability. `--full` runs the release guardrails with
`UPKEEPER_DRY_RUN=1` for startup checks and a local fake `codex` binary for
launch/capture failure classification, including central startup,
symlinked-client startup, missing-module failure, missing prompt-template
failure, and empty-transcript failure.

## GitHub Settings

Recommended repository settings:

- Enable the dependency graph.
- Enable Dependabot alerts.
- Enable Dependabot security updates.
- Do not add Dependabot version-update configuration until the repo has a real
  supported manifest or GitHub Actions workflow to update.

If GitHub still reports "No dependencies found", that is normal for the current
repo shape. The dependency graph is future-proofing for later supported
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
- `cut`
- `date`
- `df`
- `find`
- `git`
- `grep`
- `jq`
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

## Backend Dependency

- `codex` is required for non-dry-run backend cycles.

`UPKEEPER_DRY_RUN=1` can validate startup, quota discovery, target selection,
prompt compilation, symlink resolution, and failure paths without launching a
Codex backend task.

## Conditional Dependencies

- `screen` is required when detached screen fallback is enabled. That is the
  default when `CODEX_FALLBACK_ENABLED=1` and `CODEX_FALLBACK_SCREEN_ENABLED=1`.

## Optional Dependencies

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
