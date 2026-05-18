# Upkeeper Release Checklist

Use this checklist before treating `main` as a release-ready wrapper state.

## Source State

- `main` is clean and synced with `origin/main`.
- Open feature branches or backlog PRs are either merged, intentionally left
  open, or documented as out of scope for the release.
- No `runtime/`, `Upkeeper.log`, transcripts, local manifests, locks, Codex
  session files, or other machine-local evidence is staged.
- The current year's `change_notes_YYYY.md` has entries for notable
  operator-facing changes.

## Validation

Run the applicable local checks from the central checkout:

```sh
tools/validate_upkeeper.sh --deps
bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf
set -e; for test_script in tests/*.bash; do bash "$test_script"; done
tools/check_public_docs.sh --quick
tools/validate_upkeeper.sh --quick
tools/validate_upkeeper.sh --full
git diff --check
```

Docs-only releases may use the cheaper docs path when no runtime, tool, config,
prompt, test, or launcher behavior changed:

```sh
tools/check_public_docs.sh --quick
tools/validate_upkeeper.sh --smoke
git diff --check
```

## Documentation

- README links to the relevant operator, compatibility, security, dependency,
  release-readiness, and prompt docs.
- `docs/compatibility.md` still describes the public operator-visible surface.
- `docs/security.md` still describes local trust and evidence boundaries.
- `docs/dependencies.md` still matches validator and runtime dependency checks.
- `docs/known-issues.md` lists the major unresolved release risks.

## Merge And Cleanup

- PR CI is green before merge.
- Merge commits mention operator-facing impact when behavior changes.
- After merge, verify local `main` is clean and synced with `origin/main`.
- Delete merged feature branches and prune stale remotes.
